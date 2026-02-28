# ScreenPipe Windows Container Build Script
# This script is designed to run inside a Windows Docker container
# It installs all dependencies and builds the project

param(
    [switch]$SkipDeps,
    [switch]$SkipRustBuild,
    [switch]$SkipTauriBuild,
    [string]$OutputPath = "C:\Build",
    [string]$BuildMode = "release",  # "release" or "debug"
    [string]$GitRepoUrl = "https://github.com/mediar-ai/screenpipe.git",
    [string]$GitBranch = "main",
    [string]$ProjectRoot = "C:\screenpipe"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "Continue"

# Colors for output
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }
function Write-Success { param($Message) Write-Host "[SUCCESS] $Message" -ForegroundColor Green }
function Write-Warning { param($Message) Write-Host "[WARNING] $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }

# Create output directory
New-Item -ItemType Directory -Force -Path $OutputPath | Out-Null

# Log file
$LogFile = "$OutputPath\build.log"
Start-Transcript -Path $LogFile -Append

$StartTime = Get-Date
Write-Info "Starting ScreenPipe build at $StartTime"
Write-Info "Build mode: $BuildMode"
Write-Info "Output path: $OutputPath"

# ============================================================================
# STEP 1: Install Dependencies
# ============================================================================
if (-not $SkipDeps) {
    Write-Info "Installing dependencies..."
    
    # Install Chocolatey if not present
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Info "Installing Chocolatey..."
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        $env:PATH = "$env:PATH;$env:ALLUSERSPROFILE\chocolatey\bin"
        refreshenv
        Write-Success "Chocolatey installed"
    }
    
    # Install Git
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Info "Installing Git..."
        choco install git -y --no-progress
        $env:PATH = "$env:PATH;C:\Program Files\Git\cmd"
        refreshenv
        Write-Success "Git installed"
    }
    
    # Install Rust
    if (-not (Get-Command rustc -ErrorAction SilentlyContinue)) {
        Write-Info "Installing Rust..."
        $rustupInit = "$env:TEMP\rustup-init.exe"
        Invoke-WebRequest -Uri "https://win.rustup.rs/x86_64" -OutFile $rustupInit
        & $rustupInit -y --default-toolchain stable --target x86_64-pc-windows-msvc
        $env:PATH = "$env:PATH;$env:USERPROFILE\.cargo\bin"
        [Environment]::SetEnvironmentVariable("PATH", $env:PATH, "Machine")
        refreshenv
        Write-Success "Rust installed"
    }
    
    # Install Node.js LTS
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        Write-Info "Installing Node.js..."
        choco install nodejs-lts -y --no-progress
        $env:PATH = "$env:PATH;C:\Program Files\nodejs"
        refreshenv
        Write-Success "Node.js installed"
    }
    
    # Install Bun
    if (-not (Get-Command bun -ErrorAction SilentlyContinue)) {
        Write-Info "Installing Bun..."
        $bunInstall = "$env:TEMP\bun-install.ps1"
        Invoke-WebRequest -Uri "https://bun.sh/install.ps1" -OutFile $bunInstall
        & $bunInstall
        $env:PATH = "$env:PATH;$env:USERPROFILE\.bun\bin"
        [Environment]::SetEnvironmentVariable("PATH", $env:PATH, "Machine")
        refreshenv
        Write-Success "Bun installed"
    }
    
    # Install Visual Studio Build Tools components
    Write-Info "Checking Visual Studio Build Tools..."
    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vsWhere) {
        $vsPath = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
        if ($vsPath) {
            Write-Success "Visual Studio Build Tools found at: $vsPath"
            & "$vsPath\VC\Auxiliary\Build\vcvars64.bat"
        } else {
            Write-Warning "VC++ tools not found. Attempting to install..."
            choco install visualstudio2022buildtools -y --no-progress
            choco install visualstudio2022-workload-vctools -y --no-progress
        }
    }
    
    # Install LLVM (for bindgen)
    if (-not (Test-Path "C:\Program Files\LLVM\bin\clang.exe")) {
        Write-Info "Installing LLVM..."
        choco install llvm -y --no-progress
        $env:PATH = "$env:PATH;C:\Program Files\LLVM\bin"
        [Environment]::SetEnvironmentVariable("PATH", $env:PATH, "Machine")
        Write-Success "LLVM installed"
    }
    
    # Install WebView2 Runtime
    Write-Info "Checking WebView2 Runtime..."
    $webview2Key = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
    if (-not (Test-Path $webview2Key)) {
        Write-Info "Installing WebView2 Runtime..."
        $webview2Installer = "$env:TEMP\MicrosoftEdgeWebview2Setup.exe"
        Invoke-WebRequest -Uri "https://go.microsoft.com/fwlink/p/?LinkId=2124703" -OutFile $webview2Installer
        & $webview2Installer /silent /install
        Write-Success "WebView2 Runtime installed"
    }
    
    Write-Success "All dependencies installed"
} else {
    Write-Info "Skipping dependency installation (SkipDeps flag set)"
}

# Refresh environment
$env:PATH = "$env:PATH;$env:USERPROFILE\.cargo\bin;C:\Program Files\nodejs;$env:USERPROFILE\.bun\bin"

# Verify installations
Write-Info "Verifying installations..."
rustc --version
cargo --version
node --version
bun --version
git --version

# ============================================================================
# STEP 2: Clone Repository (if not mounted)
# ============================================================================
Write-Info "Setting up project..."

# Check if project is already mounted/cloned
if (-not (Test-Path "$ProjectRoot\Cargo.toml")) {
    Write-Info "Project not found at $ProjectRoot. Cloning from GitHub..."
    
    # Ensure Git is installed
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Info "Installing Git..."
        choco install git -y --no-progress
        $env:PATH = "$env:PATH;C:\Program Files\Git\cmd"
        refreshenv
    }
    
    # Clone the repository
    Write-Info "Cloning $GitRepoUrl (branch: $GitBranch)..."
    git clone --branch $GitBranch --depth 1 $GitRepoUrl $ProjectRoot
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to clone repository!"
        exit 1
    }
    
    Write-Success "Repository cloned successfully"
} else {
    Write-Info "Project already exists at $ProjectRoot"
}

Set-Location $ProjectRoot

# Configure Git (needed for some dependencies)
git config --global core.longpaths true
git config --global --add safe.directory $ProjectRoot

# ============================================================================
# STEP 3: Build Rust Project
# ============================================================================
if (-not $SkipRustBuild) {
    Write-Info "Building Rust project (mode: $BuildMode)..."
    
    # Set environment variables for Windows build
    $env:RUST_BACKTRACE = "1"
    $env:CARGO_NET_GIT_FETCH_WITH_CLI = "true"
    
    # Force dynamic C++ runtime to avoid /MT vs /MD conflicts
    $env:RUSTFLAGS = "-C target-feature=+crt-static"
    
    # Build based on mode
    if ($BuildMode -eq "release") {
        Write-Info "Running: cargo build --release"
        cargo build --release 2>&1 | Tee-Object -FilePath "$OutputPath\rust-build.log"
    } else {
        Write-Info "Running: cargo build"
        cargo build 2>&1 | Tee-Object -FilePath "$OutputPath\rust-build.log"
    }
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Rust build failed! Check $OutputPath\rust-build.log"
        exit 1
    }
    
    Write-Success "Rust build completed"
    
    # Copy Rust binaries to output
    $targetDir = if ($BuildMode -eq "release") { "target\release" } else { "target\debug" }
    $binaries = @("screenpipe.exe", "screenpipe-server.exe", "screenpipe-vision.exe", "screenpipe-audio.exe")
    foreach ($bin in $binaries) {
        $binPath = "$ProjectRoot\$targetDir\$bin"
        if (Test-Path $binPath) {
            Copy-Item $binPath "$OutputPath\$bin" -Force
            Write-Info "Copied $bin to output"
        }
    }
} else {
    Write-Info "Skipping Rust build (SkipRustBuild flag set)"
}

# ============================================================================
# STEP 4: Build Tauri App
# ============================================================================
if (-not $SkipTauriBuild) {
    Write-Info "Building Tauri app..."
    
    $appDir = "$ProjectRoot\apps\screenpipe-app-tauri"
    if (-not (Test-Path $appDir)) {
        Write-Error "Tauri app directory not found at $appDir"
        exit 1
    }
    
    Set-Location $appDir
    
    # Install dependencies
    Write-Info "Installing Node dependencies..."
    bun install 2>&1 | Tee-Object -FilePath "$OutputPath\bun-install.log"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Bun install failed! Check $OutputPath\bun-install.log"
        exit 1
    }
    
    # Run pre-build script
    Write-Info "Running pre-build script..."
    bun run prebuild 2>&1 | Tee-Object -FilePath "$OutputPath\prebuild.log"
    
    # Build Tauri app
    Write-Info "Building Tauri application..."
    $env:TAURI_SIGNING_PRIVATE_KEY = ""
    $env:TAURI_SIGNING_PRIVATE_KEY_PASSWORD = ""
    
    bun tauri build 2>&1 | Tee-Object -FilePath "$OutputPath\tauri-build.log"
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Tauri build failed! Check $OutputPath\tauri-build.log"
        exit 1
    }
    
    Write-Success "Tauri build completed"
    
    # Copy Tauri artifacts to output
    $tauriOutDir = "$ProjectRoot\apps\screenpipe-app-tauri\src-tauri\target\release\bundle"
    if (Test-Path $tauriOutDir) {
        Write-Info "Copying Tauri artifacts to output..."
        Get-ChildItem -Path $tauriOutDir -Recurse -Include "*.msi", "*.exe", "*.nsis", "*.appx", "*.msix" | ForEach-Object {
            $dest = "$OutputPath\$($_.Name)"
            Copy-Item $_.FullName $dest -Force
            Write-Info "Copied: $($_.Name)"
        }
    }
} else {
    Write-Info "Skipping Tauri build (SkipTauriBuild flag set)"
}

# ============================================================================
# STEP 5: Summary
# ============================================================================
$EndTime = Get-Date
$Duration = $EndTime - $StartTime

Write-Info "========================================"
Write-Info "Build completed!"
Write-Info "Duration: $($Duration.ToString('hh\:mm\:ss'))"
Write-Info "Output directory: $OutputPath"
Write-Info "========================================"

# List output files
Write-Info "Output files:"
Get-ChildItem $OutputPath | ForEach-Object {
    $size = if ($_.Length -gt 1GB) { "0:N2} GB" -f ($_.Length / 1GB) }
            elseif ($_.Length -gt 1MB) { "0:N2} MB" -f ($_.Length / 1MB) }
            elseif ($_.Length -gt 1KB) { "0:N2} KB" -f ($_.Length / 1KB) }
            else { "$($_.Length) B" }
    Write-Host "  - $($_.Name) ($size)" -ForegroundColor Gray
}

Stop-Transcript

Write-Success "Build script completed successfully!"
