# Change Log

```Text
Author:          Holger Zimmermann | <zimmermann.holger@live.de>
Current Version: 2026.10.1.1358
Last Update:     2026-10-01
```

- Version 2026.10.1.1358
  - Remove unused Functions
  - Update Help Context

- Version 2026.10.1.746
  - Start removing Python
  - Added Get-GarminUser

- Version 2026.9.30.1129
  - Added Function Get-GarminBadges

- Version 2026.8.25.777
  - Update Readme File

- Version 2026.8.19.925
  - Added Function Invoke-PipInstall.ps1

- Version 2026.8.18.1071
  - Added Functions Test-GCCarePythonInstalled.ps1 & Test-GCCarePipPackageInstalled.ps1

- Version 2026.6.9.954
  - Updated Function Convert-SecToMin

- Version 2026.6.4.614
  - Updated Help Info & Readme file

- Version 2026.6.1.1089
  - Added Function Convert-TanitaExportToFitFile
  - Added Function Send-FitFileToGarminConnect

- Version 2026.6.1.823
  - Added Function Update-TCXFile

- Version 2026.5.22.1018
  - First Version

## internal - update via git

```PowerShell
$Host.UI.RawUI.WindowTitle = "GIT - Uploading GCCare"
$dir = "$env:OneDriveConsumer\Programming\GitHub\GCCare"
Set-Location $dir
git pull
git status
git add -A
git commit -m 'Version 2026.8.25.777 is out - see also readme.md or changeLog.md'
git push

Publish-Module -Exclude '.git\*' -Name .\GCCare.psd1  -NuGetApiKey $NuGetApiKey
