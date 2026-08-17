[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][string]$FindingsPath,
    [Parameter(Mandatory = $true)][string]$ChaptersPath,
    [Parameter(Mandatory = $true)][string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Has-Property([object]$Object, [string]$Name) {
    return $null -ne $Object -and $Object.PSObject.Properties.Name -contains $Name
}
function Value-Or([object]$Object, [string]$Name, [string]$Fallback = '未知') {
    if (Has-Property $Object $Name) {
        $value = [string]$Object.$Name
        if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
    }
    return $Fallback
}
function Format-Bytes([object]$Value) {
    if ($null -eq $Value) { return '未知' }
    $bytes = [double]$Value
    if ($bytes -ge 1GB) { return ('{0:N2} GiB' -f ($bytes / 1GB)) }
    if ($bytes -ge 1MB) { return ('{0:N1} MiB' -f ($bytes / 1MB)) }
    if ($bytes -ge 1KB) { return ('{0:N1} KiB' -f ($bytes / 1KB)) }
    return ('{0:N0} B' -f $bytes)
}

$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $ManifestPath | ConvertFrom-Json
$parsedFindings = Get-Content -Raw -Encoding UTF8 -LiteralPath $FindingsPath | ConvertFrom-Json
$findings = [object[]]$parsedFindings
$chaptersText = Get-Content -Raw -Encoding UTF8 -LiteralPath $ChaptersPath
if ([string]::IsNullOrWhiteSpace($chaptersText)) { throw "目录章节为空：$ChaptersPath" }
$target = [IO.Path]::GetFullPath($ReportPath)
if (Test-Path -LiteralPath $target) { throw "报告已存在，拒绝覆盖：$target" }
$parent = Split-Path -Parent $target
if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }

function Get-DisplayPath([object]$Finding) {
    if (Has-Property $Finding 'path') { return [string]$Finding.path }
    if (Has-Property $Finding 'paths') { return @($Finding.paths) -join '；' }
    return '未知'
}
$lines = [Collections.Generic.List[string]]::new()
function Add-Line([string]$Text = '') { $script:lines.Add($Text) }

Add-Line '# Windows 系统盘空间审计（初稿）'
Add-Line
Add-Line '> 本文由轻量发现记录生成，仅供主 Agent继续编辑、重组和补充。最终以人工审阅后的 Markdown 为准。'
Add-Line
Add-Line '## 审计概况'
Add-Line
Add-Line "- 模式：只读；本次未执行清理、删除或系统变更。"
if (Has-Property $manifest 'system_drive') { Add-Line "- 目标盘：$($manifest.system_drive)" }
if (Has-Property $manifest 'baseline_free_bytes') { Add-Line "- 基线可用空间：$(Format-Bytes $manifest.baseline_free_bytes)" }
Add-Line "- 已记录对象：$($findings.Count) 项。"
Add-Line
Add-Line '## 主要空间去向'
Add-Line
Add-Line '| 对象或目录 | 大概位置 | 占用与口径 | 它是什么 |'
Add-Line '|---|---|---:|---|'
$overviewCandidates = @(
    @($findings | Where-Object { (Has-Property $_ 'logical_bytes') -and $null -ne $_.logical_bytes } | Sort-Object @{ Expression = { -[double]$_.logical_bytes } })
    @($findings | Where-Object { (-not (Has-Property $_ 'logical_bytes') -or $null -eq $_.logical_bytes) -and (Has-Property $_ 'role') -and $_.role -eq 'focus' })
)
$overview = [Collections.Generic.List[object]]::new()
$overviewIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($finding in $overviewCandidates) {
    $overviewId = Value-Or $finding 'id'
    if ($overviewIds.Add($overviewId)) { $overview.Add($finding) }
    if ($overview.Count -ge 12) { break }
}
foreach ($finding in $overview) {
    $displayPath = (Get-DisplayPath $finding).Replace('|','\|')
    $summary = (Value-Or $finding 'summary').Replace('|','\|')
    $size = if ((Has-Property $finding 'logical_bytes') -and $null -ne $finding.logical_bytes) { Format-Bytes $finding.logical_bytes } else { '未知' }
    if ((Has-Property $finding 'measurement_status') -and -not [string]::IsNullOrWhiteSpace([string]$finding.measurement_status)) {
        $size = "$size（$($finding.measurement_status)）"
    }
    Add-Line "| $(Value-Or $finding 'id') | ``$displayPath`` | $size | $summary |"
}
Add-Line
Add-Line '> 以上是占用概览，不等于可回收空间。正文按目录解释每个对象的来源、用途和处理影响。'
Add-Line

Add-Line $chaptersText.Trim()
Add-Line

Add-Line '## 覆盖、限制与本次执行情况'
Add-Line
Add-Line '- 未检查或扫描不完整的范围，应由主 Agent根据原始证据补充。'
Add-Line '- 以上处理方式仅供用户理解和选择，不构成清理授权；执行前需重新核验对象和影响。'

$utf8Bom = [Text.UTF8Encoding]::new($true)
[IO.File]::WriteAllText($target, ($lines -join "`r`n") + "`r`n", $utf8Bom)
Write-Output $target
