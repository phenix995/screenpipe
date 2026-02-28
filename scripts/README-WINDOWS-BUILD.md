# ScreenPipe Windows Container Build

This directory contains scripts and configurations for building ScreenPipe inside a Windows Docker container.

## Files

- [`build-windows-container.ps1`](build-windows-container.ps1) - Main PowerShell build script that runs inside the container
- [`Dockerfile.windows`](Dockerfile.windows) - Windows container image definition
- [`../docker-compose.windows-build.yml`](../docker-compose.windows-build.yml) - Docker Compose configuration

## Prerequisites

1. **Docker Desktop** with Windows containers enabled
2. **Switch to Windows containers** (Docker Desktop tray icon → Switch to Windows containers)
3. At least **16GB RAM** and **8 CPU cores** allocated to Docker
4. **50GB+ free disk space**

## Quick Start

### Option 1: Using Docker Compose (Recommended)

```powershell
# Set environment variables
$env:OUTPUT_PATH = "C:\Build"
$env:GIT_BRANCH = "main"
$env:BUILD_MODE = "release"
$env:WINDOWS_ISOLATION = "process"  # or "hyperv" if process fails

# Build and run
docker-compose -f docker-compose.windows-build.yml up --build
```

### Option 2: Using Docker Commands

```powershell
# Build the image
docker build -t screenpipe-builder:windows -f scripts/Dockerfile.windows scripts/

# Run the container
docker run --rm `
  -e GIT_REPO_URL="https://github.com/mediar-ai/screenpipe.git" `
  -e GIT_BRANCH="main" `
  -e BUILD_MODE="release" `
  -v "C:\Build:C:\Build" `
  screenpipe-builder:windows
```

### Option 3: Run with Custom Parameters

```powershell
# Run with specific branch and debug mode
docker-compose -f docker-compose.windows-build.yml run --rm screenpipe-builder `
  powershell -Command "C:\scripts\build.ps1 -GitBranch dev -BuildMode debug -OutputPath C:\Build"
```

## Build Script Parameters

The [`build-windows-container.ps1`](build-windows-container.ps1) script accepts the following parameters:

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-SkipDeps` | switch | false | Skip dependency installation |
| `-SkipRustBuild` | switch | false | Skip Rust build step |
| `-SkipTauriBuild` | switch | false | Skip Tauri build step |
| `-OutputPath` | string | `C:\Build` | Output directory for build artifacts |
| `-BuildMode` | string | `release` | Build mode: `release` or `debug` |
| `-GitRepoUrl` | string | GitHub URL | Repository URL to clone |
| `-GitBranch` | string | `main` | Git branch to checkout |
| `-ProjectRoot` | string | `C:\screenpipe` | Project directory inside container |

## Environment Variables

When using Docker Compose, you can set these environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `OUTPUT_PATH` | `C:\Build` | Host path for build output |
| `GIT_REPO_URL` | `https://github.com/mediar-ai/screenpipe.git` | Repository URL |
| `GIT_BRANCH` | `main` | Branch to build |
| `BUILD_MODE` | `release` | Build mode |
| `WINDOWS_ISOLATION` | `process` | Container isolation mode |

## Output

Build artifacts will be copied to the specified output directory:

- Rust binaries (`screenpipe.exe`, `screenpipe-server.exe`, etc.)
- Tauri installers (`.msi`, `.exe`, `.nsis`)
- Build logs (`build.log`, `rust-build.log`, `tauri-build.log`)

## Troubleshooting

### Container Isolation Issues

If you get isolation errors, try Hyper-V mode:
```powershell
$env:WINDOWS_ISOLATION = "hyperv"
docker-compose -f docker-compose.windows-build.yml up --build
```

### Memory Issues

Increase Docker memory limit to at least 16GB in Docker Desktop settings.

### Build Failures

Check the logs in the output directory:
- `build.log` - Main build log
- `rust-build.log` - Rust compilation log
- `tauri-build.log` - Tauri build log
- `bun-install.log` - Node dependencies installation log

### Manual Debugging

Run container interactively to debug:
```powershell
docker run -it --rm `
  -v "C:\Build:C:\Build" `
  --entrypoint powershell `
  screenpipe-builder:windows
```

Then manually run build steps inside the container.

## Notes

- First build will take 30-60 minutes (installing dependencies)
- Subsequent builds are faster due to Docker layer caching
- The container clones the repository fresh each time
- Build artifacts are persisted to the host via volume mount
