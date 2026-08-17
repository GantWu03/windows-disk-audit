[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$MergedFindingsPath,
    [Parameter(Mandatory = $true)][string]$ReportPath,
    [Parameter(Mandatory = $true)][string]$FindingsPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Has-Property([object]$Object, [string]$Name) {
    return $null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name
}

function Add-Problem([string]$Message) { $script:problems.Add($Message) }

function Normalize-Path([string]$Path) {
    try {
        $full = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
        $root = [IO.Path]::GetPathRoot($full)
        if (-not $full.Equals($root, [StringComparison]::OrdinalIgnoreCase)) { $full = $full.TrimEnd('\','/') }
        return $full
    } catch { return $null }
}

function Is-InScope([string]$Path, [string[]]$Allowed, [string[]]$Excluded) {
    $candidate = Normalize-Path $Path
    if ($null -eq $candidate) { return $false }
    foreach ($blocked in $Excluded) {
        $prefix = $blocked.TrimEnd('\') + '\'
        if ($candidate.Equals($blocked, [StringComparison]::OrdinalIgnoreCase) -or $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    }
    foreach ($root in $Allowed) {
        $prefix = $root.TrimEnd('\') + '\'
        if ($candidate.Equals($root, [StringComparison]::OrdinalIgnoreCase) -or $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

$manifestFile = [IO.Path]::GetFullPath($ManifestPath)
$mergedFindingsFile = [IO.Path]::GetFullPath($MergedFindingsPath)
$reportFile = [IO.Path]::GetFullPath($ReportPath)
$findingsFile = [IO.Path]::GetFullPath($FindingsPath)
foreach ($file in @($manifestFile, $mergedFindingsFile, $reportFile, $findingsFile)) {
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw "文件不存在：$file" }
}

$problems = [Collections.Generic.List[string]]::new()
$warnings = [Collections.Generic.List[string]]::new()
try { $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestFile | ConvertFrom-Json }
catch { throw "audit-manifest.json 无法解析：$($_.Exception.Message)" }
try {
    $mergedFindingsText = Get-Content -Raw -Encoding UTF8 -LiteralPath $mergedFindingsFile
    $mergedFindings = [object[]]($mergedFindingsText | ConvertFrom-Json)
} catch { throw "findings.raw.json 无法解析：$($_.Exception.Message)" }
try {
    $findingsText = Get-Content -Raw -Encoding UTF8 -LiteralPath $findingsFile
    $parsedFindings = $findingsText | ConvertFrom-Json
    $findings = [object[]]$parsedFindings
} catch { throw "findings.json 无法解析：$($_.Exception.Message)" }
$report = Get-Content -Raw -Encoding UTF8 -LiteralPath $reportFile

if (-not $mergedFindingsText.TrimStart().StartsWith('[')) { Add-Problem 'findings.raw.json 顶层必须是数组。' }
if (-not $findingsText.TrimStart().StartsWith('[')) { Add-Problem 'findings.json 顶层必须是数组。' }
if ([string]::IsNullOrWhiteSpace($report)) { Add-Problem 'Markdown 报告为空。' }
if ($report -match '待填写|<用户指定|<报告|<Skill|<对象名称|\[发现 ID\]') { Add-Problem '报告仍含明显模板占位符。' }
$overviewPattern = '(?im)^\|[^\r\n]*(对象|目录|文件)[^\r\n]*\|[^\r\n]*(占用|大小)[^\r\n]*\|[^\r\n]*(是什么|用途|概述)[^\r\n]*\|\r?\n^\|[-: |]+\|\r?\n(?:^\|[^\r\n]*\|\r?\n?)+'
$overviewMatch = [regex]::Match($report, $overviewPattern)
$reportBody = $report
if (-not $overviewMatch.Success) {
    Add-Problem '报告开头缺少“对象/目录、占用、是什么”主要空间去向概览表。'
} else {
    $latestOverviewStart = [Math]::Min(4000, [Math]::Max(1, [Math]::Floor($report.Length * 0.25)))
    if ($overviewMatch.Index -gt $latestOverviewStart) { Add-Problem '主要空间去向概览表必须位于报告前部，不能放在正文或附录末尾。' }
    $reportBody = $report.Substring($overviewMatch.Index + $overviewMatch.Length)
    if ($reportBody -notmatch '(?im)^##\s+[^\r\n]*(根目录|Windows|系统区|程序|Program|应用数据|用户|AppData|虚拟|Docker|WSL|未知对象)') {
        Add-Problem '概览表之后缺少按真实目录组织的正文章节。'
    }
}

if (-not (Has-Property $manifest 'mode') -or $manifest.mode -ne 'read_only') { Add-Problem '审计清单必须是 read_only。' }
if (-not (Has-Property $manifest 'cleanup_authorized') -or [bool]$manifest.cleanup_authorized) { Add-Problem '只读审计不得包含清理授权。' }
if ($report -notmatch '只读|未执行.{0,8}(清理|删除|变更)|没有执行.{0,8}(清理|删除|变更)') {
    Add-Problem '报告应明确说明本次只读或未执行清理。'
}

$allowed = @()
$excluded = @()
if (Has-Property $manifest 'allowed_paths') { $allowed = @($manifest.allowed_paths | ForEach-Object { Normalize-Path ([string]$_) } | Where-Object { $null -ne $_ }) }
if (Has-Property $manifest 'excluded_paths') { $excluded = @($manifest.excluded_paths | ForEach-Object { Normalize-Path ([string]$_) } | Where-Object { $null -ne $_ }) }
if ($allowed.Count -eq 0) { Add-Problem '审计清单没有有效 allowed_paths。' }

$rawSourceRefs = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($rawFinding in $mergedFindings) {
    $rawId = if (Has-Property $rawFinding 'id') { [string]$rawFinding.id } else { '<missing-id>' }
    if (-not (Has-Property $rawFinding 'source_refs') -or @($rawFinding.source_refs).Count -eq 0) {
        Add-Problem "$rawId 合并候选缺少 source_refs。"
        continue
    }
    foreach ($sourceRef in @($rawFinding.source_refs | ForEach-Object { [string]$_ })) {
        if ([string]::IsNullOrWhiteSpace($sourceRef) -or -not $rawSourceRefs.Add($sourceRef)) {
            Add-Problem "合并候选 source_ref 为空或重复：$sourceRef"
        }
    }
}

$canonicalActions = @(
    'none','keep','investigate','clean_via_system','clean_via_app','uninstall','migrate',
    'isolate','direct_clean','delete','system_setting_change','archive_or_cleanup'
)
$actionableActions = @(
    'clean_via_system','clean_via_app','uninstall','migrate','isolate','direct_clean','delete',
    'system_setting_change','archive_or_cleanup'
)
$ids = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$finalSourceRefs = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($finding in $findings) {
    $id = if (Has-Property $finding 'id') { [string]$finding.id } else { '<missing-id>' }
    foreach ($field in @('id','summary','observations','state_changes_performed','actual_result')) {
        if (-not (Has-Property $finding $field)) { Add-Problem "$id 缺少轻量核心字段：$field" }
    }
    if (-not (Has-Property $finding 'path') -and -not (Has-Property $finding 'paths')) { Add-Problem "$id 缺少轻量核心路径：path 或 paths" }
    if ($id -eq '<missing-id>') { continue }
    if ([string]::IsNullOrWhiteSpace($id) -or -not $ids.Add($id)) { Add-Problem "发现 ID 为空或重复：$id" }
    if (-not (Has-Property $finding 'review_status') -or [string]::IsNullOrWhiteSpace([string]$finding.review_status)) {
        Add-Problem "$id 缺少主 Agent 复核状态 review_status。"
    }
    if (-not (Has-Property $finding 'source_refs') -or @($finding.source_refs).Count -eq 0) {
        Add-Problem "$id 缺少候选来源 source_refs。"
    } else {
        foreach ($sourceRef in @($finding.source_refs | ForEach-Object { [string]$_ })) {
            if ([string]::IsNullOrWhiteSpace($sourceRef)) { Add-Problem "$id 包含空 source_ref。"; continue }
            if (-not $sourceRef.StartsWith('main:', [StringComparison]::OrdinalIgnoreCase) -and -not $rawSourceRefs.Contains($sourceRef)) {
                Add-Problem "$id 引用了不存在的子 Agent 候选：$sourceRef"
            }
            [void]$finalSourceRefs.Add($sourceRef)
        }
    }
    if ((Has-Property $finding 'summary') -and [string]::IsNullOrWhiteSpace([string]$finding.summary)) { Add-Problem "$id summary 不能为空。" }
    if ((Has-Property $finding 'observations') -and @($finding.observations).Count -eq 0) { Add-Problem "$id observations 至少需要一项本机观察。" }
    $findingPaths = @()
    if (Has-Property $finding 'path') { $findingPaths += [string]$finding.path }
    if (Has-Property $finding 'paths') { $findingPaths += @($finding.paths | ForEach-Object { [string]$_ }) }
    foreach ($findingPath in $findingPaths) {
        if ($allowed.Count -gt 0 -and -not (Is-InScope $findingPath $allowed $excluded)) { Add-Problem "$id 路径不在允许范围或命中排除项：$findingPath" }
    }
    if ((Has-Property $finding 'state_changes_performed') -and @($finding.state_changes_performed).Count -gt 0) { Add-Problem "$id 只读审计包含状态变更。" }
    if ((Has-Property $finding 'actual_result') -and $finding.actual_result -ne 'not_executed') { Add-Problem "$id 只读审计不能声明已执行结果。" }

    foreach ($name in @('logical_bytes','allocated_bytes','reclaimable_min_bytes','reclaimable_max_bytes')) {
        if ((Has-Property $finding $name) -and $null -ne $finding.$name) {
            try { $value = [double]$finding.$name } catch { Add-Problem "$id $name 必须是非负数字或 null。"; continue }
            if ($value -lt 0) { Add-Problem "$id $name 不能为负数。" }
        }
    }

    $hasMin = Has-Property $finding 'reclaimable_min_bytes'
    $hasMax = Has-Property $finding 'reclaimable_max_bytes'
    if ($hasMin -or $hasMax) {
        $min = if ($hasMin) { $finding.reclaimable_min_bytes } else { $null }
        $max = if ($hasMax) { $finding.reclaimable_max_bytes } else { $null }
        if (($null -eq $min) -xor ($null -eq $max)) { Add-Problem "$id 可回收上下界必须同时为空或同时填写。" }
        elseif ($null -ne $min) {
            if ([double]$max -lt [double]$min) { Add-Problem "$id 可回收范围非法。" }
            $basis = if (Has-Property $finding 'reclaim_basis') { [string]$finding.reclaim_basis } else { '' }
            if ([double]$max -gt 0 -and ([string]::IsNullOrWhiteSpace($basis) -or $basis -eq 'unknown')) { Add-Problem "$id 填写非零可回收量但没有明确依据。" }
        }
    }

    $action = if (Has-Property $finding 'recommended_action') { [string]$finding.recommended_action } else { '' }
    if (-not [string]::IsNullOrWhiteSpace($action) -and $action -notin $canonicalActions) {
        Add-Problem "$id recommended_action 使用未知值：$action"
    }
    $active = if (Has-Property $finding 'active_use') { [string]$finding.active_use } else { '' }
    $protected = (Has-Property $finding 'protected_class') -and [bool]$finding.protected_class
    if ($active -eq 'yes' -and $action -in @('direct_clean','delete')) { Add-Problem "$id 正在活动，不能建议直接清理。" }
    if ($protected -and $action -in @('direct_clean','delete','isolate')) { Add-Problem "$id 属于受保护对象，不能按普通文件直接清理或隔离。" }

    if ($action -in $actionableActions) {
        foreach ($field in @('object_class','active_use','recommendation','impact','decision_basis','evidence')) {
            if (-not (Has-Property $finding $field) -or $null -eq $finding.$field -or
                (($finding.$field -is [string]) -and [string]::IsNullOrWhiteSpace([string]$finding.$field)) -or
                (($finding.$field -is [array]) -and @($finding.$field).Count -eq 0)) {
                Add-Problem "$id 含动作性建议，但 decision index 缺少：$field"
            }
        }
        if ($protected) {
            $evidenceKinds = if (Has-Property $finding 'evidence') { @($finding.evidence | ForEach-Object { if (Has-Property $_ 'kind') { [string]$_.kind } }) } else { @() }
            if (-not ($evidenceKinds -contains 'official') -and -not ($evidenceKinds -contains 'specialized')) {
                Add-Problem "$id 是受保护对象且含动作性建议，但缺少官方或专用工具证据。"
            }
        }
    }

    $role = if (Has-Property $finding 'role') { [string]$finding.role } else { '' }
    if ($id -ne '<missing-id>') {
        $idIndex = $reportBody.IndexOf($id, [StringComparison]::OrdinalIgnoreCase)
        if ($idIndex -lt 0) {
            Add-Problem "$id 只出现在概览或没有出现在按目录组织的正文中。"
        } else {
            $segmentLength = [Math]::Min(1400, $reportBody.Length - $idIndex)
            $segment = $reportBody.Substring($idIndex, $segmentLength)
            $nextHeading = [regex]::Match($segment.Substring([Math]::Min($id.Length, $segment.Length)), '(?m)^#{2,6}\s+')
            if ($nextHeading.Success) { $segment = $segment.Substring(0, [Math]::Min($segment.Length, $id.Length + $nextHeading.Index)) }
            $hasPurpose = $segment -match '是什么|用于|保存|记录|组成|缓存|组件|数据|文件|目录|安装|备份|维护'
            if (-not $hasPurpose) { Add-Problem "$id 的目录正文没有解释基本用途或对象性质。" }
            if ($role -ne 'record') {
                $hasChoice = $segment -match '保留|清理|删除|卸载|迁移|处理|核验|调查|不要|可以|无需|不建议'
                $hasImpact = $segment -match '影响|会|不会|重新|失去|风险|代价|重建|下载|增长'
                if (-not $hasChoice) { Add-Problem "$id 的目录正文没有说明可选处理方式或当前选择。" }
                if (-not $hasImpact) { Add-Problem "$id 的目录正文没有说明处理影响、代价或后续变化。" }
            }
            if ([string]::IsNullOrWhiteSpace($action) -and $segment -match '清理|删除|卸载|迁移|关闭|重置') {
                $warnings.Add("$id 的目录正文似乎提出状态变化，但 findings.json 没有 recommended_action；请核对 decision index。")
            }
        }
    }

    if ($role -eq 'focus') {
        if (-not (Has-Property $finding 'recommendation') -or [string]::IsNullOrWhiteSpace([string]$finding.recommendation)) { $warnings.Add("$id 是重点对象但没有具体建议。") }
        if (-not (Has-Property $finding 'impact') -or [string]::IsNullOrWhiteSpace([string]$finding.impact)) { $warnings.Add("$id 是重点对象但没有说明处理影响。") }
    }
}

foreach ($sourceRef in $rawSourceRefs) {
    if (-not $finalSourceRefs.Contains($sourceRef)) {
        Add-Problem "子 Agent 候选没有进入最终复核结果：$sourceRef"
    }
}

if ($report -match '(?i)takeown|icacls\s+.+/grant|Remove-Item\s+.+-Recurse.+-Force') {
    Add-Problem '只读审计报告不得包含可直接复制执行的夺权或强制递归删除命令。'
}

foreach ($warning in $warnings) { Write-Warning $warning }
if ($problems.Count -gt 0) {
    Write-Output 'REPORT_VALIDATION_FAILED'
    $problems | ForEach-Object { Write-Output "- $_" }
    exit 1
}

Write-Output "REPORT_VALIDATION_OK findings=$($findings.Count) warnings=$($warnings.Count)"
