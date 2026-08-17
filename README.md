# windows-disk-audit

> 把“C 盘快满了”变成一份有调查顺序、有证据、能解释处理影响的 Windows 系统盘空间审计报告。

该 Skill 先做只读盘点，再按故障关联、空间收益和风险定向深查。它提供调查框架和目录教程，但不会把模型限制成逐字段填表，也不会把 `Cache`、`Temp`、旧日期或大文件直接当成可删证据。

## 适用场景

- C 盘持续变小，不知道哪个目录在增长。
- 想系统检查 Windows、应用、用户缓存、Docker、WSL 和虚拟磁盘。
- 想知道一个文件如何产生、有什么用、处理后会怎样。
- 想把多轮排查整理成可复盘的中文 Markdown。

不用于 RAM、云盘配额、非 Windows 系统，也不是一键“系统优化器”。

## 安装与调用

可以直接从 GitHub 安装：

```powershell
npx skills add GantWu03/windows-disk-audit --skill windows-disk-audit
```

也可以克隆仓库后从本地安装：

```powershell
npx skills add . --list
npx skills add . --skill windows-disk-audit
```

## 你可以直接这样说

```text
用 windows-disk-audit 只读检查我的 C 盘，先查大头，最后输出中文 Markdown 报告。
```

```text
检查 Windows Update、Docker、WSL 和 AppData 为什么占这么多，不要清理。
```

```text
继续补查较小文件，并把重要结论合并到同一份 C 盘排查报告。
```

## 设计方式

流程由六步组成：

1. 定义只读范围，取得容量和根一级基线。
2. 依据故障关联、收益、风险和调查成本形成短名单。
3. 基线完成后，先按本机实际大头确定完整分工：显著大目录一个子 Agent，多个较小目录按来源或用途合并；每个一级大目录必须分配或列为盲区，再在软件允许范围内并行调查。
4. 脚本无损合并全部候选；主 Agent只生成概览、修正父子计量、合并真正重复项和裁决真实矛盾。最终正文直接使用子 Agent章节，不再重写或压缩。
5. 大头解释后，按需要聚合小文件和补查盲区。
6. 报告开头用表格概述主要空间去向，正文按真实目录解释对象的用途、成因、处理选择和影响；清理另开任务并逐项授权。

[Windows 检查地图](references/windows-map.md) 说明常见区域，[目录级操作手册](references/directory-procedures.md) 说明进入目录后如何定界、拆分、识别生成者和核验影响。这些内容是可调整的教程。模型可以使用更精确的只读工具、增加调查维度、改变表达方式或继续探索未枚举的线索，只需遵守范围和安全边界。

## 目录章节与主 Agent汇总

子 Agent或串行目录簇直接按目录撰写 `chapter.md`，并对负责路径内的事实、依据、处理选择和影响负责；目录内新发现的大头继续由它调查。`scripts/merge_findings.ps1` 无损合并候选。最终正文直接使用这些章节；主 Agent只生成概览、修正父子计量、合并真正重复项和裁决真实矛盾，不做摘要或文风重写。子 Agent承认的盲区和不确定性必须保留，不能在最终报告中升级为确定结论。

子 Agent先检查本机事实；涉及产品归属、官方维护方法、命令范围、删除影响或易变行为时，优先查找 Microsoft 或产品官方资料。官方资料不可用或未回答问题时，再使用专用工具、可靠一手资料或标明推断。主 Agent只在裁决矛盾时补查。

## 数据与报告

- `audit-manifest.json` 保存范围、授权和预算。
- `cluster-plan.json` 保存基于本机基线、在启动子 Agent前确定的目录簇、负责路径和分组理由。
- `baseline\` 与 `clusters\` 保存原始只读证据、目录簇候选、覆盖记录和 `chapter.md`。
- `merged\findings.raw.json` 与 `merged\chapters.raw.md` 分别保存子 Agent候选和目录章节的无损集合。
- `final\findings.json` 保存无损合并、去重和必要矛盾裁决后的完整候选；若报告包含动作性建议或可回收数字则建立对应 decision index。[轻量记录约定](references/data-contracts.md) 只要求少量安全与来源字段，其余按对象需要选择。
- 各目录簇 `chapter.md` 是面向用户的原始解释章节。
- 最终 Markdown 由主 Agent生成的“主要空间去向”概览表和子 Agent原章节构成；正文只允许删除真正重复、修正父子计量和合入真实矛盾裁决。

`scripts/render_report.ps1` 可以从轻量记录生成可编辑初稿，但不是唯一报告生成方式。`scripts/validate_report.ps1` 检查候选来源闭合、只读状态、范围、动作枚举、危险建议和无依据可回收量等硬门禁，不要求固定章节或与渲染器逐字一致。

报告开头用表格列出主要对象或目录、占用口径和它是什么；正文以真实目录为主线。每个有意义的对象自然解释位置、占用、用途、形成原因、可选处理方式、处理影响、依据和不确定性。这些是解释责任，不是固定 schema；只有来源、性质、处理方式和影响相同的对象才能合并。默认不生成行动排行榜，是否处理由用户阅读后决定。

## 只读脚本

```powershell
$skillRoot = (Resolve-Path -LiteralPath '<Skill 安装目录>').Path
& (Join-Path $skillRoot 'scripts\new_audit_manifest.ps1') `
  -OutputDirectory E:\StorageAudit `
  -AllowedPaths "$env:SystemDrive\" `
  -TimeBudgetMinutes 60
$manifestPath = 'E:\StorageAudit\audit-manifest.json'

& (Join-Path $skillRoot 'scripts\collect_inventory.ps1') `
  -ManifestPath $manifestPath `
  -Phase baseline `
  -SecondsPerPath 5
```

需要生成初稿和检查硬门禁时：

```powershell
& (Join-Path $skillRoot 'scripts\merge_findings.ps1') `
  -ClustersDirectory E:\StorageAudit\clusters `
  -OutputDirectory E:\StorageAudit\merged

& (Join-Path $skillRoot 'scripts\render_report.ps1') `
  -ManifestPath $manifestPath `
  -FindingsPath E:\StorageAudit\final\findings.json `
  -ChaptersPath E:\StorageAudit\merged\chapters.raw.md `
  -ReportPath E:\StorageAudit\final\报告初稿.md

& (Join-Path $skillRoot 'scripts\validate_report.ps1') `
  -ManifestPath $manifestPath `
  -MergedFindingsPath E:\StorageAudit\merged\findings.raw.json `
  -ReportPath E:\StorageAudit\final\C盘空间排查报告.md `
  -FindingsPath E:\StorageAudit\final\findings.json
```

## 安全边界

- 不手删 `WinSxS`、`Windows\Installer`、`System32`、驱动仓库或 WindowsApps 内部文件。
- 不把休眠、分页、交换文件按普通文件处理。
- 不在更新、安装、数据库、虚拟机或相关应用运行时清理。
- 不因工作树很旧、日志很大、虚拟磁盘长时间未修改就判断可删。
- 权限不足只记录为检查缺口，不夺取系统目录所有权。
- 系统盘进入危险空间区时，不启动新的高写入操作，把报告和临时文件放到其他盘；脚本的 5 GiB 门禁是可调整的保守默认值。

## 验证

```powershell
python -m unittest discover -s tests -p "test_*.py"
python <meta-skill目录>\scripts\validate_skill.py .
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\validate_report.ps1 `
  -ManifestPath evals\fixtures\sample-manifest.json `
  -MergedFindingsPath evals\fixtures\sample-merged-findings.json `
  -ReportPath evals\fixtures\sample-report.md `
  -FindingsPath evals\fixtures\sample-findings.json
npx skills add . --list
```

当前为公开候选版本。内置测试验证结构化合并、范围门禁和报告安全约束；不同客户端、Windows 版本与真实机器环境仍可能表现不同，请保留只读边界并核对报告中的不确定性。

## Troubleshooting

- 显示 0 B 时先看权限、超时和扫描完整性，不要直接判断为空目录。
- 扫描太慢时退回一级目录和短名单，减少单次目标，不递归整个系统盘。
- 报告变成行动摘要时，恢复“概览表 + 真实目录正文”；让每个对象说明用途、成因、选择和影响，不通过删候选或一句建议换取简洁。
- 缓存很快长回来时，调查生成活动、位置和上限，不重复盲目清空。

## 许可

MIT License  
Copyright (c) 2026 The windows-disk-audit contributors
