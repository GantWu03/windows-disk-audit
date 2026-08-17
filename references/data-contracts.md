# 轻量记录约定

结构化数据用于保留事实、方便合并和防止数字漂移，不是要求模型把每个对象填成同样长度的表格。最终 Markdown 可以自然组织；未知扩展字段应被接受。

## 审计清单

建议先用 `scripts/new_audit_manifest.ps1` 生成 `audit-manifest.json`。只读审计的硬性值是：

```json
{
  "mode": "read_only",
  "cleanup_authorized": false,
  "allowed_paths": ["规范化绝对路径"],
  "excluded_paths": [],
  "output_directory": "绝对路径"
}
```

目标不能静默越出 `allowed_paths`；排除路径优先。UNC、相对路径和未解析环境变量不进入清单。中间文件集中到 `work\<executor_id>`；最终交付后清理本次任务明确创建且用途已知的临时文件。

## 目录簇计划

基线完成后、启动子 Agent前写出 `cluster-plan.json`。它用于证明分工来自本机实际占用，而不是固定模板。每个目录簇至少记录稳定 `cluster_id`、负责路径、分组理由和产物目录；可以增加预期大头、相关操作卡、执行顺序或 Agent 标识。

```json
{
  "based_on": "baseline/inventory.json",
  "clusters": [
    {
      "cluster_id": "windows-system",
      "paths": ["C:\\Windows"],
      "grouping_reason": "本机显著大目录，内部需要连续下钻",
      "output_directory": "clusters\\windows-system"
    },
    {
      "cluster_id": "small-user-tools",
      "paths": ["C:\\Users\\Example\\.cache", "C:\\Users\\Example\\.gradle"],
      "grouping_reason": "多个较小开发目录，生成活动和处理影响相近",
      "output_directory": "clusters\\small-user-tools"
    }
  ]
}
```

显著大目录原则上独立成簇，多个较小目录合并；同一应用跨位置的数据可放在同一簇。子 Agent可以继续调查 `paths` 内新发现的子项，但不得跨入其他簇或越出授权范围。

基线中达到本次“大目录”标准的每个一级对象必须在计划里记录 `assigned_cluster`，或者进入顶层 `blind_spots` 并说明未调查原因。阈值按本机容量、空间紧迫程度和本次预算确定，不要求固定 GiB 数；不能静默遗漏未知、超时或固定清单之外的大目录。

## 发现记录

每个目录簇的 `findings.json` 顶层为数组，保存该簇已经形成的全部候选。空目录和未达到本次候选标准的普通文件不必入选；候选一旦写入，后续不得因低收益省略。每个目录簇另写 `coverage.json`，至少说明检查路径、完整/部分状态及限制，并写 `chapter.md` 直接解释该目录簇中的对象。

最小记录示例：

```json
{
  "id": "U-001",
  "path": "C:\\Users\\Example\\AppData\\Local\\Tool\\Cache",
  "summary": "某开发工具下载和构建产生的可再生缓存，本次占用较大。",
  "observations": [
    "只读测量得到约 2.6 GiB 逻辑大小",
    "相关应用当前未运行"
  ],
  "state_changes_performed": [],
  "actual_result": "not_executed"
}
```

轻量核心包括：稳定 `id`、实际 `path`（聚合记录可改用 `paths`）、能独立读懂的 `summary`、至少一项本机 `observations`、空的 `state_changes_performed` 和 `actual_result=not_executed`。其中后两项是只读安全证明。

根据重要性按需增加：

```json
{
  "path_template": "%LOCALAPPDATA%\\Tool\\Cache",
  "role": "focus",
  "logical_bytes": 2791728742,
  "measurement_status": "complete",
  "source": "生成者",
  "purpose": "用途",
  "creation_reason": "出现原因",
  "active_use": "no",
  "recommendation": "现在不必定期清空；急需空间时退出工具后，只清理其已确认的下载缓存，不要删除整个工具目录。",
  "impact": "不会影响已经安装的工具或现有源码；以后使用缺失组件时会重新下载，因此网络较慢时不值得频繁清。",
  "risk": "low",
  "priority": "normal",
  "reclaimable_min_bytes": null,
  "reclaimable_max_bytes": null,
  "reclaim_basis": null,
  "evidence": [
    {
      "kind": "local|official|specialized|cross_check",
      "locator": "命令、证据文件或 URL",
      "supports": "该证据实际支持的结论"
    }
  ],
  "uncertainty": "仍未知的部分",
  "next_check": "若要执行，下一项最有价值的核验"
}
```

`role` 可用于表达详略：

- `focus`：影响用户决策，需要负责该目录的子 Agent深入解释。
- `brief`：有用但在前因后果相同的情况下可以合并或简写。
- `record`：只需较短解释，但仍在目录正文中说明基本用途和当前为何不处理。

不要求每项都填写 `role`，负责目录的子 Agent也可以直接在撰写章节时判断详略。

目录簇覆盖记录使用轻量结构：

```json
{
  "checked_paths": ["C:\\Example"],
  "completeness": "complete|partial",
  "limitations": ["超时、权限、活动文件或未展开范围"],
  "blind_spots": ["仍未解释的对象"]
}
```

`checked_paths` 也可按工具改名为 `scope` 或 `paths_checked`；路径和完整性状态必须存在。盘点脚本的 `measurement_kind=complete_logical` 对应发现中的 `measurement_status=complete`，`partial_lower_bound` 对应 `partial`，且正文必须称为下界而不是完整值。

`limitations` 和 `blind_spots` 是对子 Agent结论边界的正式声明。无损合并和最终报告必须保留；除非真实矛盾裁决取得了能解决该项的新证据，否则主 Agent不得删除、弱化或改写为确定事实。

同目录的 `chapter.md` 至少让每个候选 ID 出现在自己的解释中，并自然包含对象用途或性质、处理选择及影响。合并脚本检查这些语义是否存在，但不规定小标题、段落数量或固定措辞。

## 无损合并与来源闭合

运行 `scripts/merge_findings.ps1` 后，每个候选获得稳定的 `source_refs`，例如 `win-sys:F-003`，并进入 `merged/findings.raw.json`。主 Agent在其上通过去重、重复计数修正和必要矛盾裁决形成 `final/findings.json`：

- 每项保留非空 `source_refs` 和自然语言 `review_status`；
- 主 Agent在矛盾裁决中新增发现使用 `main:<id>` 来源；
- 合并真正重复的记录时，一个最终项可以引用多个来源；
- 拆分一个混合候选时，多个最终项可以引用同一来源；
- 来源、对象类别、处理方法或影响不同的子目录不能只因同属一个父目录而聚合；
- 合并集合里的每个来源都必须在最终结果中出现。主 Agent只在跨章节矛盾裁决时修正事实结论，不可按重要性筛除。

这是内部完整性协议，不要求 Markdown 展开同样的字段结构；但结构化来源闭合不能替代面向用户的目录解释。

## 字段选择原则

- 有数字就说明口径。`logical_bytes` 是枚举长度总和；超时或权限受限时标为部分结果。
- `allocated_bytes` 只有专用工具能正确处理硬链接、稀疏、压缩或去重时才填写。
- `reclaimable_min/max` 只在已识别可处理子集或官方/应用工具给出范围时填写；不能复制目录逻辑大小。
- 观察和推断可以分开保存，也可以在 `summary`/`observations` 中清楚标明“观察到”和“据此推测”。高风险结论应更明确地区分。
- `recommendation` 要让用户知道具体做什么、不做什么、是否值得；`impact` 要说明当前软件/项目/数据和未来重下载、重建或复发。只有相关时才分别展开。
- `evidence` 可以是本机事实、官方资料或专用工具。低收益记录不强制外部证据；会改变系统或数据的建议应有足够依据。
- 允许添加任意有用字段；不要为了适配本约定丢失更精确的证据。

### 动作性建议的 decision index

纯描述、保留和待调查记录仍可保持轻量。只要报告提出清理、系统维护、应用清理、卸载、迁移或隔离等动作，必须在对应发现中加入 `recommended_action`，并保留足以审计该决定的少量信息：`object_class`、`active_use`、自然语言 `recommendation`、`impact`、`decision_basis` 和至少一条本机、官方或专用 `evidence`。报告在相关段落引用发现 ID。

`recommended_action` 只使用以下规范值：`none`、`keep`、`investigate`、`clean_via_system`、`clean_via_app`、`uninstall`、`migrate`、`isolate`、`direct_clean`、`delete`、`system_setting_change`、`archive_or_cleanup`。未知值直接失败，避免动作建议绕过校验。

这不是要求所有发现填表，而是让会改变系统或数据的建议无法脱离证据索引。易变且涉及状态变化的产品命令若没有已核验官方资料或专用本机证据，应降为继续调查；受保护对象的动作性建议必须有官方或专用证据。联网仍由 Agent自行选择。

## 安全校验

以下规则始终适用：

1. 只读审计的 `state_changes_performed` 必须为空，`actual_result` 必须为 `not_executed`。
2. 权限不足、超时、访问失败和部分扫描不能写成完整、0 B 或无影响。
3. 非零可回收范围必须有明确依据，且上下界同时填写。
4. 系统维护对象、安装修复源、活动数据库、虚拟磁盘、恢复数据、项目和用户原始数据不能建议直接按文件删除。
5. 活动对象不能标为立即直接清理。
6. “未发现某种引用”、旧时间、相同大小或可重新下载不能单独证明可删除。
7. 父目录和子目录不能同时计入空间收益汇总。
8. 最终 Markdown 开头包含主要空间去向概览表，正文按真实目录组织并出现每个最终发现 ID；不能用行动摘要代替目录解释。

验证器只强制候选闭合、动作枚举、安全和一致性规则。它不要求固定章节、固定字段总数、每项同样详尽或确定性 Markdown。
