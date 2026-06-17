# 1. Elevate the script to Administrator to allow Java installation
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Requesting Administrator privileges to install Java..." -ForegroundColor Yellow
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    Exit
}

# Optimize download speeds by hiding the visual progress bar
$ProgressPreference = 'SilentlyContinue'

# Force Windows to establish a secure modern TLS connection to stop Maven corruption drops
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# 2. Install Eclipse Temurin Java 17 via Windows Package Manager (Winget)
Write-Host "Installing Eclipse Temurin Java 17..." -ForegroundColor Cyan
# Added --include-unknown to handle environment differences inside admin elevation
winget install --id EclipseAdoptium.Temurin.17.JDK --silent --accept-source-agreements --accept-package-agreements --include-unknown

# 3. Define local destination directories
$downloadsFolder = [System.IO.Path]::Combine([Environment]::GetFolderPath('UserProfile'), 'Downloads')
$modsFolder      = [System.IO.Path]::Combine($env:APPDATA, '.minecraft', 'mods')

$minecraftDir = Join-Path $env:APPDATA ".minecraft"
$mcVersion = "1.6.4"
$mcLauncherVersion = "0.19.3"

# Ensure the .minecraft/mods folder actually exists
if (-not (Test-Path -Path $modsFolder)) {
    New-Item -ItemType Directory -Path $modsFolder -Force | Out-Null
    Write-Host "Created directory: $modsFolder" -ForegroundColor Green
}

# 4. Download Legacy Fabric Installer using forced browser emulation headers
$fabricUrl = "https://maven.legacyfabric.net/net/legacyfabric/fabric-installer/1.1.1/fabric-installer-1.1.1.jar"
$fabricPath = Join-Path $downloadsFolder "fabric-installer-1.1.1.jar"

Write-Host "Downloading Legacy Fabric Installer..." -ForegroundColor Cyan
# Cleaned up: Only use Invoke-WebRequest with UserAgent string to prevent locks or drops
Invoke-WebRequest -Uri $fabricUrl -OutFile $fabricPath -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"

# 5. Download Better Than Wolves CE Mod to the .minecraft/mods folder
$modUrl = "https://cdn.modrinth.com/data/PiC4CKoa/versions/Pbz5N4Ul/btwce-3.1.0.jar?mr_download_reason=standalone&mr_game_version=1.6.4&mr_loader=legacy-fabric"
$modPath = Join-Path $modsFolder "btwce-3.1.0.jar"

Write-Host "Downloading Better Than Wolves CE Mod..." -ForegroundColor Cyan
Invoke-WebRequest -Uri $modUrl -OutFile $modPath -UserAgent "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"

# Restore default progress bar setting
$ProgressPreference = 'Continue'

# Dynamic System Lookup for the newly installed Temurin Java Paths
$temurinBaseDir = "C:\Program Files\Eclipse Adoptium"
$javaExePath = ""
$javawPath = ""

if (Test-Path $temurinBaseDir) {
    # Dynamically grab whatever JDK 17 sub-version folder winget downloaded
    $jdkDir = Get-ChildItem -Path $temurinBaseDir -Directory | Where-Object { $_.Name -like "jdk-17*" } | Select-Object -First 1
    if ($jdkDir) {
        $javaExePath = Join-Path $jdkDir.FullName "bin\java.exe"
        $javawPath   = Join-Path $jdkDir.FullName "bin\javaw.exe"
    }
}

# Fallback checking to stop execution if pathing is fundamentally missing
if (-not $javaExePath -or -not (Test-Path $javaExePath)) { 
    Write-Host "Critical Error: Java 17 path could not be resolved automatically." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    Exit
}

# =========================================================================
# 6. RUN THE FABRIC INSTALLER HEADLESSLY (NO POPUP WINDOW REQUIRED)
# =========================================================================
Write-Host "`nRunning Legacy Fabric Installer headlessly via CLI..." -ForegroundColor Green
Start-Process -FilePath $javaExePath -ArgumentList "-jar `"$fabricPath`" client -dir `"$minecraftDir`" -mcversion $mcVersion -noprofile" -Wait -NoNewWindow

# =========================================================================
# 7. MODIFY THE JSON FILE
# =========================================================================
Write-Host "`nUpdating launcher_profiles.json with Java 17 path..." -ForegroundColor Cyan

$jsonPath = Join-Path $minecraftDir "launcher_profiles.json"

if (Test-Path $jsonPath) {
    $json = Get-Content -Raw -Path $jsonPath | ConvertFrom-Json
    
    # FIX: Changed single quotes to double quotes so $mcVersion resolves to 1.6.4
    $profileName = "fabric-loader-$mcVersion"
    
    if ($json.profiles -and $json.profiles.$profileName) {
        
        if ($json.profiles.$profileName.PSObject.Properties['javaDir']) {
            $json.profiles.$profileName.javaDir = $javawPath
            Write-Host "Replaced existing javaDir attribute." -ForegroundColor Yellow
        } else {
            $json.profiles.$profileName | Add-Member -MemberType NoteProperty -Name "javaDir" -Value $javawPath -Force
            Write-Host "Added new javaDir attribute." -ForegroundColor Green
        }
        
        $json | ConvertTo-Json -Depth 100 | Set-Content -Path $jsonPath
        Write-Host "Successfully attached Java 17 path to '$profileName' profile!" -ForegroundColor Green
    } else {
        Write-Host "Profile block '$profileName' missing. Generating it manually..." -ForegroundColor Yellow
        
        if (-not $json.profiles) { $json | Add-Member -MemberType NoteProperty -Name "profiles" -Value (New-Object PSObject) }
        
        $newProfile = [PSCustomObject]@{
            created       = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.000Z")
            icon          = "Furnace"
            javaDir       = $javawPath
            lastUsed      = (Get-Date -Format "yyyy-MM-ddTHH:mm:ss.000Z")
            lastVersionId = "fabric-loader-$mcLauncherVersion-$mcVersion"
            name          = $profileName
            type          = "custom"
        }
        
        $json.profiles | Add-Member -MemberType NoteProperty -Name $profileName -Value $newProfile -Force
        $json | ConvertTo-Json -Depth 100 | Set-Content -Path $jsonPath
        Write-Host "Successfully injected custom '$profileName' configuration object directly!" -ForegroundColor Green
    }
} else {
    Write-Host "Error: launcher_profiles.json file could not be found at path: $jsonPath" -ForegroundColor Red
}

Write-Host "`n Setup completed successfully!" -ForegroundColor Green
Write-Host "Java 17 (Temurin) is installed." -ForegroundColor Gray
Write-Host "Fabric Installer saved to: $fabricPath" -ForegroundColor Gray
Write-Host "Mod file saved to: $modPath" -ForegroundColor Gray
Read-Host "Press Enter to exit"
