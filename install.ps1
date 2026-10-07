
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor [System.Net.SecurityProtocolType]::Tls12

$ProgressPreference = 'SilentlyContinue';

Write-Host " ==== 네오포지 설치기 ==== " -ForegroundColor Yellow


# Check NeoForge Install Path
# 기본 마인크래프트 경로, CurseForge, Modrinth, Prism Launcher, FTB App의 설치 여부를 파악합니다.

$targets = @(
    @{
        Name   = "Vanilla Minecraft"
        Target = "$env:APPDATA\.minecraft"
        Check  = { Test-Path "$env:APPDATA\.minecraft" }
    }
    @{
        Name   = "Modrinth App"
        Target = "$env:APPDATA\ModrinthApp\profiles"
        Check  = { Test-Path "$env:APPDATA\ModrinthApp\profiles" }
    }
    @{
        Name   = "CurseForge"
        Target = "CurseForge Program"
        Check  = {
            $reg = Get-ItemProperty "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*", "HKLM:\Software\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*" -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like "*CurseForge*" }
            $exe = (Test-Path "$env:LOCALAPPDATA\Programs\CurseForge\CurseForge.exe") -or (Test-Path "$env:ProgramFiles\CurseForge\CurseForge.exe")
            [bool]($reg -or $exe)
        }
    }
    @{ # Path 검증 필요
        Name   = "Prism Launcher"
        Target = "$env:APPDATA\PrismLauncher\instances"
        Check  = { Test-Path "$env:APPDATA\PrismLauncher\instances" }
    }
    @{ # Path 검증 필요
        Name   = "FTB App"
        Target = "$env:LOCALAPPDATA\.ftba\instances"
        Check  = { (Test-Path "$env:LOCALAPPDATA\.ftba\instances") -or (Test-Path "$env:USERPROFILE\.ftba\instances") }
    }
)

function Select-ModsFolderGUI {
    Add-Type -AssemblyName System.Windows.Forms
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "mods 폴더로 이동 후 [열기]를 누르거나, 아래 '파일 이름'에 경로를 붙여넣으세요"
    $dialog.Filter = "모든 파일 (*.*)|*.*"
    $dialog.FileName = "현재 폴더 선택"
    $dialog.CheckFileExists = $false
    $dialog.CheckPathExists = $false
    $dialog.ValidateNames = $false

    if ($dialog.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $chosen = $dialog.FileName
        if (Test-Path -Path $chosen -PathType Container) {
            return $chosen
        }
        $dir = [System.IO.Path]::GetDirectoryName($chosen)
        if (Test-Path -Path $dir -PathType Container) {
            return $dir
        }
        $cleaned = $chosen.Trim('"').Trim("'")
        if (Test-Path -Path $cleaned -PathType Container) {
            return $cleaned
        }
    }
    return $null
}

function Install-ModsFromManifest {
    param (
        [string]$TargetDir,
        [string]$ManifestFilePath = ".\mods_manifest.json"
    )

    $manifest = $null

    # [원격 배포 모드] GitHub Raw Content URL을 통한 온라인 매니페스트 수신 (추후 활성화)
    # $remoteManifestUrl = "https://raw.githubusercontent.com/<USERNAME>/<REPOSITORY>/main/mods_manifest.json"
    # Write-Host "온라인 매니페스트 조회 중: $remoteManifestUrl ..." -ForegroundColor Cyan
    # try {
    #     $manifest = Invoke-RestMethod -Uri $remoteManifestUrl -Method Get -ErrorAction Stop
    # }
    # catch {
    #     Write-Warning "온라인 매니페스트 수신 실패: $($_.Exception.Message). 로컬 매니페스트를 탐색합니다."
    # }

    # [로컬 모드] 웹 조회가 주석 처리되어 있거나 로컬 환경일 때 파일에서 읽기
    if (-not $manifest) {
        if (-not (Test-Path $ManifestFilePath)) {
            $fallback = Join-Path $PSScriptRoot "mods_manifest.json"
            if (Test-Path $fallback) {
                $ManifestFilePath = $fallback
            }
            else {
                Write-Error "매니페스트 파일(mods_manifest.json)을 찾을 수 없습니다: $ManifestFilePath"
                return
            }
        }
        $manifest = Get-Content -Path $ManifestFilePath -Raw -Encoding utf8 | ConvertFrom-Json
    }

    $mods = $manifest.Mods
    $total = $mods.Count

    Write-Host "`n==== 모드 다운로드 시작 (총 $total 개) ====" -ForegroundColor Cyan
    $index = 0

    foreach ($mod in $mods) {
        $index++
        $destFile = Join-Path $TargetDir $mod.FileName

        # 파일이 이미 존재하고 해시가 일치하면 건너뜀 (Smart Sync)
        if (Test-Path -Path $destFile) {
            $localHash = (Get-FileHash -Path $destFile -Algorithm SHA1).Hash.ToLower()
            if ($localHash -eq $mod.Sha1.ToLower()) {
                Write-Host "[$index/$total] 이미 최신 버전 (건너뜀): $($mod.FileName)" -ForegroundColor DarkGreen
                continue
            }
        }

        Write-Host "[$index/$total] 다운로드 중: $($mod.FileName) ..." -ForegroundColor Cyan
        try {
            Invoke-WebRequest -UseBasicParsing -Uri $mod.DownloadUrl -OutFile $destFile
        }
        catch {
            Write-Host "[$index/$total] 다운로드 실패: $($mod.FileName) ($($_.Exception.Message))" -ForegroundColor Red
        }
    }

    Write-Host "`n모든 모드 파일 설치/동기화가 완료되었습니다!" -ForegroundColor Green
}

$detectedTargets = @()
foreach ($item in $targets) {
    Write-Host "Checking $($item.Target) ($($item.Name))..."
    if (& $item.Check) {
        Write-Host "Exist: $($item.Target)" -ForegroundColor Green
        $detectedTargets += $item
    }
    else {
        Write-Host "Not found: $($item.Target)" -ForegroundColor DarkGray
    }
}

$selectedTarget = $null

if ($detectedTargets.Count -eq 0) {
    Write-Host "`n설치 가능한 마인크래프트 또는 런처 환경을 찾지 못했습니다." -ForegroundColor Yellow
    $forceProceed = Read-Host "직접 mods 폴더를 지정하여 설치를 계속 진행하시겠습니까? (Y/N)"
    if ($forceProceed -ne 'Y' -and $forceProceed -ne 'y') {
        Write-Host "설치를 종료합니다." -ForegroundColor Red
        exit
    }
    $selectedTarget = @{ Name = "직접 지정" }
}
else {
    # 1. 설치 대상 선택
    Write-Host "`n==== 설치 대상 선택 ====" -ForegroundColor Cyan
    for ($i = 0; $i -lt $detectedTargets.Count; $i++) {
        Write-Host " [$($i + 1)] $($detectedTargets[$i].Name)"
    }
    Write-Host " [$($detectedTargets.Count + 1)] 직접 경로 지정 (수동)"

    $selectedIndex = -1
    while ($selectedIndex -lt 0 -or $selectedIndex -gt $detectedTargets.Count) {
        $choice = Read-Host "설치할 대상을 선택하세요 (1-$($detectedTargets.Count + 1))"
        if ($choice -match '^\d+$') {
            $selectedIndex = [int]$choice - 1
        }
    }

    if ($selectedIndex -eq $detectedTargets.Count) {
        $selectedTarget = @{ Name = "직접 지정" }
    }
    else {
        $selectedTarget = $detectedTargets[$selectedIndex]
    }
}

# 2. 선택 대상별 설치 진행
if ($selectedTarget.Name -eq "Vanilla Minecraft") {
    Write-Host "`nVanilla Minecraft 환경에 NeoForge 및 필수 구성 요소를 설치합니다..." -ForegroundColor Cyan

    # 1. launcher_profiles.json 사전 점검 및 더미 프로필 생성 (하이브리드 1단계)
    $dotMinecraft = "$env:APPDATA\.minecraft"
    if (-not (Test-Path -Path $dotMinecraft)) {
        New-Item -ItemType Directory -Path $dotMinecraft -Force | Out-Null
    }

    $profilePath = Join-Path $dotMinecraft "launcher_profiles.json"
    if (-not (Test-Path -Path $profilePath)) {
        Write-Host "Minecraft 런처 프로필(launcher_profiles.json)이 감지되지 않아 기본 프로필 설정을 자동 생성합니다..." -ForegroundColor Cyan
        $dummyProfile = @{
            profiles = @{}
            settings = @{
                crashAssistance = $true
                enableAdvanced  = $false
            }
            version  = 3
        }
        $dummyProfile | ConvertTo-Json -Depth 5 | Set-Content -Path $profilePath -Encoding UTF8
    }

    # 2. 필수 파일 다운로드 (중복 다운로드 방지)
    $installerPath = ".\neoforge-installer.jar"
    if (-not (Test-Path -Path $installerPath)) {
        Write-Host "NeoForge 인스톨러 다운로드 중..." -ForegroundColor Gray
        Invoke-WebRequest -UseBasicParsing -Uri "https://maven.neoforged.net/releases/net/neoforged/neoforge/21.1.255/neoforge-21.1.255-installer.jar" -OutFile $installerPath
    }

    $javaExe = ".\Zulu25\zulu25.36.205-ca-jdk25.0.4.1-win_x64\bin\java.exe"
    if (-not (Test-Path -Path $javaExe)) {
        if (-not (Test-Path -Path "Zulu25.zip")) {
            Write-Host "Java 런타임(Zulu25) 다운로드 중..." -ForegroundColor Gray
            Invoke-WebRequest -UseBasicParsing -Uri "https://cdn.azul.com/zulu/bin/zulu25.36.205-ca-jdk25.0.4.1-win_x64.zip" -OutFile "Zulu25.zip"
        }
        Write-Host "Java 런타임 압축 해제 중..." -ForegroundColor Gray
        Expand-Archive -Path "Zulu25.zip" -DestinationPath ".\Zulu25" -Force
    }

    # 3. NeoForge 설치 실행 및 하이브리드 실패 대응 루프 (하이브리드 2단계)
    $installerSuccess = $false
    while (-not $installerSuccess) {
        Write-Host "NeoForge 클라이언트 설치를 진행합니다..." -ForegroundColor Cyan
        $proc = Start-Process -FilePath $javaExe -ArgumentList "-jar neoforge-installer.jar --installClient" -Wait -PassThru

        if ($proc.ExitCode -eq 0) {
            Write-Host "NeoForge 클라이언트가 성공적으로 설치되었습니다!" -ForegroundColor Green
            $installerSuccess = $true
        }
        else {
            Write-Host "`n[경고] NeoForge 인스톨러 실행 중 문제가 발생했습니다. (ExitCode: $($proc.ExitCode))" -ForegroundColor Red
            Write-Host "공식 런처에서 1.21.1 버전의 원본 파일이 생성되지 않았을 때 발생할 수 있습니다." -ForegroundColor Yellow
            Write-Host "조치 방법:" -ForegroundColor White
            Write-Host "  1. Minecraft 공식 런처를 실행합니다." -ForegroundColor White
            Write-Host "  2. 1.21.1 릴리스 버전을 선택하여 게임을 1회 실행(메인 타이틀 진입) 후 게임을 닫습니다." -ForegroundColor White
            Write-Host "  3. 아래에서 'Y'를 입력하여 NeoForge 설치를 다시 시도합니다.`n" -ForegroundColor White

            $choice = Read-Host "다시 시도하시겠습니까? (Y: 재시도 / N: 건너뛰고 모드만 다운로드 / Q: 설치 중단) [Y/n/q]"
            if ($choice -match "^[nN]") {
                Write-Host "NeoForge 설치 단계를 건너뛰고 모드 다운로드를 진행합니다." -ForegroundColor Yellow
                break
            }
            elseif ($choice -match "^[qQ]") {
                Write-Host "설치가 중단되었습니다." -ForegroundColor Red
                return
            }
        }
    }

    # mods 디렉토리 생성 및 매니페스트 기반 모드 다운로드
    $modsDir = "$env:APPDATA\.minecraft\mods"
    if (-not (Test-Path -Path $modsDir)) {
        New-Item -ItemType Directory -Path $modsDir -Force | Out-Null
    }

    Install-ModsFromManifest -TargetDir $modsDir
}
else {
    Write-Host "`n[$($selectedTarget.Name)] 환경이 선택되었습니다." -ForegroundColor Cyan
    Write-Host "인스턴스의 mods 폴더 경로를 직접 입력하거나, [Enter] 키를 누르면 폴더 선택창(GUI)이 열립니다." -ForegroundColor Yellow

    $modsPath = ""
    while (-not $modsPath) {
        $inputPath = Read-Host "mods 경로 입력 (Enter 입력 시 GUI 선택창 열기)"
        if ([string]::IsNullOrWhiteSpace($inputPath)) {
            Write-Host "폴더 선택 창을 엽니다..." -ForegroundColor Gray
            $selectedFolder = Select-ModsFolderGUI
            if ($selectedFolder) {
                $modsPath = $selectedFolder
            }
            else {
                Write-Host "폴더 선택이 취소되었습니다. 다시 입력해주세요." -ForegroundColor DarkYellow
            }
        }
        elseif (Test-Path -Path $inputPath) {
            $modsPath = $inputPath
        }
        else {
            Write-Host "존재하지 않는 경로입니다: $inputPath" -ForegroundColor Red
            $createConfirm = Read-Host "해당 경로로 폴더를 생성하시겠습니까? (Y/N)"
            if ($createConfirm -eq 'Y' -or $createConfirm -eq 'y') {
                New-Item -ItemType Directory -Path $inputPath -Force | Out-Null
                $modsPath = $inputPath
            }
        }
    }

    # 지정된 mods 경로로 매니페스트 기반 모드 다운로드
    Install-ModsFromManifest -TargetDir $modsPath
}