# Windows Build & Release Guide

## Prerequisites

1. **Go** (golang.org/dl)
   ```batch
   winget install GoLang.Go
   ```

2. **Flutter** (flutter.dev/docs/get-started/install/windows)
   ```batch
   winget install Google.Flutter
   ```

3. **Inno Setup Compiler** (jrsoftware.org/isdl.php)
   ```batch
   winget install JRSoftware.InnoSetup
   ```

## Quick Start

### Build the Windows app only (no installer)

```batch
cd server
make windows-app
# Output: app/build/windows/x64/runner/Release/
```

### Build the full installer

```batch
# Using the batch script (recommended)
.\scripts\build_installer.bat 2.0.0
# Output: build/TokenGate-2.0.0-setup.exe

# Or using make
cd server
make windows-installer VERSION=2.0.0
# Output: build/TokenGate-2.0.0-setup.exe
```

## Release

Releasing a Windows version requires:

1. **GitHub Personal Access Token** (repo scope)
   ```batch
   set TOKEN_GATE_GITHUB_TOKEN=ghp_xxxx
   ```

2. **SSH key** added to GitHub (for git push)

3. Run the release script:
   ```batch
   .\scripts\release.bat v2.0.0
   ```

The script will:
1. Build the installer locally
2. Tag the commit and push to GitHub
3. Create a GitHub Release and upload the installer

## Installer Features

The Inno Setup installer (`installer.iss`) provides:

- **Custom installation path**: Users can choose where to install (default: `C:\Program Files\TokenGate`)
- **Multi-language support**: English, 简体中文, 日本語
- **Desktop shortcut**: Optional (checkbox in installer)
- **Quick launch icon**: Optional (Windows 7 and below)
- **Start menu entry**: Always created
- **Uninstall program**: Complete removal including user data
- **Running app detection**: Automatically closes any running TokenGate instances before installing

## File Structure

After installation:

```
C:\Program Files\TokenGate\
├── TokenGate.exe
├── flutter_assets/
├── data/
└── (other Flutter runtime files)

%LOCALAPPDATA%\TokenGate\          # User data (created on first run)
%USERPROFILE%\.token_gate\        # Database and config (created on first run)
```

## Troubleshooting

### "Inno Setup Compiler (iscc) not found"

Install Inno Setup:
```batch
winget install JRSoftware.InnoSetup
```

Then verify:
```batch
iscc /?
```

### "Failed to push tag"

Make sure your SSH key is added to GitHub:
```batch
ssh -T git@github.com
```

### "TOKEN_GATE_GITHUB_TOKEN not set"

Create a PAT at https://github.com/settings/tokens (needs repo scope) and set:
```batch
set TOKEN_GATE_GITHUB_TOKEN=ghp_xxxx
```

## Testing the Installer

Before releasing, test the installer on a clean Windows machine:

1. Download the installer from GitHub Releases
2. Run it and verify:
   - Custom installation path works
   - Desktop shortcut creation works
   - App launches after installation
   - Uninstall removes all files
3. Test upgrading from a previous version (if applicable)
