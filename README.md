# GCCare (Garmin Connect Care)

![Module Type](https://img.shields.io/badge/type-PowerShell%20Module-orange)
![PowerShellGallery](https://img.shields.io/powershellgallery/v/GCCare)
![PowerShell](https://img.shields.io/badge/PowerShell-7.1%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Maintenance](https://img.shields.io/badge/status-active-brightgreen)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/HerrHozi/GCCare)

```Text
Author:          Holger Zimmermann | zimmermann.holger@live.de
Current Version: 2026.10.3.686
Last Update:     2026-10-03
```

GCCare is a pure PowerShell module for Garmin Connect workflows, Tanita body-composition exports, and FIT/TCX file handling. It signs in to Garmin Connect, talks to the Garmin Connect API, creates and uploads FIT files, converts body-data CSV exports, calculates weekly averages, reads badges, user profile and the latest activity, and analyzes or adjusts TCX files - without any external runtime.

## Project Information

- Author: Holger Zimmermann
- Project: <https://github.com/HerrHozi/GCCare>
- Blog: <https://herrhozi.com>
- License: MIT

## What GCCare Does

GCCare currently provides the following capabilities:

- Sign in to Garmin Connect (including MFA) and keep the access token fresh automatically.
- Read the Garmin Connect user profile, activities (km or miles, grouped by year, month, week or type), and earned, available or non-completed badges with level summary.
- Convert Tanita CSV exports into Garmin-compatible weight FIT files.
- Upload FIT files to Garmin Connect from your personal workspace folder.
- Add a single weigh-in with body composition values (kg or lbs) to Garmin Connect.
- Calculate weekly averages from body-composition data.
- Analyze TCX lap metrics such as distance, time, moving time, ascent, descent, pace, and heart rate.
- Update TCX files with recalculated lap distance and elevation values.

By default, GCCare stores generated data and intermediate files under `$env:USERPROFILE\GCCare`.

## Module Structure

- `Public/`: exported PowerShell commands
- `Private/`: internal PowerShell helper functions, including the Garmin Connect API client (`GarminConnectApi.ps1`) and the FIT encoder (`New-GarminWeightFitFile.ps1`)
- `Docs/`: additional documentation, e.g. the Garmin Connect API reference (`GarminConnectApi.md`)
- `Examples/`: sample FIT, TCX, and CSV files
- `$env:USERPROFILE\GCCare`: default per-user workspace for generated FIT files, logs, and configuration
- `~\.garminconnect\gctoken.json`: default Garmin Connect token store

## Requirements

- Windows
- PowerShell 7.1 or later

No additional runtimes or packages are required.

## Installation

### Import from a local clone

```powershell
Import-Module .\GCCare.psd1 -Force
```

### Install from PowerShell Gallery

```powershell
Install-Module -Name GCCare -Scope CurrentUser -Force
Import-Module GCCare -Force
```

### Default folders

On import, the module creates its working folders under `$env:USERPROFILE\GCCare`:

| Folder | Purpose |
| --- | --- |
| `$env:USERPROFILE\GCCare\FitFiles` | Generated FIT files and default upload folder |
| `$env:USERPROFILE\GCCare\FitFiles\Uploaded` | FIT files that were uploaded to Garmin Connect |
| `$env:USERPROFILE\GCCare\Logs` | Log file `GCCare.log` (with `-EnableLogging`) |
| `$env:USERPROFILE\GCCare\Config` | Configuration file `GCCare.json` |
| `$env:USERPROFILE\GCCare\Temp` | Temporary files |
| `$env:USERPROFILE\GCCare\CleanUp` | Clean-up folder |

## Quick Start

### Sign in to Garmin Connect

```powershell
Get-GarminToken -Test
```

`Get-GarminToken` asks for e-mail, password and - if enabled - the MFA code, and saves the tokens to `~\.garminconnect\gctoken.json`. All Garmin Connect commands use this file and renew the access token automatically. If no token file exists yet, any Garmin Connect command starts this sign-in by itself - so calling `Get-GarminToken` first is optional.

To use another token location, pass `-TokenStore` to the commands or set `$env:GARMINTOKENS`.

### Show the Garmin Connect user

```powershell
Get-GarminUser -Quiet | Format-Table
```

### Show badges and level

```powershell
Get-GarminBadge -GroupBy Year | Format-Table
Get-GarminBadge -Type Available -GroupBy Month | Format-Table
Get-GarminBadge -Type NonCompleted -CustomSelection | Format-Table
```

`-Type` selects `Earned` (default), `Available` (not earned yet) or `NonCompleted` (joined challenges that are not completed yet). With `-CustomSelection`, the Where-Object filter and the Select-Object properties are read from the section `GarminConnectApi` in `$env:USERPROFILE\GCCare\Config\GCCare.json`:

```json
"GarminConnectApi": {
  "CustomSelection": {
    "Badge": {
      "NonCompleted": {
        "Where-Object": "{$_.badgeEarnedDate -eq $null}",
        "Select-Object": "badgeChallengeName, endDate, badgeTargetValue, badgeProgressValue"
      }
    }
  }
}
```

`-Filter` and `-Property` override these values for one call; add `-SaveCustomSelection` to store them:

```powershell
Get-GarminBadge -Type NonCompleted -Property badgeChallengeName, endDate, badgeProgressValue -SaveCustomSelection
```

### Convert Tanita measurements to FIT files

```powershell
Convert-TanitaExportToFitFile -csvFile "$env:USERPROFILE\GCCare\Examples\example_scale_measurements.csv" -LastX 7
```

Add `-Upload` to upload the created FIT files to Garmin Connect right away.

The CSV column names are read from the section `MeasurementHeaders` in `$env:USERPROFILE\GCCare\Config\GCCare.json`. Change the values to match your export, e.g. for a German system:

```json
"MeasurementHeaders": {
  "Date": "Datum",
  "Weight (kg)": "Gewicht",
  "Body Fat (%)": "Fettanteil"
}
```

Keys that are not listed keep the default Tanita column name. Comma or semicolon as delimiter, decimal commas and dates like `02.10.2026 06:47` are detected automatically. For a single call, use `-HeaderMapping @{ 'Date' = 'Datum' }`.

### Add a single weigh-in

```powershell
Add-GarminBodyComposition -Weight 94,5
Add-GarminBodyComposition -Weight 94,5 -BodyFat 26,7 -BodyWater 54,7 -MuscleMass 66,2 -BoneMass 3,4 -Date '2026-10-03 07:15'
```

Only `-Weight` is mandatory; without `-Date`, the current date and time is used. Decimal numbers may be entered with `.` or `,`. Weight, muscle and bone mass are read in kg or lbs depending on the measurement system of the Garmin Connect profile (override with `-Unit`); the BMI is calculated from the profile height when `-Bmi` is not given. The values are uploaded as a temporary FIT file - values that are not passed stay empty in Garmin Connect. Use `-WhatIf` to create the FIT file without uploading it.

### Calculate weekly averages from body data

```powershell
Get-WeeklyBodyMetrics -CsvFile "$env:USERPROFILE\GCCare\bodydata.csv"
```

### Upload FIT files to Garmin Connect

```powershell
Send-FitFileToGarminConnect -ImportDirectory "$env:USERPROFILE\GCCare\FitFiles"
```

Uploaded files (and files Garmin Connect already knows) are moved to `FitFiles\Uploaded`, so the next run only uploads new files. Failed uploads stay in place and are retried. Use `-KeepFiles` to leave all files where they are, or `-Path` to upload single files.

### Show activities

```powershell
Get-GarminActivity
Get-GarminActivity -ActivityType all -Last 20 -Miles
Get-GarminActivity -StartDate 2026-01-01 -GroupBy Month | Format-Table
Get-GarminActivity -ActivityType all -StartDate 2026-09-01 -EndDate 2026-09-30 -GroupBy ActivityType | Format-Table
```

Without parameters, the last 10 running activities (including trail and treadmill runs) are returned. The API objects are extended with `StartTime`, `TypeKey`, `TotalDistance`, `TotalTime`, `AvgPace`, `AvgSpeed`, `ElevGain` and `Unit` - metric by default, imperial with `-Miles`. `-GroupBy` accepts `Year`, `Month`, `Week` (ISO) and `ActivityType`. `-CustomSelection`, `-Filter`, `-Property` and `-SaveCustomSelection` work like for badges; the values are stored per activity type under `GarminConnectApi > CustomSelection > Activity` (fallback `Default`).

### Inspect the latest Garmin activity

```powershell
Get-GarminLastActivity
```

### Analyze a TCX file

```powershell
Invoke-TCXFileAnalysis -tcxFile "$env:USERPROFILE\GCCare\activity.tcx"
```

### Update a TCX file

```powershell
Update-TCXFile -tcxFile "$env:USERPROFILE\GCCare\activity.tcx"
```

## Public Commands

The module currently exports the following commands:

| Command | Alias | Purpose |
| --- | --- | --- |
| `Add-GarminBodyComposition` | `Add-BodyComposition` | Add a single weigh-in with optional body composition values (kg or lbs) to Garmin Connect. |
| `Convert-TanitaExportToFitFile` | None | Convert Tanita CSV exports to Garmin-compatible weight FIT files and optionally upload them. |
| `Get-GarminActivity` | None | Return Garmin Connect activities (default: last 10 runs) with distance, time, pace and elevation in km or miles, optionally grouped by year, month, week or activity type. |
| `Get-GarminBadge` | `Get-GarminBadges` | Return earned, available or non-completed Garmin Connect badges with points and level, optionally grouped by year, month or name, or with a custom selection from `GCCare.json`. |
| `Get-GarminLastActivity` | None | Return the most recent Garmin Connect activity. |
| `Get-GarminToken` | None | Sign in to Garmin Connect and create or refresh the token store. |
| `Get-GarminUser` | None | Return the Garmin Connect user profile and personal settings. |
| `Get-WeeklyBodyMetrics` | None | Aggregate Tanita body-composition data by ISO week and return average values. |
| `Invoke-TCXFileAnalysis` | None | Inspect a TCX file and return lap-by-lap distance, time, pace, elevation, and heart-rate metrics. |
| `Send-FitFileToGarminConnect` | None | Upload local FIT files to Garmin Connect, report the status per file and move uploaded files to `Uploaded`. |
| `Update-TCXFile` | None | Recalculate and rewrite distance/elevation values in a TCX file. |

Use `Get-Help` for detailed command documentation:

```powershell
Get-Help Get-GarminToken -Full
Get-Help Get-GarminUser -Full
Get-Help Get-GarminBadge -Full
Get-Help Get-GarminActivity -Full
Get-Help Get-GarminLastActivity -Full
Get-Help Add-GarminBodyComposition -Full
Get-Help Convert-TanitaExportToFitFile -Full
Get-Help Send-FitFileToGarminConnect -Full
Get-Help Get-WeeklyBodyMetrics -Full
Get-Help Invoke-TCXFileAnalysis -Full
Get-Help Update-TCXFile -Full
```

## Garmin Connect API

All Garmin Connect commands use the internal helper `Invoke-GarminConnectApi`, which calls `https://connectapi.garmin.com` with the stored bearer token. More than 130 known endpoints - activities, sleep, HRV, weight, gear, workouts and more - are documented with PowerShell examples in [`Docs/GarminConnectApi.md`](Docs/GarminConnectApi.md).

To use the helper directly, import the module with private functions exported:

```powershell
$env:GCCare_EXPORT_PRIVATE = 1
Import-Module .\GCCare.psd1 -Force
Invoke-GarminConnectApi -Path '/activitylist-service/activities/search/activities' -Query @{ start = 0; limit = 5 }
```

The Garmin Connect API is not official. Garmin may change endpoints or the sign-in flow at any time.

## Typical Workflows

1. Import the module.
2. Sign in once with `Get-GarminToken`.
3. Convert Tanita exports with `Convert-TanitaExportToFitFile` or inspect weekly averages with `Get-WeeklyBodyMetrics`.
4. Upload the generated FIT files with `Send-FitFileToGarminConnect` (or `Convert-TanitaExportToFitFile -Upload`).
5. Check badges, user profile or activities with `Get-GarminBadge`, `Get-GarminUser`, `Get-GarminActivity` and `Get-GarminLastActivity`.
6. Analyze or update TCX files when you need corrected lap distance or elevation values.

## Logging and Output

Most public functions use the module's common output helpers and support optional logging switches where appropriate.

- Use `-EnableLogging` when available to write detailed execution output to `$env:USERPROFILE\GCCare\Logs\GCCare.log`.
- Review generated FIT files in `$env:USERPROFILE\GCCare\FitFiles`.
- Keep a clean backup of your source CSV, FIT, or TCX files before processing them.

## Recommended Safety Practices

- Use your own Garmin account and valid test data.
- Keep the token file `gctoken.json` private and never commit it to a repository - it grants access to your Garmin account.
- Keep backups of source files before conversion or update operations.
- Test a conversion with `-LastX 1` before uploading many files to Garmin Connect.
- Store all generated data in `$env:USERPROFILE\GCCare` to keep the working directory consistent and easy to back up.

## Contributing

Issues and pull requests are welcome.

If you contribute changes, please include:

- Reproduction steps
- Expected and actual behavior
- Relevant sample files or sanitized screenshots where useful

## Acknowledgments

Thanks to the Garmin Connect and FIT tooling ecosystem, and to the open-source projects that document the Garmin Connect API and the FIT protocol.
