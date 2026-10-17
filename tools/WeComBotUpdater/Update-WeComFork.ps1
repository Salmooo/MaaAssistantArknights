[CmdletBinding()]
param(
    [string]$Branch = "feat/wecom-bot-settings",
    [string]$UpstreamRemote = "upstream",
    [string]$UpstreamUrl = "https://github.com/MaaAssistantArknights/MaaAssistantArknights.git",
    [string]$UpstreamBranch = "dev-v2",
    [switch]$RefreshNativeCore,
    [switch]$NoBuild,
    [switch]$NoPush,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$RepoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot "..\.."))
$BackupRoot = Join-Path $RepoRoot ".updater-backups"
$CacheRoot = Join-Path $RepoRoot ".updater-cache"
$Timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$OriginalBranch = ""
$OriginalHead = ""
$BackupBranch = ""

function Write-Step {
    param([string]$Message)

    Write-Host ""
    Write-Host "==> $Message" -ForegroundColor Cyan
}

function Invoke-Git {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Arguments
    )

    $Output = & git -c "safe.directory=$RepoRoot" @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        $Text = ($Output | Out-String).Trim()
        throw "git $($Arguments -join ' ') 失败：`n$Text"
    }
    return $Output
}

function Test-GitRef {
    param([string]$Ref)

    & git -c "safe.directory=$RepoRoot" show-ref --verify --quiet $Ref
    return $LASTEXITCODE -eq 0
}

function Get-RequiredFilePath {
    param([string]$RelativePath)

    return Join-Path $RepoRoot $RelativePath
}

function Assert-WeComFeature {
    $RequiredPaths = @(
        "src/MaaWpfGui/Services/WeComBot/WeComBotClient.cs",
        "src/MaaWpfGui/Services/WeComBot/WeComBotCommandService.cs",
        "src/MaaWpfGui/Services/WeComBot/WeComBotService.cs",
        "src/MaaWpfGui/Configuration/Global/WeComBot.cs",
        "src/MaaWpfGui/ViewModels/UserControl/Settings/WeComBotSettingsUserControlModel.cs",
        "src/MaaWpfGui/Views/UserControl/Settings/WeComBotSettingsUserControl.xaml"
    )
    $Missing = @()
    foreach ($RelativePath in $RequiredPaths) {
        $Path = Get-RequiredFilePath $RelativePath
        if (-not (Test-Path -LiteralPath $Path)) {
            $Missing += $RelativePath
        }
    }
    if ($Missing.Count -gt 0) {
        throw "合并后企微功能文件缺失：`n$($Missing -join "`n")"
    }

    $RegistrationChecks = @(
        @{ Path = "src/MaaWpfGui/Main/Bootstrapper.cs"; Text = "WeComBot" },
        @{ Path = "src/MaaWpfGui/Helper/Instances.cs"; Text = "WeComBot" },
        @{ Path = "src/MaaWpfGui/Views/UI/SettingsView.xaml"; Text = "WeComBot" },
        @{ Path = "src/MaaWpfGui/Res/Localizations/zh-cn.xaml"; Text = "WeComBot" }
    )
    foreach ($Check in $RegistrationChecks) {
        $Path = Get-RequiredFilePath $Check.Path
        if (-not (Select-String -LiteralPath $Path -SimpleMatch -Quiet -Pattern $Check.Text)) {
            throw "合并后企微注册缺失：$($Check.Path) 中找不到 $($Check.Text)"
        }
    }
}

function Resolve-DotNet {
    $Candidates = @(
        $env:MAA_BOT_DOTNET,
        (Join-Path $RepoRoot ".dotnet-sdk\sdk\dotnet.exe"),
        (Join-Path $RepoRoot "..\.dotnet-sdk\sdk\dotnet.exe")
    )
    foreach ($Candidate in $Candidates) {
        if ($Candidate -and (Test-Path -LiteralPath $Candidate)) {
            return (Resolve-Path -LiteralPath $Candidate).Path
        }
    }

    $Command = Get-Command dotnet.exe -ErrorAction SilentlyContinue
    if ($Command) {
        $Sdks = & $Command.Source --list-sdks 2>$null
        if ($Sdks -match "(?m)^10\.") {
            return $Command.Source
        }
    }
    throw "找不到 .NET 10 SDK。请设置环境变量 MAA_BOT_DOTNET 指向 dotnet.exe，或安装 .NET 10 SDK。"
}

function Get-RepoMaaProcesses {
    $DebugDir = Join-Path $RepoRoot "build\bin\Debug"
    return @(
        Get-Process -Name "MAA" -ErrorAction SilentlyContinue | Where-Object {
            try {
                $_.Path -and $_.Path.StartsWith($DebugDir, [StringComparison]::OrdinalIgnoreCase)
            }
            catch {
                $false
            }
        }
    )
}

function Get-LatestOfficialRelease {
    $Headers = @{
        Accept = "application/vnd.github+json"
        "User-Agent" = "MAA-WeCom-Bot-Updater"
    }
    $Release = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/MaaAssistantArknights/MaaAssistantArknights/releases/latest" `
        -Headers $Headers
    $Asset = $Release.assets | Where-Object {
        $_.name -match "^MAA-v.+win-x64\.zip$"
    } | Select-Object -First 1
    if (-not $Asset) {
        throw "最新官方 Release 中没有找到 win-x64 ZIP：$($Release.tag_name)"
    }
    return @{
        Tag = $Release.tag_name
        Name = $Asset.name
        Url = $Asset.browser_download_url
    }
}

function Install-OfficialNativeCore {
    param(
        [hashtable]$Release,
        [string]$Destination
    )

    New-Item -ItemType Directory -Path $CacheRoot -Force | Out-Null
    $SafeTag = $Release.Tag -replace "[^A-Za-z0-9._-]", "_"
    $ZipPath = Join-Path $CacheRoot "$SafeTag-win-x64.zip"
    $ExtractRoot = Join-Path $CacheRoot "$SafeTag-extracted"

    if (-not (Test-Path -LiteralPath $ZipPath)) {
        Write-Step "下载官方 Windows 内核 $($Release.Tag)"
        Invoke-WebRequest -Uri $Release.Url -OutFile $ZipPath
    }
    if (-not (Test-Path -LiteralPath (Join-Path $ExtractRoot "MaaCore.dll"))) {
        if (Test-Path -LiteralPath $ExtractRoot) {
            Remove-Item -LiteralPath $ExtractRoot -Recurse -Force
        }
        Write-Step "解压官方 Windows 内核"
        Expand-Archive -LiteralPath $ZipPath -DestinationPath $ExtractRoot -Force
    }

    $CoreSource = Join-Path $ExtractRoot "MaaCore.dll"
    if (-not (Test-Path -LiteralPath $CoreSource)) {
        $Found = Get-ChildItem -LiteralPath $ExtractRoot -Filter "MaaCore.dll" -Recurse -File |
            Select-Object -First 1
        if (-not $Found) {
            throw "官方压缩包中没有 MaaCore.dll"
        }
        $ExtractRoot = $Found.Directory.FullName
    }

    $NativeFiles = @(
        "DirectML.dll",
        "fastdeploy_ppocr_maa.dll",
        "MaaAdbControlUnit.dll",
        "MaaCore.dll",
        "MaaUtils.dll",
        "MaaWin32ControlUnit.dll",
        "onnxruntime_maa.dll",
        "opencv_world4_maa.dll"
    )
    $Available = @()
    foreach ($Name in $NativeFiles) {
        $Source = Join-Path $ExtractRoot $Name
        if (Test-Path -LiteralPath $Source) {
            $Available += $Name
        }
    }
    if ($Available -notcontains "MaaCore.dll") {
        throw "官方压缩包缺少 MaaCore.dll"
    }

    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $NativeBackup = Join-Path $BackupRoot "native-core-$Timestamp"
    New-Item -ItemType Directory -Path $NativeBackup -Force | Out-Null
    foreach ($Name in $Available) {
        $Existing = Join-Path $Destination $Name
        if (Test-Path -LiteralPath $Existing) {
            Copy-Item -LiteralPath $Existing -Destination (Join-Path $NativeBackup $Name) -Force
        }
    }

    try {
        foreach ($Name in $Available) {
            Copy-Item -LiteralPath (Join-Path $ExtractRoot $Name) -Destination (Join-Path $Destination $Name) -Force
        }
    }
    catch {
        foreach ($BackupFile in Get-ChildItem -LiteralPath $NativeBackup -File) {
            Copy-Item -LiteralPath $BackupFile.FullName -Destination (Join-Path $Destination $BackupFile.Name) -Force
        }
        throw
    }

    Set-Content `
        -LiteralPath (Join-Path $Destination "wecom-updater-core-version.txt") `
        -Value $Release.Tag `
        -Encoding UTF8
    Write-Host "官方内核已更新：$($Release.Tag)" -ForegroundColor Green
}

Set-Location -LiteralPath $RepoRoot
Invoke-Git rev-parse --git-dir | Out-Null

Write-Host "MAA 企微版更新器" -ForegroundColor Green
Write-Host "仓库：$RepoRoot"
Write-Host "企微分支：$Branch"
Write-Host "官方分支：$UpstreamRemote/$UpstreamBranch"

$Dirty = @(& git -c "safe.directory=$RepoRoot" status --porcelain)
if ($Dirty.Count -gt 0) {
    throw "工作区有未提交改动。请先提交或暂存，更新器不会覆盖这些改动。`n$($Dirty -join "`n")"
}

if (-not (Test-GitRef "refs/heads/$Branch")) {
    throw "本地分支不存在：$Branch"
}

$OriginalBranch = (Invoke-Git branch --show-current).Trim()
$OriginalHead = (Invoke-Git rev-parse HEAD).Trim()
$BackupBranch = "backup/wecom-bot-$Timestamp"

$Remotes = @(Invoke-Git remote)
if ($Remotes -notcontains $UpstreamRemote) {
    Write-Step "添加官方远程 $UpstreamRemote"
    Invoke-Git remote add $UpstreamRemote $UpstreamUrl | Out-Null
}
else {
    $ExistingUrl = (Invoke-Git remote get-url $UpstreamRemote).Trim()
    if ($ExistingUrl -ne $UpstreamUrl) {
        throw "远程 $UpstreamRemote 已存在但地址不同：$ExistingUrl"
    }
}

if ($OriginalBranch -ne $Branch) {
    Write-Step "切换到企微分支 $Branch"
    if (-not $DryRun) {
        Invoke-Git switch $Branch | Out-Null
    }
}

Write-Step "获取官方更新"
Invoke-Git fetch $UpstreamRemote --prune --tags --force | ForEach-Object { Write-Host $_ }
$UpstreamRef = "$UpstreamRemote/$UpstreamBranch"
Invoke-Git rev-parse --verify $UpstreamRef | Out-Null

$Counts = @(Invoke-Git rev-list --left-right --count "HEAD...$UpstreamRef")
$Pair = ($Counts -join " ").Trim() -split "\s+"
$Ahead = [int]$Pair[0]
$Behind = [int]$Pair[1]
Write-Host "企微独有提交：$Ahead；官方领先提交：$Behind"

if ($Behind -eq 0) {
    Write-Host "已经是最新的官方代码，无需合并。" -ForegroundColor Green
    exit 0
}

if ($DryRun) {
    Write-Host "DryRun：仅检查更新，不合并、不构建、不推送。" -ForegroundColor Yellow
    exit 0
}

New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
Write-Step "创建安全备份 $BackupBranch"
Invoke-Git branch --force $BackupBranch $OriginalHead | Out-Null
$MergeBase = (Invoke-Git merge-base $OriginalHead $UpstreamRef).Trim()
$PatchDir = Join-Path $BackupRoot "patches-$Timestamp"
New-Item -ItemType Directory -Path $PatchDir -Force | Out-Null
Invoke-Git format-patch --binary --quiet --output-directory $PatchDir "$MergeBase..$OriginalHead" | Out-Null
@"
Previous HEAD: $OriginalHead
Previous branch: $OriginalBranch
Backup branch: $BackupBranch
Upstream: $UpstreamRef
Created: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
"@ | Set-Content -LiteralPath (Join-Path $BackupRoot "last-update.txt") -Encoding UTF8

$MergeSucceeded = $false
$UpdateReady = $false
$MaaProcesses = @()
$MaaWasRunning = $false
$BuildSucceeded = $true
try {
    Write-Step "合并官方 $UpstreamRef"
    $MergeOutput = & git -c "safe.directory=$RepoRoot" merge --no-ff --no-edit $UpstreamRef 2>&1
    $MergeOutput | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        $Conflicts = @(& git -c "safe.directory=$RepoRoot" diff --name-only --diff-filter=U 2>$null)
        & git -c "safe.directory=$RepoRoot" merge --abort 2>$null
        $ConflictText = if ($Conflicts.Count -gt 0) { $Conflicts -join "`n" } else { "未知文件" }
        throw "官方更新存在冲突，已自动取消合并并恢复原分支。`n冲突文件：`n$ConflictText"
    }
    $MergeSucceeded = $true

    Assert-WeComFeature
    Write-Host "企微功能完整性检查通过。" -ForegroundColor Green

    $MaaProcesses = @(Get-RepoMaaProcesses)
    $MaaWasRunning = $MaaProcesses.Count -gt 0
    if ($MaaWasRunning) {
        Write-Step "关闭仓库构建版 MAA 以便重建"
        $MaaProcesses | Stop-Process -Force
        Start-Sleep -Seconds 2
    }

    $OfficialRelease = $null
    if ($RefreshNativeCore) {
        $OfficialRelease = Get-LatestOfficialRelease
    }

    if (-not $NoBuild) {
        $DotNet = Resolve-DotNet
        $VersionTag = (& git -c "safe.directory=$RepoRoot" describe --tags --abbrev=0 $UpstreamRef 2>$null)
        if (-not $VersionTag -and $OfficialRelease) {
            $VersionTag = $OfficialRelease.Tag
        }
        $BuildArgs = @(
            "build",
            (Join-Path $RepoRoot "src/MaaWpfGui/MaaWpfGui.csproj"),
            "-c",
            "Debug",
            "-p:Platform=x64"
        )
        if ($VersionTag) {
            $BuildArgs += "-p:InformationalVersion=$VersionTag"
        }
        Write-Step "构建 MAA GUI"
        Write-Host "$DotNet $($BuildArgs -join ' ')"
        & $DotNet @BuildArgs
        if ($LASTEXITCODE -ne 0) {
            throw "MAA GUI 构建失败"
        }
    }

    if ($RefreshNativeCore) {
        Install-OfficialNativeCore `
            -Release $OfficialRelease `
            -Destination (Join-Path $RepoRoot "build\bin\Debug")
    }

    $UpdateReady = $true
    if (-not $NoPush) {
        Write-Step "推送企微分支 $Branch"
        Invoke-Git push origin $Branch | ForEach-Object { Write-Host $_ }
    }
}
catch {
    Write-Host ""
    Write-Host "更新失败：$($_.Exception.Message)" -ForegroundColor Red
    if ($MergeSucceeded -and -not $UpdateReady) {
        Write-Step "恢复到更新前版本 $OriginalHead"
        & git -c "safe.directory=$RepoRoot" reset --hard $OriginalHead 2>&1 | Write-Host
    }
    $BuildSucceeded = $false
}
finally {
    if ($MaaWasRunning) {
        $MaaExe = Join-Path $RepoRoot "build\bin\Debug\MAA.exe"
        if (Test-Path -LiteralPath $MaaExe) {
            Write-Step "重新启动仓库构建版 MAA"
            Start-Process -FilePath $MaaExe -WorkingDirectory (Split-Path $MaaExe) | Out-Null
        }
    }
}

if (-not $BuildSucceeded) {
    Write-Host ""
    if ($UpdateReady) {
        Write-Host "本地更新已完成，但推送或收尾步骤失败。可检查网络后再次运行。" -ForegroundColor Yellow
    }
    else {
        Write-Host "原版本已保留。恢复命令：" -ForegroundColor Yellow
        Write-Host "  git switch $BackupBranch"
    }
    Write-Host "补丁目录：$PatchDir"
    exit 1
}

Write-Host ""
Write-Host "更新完成，企微功能已保留。" -ForegroundColor Green
Write-Host "更新前备份：$BackupBranch"
Write-Host "补丁目录：$PatchDir"
