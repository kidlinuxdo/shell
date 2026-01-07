@echo off
chcp 65001 > nul
cd /d "%~dp0"
TITLE Cloudflared 智能安装工具
COLOR 0A

:: --- 1. 自动获取管理员权限 (防止闪退核心) ---
>nul 2>&1 "%SYSTEMROOT%\system32\cacls.exe" "%SYSTEMROOT%\system32\config\system"
if '%errorlevel%' NEQ '0' (
    echo 正在请求管理员权限，请在弹出的窗口中点击“是”...
    goto UACPrompt
) else ( goto gotAdmin )

:UACPrompt
    echo Set UAC = CreateObject^("Shell.Application"^) > "%temp%\getadmin.vbs"
    echo UAC.ShellExecute "%~s0", "", "", "runas", 1 >> "%temp%\getadmin.vbs"
    "%temp%\getadmin.vbs"
    exit /B

:gotAdmin
    if exist "%temp%\getadmin.vbs" ( del "%temp%\getadmin.vbs" )
    pushd "%CD%"
    CD /D "%~dp0"

:: --- 2. 执行 PowerShell 逻辑 ---
echo 正在初始化环境...
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference = 'Stop';" ^
    "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;" ^
    "$installDir = \"$env:ProgramData\cloudflared\";" ^
    "$bin = \"$installDir\cloudflared.exe\";" ^
    "$log = \"$installDir\cloudflared.log\";" ^
    "$svc = \"CloudflaredTunnel\";" ^
    "Write-Host '--------------------------------------------' -F Cyan;" ^
    "Write-Host '       Cloudflared 隧道一键配置工具' -F Cyan;" ^
    "Write-Host '--------------------------------------------' -F Cyan;" ^
    "if (!(Test-Path $installDir)) { New-Item -Path $installDir -ItemType Directory -Force | Out-Null };" ^
    "if (!(Test-Path $bin)) { Write-Host '正在下载主程序 (需联网)...' -F Yellow; try { (New-Object System.Net.WebClient).DownloadFile('https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe', $bin); Write-Host '下载成功!' -F Green } catch { Write-Host '下载失败! 请检查网络或代理。' -F Red; Start-Sleep 5; exit } } else { Write-Host '检测到主程序已存在，跳过下载。' -F Green };" ^
    "Write-Host ' ';" ^
    "Write-Host '请选择运行模式:' -F White;" ^
    "Write-Host '1) 临时测试 (窗口关闭即停止)' -F Gray;" ^
    "Write-Host '2) 安装服务 (开机自启 + 随机免费域名)' -F Green;" ^
    "Write-Host '3) 安装服务 (Token模式 + 固定域名)' -F Yellow;" ^
    "$m = Read-Host '请输入数字 (1/2/3)'; " ^
    "if ($m -eq '1') { " ^
        "$p = Read-Host '请输入本地端口 (默认8080)'; if(!$p){$p='8080'}; " ^
        "Write-Host '正在启动... 请留意下方输出的 trycloudflare.com 网址' -F Cyan; " ^
        "& $bin tunnel --url localhost:$p; " ^
    "} elseif ($m -eq '2') { " ^
        "$p = Read-Host '请输入本地端口 (默认8080)'; if(!$p){$p='8080'}; " ^
        "Write-Host '正在清理旧服务...' -F Gray; " ^
        "sc.exe stop $svc | Out-Null; sc.exe delete $svc | Out-Null; Start-Sleep 1; " ^
        "if (Test-Path $log) { Remove-Item $log -Force }; " ^
        "$cmd = \"`\"$bin`\" tunnel --url localhost:$p --logfile `\"$log`\"\"; " ^
        "sc.exe create $svc binPath= $cmd start= auto | Out-Null; " ^
        "Start-Service $svc; " ^
        "Write-Host '服务已启动! 正在获取分配的域名 (请等待约 10 秒)...' -F Yellow; " ^
        "$foundURL = $null; " ^
        "for ($i=0; $i -lt 15; $i++) { " ^
            "Start-Sleep 2; " ^
            "if (Test-Path $log) { " ^
                "$content = Get-Content $log -Tail 50; " ^
                "foreach ($line in $content) { if ($line -match 'https://[-a-z0-9]+\.trycloudflare\.com') { $foundURL = $matches[0]; break } } " ^
                "if ($foundURL) { break } " ^
            "} " ^
        "} " ^
        "if ($foundURL) { " ^
            "Write-Host ' ';" ^
            "Write-Host '============================================' -F Green;" ^
            "Write-Host ' 您的公网访问地址: ' -NoNewline -F White; " ^
            "Write-Host $foundURL -F White -BackgroundColor DarkGreen; " ^
            "Write-Host '============================================' -F Green;" ^
            "Write-Host ' (提示: 服务已在后台运行，关闭窗口不会断开)' -F Gray;" ^
        "} else { " ^
            "Write-Host '获取超时，请手动查看日志文件:' -F Red; Write-Host $log -F Gray; " ^
        "} " ^
    "} elseif ($m -eq '3') { " ^
        "$t = Read-Host '请粘贴 Cloudflare Token'; " ^
        "sc.exe stop $svc | Out-Null; sc.exe delete $svc | Out-Null; Start-Sleep 1; " ^
        "$cmd = \"`\"$bin`\" tunnel run --token $t\"; " ^
        "sc.exe create $svc binPath= $cmd start= auto | Out-Null; Start-Service $svc; " ^
        "Write-Host '服务安装成功! 请在 Cloudflare 网页端查看状态。' -F Green; " ^
    "}"

echo.
echo 按任意键退出...
pause >nul
