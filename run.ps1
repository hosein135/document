#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'

# Windows bootstrap for مدار منطقی:
#   WinGet → vfox → pinned Typst → Parastoo fonts → typst compile → PDF
# Patterns adapted from ../animation1/run.ps1 (winget, vfox wrappers, PATH).

Set-Location $PSScriptRoot
Write-Host "Working directory set to: $PSScriptRoot" -ForegroundColor Cyan

$vfoxVersion = "0.6.2"
$vfoxPackageId = "version-fox.vfox"
$typstTargetVersion = "0.13.1"
$parastooVersion = "2.0.1"
$parastooZipUrl = "https://github.com/rastikerdar/parastoo-font/archive/refs/tags/v$parastooVersion.zip"

function Write-Section([string]$Title) {
    Write-Host ""
    Write-Host ("=" * 64) -ForegroundColor DarkCyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host ("=" * 64) -ForegroundColor DarkCyan
}

function Refresh-SessionPath {
    param([string]$WingetPackagesRoot)

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    if ($WingetPackagesRoot -and (Test-Path $WingetPackagesRoot)) {
        foreach ($exeName in @("vfox.exe", "typst.exe")) {
            $exe = Get-ChildItem -Path $WingetPackagesRoot -Recurse -Filter $exeName -ErrorAction SilentlyContinue |
                Select-Object -First 1
            if ($exe -and ($env:Path -notlike "*$($exe.DirectoryName)*")) {
                $env:Path = "$($exe.DirectoryName);$env:Path"
            }
        }
    }

    foreach ($sdkRoot in @("$HOME\.vfox\sdks", "$HOME\.version-fox\sdks")) {
        if (-not (Test-Path $sdkRoot)) { continue }
        $exe = Get-ChildItem -Path $sdkRoot -Recurse -Filter "typst.exe" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($exe -and ($env:Path -notlike "*$($exe.DirectoryName)*")) {
            $env:Path = "$($exe.DirectoryName);$env:Path"
        }
    }

    foreach ($vfoxHome in @("$HOME\.vfox", "$HOME\.version-fox")) {
        if ((Test-Path $vfoxHome) -and ($env:Path -notlike "*$vfoxHome*")) {
            $env:Path = "$vfoxHome;$env:Path"
        }
    }
}

function Add-VfoxSdkToMachinePath {
    param([Parameter(Mandatory = $true)][string]$ExeName)

    $cmd = Get-Command $ExeName -ErrorAction SilentlyContinue
    $binDir = $null
    if ($cmd -and $cmd.Source) {
        $binDir = Split-Path $cmd.Source -Parent
    }
    if (-not $binDir) {
        foreach ($root in @("$HOME\.vfox\sdks", "$HOME\.version-fox\sdks")) {
            if (Test-Path $root) {
                $exe = Get-ChildItem -Path $root -Recurse -Filter $ExeName -ErrorAction SilentlyContinue |
                    Select-Object -First 1
                if ($exe) { $binDir = $exe.DirectoryName; break }
            }
        }
    }
    if (-not $binDir) {
        Write-Host "  WARNING: $ExeName not found on PATH or in vfox SDK directories." -ForegroundColor Yellow
        return $false
    }

    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    if ($machinePath -like "*$binDir*") {
        if ($env:Path -notlike "*$binDir*") { $env:Path = "$binDir;$env:Path" }
        return $true
    }

    [System.Environment]::SetEnvironmentVariable("Path", "$binDir;$machinePath", "Machine")
    if ($env:Path -notlike "*$binDir*") { $env:Path = "$binDir;$env:Path" }
    Write-Host "  Added $binDir to system PATH (permanent)" -ForegroundColor Green
    return $true
}

function Invoke-Vfox {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$VfoxArgs)
    $prevEAP = $ErrorActionPreference
    $prevNative = $null
    if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
        $prevNative = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
    }
    $ErrorActionPreference = 'Continue'
    $exe = (Get-Command vfox -ErrorAction SilentlyContinue).Source
    if (-not $exe) { $exe = 'vfox' }
    & $exe @VfoxArgs
    $code = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    if ($null -ne $prevNative) { $PSNativeCommandUseErrorActionPreference = $prevNative }
    return $code
}

function Install-VfoxSdk {
    param(
        [Parameter(Mandatory = $true)][string]$Plugin,
        [Parameter(Mandatory = $true)][string]$Version
    )
    Write-Host "  Downloading and installing $Plugin@$Version via vfox..." -ForegroundColor Cyan
    Write-Host "  (vfox shows its own progress bar)" -ForegroundColor DarkGray
    $exitCode = Invoke-Vfox install "${Plugin}@${Version}"
    if ($exitCode -ne 0) {
        $listOut = & {
            $prev = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            & vfox list $Plugin 2>&1 | Out-String
            $ErrorActionPreference = $prev
        }
        if ($listOut -match [regex]::Escape($Version)) {
            Write-Host "  $Plugin@$Version is already installed." -ForegroundColor Green
            return $true
        }
        Write-Host "  vfox install $Plugin@$Version failed (exit $exitCode)." -ForegroundColor Yellow
        return $false
    }
    Write-Host "  $Plugin@$Version installed." -ForegroundColor Green
    return $true
}

function Download-File {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination,
        [string]$Label = "Downloading"
    )
    Write-Host "  $Label" -ForegroundColor Cyan
    Write-Host "  URL: $Url" -ForegroundColor DarkGray
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curl) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & curl.exe -L -# -o "$Destination" "$Url"
        $curlExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP
        if ($curlExit -eq 0 -and (Test-Path $Destination)) {
            $sizeMB = [math]::Round((Get-Item $Destination).Length / 1MB, 1)
            Write-Host "  Done ($sizeMB MB)" -ForegroundColor Green
            return $true
        }
    }
    $prevProgress = $ProgressPreference
    $ProgressPreference = 'Continue'
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination
        $sizeMB = [math]::Round((Get-Item $Destination).Length / 1MB, 1)
        Write-Host "  Done ($sizeMB MB)" -ForegroundColor Green
        return $true
    } catch {
        Write-Host "  Download failed: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    } finally {
        $ProgressPreference = $prevProgress
    }
}

function Ensure-ParastooFonts {
    param([Parameter(Mandatory = $true)][string]$DestDir)

    $ttf = @(Get-ChildItem -Path $DestDir -Recurse -Filter "*.ttf" -ErrorAction SilentlyContinue)
    if ($ttf.Count -gt 0) {
        Write-Host "Parastoo fonts already present ($($ttf.Count) TTF) in $DestDir" -ForegroundColor Green
        return $DestDir
    }

    Write-Host "Fetching parastoo-font v$parastooVersion (same release as nixpkgs.parastoo-fonts)..." -ForegroundColor Yellow
    $tmpZip = Join-Path $env:TEMP "parastoo-font-v$parastooVersion.zip"
    $tmpExtract = Join-Path $env:TEMP "parastoo-font-v$parastooVersion"
    if (-not (Download-File -Url $parastooZipUrl -Destination $tmpZip -Label "Downloading Parastoo $parastooVersion")) {
        throw "Could not download Parastoo fonts."
    }
    if (Test-Path $tmpExtract) { Remove-Item -Recurse -Force $tmpExtract }
    Expand-Archive -Path $tmpZip -DestinationPath $tmpExtract -Force

    New-Item -ItemType Directory -Force -Path $DestDir | Out-Null
    $copied = 0
    Get-ChildItem -Path $tmpExtract -Recurse -Filter "*.ttf" | ForEach-Object {
        Copy-Item -Force $_.FullName (Join-Path $DestDir $_.Name)
        $copied++
    }
    if ($copied -lt 1) {
        throw "Parastoo zip extracted but no TTF files were found."
    }
    Write-Host "  Installed $copied Parastoo TTF files → $DestDir" -ForegroundColor Green
    return $DestDir
}

## 1. INSTALL WINGET
Write-Section "Bootstrap: WinGet"
if (!(Get-Command winget -ErrorAction SilentlyContinue)) {
    Write-Host "WinGet not found. Installing WinGet and App Installer dependencies..." -ForegroundColor Yellow
    $installerPath = "$env:TEMP\Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle"
    $downloaded = Download-File -Url "https://aka.ms/getwinget" -Destination $installerPath -Label "Downloading WinGet (App Installer)"
    if (-not $downloaded) { throw "Failed to download WinGet." }
    Add-AppxPackage -Path $installerPath
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue
    Write-Host "WinGet installed successfully." -ForegroundColor Green
} else {
    Write-Host "WinGet is already installed." -ForegroundColor Green
}

## 2. PATH REFRESH
$wingetPackagesRoot = "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
Refresh-SessionPath -WingetPackagesRoot $wingetPackagesRoot

## 3. VFOX
Write-Section "Bootstrap: vfox + Typst"
if (!(Get-Command vfox -ErrorAction SilentlyContinue)) {
    Write-Host "Installing vfox version $vfoxVersion via winget..." -ForegroundColor Yellow
    winget install --id $vfoxPackageId --version $vfoxVersion --exact --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { throw "Failed to install vfox $vfoxVersion." }
} else {
    Write-Host "vfox is already installed." -ForegroundColor Green
}

Refresh-SessionPath -WingetPackagesRoot $wingetPackagesRoot
foreach ($p in @(
    "$env:LOCALAPPDATA\vfox",
    "$HOME\AppData\Local\vfox",
    "$env:ProgramFiles\vfox"
)) {
    if ((Test-Path $p) -and ($env:Path -notlike "*$p*")) { $env:Path = "$p;$env:Path" }
}

if (Get-Command vfox -ErrorAction SilentlyContinue) {
    Write-Host "vfox successfully located. Activating session environment..." -ForegroundColor Green
    Invoke-Expression "$(vfox activate pwsh)"
} else {
    throw "vfox executable could not be resolved. Please verify package availability."
}

## 4. TYPST PLUGIN + PINNED VERSION
Write-Host "Adding Typst plugin to vfox..." -ForegroundColor Yellow
$addCode = Invoke-Vfox add typst
if ($addCode -ne 0) {
    Write-Host "Registry add skipped or already present; trying GitHub zip if needed..." -ForegroundColor Yellow
    $pluginZip = "https://github.com/GuilleX7/vfox-typst/archive/refs/heads/master.zip"
    Invoke-Vfox add --source $pluginZip typst | Out-Null
}

Write-Host "Installing Typst version $typstTargetVersion..." -ForegroundColor Yellow
if (-not (Install-VfoxSdk -Plugin "typst" -Version $typstTargetVersion)) {
    throw "Failed to install typst@$typstTargetVersion via vfox."
}

Write-Host "Activating Typst $typstTargetVersion globally and for this project..." -ForegroundColor Yellow
Invoke-Vfox use -g "typst@$typstTargetVersion" | Out-Null
Invoke-Vfox use -p "typst@$typstTargetVersion" | Out-Null

if (Get-Command vfox -ErrorAction SilentlyContinue) {
    Invoke-Expression "$(vfox activate pwsh)"
}
Add-VfoxSdkToMachinePath -ExeName "typst.exe" | Out-Null
Refresh-SessionPath -WingetPackagesRoot $wingetPackagesRoot
if (Get-Command vfox -ErrorAction SilentlyContinue) {
    Invoke-Expression "$(vfox activate pwsh)"
}

if (-not (Get-Command typst -ErrorAction SilentlyContinue)) {
    throw "typst executable could not be resolved after vfox install."
}
Write-Host "Verifying Typst version..." -ForegroundColor Cyan
typst --version

## 5. PARASTOO FONTS (same 2.0.1 as nixpkgs.parastoo-fonts)
Write-Section "Bootstrap: Parastoo fonts"
$fontDir = Join-Path $PSScriptRoot "vendor\parastoo-fonts"
Ensure-ParastooFonts -DestDir $fontDir | Out-Null

## 6. COMPILE PDF
Write-Section "Compile Typst → PDF"
$src = Join-Path $PSScriptRoot "src\main.typ"
$outDir = Join-Path $PSScriptRoot "output"
$pdf = Join-Path $outDir "madar-manteghi.pdf"
if (-not (Test-Path $src)) { throw "Missing Typst source: $src" }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

$env:TYPST_FONT_PATHS = $fontDir
Write-Host "typst compile --font-path $fontDir --ignore-system-fonts" -ForegroundColor DarkGray
$prevNative = $null
if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue) {
    $prevNative = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
}
try {
    & typst compile --root $PSScriptRoot --font-path $fontDir --ignore-system-fonts $src $pdf
    if ($LASTEXITCODE -ne 0) { throw "typst compile failed (exit $LASTEXITCODE)." }
} finally {
    if ($null -ne $prevNative) {
        $PSNativeCommandUseErrorActionPreference = $prevNative
    }
}

Write-Section "Done"
Write-Host "==> PDF ready: $pdf" -ForegroundColor Green
Get-Item $pdf | Format-Table Name, Length, LastWriteTime
