# Windows Installer 缓存附注

仅在 `%WINDIR%\Installer` 成为显著对象、用户追问其清理方法，或报告准备给出相关处理建议时读取。本附注用于避免把安装维护缓存误判为普通更新下载；它不是删除教程。

## 它保存什么

Windows Installer 会在这里保存已安装 MSI 产品所需的缓存安装包和 MSP 补丁。它们可能参与后续更新、修复、修改和卸载，并且缓存文件与具体机器的安装状态相关。文件缺失后，问题可能不会立即出现，而是在未来维护产品时才暴露。

## 不能成立的推断

以下证据最多形成调查线索，不能单独证明文件孤立、可删或可换算成回收量：

- 文件很旧、很大、名称随机或补丁已经被新版本取代；
- 目录文件数多于某一个注册表位置的记录数；
- 只检查当前用户、单一 SID、单一安装上下文或 `HKLM\Software\Classes\Installer\Patches`；
- 没有在卸载列表中看到同名产品；
- 文件大小或哈希相同；
- 自写脚本没有发现引用。

MSI 产品和补丁可能存在机器级、当前用户或其他用户的 managed/unmanaged 安装上下文。完整只读清点应考虑 `MsiEnumProductsEx`、`MsiEnumPatchesEx`，并通过 `MsiGetProductInfoEx`、`MsiGetPatchInfoEx` 查询安装状态和 `LocalPackage` 等属性。不要使用 `Win32_Product`，它可能触发安装器一致性检查或修复。

## 调查时怎么做

1. 分开统计 MSI、MSP、其他文件和最近写入，仅把目录逻辑大小写成“当前可见占用”。
2. 核对当前安装的 MSI 产品、发布者、版本、安装上下文和卸载入口。
3. 跨相关用户与安装上下文枚举产品和补丁，并建立 `LocalPackage` 到实际缓存文件的映射。
4. 对未匹配项继续检查产品厂商、补丁元数据、安装日志和厂商支持方式；写成“未匹配”而不是“孤立”。
5. 将目录大小、已建立维护引用的大小、尚未解释的大小和可安全回收量分开。没有受支持的处理依据时，可安全回收量为未知。

## 处理边界

- 不按文件手删、移动或隔离 MSI/MSP，不建议用户运行来源不明的清理脚本。
- 不把 `msizap`、Windows Installer CleanUp Utility、PatchCleaner 类第三方工具描述为当前 Microsoft 支持的通用清理方案。
- 不声称系统还原点能够可靠恢复被删的 Installer 缓存；需要恢复时可能依赖厂商安装介质、可还原的完整系统状态备份，甚至重装产品或系统。
- Windows 的磁盘清理、存储感知和 Windows Update 清理不等于 Installer 缓存清理。
- 普通用户可采用的支持路径通常是：保留；通过“已安装的应用”标准卸载不再使用的产品；按产品厂商文档修复、卸载或重装。实际释放量必须在操作后测量，不能事前把未匹配文件全部计入。

## 报告建议写法

可以写：

> `%WINDIR%\Installer` 是已安装软件的维护缓存。当前目录占用较大，但仅凭文件年代、数量或一次注册表比对不能判断哪些可删。本次没有得到受支持的逐文件清理依据，因此不手删，也不填写预计回收量。若要减少它，先确认是否仍需要相关 MSI 产品，并优先使用标准卸载或厂商支持的修复/重装流程。

不要写：

> 注册表有 32 条而目录有 71 个补丁，所以其余 39 个是孤立文件，可用工具释放 20–35 GiB。

## 一手依据

- [Microsoft：Restore missing Windows Installer cache files](https://learn.microsoft.com/en-us/troubleshoot/windows-client/application-management/missing-windows-installer-cache)
- [Microsoft：Using Windows Installer to Inventory Products and Patches](https://learn.microsoft.com/en-us/windows/win32/msi/inventory-products-and-patches-)
- [Microsoft：MsiEnumPatchesEx](https://learn.microsoft.com/en-us/windows/win32/api/msi/nf-msi-msienumpatchesexw)
