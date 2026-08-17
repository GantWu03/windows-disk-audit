[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory,

    [ValidatePattern('^[A-Za-z]:$')]
    [string]$SystemDrive = $env:SystemDrive,

    [string[]]$AllowedPaths = @(),
    [string[]]$ExcludedPaths = @(),

    [ValidateRange(5, 1440)]
    [int]$TimeBudgetMinutes = 60,

    [ValidateRange(0, [long]::MaxValue)]
    [long]$MinExpectedReclaimBytes = 100MB,

    [ValidateRange(1GB, [long]::MaxValue)]
    [long]$LowSpaceWriteGateBytes = 5GB,

    [switch]$AdminReadOnlyAllowed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

$normalizedDrive = $SystemDrive.ToUpperInvariant()
$systemRoot = "$normalizedDrive\"
$outputFullPath = ConvertTo-NormalizedPath $OutputDirectory

$normalizedAllowed = @($AllowedPaths | ForEach-Object { ConvertTo-NormalizedPath $_ })
if ($normalizedAllowed.Count -eq 0) { $normalizedAllowed = @($systemRoot) }
$normalizedExcluded = @($ExcludedPaths | ForEach-Object { ConvertTo-NormalizedPath $_ })

foreach ($path in $normalizedAllowed) {
    if (-not $path.StartsWith($systemRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "审计允许路径必须位于系统盘 $normalizedDrive：$path"
    }
}

$manifestPath = Join-Path $outputFullPath 'audit-manifest.json'
if (Test-Path -LiteralPath $manifestPath) {
    throw "审计清单已存在，拒绝覆盖：$manifestPath"
}

$drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$normalizedDrive'" |
    Select-Object -First 1 DeviceID,Size,FreeSpace
if ($null -eq $drive) { throw "无法读取系统盘：$normalizedDrive" }

$outputDrive = [IO.Path]::GetPathRoot($outputFullPath).TrimEnd('\')
if ([int64]$drive.FreeSpace -lt $LowSpaceWriteGateBytes -and $outputDrive.Equals($normalizedDrive, [StringComparison]::OrdinalIgnoreCase)) {
    throw "系统盘可用空间低于本次写入门禁 $LowSpaceWriteGateBytes 字节，输出目录必须位于非系统盘。"
}

New-Item -ItemType Directory -Path $outputFullPath -Force | Out-Null
foreach ($relative in ('baseline', 'clusters', 'work', 'final')) {
    New-Item -ItemType Directory -Path (Join-Path $outputFullPath $relative) -Force | Out-Null
}

$auditId = '{0}-{1}' -f ([datetime]::UtcNow.ToString('yyyyMMddTHHmmssZ')), ([guid]::NewGuid().ToString('N').Substring(0, 8))
$manifest = [ordered]@{
    schema_version = '1.0'
    audit_id = $auditId
    created_at_utc = [datetime]::UtcNow.ToString('o')
    system_drive = $normalizedDrive
    mode = 'read_only'
    baseline_free_bytes = [int64]$drive.FreeSpace
    admin_readonly_allowed = [bool]$AdminReadOnlyAllowed
    time_budget_minutes = $TimeBudgetMinutes
    min_expected_reclaim_bytes = $MinExpectedReclaimBytes
    low_space_write_gate_bytes = $LowSpaceWriteGateBytes
    output_directory = $outputFullPath
    allowed_paths = $normalizedAllowed
    excluded_paths = $normalizedExcluded
    cleanup_authorized = $false
}

$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
[pscustomobject]@{ manifest = $manifestPath; audit_id = $auditId; output_directory = $outputFullPath }
