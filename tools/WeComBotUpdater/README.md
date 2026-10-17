# MAA 企微版一键更新器

这个工具用于把官方 `MaaAssistantArknights/dev-v2` 的新提交合并到个人分支 `feat/wecom-bot-settings`，同时保留企业微信机器人功能。

## 一键使用

- 仅更新官方源码、资源和 GUI：双击 `一键更新企微版.cmd`。
- 同时替换最新官方 MaaCore 与 OCR、ADB、DirectML 等原生组件：双击 `一键更新企微版-含官方内核.cmd`。

更新器会执行以下流程：

1. 检查工作区必须没有未提交改动。
2. 自动添加官方远程 `upstream` 并拉取最新 `dev-v2`。
3. 创建 `backup/wecom-bot-时间戳` 本地备份分支，并保存企微补丁。
4. 以普通 merge commit 合并官方代码，不覆盖历史，不强制推送。
5. 检查企微服务、配置、设置页和本地化注册是否仍然存在。
6. 使用 .NET 10 重新构建 `src/MaaWpfGui/MaaWpfGui.csproj`。
7. 构建成功后普通推送 `origin/feat/wecom-bot-settings`。

版本号只使用正式 `v*` 标签，例如 `v6.20.0-beta.1`。内部 `alpha/...` 标签不会写入 `InformationalVersion`，避免启动阶段因为 HTTP `User-Agent` 含额外斜杠而闪退。

如果官方改动与企微代码发生冲突，更新器会取消本次合并并保持原版本。解决冲突后可以再次运行。

## 官方内核更新

`-RefreshNativeCore` 会从 GitHub 最新正式 Release 下载 Windows x64 包，只同步以下原生文件：

- `MaaCore.dll`
- `MaaAdbControlUnit.dll`
- `MaaWin32ControlUnit.dll`
- `MaaUtils.dll`
- `DirectML.dll`
- `onnxruntime_maa.dll`
- `opencv_world4_maa.dll`
- `fastdeploy_ppocr_maa.dll`

不会覆盖自定义 `MAA.dll`、`MAA.exe`、`config`、`cache`、`data` 或企微配置。旧原生文件会备份到 `.updater-backups/native-core-时间戳`。

## 高级参数

```powershell
.\Update-WeComFork.ps1 -DryRun
.\Update-WeComFork.ps1 -NoBuild
.\Update-WeComFork.ps1 -NoPush
.\Update-WeComFork.ps1 -RefreshNativeCore
```

- `-DryRun`：只拉取并显示官方领先多少提交，不合并。
- `-NoBuild`：只更新源码，不编译。
- `-NoPush`：本地更新和构建成功，但不推送 GitHub。
- `-RefreshNativeCore`：同时更新官方原生内核。

## 环境要求

- Windows PowerShell 5.1 或 PowerShell 7。
- Git。
- .NET 10 SDK。更新器优先使用环境变量 `MAA_BOT_DOTNET`，其次查找仓库内或仓库同级的 `.dotnet-sdk\sdk\dotnet.exe`，最后检查系统 `dotnet.exe`。

## 失败恢复

更新器失败时会尽量自动恢复到更新前的提交。仍然可以手动恢复：

```powershell
git switch backup/wecom-bot-时间戳
```

补丁和最近一次更新信息保存在 `.updater-backups`，下载缓存保存在 `.updater-cache`，两者都不会提交到 Git。

## 注意

- Git 只能自动同步官方源码和资源。若需要更新 MaaCore 二进制，请使用“含官方内核”入口。
- 仓库构建版 MAA 正在运行时，更新器只关闭 `build/bin/Debug/MAA.exe`，不会关闭其他安装版 MAA；构建完成后会重新启动它。
- 冲突属于官方代码与本分支修改同一位置的情况。为了保证企微功能不被静默丢弃，更新器不会使用 `theirs` 策略强行覆盖。
