[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ManifestPath,

    [ValidateSet('baseline', 'cluster')]
    [string]$Phase = 'baseline',

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$')]
    [string]$ClusterId,

    [string[]]$Paths = @(),

    [ValidateRange(1, 300)]
    [int]$SecondsPerPath = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-DisplayPath {
    param([AllowNull()][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $Path }

    $result = $Path
    $mappings = @(
        @{ Value = $env:LOCALAPPDATA; Name = '%LOCALAPPDATA%' },
        @{ Value = $env:USERPROFILE; Name = '%USERPROFILE%' },
        @{ Value = $env:ProgramData; Name = '%ProgramData%' },
        @{ Value = ${env:ProgramFiles(x86)}; Name = '%ProgramFiles(x86)%' },
        @{ Value = $env:ProgramFiles; Name = '%ProgramFiles%' },
        @{ Value = $env:APPDATA; Name = '%APPDATA%' },
        @{ Value = $env:WINDIR; Name = '%WINDIR%' },
        @{ Value = $env:PUBLIC; Name = '%PUBLIC%' },
        @{ Value = $env:SystemDrive; Name = '%SystemDrive%' }
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Value) } |
        Sort-Object { $_.Value.Length } -Descending

    foreach ($mapping in $mappings) {
        if ($result.StartsWith($mapping.Value, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $mapping.Name + $result.Substring($mapping.Value.Length)
        }
    }
    return $result
}

function Measure-PathLimited {
    param(
        [Parameter(Mandatory = $true)][string]$LiteralPath,
        [Parameter(Mandatory = $true)][int]$TimeLimitSeconds
    )

    $result = [ordered]@{
        path = $LiteralPath
        display_path = ConvertTo-DisplayPath $LiteralPath
        exists = $false
        type = 'unknown'
        logical_bytes = 0L
        allocated_bytes = $null
        file_count = 0L
        directory_count = 0L
        latest_write_utc = $null
        reparse_points_skipped = 0
        access_errors = 0
        timed_out = $false
        complete = $false
        notes = @()
    }

    if (-not (Test-Path -LiteralPath $LiteralPath)) {
        $result.notes += 'path_not_found'
        return [pscustomobject]$result
    }

    $item = Get-Item -LiteralPath $LiteralPath -Force
    $result.exists = $true

    if (-not $item.PSIsContainer) {
        $result.type = 'file'
        $result.logical_bytes = [int64]$item.Length
        $result.file_count = 1
        $result.latest_write_utc = $item.LastWriteTimeUtc.ToString('o')
        $result.complete = $true
        return [pscustomobject]$result
    }

    $result.type = 'directory'
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        $result.reparse_points_skipped = 1
        $result.notes += 'root_is_reparse_point_not_traversed'
        return [pscustomobject]$result
    }

    $watch = [Diagnostics.Stopwatch]::StartNew()
    $queue = [Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($item.FullName)
    $latest = [datetime]::MinValue

    while ($queue.Count -gt 0) {
        if ($watch.Elapsed.TotalSeconds -ge $TimeLimitSeconds) {
            $result.timed_out = $true
            break
        }

        $current = $queue.Dequeue()
        $result.directory_count++

        try {
            foreach ($filePath in [IO.Directory]::EnumerateFiles($current)) {
                if ($watch.Elapsed.TotalSeconds -ge $TimeLimitSeconds) {
                    $result.timed_out = $true
                    break
                }
                try {
                    $file = [IO.FileInfo]::new($filePath)
                    $result.logical_bytes += [int64]$file.Length
                    $result.file_count++
                    if ($file.LastWriteTimeUtc -gt $latest) { $latest = $file.LastWriteTimeUtc }
                }
                catch { $result.access_errors++ }
            }
        }
        catch { $result.access_errors++ }

        if ($result.timed_out) { break }

        try {
            foreach ($directoryPath in [IO.Directory]::EnumerateDirectories($current)) {
                if ($watch.Elapsed.TotalSeconds -ge $TimeLimitSeconds) {
                    $result.timed_out = $true
                    break
                }
                try {
                    $directory = [IO.DirectoryInfo]::new($directoryPath)
                    if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                        $result.reparse_points_skipped++
                        continue
                    }
                    $queue.Enqueue($directory.FullName)
                    if ($directory.LastWriteTimeUtc -gt $latest) { $latest = $directory.LastWriteTimeUtc }
                }
                catch { $result.access_errors++ }
            }
        }
        catch { $result.access_errors++ }
    }

    $watch.Stop()
    if ($latest -ne [datetime]::MinValue) { $result.latest_write_utc = $latest.ToString('o') }
    $result.complete = -not $result.timed_out -and $result.access_errors -eq 0
    if ($result.timed_out) { $result.notes += 'partial_measurement_time_limit' }
    if ($result.access_errors -gt 0) { $result.notes += 'partial_measurement_access_errors' }
    return [pscustomobject]$result
}

function ConvertTo-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$LiteralPath)
    $expanded = [Environment]::ExpandEnvironmentVariables($LiteralPath)
    if ([string]::IsNullOrWhiteSpace($expanded) -or -not [IO.Path]::IsPathRooted($expanded)) {
        throw "路径必须是已解析的绝对路径：$LiteralPath"
    }
    if ($expanded.StartsWith('\\')) { throw "不接受 UNC 路径：$LiteralPath" }
    $full = [IO.Path]::GetFullPath($expanded)
    $root = [IO.Path]::GetPathRoot($full)
    if (-not $full.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
        $full = $full.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    }
    return $full
}

function Test-PathWithin {
    param([string]$Candidate, [string]$Root)
    if ($Candidate.Equals($Root, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    $prefix = $Root
    if (-not $prefix.EndsWith([string][IO.Path]::DirectorySeparatorChar)) { $prefix += [IO.Path]::DirectorySeparatorChar }
    return $Candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

function Test-PathAllowed {
    param([string]$Candidate, [string[]]$AllowedRoots, [string[]]$ExcludedRoots)
    $allowed = $false
    foreach ($root in $AllowedRoots) {
        if (Test-PathWithin $Candidate $root) { $allowed = $true; break }
    }
    if (-not $allowed) { return $false }
    foreach ($root in $ExcludedRoots) {
        if (Test-PathWithin $Candidate $root) { return $false }
    }
    return $true
}

function New-RejectedMeasurement {
    param([string]$LiteralPath, [string]$Reason)
    return [pscustomobject][ordered]@{
        path = $LiteralPath
        display_path = ConvertTo-DisplayPath $LiteralPath
        exists = Test-Path -LiteralPath $LiteralPath
        type = 'rejected'
        logical_bytes = 0L
        allocated_bytes = $null
        file_count = 0L
        directory_count = 0L
        latest_write_utc = $null
        reparse_points_skipped = 0
        access_errors = 0
        timed_out = $false
        complete = $false
        notes = @($Reason)
    }
}

$manifestFullPath = ConvertTo-NormalizedPath $ManifestPath
if (-not (Test-Path -LiteralPath $manifestFullPath -PathType Leaf)) { throw "审计清单不存在：$manifestFullPath" }
$manifest = Get-Content -LiteralPath $manifestFullPath -Raw -Encoding UTF8 | ConvertFrom-Json

foreach ($field in ('audit_id','system_drive','mode','output_directory','allowed_paths','excluded_paths','cleanup_authorized','time_budget_minutes')) {
    if ($manifest.PSObject.Properties.Name -notcontains $field) { throw "审计清单缺少字段：$field" }
}
if ($manifest.mode -ne 'read_only' -or [bool]$manifest.cleanup_authorized) {
    throw '盘点脚本只接受 mode=read_only 且 cleanup_authorized=false 的审计清单。'
}
if ($Phase -eq 'cluster' -and [string]::IsNullOrWhiteSpace($ClusterId)) { throw 'cluster 阶段必须提供 -ClusterId。' }
if ($Phase -eq 'baseline' -and @($Paths).Count -gt 0) { throw 'baseline 阶段由脚本生成粗测目标，不接受 -Paths。' }

$normalizedDrive = ([string]$manifest.system_drive).ToUpperInvariant()
$rootPath = "$normalizedDrive\"
$allowedRoots = @($manifest.allowed_paths | ForEach-Object { ConvertTo-NormalizedPath ([string]$_) })
$excludedRoots = @($manifest.excluded_paths | ForEach-Object { ConvertTo-NormalizedPath ([string]$_) })
$outputRoot = ConvertTo-NormalizedPath ([string]$manifest.output_directory)
$outputFullPath = if ($Phase -eq 'baseline') {
    Join-Path $outputRoot 'baseline'
} else {
    Join-Path (Join-Path $outputRoot 'clusters') $ClusterId
}

$driveInfo = try {
    Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$normalizedDrive'" |
        Select-Object -First 1 DeviceID,Size,FreeSpace,VolumeName,FileSystem
} catch {
    $fallback = [IO.DriveInfo]::new($normalizedDrive)
    [pscustomobject]@{ DeviceID=$normalizedDrive; Size=$fallback.TotalSize; FreeSpace=$fallback.AvailableFreeSpace; VolumeName=$fallback.VolumeLabel; FileSystem=$fallback.DriveFormat }
}
if ($null -eq $driveInfo) { throw "无法读取系统盘：$normalizedDrive" }
$lowSpaceThreshold = if ($manifest.PSObject.Properties.Name -contains 'low_space_write_gate_bytes') { [int64]$manifest.low_space_write_gate_bytes } else { [int64]5GB }
$outputDrive = [IO.Path]::GetPathRoot($outputRoot).TrimEnd('\')
if ([int64]$driveInfo.FreeSpace -lt $lowSpaceThreshold -and $outputDrive.Equals($normalizedDrive, [StringComparison]::OrdinalIgnoreCase)) {
    throw "系统盘可用空间低于本次写入门禁 $lowSpaceThreshold 字节；盘点未写入证据，请改用非系统盘输出目录。"
}

New-Item -ItemType Directory -Force -Path $outputFullPath | Out-Null
$jsonPath = Join-Path $outputFullPath 'inventory.json'
$draftPath = Join-Path $outputFullPath 'report-draft.md'
if ((Test-Path -LiteralPath $jsonPath) -or (Test-Path -LiteralPath $draftPath)) {
    throw "结果已存在，拒绝覆盖；请使用新的 cluster_id 或新的审计目录：$outputFullPath"
}

$rootEntries = @()
$rootErrors = @()
$wholeSystemDriveAllowed = $false
foreach ($allowedRoot in $allowedRoots) {
    if ($allowedRoot.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase)) { $wholeSystemDriveAllowed = $true; break }
}
if ($wholeSystemDriveAllowed) {
  try {
      $rootEntries = @(Get-ChildItem -LiteralPath $rootPath -Force -ErrorAction Stop | ForEach-Object {
        [pscustomobject]@{
            name = $_.Name
            actual_path = $_.FullName
            display_path = ConvertTo-DisplayPath $_.FullName
            type = if ($_.PSIsContainer) { 'directory' } else { 'file' }
            logical_bytes = if ($_.PSIsContainer) { $null } else { [int64]$_.Length }
            last_write_utc = $_.LastWriteTimeUtc.ToString('o')
            attributes = $_.Attributes.ToString()
            link_type = $_.LinkType
            target = $_.Target
        }
      })
  } catch { $rootErrors += $_.Exception.Message }
} else {
    $rootErrors += '审计范围未包含系统盘根目录，因此未读取根目录条目。'
}

$knownCandidateDefinitions = @(
    @{ Template='%WINDIR%\Installer'; Path=(Join-Path $env:WINDIR 'Installer'); Category='windows_installer' },
    @{ Template='%WINDIR%\SoftwareDistribution\Download'; Path=(Join-Path $env:WINDIR 'SoftwareDistribution\Download'); Category='windows_update' },
    @{ Template='%WINDIR%\WinSxS'; Path=(Join-Path $env:WINDIR 'WinSxS'); Category='component_store' },
    @{ Template='%WINDIR%\Temp'; Path=(Join-Path $env:WINDIR 'Temp'); Category='system_temp' },
    @{ Template='%ProgramData%'; Path=$env:ProgramData; Category='machine_app_data' },
    @{ Template='%ProgramFiles%'; Path=$env:ProgramFiles; Category='installed_apps' },
    @{ Template='%ProgramFiles(x86)%'; Path=${env:ProgramFiles(x86)}; Category='installed_apps' },
    @{ Template='%USERPROFILE%'; Path=$env:USERPROFILE; Category='user_profile' },
    @{ Template='%LOCALAPPDATA%'; Path=$env:LOCALAPPDATA; Category='user_local_app_data' },
    @{ Template='%APPDATA%'; Path=$env:APPDATA; Category='user_roaming_app_data' }
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Path) }

$knownCandidates = @($knownCandidateDefinitions | Where-Object {
    $candidatePath = ConvertTo-NormalizedPath ([string]$_.Path)
    Test-PathAllowed $candidatePath $allowedRoots $excludedRoots
} | ForEach-Object {
    [pscustomobject]@{ path_template=$_.Template; category=$_.Category; exists=(Test-Path -LiteralPath $_.Path); actual_path=$_.Path }
})

$candidatePaths = [Collections.Generic.List[string]]::new()
if ($Phase -eq 'baseline') {
    if ($wholeSystemDriveAllowed) {
        foreach ($entry in $rootEntries) {
            if ($entry.type -eq 'directory' -and $entry.attributes -notmatch 'ReparsePoint') { $candidatePaths.Add([string]$entry.actual_path) }
        }
    } else {
        foreach ($allowedRoot in $allowedRoots) {
            if (-not (Test-Path -LiteralPath $allowedRoot -PathType Container)) { $candidatePaths.Add($allowedRoot); continue }
            foreach ($item in @(Get-ChildItem -LiteralPath $allowedRoot -Force -ErrorAction SilentlyContinue)) {
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $candidatePaths.Add($item.FullName) }
            }
        }
    }
} else {
    foreach ($path in @($Paths)) {
        if (-not [string]::IsNullOrWhiteSpace($path)) { $candidatePaths.Add([string]$path) }
    }
}

$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$measurements = [Collections.Generic.List[object]]::new()
$scopeRejections = [Collections.Generic.List[object]]::new()
$overallWatch = [Diagnostics.Stopwatch]::StartNew()
$timeBudgetSeconds = [int]$manifest.time_budget_minutes * 60

foreach ($path in $candidatePaths) {
    if ($overallWatch.Elapsed.TotalSeconds -ge $timeBudgetSeconds) { break }
    try { $full = ConvertTo-NormalizedPath $path } catch {
        $rejected = New-RejectedMeasurement $path 'invalid_or_unresolved_path'
        $measurements.Add($rejected); $scopeRejections.Add($rejected); continue
    }
    if (-not $seen.Add($full)) { continue }
    if (-not (Test-PathAllowed $full $allowedRoots $excludedRoots)) {
        $rejected = New-RejectedMeasurement $full 'scope_rejected'
        $measurements.Add($rejected); $scopeRejections.Add($rejected); continue
    }
    $measurements.Add((Measure-PathLimited -LiteralPath $full -TimeLimitSeconds $SecondsPerPath))
}
$overallWatch.Stop()

$services = @()
if ($wholeSystemDriveAllowed) {
    $serviceNames = 'BITS','wuauserv','TrustedInstaller','msiserver','vmcompute','LxssManager'
    $services = @(foreach ($serviceName in $serviceNames) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
        if ($null -ne $service) { [pscustomobject]@{ name=$service.Name; status=$service.Status.ToString(); start_type=$service.StartType.ToString() } }
    })
}

$shortlist = @($measurements | Where-Object { $_.type -ne 'rejected' -and $_.exists } |
    Sort-Object logical_bytes -Descending | ForEach-Object {
        [pscustomobject]@{
            path = $_.path
            path_template = $_.display_path
            measured_logical_bytes = [int64]$_.logical_bytes
            measurement_kind = if ($_.complete) { 'complete_logical' } else { 'partial_lower_bound' }
            priority = 'unassigned'
            reason = if ($_.complete) { '本层只读测量结果，仍需识别来源和风险。' } else { '限时或权限下界；进入短名单前必须保留 partial 标记。' }
            scan_cost = if ($_.timed_out) { 'high' } elseif ($_.file_count -gt 10000) { 'medium' } else { 'low' }
        }
    })

$inventory = [ordered]@{
    schema_version = '2.0'
    audit_id = [string]$manifest.audit_id
    phase = $Phase
    cluster_id = if ($Phase -eq 'cluster') { $ClusterId } else { $null }
    collected_at_utc = [datetime]::UtcNow.ToString('o')
    mode = 'read_only'
    system_drive = $normalizedDrive
    manifest_path = $manifestFullPath
    allowed_paths = $allowedRoots
    excluded_paths = $excludedRoots
    drive = [ordered]@{ size_bytes=[int64]$driveInfo.Size; free_bytes=[int64]$driveInfo.FreeSpace; used_bytes=[int64]$driveInfo.Size-[int64]$driveInfo.FreeSpace; file_system=$driveInfo.FileSystem; volume_name=$driveInfo.VolumeName }
    low_space_gate = [ordered]@{ threshold_bytes=$lowSpaceThreshold; triggered=[int64]$driveInfo.FreeSpace -lt $lowSpaceThreshold; instruction='Agent 不启动新的高写入活动；未经授权不终止现有进程。输出使用非系统盘。' }
    root_entries = $rootEntries
    root_errors = $rootErrors
    known_candidates = $knownCandidates
    relevant_services = $services
    targeted_measurements = @($measurements)
    shortlist_candidates = $shortlist
    scope_rejections = @($scopeRejections)
    time_budget_exhausted = $overallWatch.Elapsed.TotalSeconds -ge $timeBudgetSeconds
    measurement_notes = @(
        'baseline 测量授权范围内的一级对象；通用候选只作为范围内元数据，不与父目录重复测量。partial_lower_bound 不是完整大小。',
        'logical_bytes 不等于 allocated_bytes 或可回收空间；本脚本不采集 allocated_bytes。',
        '超时、权限错误或范围拒绝必须保留，不能改写为 0 B。',
        '重解析点不会递归进入；父子候选不得在摘要中重复计量。'
    )
}

$inventory | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$sizeGiB = [math]::Round([int64]$driveInfo.Size / 1GB, 2)
$freeGiB = [math]::Round([int64]$driveInfo.FreeSpace / 1GB, 2)
$usedGiB = [math]::Round(([int64]$driveInfo.Size - [int64]$driveInfo.FreeSpace) / 1GB, 2)
$lines = @(
    '# Windows 系统盘空间排查报告初稿','',
    '> 仅含只读事实；不是最终报告，也不包含清理授权。','',
    '## 1. 审计概况','',
    "- 审计 ID：$($manifest.audit_id)",
    "- 阶段：$Phase",
    "- 系统盘：$normalizedDrive",
    "- 总容量 / 已用 / 剩余：$sizeGiB GiB / $usedGiB GiB / $freeGiB GiB",
    "- 原始盘点：$jsonPath",'',
    '## 2. 粗测短名单',''
)
if ($shortlist.Count -eq 0) { $lines += '- 没有形成可排序测量；检查范围拒绝、权限和时间预算。' }
else {
    foreach ($item in $shortlist) {
        $gib = [math]::Round($item.measured_logical_bytes / 1GB, 3)
        $lines += "- $($item.path_template)：$gib GiB（$($item.measurement_kind)）；实际占用未知；可回收未知。"
    }
}
$lines += @('','## 3. 门禁','','- 只有带测量口径或明确故障关联证据的对象才能进入 G1。','- `partial_lower_bound` 必须继续核验，不能冒充完整大小。','- 本初稿不得直接转成清理命令。')
$lines | Set-Content -LiteralPath $draftPath -Encoding UTF8

[pscustomobject]@{ inventory=$jsonPath; draft_report=$draftPath; phase=$Phase; measurements=$measurements.Count; shortlist=$shortlist.Count; scope_rejections=$scopeRejections.Count }
