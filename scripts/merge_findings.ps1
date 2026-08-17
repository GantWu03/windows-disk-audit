[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ClustersDirectory,
    [Parameter(Mandatory = $true)][string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-JsonUtf8Bom([string]$Path, [object]$Value) {
    $json = $Value | ConvertTo-Json -Depth 30
    [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, [Text.UTF8Encoding]::new($true))
}
function Has-Property([object]$Object, [string]$Name) {
    return $null -ne $Object -and $null -ne $Object.PSObject.Properties[$Name]
}

$clustersRoot = [IO.Path]::GetFullPath($ClustersDirectory)
$outputRoot = [IO.Path]::GetFullPath($OutputDirectory)
if (-not (Test-Path -LiteralPath $clustersRoot -PathType Container)) {
    throw "子 Agent 目录不存在：$clustersRoot"
}

$clusterDirectories = @(Get-ChildItem -LiteralPath $clustersRoot -Directory -Force | Sort-Object Name)
if ($clusterDirectories.Count -eq 0) { throw "没有找到子 Agent 目录：$clustersRoot" }

$merged = [Collections.Generic.List[object]]::new()
$coverage = [Collections.Generic.List[object]]::new()
$chapters = [Collections.Generic.List[string]]::new()
$sourceRefs = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$sequence = 0

foreach ($cluster in $clusterDirectories) {
    $findingsPath = Join-Path $cluster.FullName 'findings.json'
    $coveragePath = Join-Path $cluster.FullName 'coverage.json'
    $chapterPath = Join-Path $cluster.FullName 'chapter.md'
    foreach ($required in @($findingsPath, $coveragePath, $chapterPath)) {
        if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
            throw "子 Agent $($cluster.Name) 缺少必需产物：$required"
        }
    }

    $findingsText = Get-Content -Raw -Encoding UTF8 -LiteralPath $findingsPath
    if (-not $findingsText.TrimStart().StartsWith('[')) {
        throw "$findingsPath 顶层必须是数组。"
    }
    $parsedFindings = $findingsText | ConvertFrom-Json
    $clusterFindings = [object[]]$parsedFindings
    $clusterCoverage = Get-Content -Raw -Encoding UTF8 -LiteralPath $coveragePath | ConvertFrom-Json
    $clusterChapter = Get-Content -Raw -Encoding UTF8 -LiteralPath $chapterPath
    if ([string]::IsNullOrWhiteSpace($clusterChapter)) { throw "子 Agent $($cluster.Name) 的 chapter.md 为空。" }
    $coveragePaths = @()
    foreach ($name in @('scope','paths_checked','checked_paths')) {
        if (Has-Property $clusterCoverage $name) { $coveragePaths += @($clusterCoverage.$name) }
    }
    if ($coveragePaths.Count -eq 0) { throw "子 Agent $($cluster.Name) 的 coverage.json 未记录检查路径。" }
    if (-not (Has-Property $clusterCoverage 'completeness') -and -not (Has-Property $clusterCoverage 'status')) {
        throw "子 Agent $($cluster.Name) 的 coverage.json 未说明完整或部分状态。"
    }

    $coverage.Add([ordered]@{
        source_cluster = $cluster.Name
        source_file = $coveragePath
        coverage = $clusterCoverage
    })

    foreach ($finding in $clusterFindings) {
        $candidateId = if ($null -ne $finding) { [string]$finding.id } else { '' }
        if ([string]::IsNullOrWhiteSpace($candidateId)) {
            throw "$findingsPath 包含缺少 id 的候选。"
        }
        if ($clusterChapter -notmatch [regex]::Escape($candidateId)) {
            throw "子 Agent $($cluster.Name) 的 chapter.md 未解释候选：$candidateId"
        }
        $candidateIndex = $clusterChapter.IndexOf($candidateId, [StringComparison]::OrdinalIgnoreCase)
        $candidateSegment = $clusterChapter.Substring($candidateIndex, [Math]::Min(1600, $clusterChapter.Length - $candidateIndex))
        $afterId = $candidateSegment.Substring([Math]::Min($candidateId.Length, $candidateSegment.Length))
        $nextHeading = [regex]::Match($afterId, '(?m)^#{2,6}\s+')
        if ($nextHeading.Success) { $candidateSegment = $candidateSegment.Substring(0, [Math]::Min($candidateSegment.Length, $candidateId.Length + $nextHeading.Index)) }
        if ($candidateSegment.Length -lt 80) { throw "子 Agent $($cluster.Name) 的 chapter.md 对 $candidateId 只有标题或一句结论。" }
        if ($candidateSegment -notmatch '是什么|用于|保存|记录|缓存|组件|数据|文件|目录|安装|备份|维护') {
            throw "子 Agent $($cluster.Name) 的 chapter.md 未说明 $candidateId 的用途或性质。"
        }
        if ($candidateSegment -notmatch '保留|清理|删除|卸载|迁移|处理|核验|调查|不要|可以|无需|不建议') {
            throw "子 Agent $($cluster.Name) 的 chapter.md 未说明 $candidateId 的处理选择。"
        }
        if ($candidateSegment -notmatch '影响|会|不会|重新|失去|风险|代价|重建|下载|增长') {
            throw "子 Agent $($cluster.Name) 的 chapter.md 未说明 $candidateId 的处理影响或后续变化。"
        }
        $sourceRef = "$($cluster.Name):$candidateId"
        if (-not $sourceRefs.Add($sourceRef)) { throw "候选来源标识重复：$sourceRef" }
        $sequence++
        $record = [ordered]@{
            id = ('M-{0:D4}' -f $sequence)
            source_refs = @($sourceRef)
            source_cluster = $cluster.Name
            source_candidate_id = $candidateId
            review_status = 'pending_review'
        }
        foreach ($property in $finding.PSObject.Properties) {
            if ($property.Name -in @('id','source_refs','source_cluster','source_candidate_id','review_status')) { continue }
            $record[$property.Name] = $property.Value
        }
        $merged.Add([pscustomobject]$record)
    }
    $chapters.Add("<!-- source_cluster: $($cluster.Name) -->`r`n$($clusterChapter.Trim())")
}

if (-not (Test-Path -LiteralPath $outputRoot)) {
    New-Item -ItemType Directory -Path $outputRoot -Force | Out-Null
}
$findingsOutput = Join-Path $outputRoot 'findings.raw.json'
$coverageOutput = Join-Path $outputRoot 'coverage.raw.json'
$chaptersOutput = Join-Path $outputRoot 'chapters.raw.md'
$indexOutput = Join-Path $outputRoot 'merge-index.json'
foreach ($target in @($findingsOutput, $coverageOutput, $chaptersOutput, $indexOutput)) {
    if (Test-Path -LiteralPath $target) { throw "拒绝覆盖已有合并产物：$target" }
}

Write-JsonUtf8Bom $findingsOutput @($merged)
Write-JsonUtf8Bom $coverageOutput @($coverage)
[IO.File]::WriteAllText($chaptersOutput, (@($chapters) -join "`r`n`r`n") + "`r`n", [Text.UTF8Encoding]::new($true))
Write-JsonUtf8Bom $indexOutput ([ordered]@{
    schema_version = '1.0'
    created_at_utc = [DateTime]::UtcNow.ToString('o')
    cluster_count = $clusterDirectories.Count
    candidate_count = $merged.Count
    chapter_count = $chapters.Count
    source_refs = @($sourceRefs | Sort-Object)
})

Write-Output "MERGE_OK clusters=$($clusterDirectories.Count) candidates=$($merged.Count) output=$outputRoot"
