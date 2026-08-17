# Windows 检查地图

这是通用检查地图，不是默认删除清单。只深查真实存在且进入短名单的路径。

本文件只负责选择检查对象。选中某类后，参照 [目录级操作手册](directory-procedures.md) 的对应操作卡；若专用工具能给出更直接的只读证据，可以采用并说明口径。不能把这里列出的路径直接当成递归扫描清单或删除清单。

## 通用变量

| 变量 | 含义 |
|---|---|
| `%SystemDrive%` | Windows 系统盘，通常为 `C:` |
| `%SystemRoot%` / `%WINDIR%` | Windows 目录 |
| `%ProgramFiles%` | 64 位程序目录 |
| `%ProgramFiles(x86)%` | 32 位程序目录，可能不存在 |
| `%ProgramData%` | 机器级应用数据 |
| `%USERPROFILE%` | 当前用户目录 |
| `%LOCALAPPDATA%` | 当前用户本地应用数据 |
| `%APPDATA%` | 当前用户漫游应用数据 |
| `%TEMP%` | 当前用户临时目录 |
| `%PUBLIC%` | 公共用户目录 |
| `%OneDrive%` | 当前用户 OneDrive 根目录，存在时使用 |

迁移目标写成“用户指定的非系统盘目录”，不要假定一定存在 D 盘。

## 1. 系统盘根目录

优先识别：

- 系统管理文件：`hiberfil.sys`、`pagefile.sys`、`swapfile.sys`。只通过 Windows 设置或 `powercfg` 管理，不手删。
- 根目录未知文件夹、临时任务目录、便携软件、旧恢复或安装事务目录。
- `$Recycle.Bin`、`System Volume Information`、`Recovery`。它们涉及恢复或系统管理，权限不足时只记录。

检查：文件类型、签名/版本、父目录、创建/写入时间、当前进程路径、是否为重解析点。名称包含 `temp` 不能单独证明可清。

## 2. Windows 系统区

| 通用位置 | 主要作用 | 核心边界 |
|---|---|---|
| `%WINDIR%\Installer` | MSI/MSP 修复、更新、卸载缓存 | 禁止手删；显著时读取 [Installer 缓存附注](windows-installer-cache.md)，跨上下文核对维护引用与厂商支持方式 |
| `%WINDIR%\SoftwareDistribution\Download` | Windows Update 下载与暂存 | 先确认更新、BITS、待重启；使用系统清理 |
| `%WINDIR%\SoftwareDistribution\DataStore` | 更新历史和状态数据库 | 不是普通下载缓存，收益通常与重置代价不成比例 |
| `%WINDIR%\WinSxS` | 组件存储 | 有硬链接；只用 DISM 分析和支持的维护方式 |
| `%WINDIR%\System32\DriverStore\FileRepository` | 驱动仓库 | 用驱动/设备管理方式，不手删目录 |
| `%WINDIR%\Logs\CBS`、DISM/Panther | 组件与更新诊断 | 先判断近期故障价值和轮转状态 |
| `%WINDIR%\System32\winevt\Logs` | Windows 事件日志 | 通过事件查看器或受支持命令管理，不删文件 |
| `%WINDIR%\Minidump`、`MEMORY.DMP`、`LiveKernelReports` | 崩溃诊断 | 用户不再排障且单独授权后再处理 |
| `%WINDIR%\Temp` | 系统临时数据 | 跳过占用项；更新/安装中不清 |

## 3. 程序和机器级数据

检查 `%ProgramFiles%`、`%ProgramFiles(x86)%`、`%ProgramData%`、WindowsApps 所在位置，按以下类型归类：

- 程序主体与共享运行时：通常通过标准卸载处理。
- 安装源、更新器下载、补丁 staging、驱动离线包。
- 机器级缓存、日志、崩溃转储、下载模型和资源包。
- 多版本 Appx/MSIX：比较包类型、架构、依赖、注册状态、实际安装位置和运行路径；多条登记不等于重复实体。
- `Package Cache` 一类安装维护缓存：先查产品引用和卸载/修复需求。

不要因同名、相近版本、旧日期或未匹配一条注册记录就直接删除。

## 4. 容器、WSL 和虚拟磁盘

覆盖 Docker、WSL、Hyper-V、VMware、VirtualBox 及其他虚拟化工具。优先通过官方 CLI、配置和注册信息定位真实数据根，不依赖猜测路径。

必须区分：

1. 宿主文件逻辑/实际大小。
2. 虚拟盘声明容量。
3. 客体文件系统已用与空闲。
4. 镜像、构建缓存、容器、命名卷、发行版、快照或差分盘分别可回收多少。

VHD/VHDX/VDI/VMDK 是文件系统容器，不是普通缓存；内部删除后宿主文件也可能不自动缩小。压缩、导出、注销、prune 都属于状态变更，单独授权。

## 5. 用户根目录及隐藏目录

检查 `%USERPROFILE%` 顶层和隐藏目录，按“生成者 + 内容性质”而非固定厂商名归类：

- 包管理器下载缓存、编译缓存、依赖仓库和多版本工具链。
- 浏览器自动化运行时与 profile。
- IDE 索引、缓存、日志和插件下载。
- AI/开发工具的会话、数据库、日志、备份、工作副本和生成物。
- 模型权重、数据集、构建产物和离线 SDK。

会话、数据库、备份、项目和工作副本不是普通缓存。高频使用的可再生缓存优先迁移、限额或轮转，不必固定周期清空。

## 6. `%LOCALAPPDATA%`

依次看：

- `%LOCALAPPDATA%\Temp`、`CrashDumps`。
- `Packages` 中的应用状态、LocalCache、LocalState 和临时子目录。
- updater/download/staging 与旧安装器。
- 浏览器组件、WebView/Electron 缓存和多 profile 数据。
- 开发缓存、自动化浏览器、IDE system 目录。
- 应用本地数据库、账号状态、草稿和离线数据。

只定向清已确认的可再生子目录；不要把整个 `User Data`、`Packages` 或产品根目录当缓存。

## 7. `%APPDATA%`

常见内容：多账号 profile、插件、Service Worker、Cache/Code Cache/GPUCache、日志、更新下载、数据库和漫游配置。

核对具体生成应用、账号数量、退出状态、是否含聊天/云文档/离线资料。即使子目录叫缓存，也要说明重新登录、离线内容和首次启动影响。

## 8. 个人目录与未知对象

检查 Desktop、Downloads、Documents、Pictures、Videos、公共目录和云同步目录：

- 大型安装包、压缩包、ISO、媒体和生成结果。
- 疑似重复文件：先比较大小和 SHA-256，再确认至少一份可靠副本。
- 扩展名可疑对象：读文件头、版本信息、签名和来源，不按扩展名下结论。
- 同步占位、冲突副本和离线状态：结合云客户端判断。

这些默认按用户数据高风险处理；年龄和体积都不是删除授权。

## 9. 第二轮较小对象

大头完成后再查约 100 MB–1 GB 的单项，然后聚合更小分片。优先找同一生成者下大量日志、崩溃转储、安装器下载、版本 staging 和构建缓存；系统 DLL、程序主体和资源文件不因体积较大就视为垃圾。
