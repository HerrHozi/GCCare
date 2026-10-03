# Change Log

```Text
Author:          Holger Zimmermann | <zimmermann.holger@live.de>
Current Version: 2026.10.3.686
Last Update:     2026-10-03
```

- Version 2026.10.3.686
  - Renamed Get-GarminBadges to Get-GarminBadge (alias Get-GarminBadges)
  - Added -Type Earned | Available | NonCompleted to Get-GarminBadge
  - Added -CustomSelection, -Filter, -Property and -SaveCustomSelection (GCCare.json > GarminConnectApi > CustomSelection > Badge)
  - -GroupBy Year | Month also for Available and NonCompleted
  - Added Function Get-GarminActivity (default: last 10 runs, -Miles, -GroupBy Year | Month | Week | ActivityType,
    custom selection per activity type in GCCare.json > GarminConnectApi > CustomSelection > Activity)
  - Added private functions Get-GarminEarnedBadgeList, Get-GarminAvailableBadgeList, Get-GarminNonCompletedBadgeList,
    Get-GarminActivityList, Get-GCCareCustomSelection and Save-GCCareCustomSelection
  - Added Function Add-GarminBodyComposition (alias Add-BodyComposition): single weigh-in via temporary FIT upload,
    kg or lbs from the profile measurement system, '.' or ',' as decimal separator
  - New-GarminWeightFitFile writes optional values only when passed (no 0 values in Garmin Connect)
  - Added private functions Get-GCCareArgumentText and ConvertTo-GCCareDecimal
  - Added start/end logging with run time to all private main functions
  - Fixed Convert-KmhToPace returning "60 sec" for paces like 5:59.6

- Version 2026.10.2.714
  - Replaced all Python Functions by PowerShell

- Version 2026.10.1.1419
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
