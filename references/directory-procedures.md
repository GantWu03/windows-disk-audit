# 目录级操作手册

本文件回答“进入一个候选目录后具体怎么查”。`windows-map.md` 决定查哪里；本文件提供可组合的调查步骤、证据线索和停止条件。它是教程，不是逐项验收表。模型可采用更直接或更精确的只读方法，并按收益与风险选择深度；范围、授权、父子去重与活动状态仍是硬门禁。默认只读，示例中的占位符需先替换为已解析的精确路径。

## 一张目录操作卡的完成标准

对重要短名单目录，通常按以下顺序推进；已有专用工具或充分证据时可以跳过不会改变结论的步骤。不能只看名称或总大小就下结论。

1. **定界**：记录精确绝对路径、通用变量路径、负责的目录簇和为什么入选。
2. **识别边界**：确认是否存在、是否为目录、是否为重解析点、目标是否跨卷。
3. **一层拆分**：先测直接子项，找出真正的大头；不要立即无限递归整个目录。
4. **深查大头**：只对排名靠前或异常增长的子项继续拆一层；记录超时和权限错误。
5. **识别生成者**：结合进程、服务、安装登记、包登记、文件版本、配置和官方 CLI 判断来源。
6. **判断活动与内容**：区分程序主体、用户状态、数据库、安装维护源、下载副本、日志、缓存和未知内容。
7. **形成建议**：对会影响决策的对象，说明占用口径、建议、主要影响与依据；低收益记录无需补齐无关内容。

完成标准不是七项填满，而是当前结论有足够依据：范围和测量状态明确；对象类别与活动性足以支撑当前判断；任何动作或收益结论都能追溯到 decision index。缺少这些基础时保持待调查，不能把 `unknown` 改写成“可清理”。

## 通用操作：所有普通目录先做这六步

### A. 解析并核验目标

```powershell
$target = [Environment]::ExpandEnvironmentVariables('<候选路径>')
$target = [IO.Path]::GetFullPath($target)
Get-Item -LiteralPath $target -Force |
  Select-Object FullName,PSIsContainer,Length,CreationTimeUtc,LastWriteTimeUtc,Attributes,LinkType,Target
```

记录：`path`、`path_template`、`exists`、时间、属性、`LinkType`、`Target`。路径不存在就记为“未发现”，不要创建它；根对象是重解析点时不得递归，先记录其目标卷并交给对应目录簇。

### B. 列直接子项，不计算目录大小

```powershell
Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue |
  Select-Object FullName,PSIsContainer,Length,LastWriteTimeUtc,Attributes,LinkType,Target
```

这一步只回答“里面有什么”。目录的 `Length` 为空不是 0，占用仍未知。把访问错误单独记录。

### C. 测直接子项，生成本层排行榜

先定位 Skill 根目录，并使用清单中的独立 `cluster_id`；脚本拒绝覆盖已有结果。

```powershell
$skillRoot = (Resolve-Path -LiteralPath '<Skill 安装目录>').Path
$manifestPath = (Resolve-Path -LiteralPath '<审计输出目录>\audit-manifest.json').Path
$clusterId = '<稳定编号>'
$children = @(Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue |
  Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
  Select-Object -ExpandProperty FullName)

if ($children.Count -eq 0) {
  [pscustomobject]@{ status='unresolved'; reason='no_direct_children'; partial_results_returned=$true }
} else {
  & (Join-Path $skillRoot 'scripts\collect_inventory.ps1') `
    -ManifestPath $manifestPath `
    -Phase cluster `
    -ClusterId $clusterId `
    -Paths ([string[]]$children) `
    -SecondsPerPath 20
}
```

从 `<审计输出目录>\clusters\<稳定编号>\inventory.json.targeted_measurements` 读取 `logical_bytes`、文件数、最近写入、`complete`、`timed_out`、`access_errors`。只在同一统计口径内排序；`allocated_bytes` 默认保持 `null`。

### D. 只继续拆大头

优先继续调查以下子项：排名靠前、近期仍写入、名称未知，或其大小足以解释本次空间异常。1 GiB 可作为常见设备的起始提示，但应服从本次收益阈值。对它重复 A–C。满足任一条件就停止向下：

- 子项已经能识别为不可手删的整体，例如程序主体、数据库或虚拟盘；
- 剩余未解释部分小于当前收益阈值；
- 连续两层没有新增高收益对象；
- 超时或权限错误已使结论无法可靠；
- 即将进入其他目录簇或重解析点。

### E. 查生成者和活动状态

```powershell
# 相关进程；用精确产品根或可执行文件名过滤结果，不要只看进程显示名
Get-CimInstance Win32_Process |
  Select-Object ProcessId,Name,ExecutablePath,CommandLine

# 安装登记；禁止用 Win32_Product，它可能触发 MSI 修复
Get-ItemProperty `
  'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', `
  'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*', `
  'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' `
  -ErrorAction SilentlyContinue |
  Select-Object DisplayName,DisplayVersion,Publisher,InstallLocation,UninstallString

# 对候选可执行文件核验版本和签名
Get-Item -LiteralPath '<精确可执行文件>' -Force |
  Select-Object FullName,@{n='Product';e={$_.VersionInfo.ProductName}},@{n='Version';e={$_.VersionInfo.FileVersion}}
Get-AuthenticodeSignature -LiteralPath '<精确可执行文件>' |
  Select-Object Status,SignerCertificate
```

进程路径命中、服务正在运行、文件持续增长或更新/同步未结束时，`active_use=yes`，本轮只记录。

### F. 给出本层结论

形成能支撑决策的简短结论：本层总量是否完整、主要子项、是否与父目录重复，以及还值得深查什么。低收益目录可合并记录；建议用自然语言说明，不受固定动作枚举限制。

`direct_clean` 只适用于来源、内容和重建路径均已验证的非活动对象，且仍需清理任务中的逐项授权。

## 操作卡 1：系统盘根目录

1. 列出根目录所有文件和一级目录；根目录文件直接记录大小，一级目录只作候选。
2. 对 `hiberfil.sys`、`pagefile.sys`、`swapfile.sys` 只识别，不尝试访问或删除：

```powershell
Get-CimInstance Win32_PageFileUsage |
  Select-Object Name,AllocatedBaseSize,CurrentUsage,PeakUsage
powercfg /a
```

3. `hiberfil.sys` 的文件大小与“关闭休眠后可能释放空间”不是同一证据；还要说明休眠和快速启动影响。
4. 对未知根目录先执行通用 A–C，再查顶层可执行文件的版本/签名、最近写入和相关进程。
5. `$Recycle.Bin`、`System Volume Information`、`Recovery` 只记录存在、可见大小和访问限制；转入系统管理类，不取得所有权。

产出：根目录条目表、三个系统管理文件说明、未知根目录短名单。门禁：不能把根目录一级目录的目录时间或空 `Length` 当作占用。

## 操作卡 2：Windows 系统区

先分别测量候选路径，不把整个 `%WINDIR%` 当成第一轮递归目标。

### 2.1 组件、安装和驱动维护

- `%WINDIR%\WinSxS`：记录限时逻辑大小，再运行只读分析：

```powershell
DISM.exe /Online /Cleanup-Image /AnalyzeComponentStore
```

报告采用 DISM 的可回收建议；资源管理器或递归求和因硬链接只能作辅助。

- `%WINDIR%\Installer`：先读取 [Windows Installer 缓存附注](windows-installer-cache.md)，再测量大小和近期写入，读取 MSI/MSP 元数据并跨安装上下文核对维护引用。没有可靠引用分析和厂商支持方式时建议只能是 `keep`/`investigate`，可安全回收量为未知。
- `DriverStore\FileRepository`：用 `pnputil /enum-drivers` 建立驱动包对应关系；不要按目录日期删除。

### 2.2 Windows Update

```powershell
Get-Service BITS,wuauserv,TrustedInstaller -ErrorAction SilentlyContinue |
  Select-Object Name,Status,StartType
Get-ItemProperty `
  'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' `
  -ErrorAction SilentlyContinue
```

分别测 `SoftwareDistribution\Download` 与 `DataStore`，不得合并判断。服务活动、待重启或文件持续写入时只观察；处理建议必须指向 Windows 的受支持清理方式。

### 2.3 转储、日志与 Temp

分别测 `MEMORY.DMP`、`Minidump`、`LiveKernelReports`、CBS/DISM/Panther 日志和 `%WINDIR%\Temp`。记录最近崩溃/更新时间，并向用户确认是否仍在排障。Temp 中被占用或近期更新写入的文件跳过，不能把未能删除等同于异常。

产出：每个系统子类单独一项，附相应系统命令证据。门禁：Installer、WinSxS、DriverStore、事件日志文件不得得到 `direct_clean`。

## 操作卡 3：程序目录、ProgramData 与 WindowsApps

1. 对 `%ProgramFiles%`、`%ProgramFiles(x86)%`、`%ProgramData%` 各自执行通用 A–C，以产品目录为第一层。
2. 对大产品目录先查卸载登记、Publisher、InstallLocation、正在运行的可执行路径，再分成：程序主体、共享运行时、更新下载、补丁 staging、日志/转储、模型/资源和未知状态。
3. 程序主体只建议标准卸载；更新下载和缓存只有在应用关闭、内容可再生且产品无维护引用时，才进入应用内清理候选。
4. WindowsApps/APPX 使用注册信息核对，不按文件夹名称判断重复：

```powershell
Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue |
  Select-Object Name,PackageFullName,Version,Architecture,InstallLocation,PackageUserInformation
```

5. 相近版本必须比较架构、框架/资源/主包类型、用户注册和实际 `InstallLocation`；多条登记不等于多份可删实体。

产出：产品级占用排行和每个产品内的内容分类。门禁：没有卸载/包注册证据时，不把程序目录标为重复版本或残留。

## 操作卡 4：用户根目录与隐藏目录

1. 对 `%USERPROFILE%` 只列一级条目；把 Desktop、Downloads、Documents、媒体、云同步与隐藏开发目录分开。
2. 对隐藏目录按生成者聚类，分别识别包缓存、工具链、浏览器运行时、IDE 系统目录、AI 工具状态、源码/worktree、模型和备份。
3. 对疑似项目先检查版本控制状态；对数据库先查主库及 `-wal`/`-shm` 集合；对浏览器 profile 先查账号、扩展和离线数据。
4. 可再生缓存要同时记录清理后的重下载量、重建时间、复发速度，以及能否通过配置迁移到非系统盘。

产出：生成者级汇总，而不是数百个点目录列表。门禁：项目、会话、数据库、备份、模型和工作副本默认保留或待调查，不因年代和体积直接进入清理候选。

## 操作卡 5：Local 与 Roaming 应用数据

1. 分别对 `%LOCALAPPDATA%` 和 `%APPDATA%` 执行 A–C，以产品根目录为第一层，不整盘混算。
2. 对入选产品目录再拆为 `Cache/Code Cache/GPUCache`、日志、CrashDumps、updater/download/staging、插件、Service Worker、数据库、LocalState/配置和用户内容。
3. 用进程路径确认应用是否退出；Electron/WebView/浏览器类应用必须区分缓存目录与整个 `User Data`/profile。
4. `%LOCALAPPDATA%\Packages` 先按包名映射 `Get-AppxPackage`，只研究确认可再生的子目录；`LocalState` 和账号状态默认保留。
5. Roaming 内容通常承担漫游配置、多账号和插件状态；同名 `Cache` 也要说明退出登录、离线内容与首次启动代价。

产出：产品 → 子目录性质 → 建议动作三级说明。门禁：不能对产品根、`Packages`、`User Data` 或 profile 根给出整目录清理建议。

## 操作卡 6：Docker、WSL 与虚拟磁盘

先用管理工具定位真实数据，再测宿主路径；禁止先全盘搜索并把所有 `.vhdx` 当缓存。

### Docker

```powershell
docker info --format '{{.DockerRootDir}}'
docker system df -v
docker context show
```

分别记录镜像、容器、构建缓存、命名卷和工具报告的 reclaimable。命名卷单列为用户/数据库数据；不运行任何 prune。

### WSL

```powershell
wsl --status
wsl --list --verbose
Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction SilentlyContinue |
  ForEach-Object { Get-ItemProperty $_.PSPath } |
  Select-Object DistributionName,BasePath,Version,State
```

从发行版注册的 `BasePath` 定位虚拟盘。分别记录宿主 VHDX 大小、客体内已用/空闲和发行版用途；内部删除不代表宿主文件立即缩小。

若用户后续要求迁移，必须另开状态变更任务并按以下顺序执行；审计阶段只把它写成待选方案：

1. **记录旧发行版**：保存发行版名、WSL 版本、默认用户、`BasePath`、客体磁盘使用量和关键服务/项目清单。
2. **导出到非系统盘**：经逐项授权后使用 `wsl --export <旧发行版名> <非系统盘备份文件.tar>`；导出前正常停止正在写入的服务。
3. **验证导出物**：确认备份文件存在且大小合理，记录 SHA-256，并用归档工具只读列出内容；无法读取就停止，不能注销旧发行版。
4. **导入为新实例**：确认目标盘空间和目标目录后，使用 `wsl --import <新发行版名> <非系统盘安装目录> <备份文件.tar> --version <1或2>`。新旧名称必须不同，以保留回退路径。
5. **启动验证**：运行 `wsl -d <新发行版名>`，核对默认用户、home、关键项目、权限、网络、包管理器和必要服务；记录失败项。
6. **观察与回退**：在用户认可的观察期内保留旧发行版和导出包。新实例失败时停止使用并回到旧实例，不覆盖唯一备份。
7. **最后注销旧实例**：只有新实例验证通过、用户再次明确授权且可靠备份仍存在时，才允许 `wsl --unregister <旧发行版名>`。该命令永久删除旧发行版数据，不得与导出或导入放在同一无停顿脚本中。

命令语义应在执行当日复核 Microsoft WSL 官方命令文档：<https://learn.microsoft.com/windows/wsl/basic-commands>。

### Hyper-V 与第三方虚拟机

```powershell
Get-VM -ErrorAction SilentlyContinue
Get-VMHardDiskDrive -VMName '<已确认虚拟机名>' -ErrorAction SilentlyContinue
Get-VHD -Path '<已确认虚拟盘路径>' -ErrorAction SilentlyContinue |
  Select-Object Path,VhdType,FileSize,Size,ParentPath,Attached
```

第三方虚拟机优先读取其管理器清单或 CLI，再核对 VDI/VMDK、快照和差分盘父子关系。

产出：管理工具视图、宿主文件大小、客体使用量、可回收对象四组数据。门禁：这四组数据不得互换；VHD/VHDX/VDI/VMDK、发行版和 volume 永远不能 `direct_clean`。

## 操作卡 7：个人目录、未知对象与疑似重复文件

1. 对个人目录按安装包/压缩包、媒体、项目、同步数据和未知文件分组；默认按用户数据处理。
2. 未知文件先看元数据、签名和前 16 字节，不因扩展名下结论：

```powershell
Get-Item -LiteralPath '<精确文件>' -Force |
  Select-Object FullName,Length,CreationTimeUtc,LastWriteTimeUtc,Attributes
Get-Content -LiteralPath '<精确文件>' -Encoding Byte -TotalCount 16
Get-AuthenticodeSignature -LiteralPath '<精确文件>' -ErrorAction SilentlyContinue
```

把前 16 字节同时显示为十六进制和 ASCII，避免模型把十进制字节误认成文件签名：

```powershell
$head = @(Get-Content -LiteralPath '<精确文件>' -Encoding Byte -TotalCount 16)
[pscustomobject]@{
  Hex   = ($head | ForEach-Object { $_.ToString('X2') }) -join ' '
  ASCII = [Text.Encoding]::ASCII.GetString([byte[]]$head)
}
```

常见签名只用于判断“可能是什么容器”，不能证明具体内容、来源或可删除性：

| 开头的十六进制/ASCII | 常见格式 | 下一步 |
|---|---|---|
| `4D 5A` / `MZ` | Windows PE，可为 EXE、DLL 或驱动 | 查版本、数字签名、安装登记和运行路径 |
| `50 4B 03 04` / `PK` | ZIP 容器，也可能是 Office、JAR、插件包 | 只读列目录，再结合父目录和生成应用判断 |
| `53 51 4C 69 74 65 20 66 6F 72 6D 61 74 20 33 00` | SQLite 3 数据库 | 同时寻找同名 `-wal`、`-shm`，应用运行时不处理 |
| `25 50 44 46 2D` / `%PDF-` | PDF | 按用户文档处理，确认来源和保留价值 |
| `89 50 4E 47 0D 0A 1A 0A` | PNG 图片 | 判断是用户内容、应用资源、缩略图还是缓存 |
| `FF D8 FF` | JPEG 图片 | 判断是否为用户唯一副本或可再生预览 |
| `37 7A BC AF 27 1C` | 7-Zip 压缩包 | 只读列目录，确认是否为备份、安装包或任务产物 |
| `1F 8B` | GZIP 压缩流 | 结合文件名、父目录和生成工具判断 |
| `76 68 64 78 66 69 6C 65` / `vhdxfile` | VHDX 虚拟磁盘 | 立即转交虚拟化操作卡，禁止按普通大文件处理 |

未匹配表中签名时写 `格式未确认`，不得根据扩展名补猜。签名命中也只提升格式置信度；仍需完成生成者、活动状态和影响核验。

3. 疑似重复文件先按相同长度形成候选，只对少量候选计算 SHA-256：

```powershell
Get-FileHash -Algorithm SHA256 -LiteralPath '<文件1>','<文件2>'
```

4. 哈希相同仍需确认至少一份可靠副本、同步状态、保留位置和用户授权；哈希不同立即停止“重复文件”结论。

产出：内容类型、可靠副本、同步/占用状态和用户价值。门禁：文件年龄、名称、扩展名、体积或相同哈希都不能单独构成删除授权。

## 操作卡 8：第二轮小文件聚合

1. 只对前面已确认的生成者目录执行，从本次收益阈值附近的单文件开始；100 MiB–1 GiB 只是常见示例。
2. 再按直接父目录、扩展名和生成者聚合日志、转储、安装器下载、版本 staging 与构建缓存。
3. 输出聚合组的总量、文件数、时间跨度和典型样本，不逐个解释小分片。
4. 聚合组仍按普通目录 A–F 核验；系统 DLL、程序资源和用户内容不能因数量多而降风险。

停止条件：连续两个生成者聚合都低于收益阈值，或新增可解释空间不足以影响建议顺序。

## 协调器任务包

在启动执行模型前，先根据基线完成全部目录簇规划。每个任务包写清审计范围、负责路径、相关操作卡、输出位置和停止条件。显著的大目录原则上独立负责，多个较小目录按生成者、用途或处理方式合并；避免一个小目录一个 Agent。基线中的一级大目录必须分配给某个任务包，不能调查的列为计划盲区并说明原因。每个目录簇固定返回 `findings.json`、`coverage.json` 和 `chapter.md`；文件内部表达可随对象调整，但必须让用户知道查了哪里、观察到什么、数字口径、用途、处理选择、影响、限制和下一步。

子 Agent可以并且应当继续调查负责路径内新发现的重大子项；这不属于扩展范围。不得跨入其他 Agent的负责路径，也不得越出用户授权范围。只要软件允许且安全门禁没有阻止，协调器可以使用软件提供的并行上限；无法并行时按同一计划串行。

任务包还应明确：本机事实优先；涉及产品归属、官方维护方法、命令范围、删除影响或易变行为时，优先查找 Microsoft 或产品官方资料并记录其实际支持的结论。官方资料不可用时标明证据边界，不凭经验提高确定性。

调查返回后，主 Agent只生成概览、修正父子计量、合并真正重复项和裁决真实矛盾，不逐项重做事实核验。最终正文直接使用子 Agent章节，子 Agent声明的盲区原样保留。是否采取动作由用户决定；任何可回收量仍须有足够证据。
