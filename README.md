# Windows 磁盘空间排查

> 只读查清 Windows 系统盘空间去了哪里，并生成一份可以继续追问的目录报告。

[![License](https://img.shields.io/github/license/GantWu03/windows-disk-audit?style=flat-square)](LICENSE)
[![Last commit](https://img.shields.io/github/last-commit/GantWu03/windows-disk-audit?style=flat-square)](https://github.com/GantWu03/windows-disk-audit/commits/main)

系统盘越来越小，扫描工具通常先给出哪些目录占用较大。这个 Skill 会继续解释里面是什么、由什么活动产生、处理后会影响什么，还会如实保留没有查明的地方。最终报告可以留着反复追问，无需在第一次检查时就决定删什么。

它默认只读，不会自动删除文件、卸载软件、停止服务或修改系统设置。

## 安装

```powershell
npx skills add GantWu03/windows-disk-audit --skill windows-disk-audit
```

安装前可以先确认仓库里能识别到这个 Skill。

```powershell
npx skills add GantWu03/windows-disk-audit --list
```

也可以克隆仓库后从本地安装。

```powershell
git clone https://github.com/GantWu03/windows-disk-audit.git
cd windows-disk-audit
npx skills add . --skill windows-disk-audit
```

## 你可以直接这样说

- “只读检查我的 C 盘，先找出最大的空间占用。”
- “解释 Windows、AppData、Docker 和开发缓存为什么这么大。”
- “不要清理，告诉我每个目录有什么用，处理后会怎样。”
- “继续检查较小的项目，并补进原来的报告。”
- “针对报告里的 Playwright 浏览器目录继续深查。”

## 你会得到什么

报告开头是一张主要空间去向表，随后按真实目录展开。每个值得关注的对象会尽量讲清它的位置、占用口径、用途、产生原因、处理选择、可能影响和未查明之处。

下面是报告中的一个简化示例。数字仅用于展示格式，不代表你的电脑。

| 对象 | 占用与口径 | 它是什么 |
|---|---|---|
| Windows Installer | 18.6 GiB，完整逻辑大小 | 已安装软件用于更新、修复和卸载的维护缓存 |
| 开发工具缓存 | 4.2 GiB，部分扫描下界 | 包管理器和自动化工具下载的可再生文件 |

### `%LOCALAPPDATA%\Tool\Cache`

这个目录保存工具已经下载过的组件，用来减少以后重复联网。它不包含项目源码。空间紧张时，可以继续核验哪些版本仍被使用。处理缓存后，相关工具可能需要重新下载组件，目录也会随着使用再次增长。

一次完整调查通常还会保存这些文件，方便后续 Agent 接着检查。

| 文件 | 用途 |
|---|---|
| `audit-manifest.json` | 记录允许检查的范围、排除项和只读状态 |
| `cluster-plan.json` | 记录本机大目录如何分工，哪些地方暂时查不到 |
| `clusters/*/chapter.md` | 各目录的完整解释章节 |
| `merged/chapters.raw.md` | 保留各目录原文的合并正文 |
| `final/findings.json` | 可供后续核验和追问的事实索引 |
| 最终 Markdown | 给用户阅读的空间概览与目录报告 |

## 它会检查哪些地方

- 系统盘根目录里的休眠、分页、交换和未知对象
- Windows 更新、组件存储、驱动仓库、日志和安装维护数据
- Program Files、ProgramData、WindowsApps 和已安装程序
- 用户目录、AppData、浏览器、聊天软件和个人文件
- 包管理器、IDE、自动化浏览器、构建缓存和 AI 工具数据
- Docker、WSL、Hyper-V 与其他虚拟磁盘
- 本机实际出现、但通用清单没有提前列出的其他大目录

大目录会继续向下拆分。较小而且性质相近的目录可以合在一组说明。扫描遇到权限、超时或重解析点时，报告会保留未知范围，不会把它写成 0 B。

## 使用前提

- [ ] Windows 10 或 Windows 11
- [ ] PowerShell 5.1 或更高版本，可用 `$PSVersionTable.PSVersion` 查看
- [ ] 安装时需要 Node.js 与 npx，可用 `node --version` 和 `npx --version` 查看
- [ ] Agent 能读取你明确允许的目录
- [ ] 系统盘空间很紧张时，准备一个非系统盘目录保存报告和中间证据

管理员权限并非必需。没有管理员权限时，部分 Windows 目录会保持未知或只得到下界。Skill 不会为了补齐数字取得目录所有权。

没有子 Agent 的客户端也能使用。它会先形成同样的目录计划，再按顺序完成调查，速度可能更慢。

## 可调整的设置

| 设置 | 默认方式 | 什么时候调整 |
|---|---|---|
| 检查范围 | Windows 系统盘 | 只想调查某个目录时缩小范围 |
| 排除范围 | 空 | 不希望读取项目、私人文件或其他目录时添加 |
| 输出目录 | 用户指定 | 系统盘空间紧张时改到其他盘 |
| 时间预算 | 用户或 Agent 决定 | 需要更深调查或只想快速定位大头时调整 |
| 低空间门禁 | 5 GiB 的保守默认值 | 设备需要预留更多空间时提高 |
| 联网查询 | 按结论需要决定 | 产品行为和官方处理方式需要核实时使用 |

可以用随包提供的脚本创建只读清单。

```powershell
$skillRoot = (Resolve-Path -LiteralPath '<Skill 安装目录>').Path

& (Join-Path $skillRoot 'scripts\new_audit_manifest.ps1') `
  -OutputDirectory 'E:\StorageAudit' `
  -AllowedPaths "$env:SystemDrive\" `
  -TimeBudgetMinutes 60
```

## 安全边界

- 审计和清理分开进行，本轮没有具体授权就不改变系统状态
- `Cache`、`Temp`、旧日期和大体积只提供调查线索，不能单独证明文件可删
- `WinSxS`、Windows Installer、驱动仓库和 WindowsApps 不按普通目录手删
- 数据库、虚拟磁盘、项目、会话、备份和个人文件默认保留
- 权限不足只记录为检查缺口，不取得系统目录所有权
- 目录大小、预计可回收量和处理后实际释放的空间分别记录
- 系统盘进入危险区后停止新的高写入操作，报告改存到其他盘

报告中的建议供用户理解和追问。需要清理、迁移、卸载或修改设置时，应当另开任务，重新核验精确路径和当前活动状态，再由用户逐项确认。

## 它怎样工作

<details>
<summary>查看调查与合并方式</summary>

Skill 先取得系统盘容量和根一级目录基线，再根据本机真正出现的大头形成完整分工。每个重要目录由一个调查任务负责，目录内发现的新对象也由它继续说明。

各任务直接写出面向用户的目录章节。合并时保留全部候选和原始章节。主 Agent只生成开头概览、修正父子目录重复计量、合并真正相同的对象，并在不同章节互相矛盾时核实裁决。它不会为了缩短报告重新摘要子 Agent正文。

涉及产品归属、命令作用范围或处理影响时，负责该目录的 Agent应优先查看 Microsoft 或产品官方资料。没有足够证据时，结论保持为待调查。

详细方法见 [调查工作流](references/workflow.md)、[Windows 检查地图](references/windows-map.md) 和 [目录级操作手册](references/directory-procedures.md)。结构化记录方式见 [轻量记录约定](references/data-contracts.md)。

</details>

## 常见问题（Troubleshooting）

| 现象 | 常见原因 | 处理办法 |
|---|---|---|
| 目录显示 0 B | 权限不足、超时，或把目录自身的 `Length` 当成占用 | 查看覆盖记录，确认扫描是否完整，不要直接判断为空 |
| 扫描很慢 | 一开始递归了整个系统盘，或单个目录文件过多 | 退回一级目录和短名单，只继续调查排名靠前的大头 |
| 报告只剩清理建议 | 汇总时压缩了子任务章节 | 使用 `merged/chapters.raw.md` 作为正文，恢复按目录解释 |
| 缓存清完很快又长回来 | 生成它的应用仍在运行，或没有调整位置和上限 | 查明生成活动，再考虑迁移、限额或应用内设置 |
| 系统目录无法读取 | 当前会话没有管理员权限，或目录受系统保护 | 保留为未知或下界，不要取得所有权 |
| 找不到 Skill | 客户端安装目录或发现规则不同 | 先运行 `npx skills add GantWu03/windows-disk-audit --list`，再检查客户端 Skill 目录 |

## 开发与验证

运行单元测试。

```powershell
python -m unittest discover -s tests -p "test_*.py"
```

检查 Skill 包结构。请把 `<meta-skill目录>` 换成 qiaomu-meta-skill 的实际安装位置。

```powershell
python <meta-skill目录>\scripts\validate_skill.py .
```

检查示例报告的安全和完整性门禁。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File scripts\validate_report.ps1 `
  -ManifestPath evals\fixtures\sample-manifest.json `
  -MergedFindingsPath evals\fixtures\sample-merged-findings.json `
  -ReportPath evals\fixtures\sample-report.md `
  -FindingsPath evals\fixtures\sample-findings.json
```

## 许可证

[MIT License](LICENSE)
