# GCCare (Garmin Connect Care)

![Module Type](https://img.shields.io/badge/type-PowerShell%20Module-orange)
![PowerShellGallery](https://img.shields.io/powershellgallery/v/GCCare)
![PowerShell](https://img.shields.io/badge/PowerShell-7.1%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Maintenance](https://img.shields.io/badge/status-active-brightgreen)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/HerrHozi/GCCare)

```Text
Author:          Holger Zimmermann | zimmermann.holger@live.de
Current Version: 2026.10.1.1358
Last Update:     2026-10-01
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
- Read the Garmin Connect user profile, earned badges with level summary, and the latest activity.
- Convert Tanita CSV exports into Garmin-compatible weight FIT files.
- Upload FIT files to Garmin Connect from a shared public workspace folder.
- Calculate weekly averages from body-composition data.
- Analyze TCX lap metrics such as distance, time, moving time, ascent, descent, pace, and heart rate.
- Update TCX files with recalculated lap distance and elevation values.

By default, GCCare stores generated data and intermediate files under `C:\Users\Public\GCCare`.

## Module Structure

- `Public/`: exported PowerShell commands
- `Private/`: internal PowerShell helper functions, including the Garmin Connect API client (`GarminConnectApi.ps1`) and the FIT encoder (`New-GarminWeightFitFile.ps1`)
- `Docs/`: additional documentation, e.g. the Garmin Connect API reference (`GarminConnectApi.md`)
- `Examples/`: sample FIT, TCX, and CSV files
- `C:\Users\Public\GCCare`: default shared workspace for generated FIT files, logs, and configuration
- `~\.garminconnect\garmin_tokens.json`: default Garmin Connect token store

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

On import, the module creates its working folders under `C:\Users\Public\GCCare`:

| Folder | Purpose |
| --- | --- |
| `C:\Users\Public\GCCare\FitFiles` | Generated FIT files and default upload folder |
| `C:\Users\Public\GCCare\Logs` | Log file `GCCare.log` (with `-EnableLogging`) |
| `C:\Users\Public\GCCare\Config` | Configuration file `GCCare.json` |
| `C:\Users\Public\GCCare\Temp` | Temporary files |
| `C:\Users\Public\GCCare\CleanUp` | Clean-up folder |

## Quick Start

### Sign in to Garmin Connect

```powershell
Get-GarminToken -Test
```

`Get-GarminToken` asks for e-mail, password and - if enabled - the MFA code, and saves the tokens to `~\.garminconnect\garmin_tokens.json`. All Garmin Connect commands use this file and renew the access token automatically. Sign in again only when the refresh token has expired.

To use another token location, pass `-TokenStore` to the commands or set `$env:GARMINTOKENS`.

### Show the Garmin Connect user

```powershell
Get-GarminUser
```

### Show earned badges and level

```powershell
Get-GarminBadges -GroupBy Year | Format-Table
```

### Convert Tanita measurements to FIT files

```powershell
Convert-TanitaExportToFitFile -csvFile 'C:\Users\Public\GCCare\bodydata.csv' -LastX 7
```

Add `-Upload` to upload the created FIT files to Garmin Connect right away.

### Calculate weekly averages from body data

```powershell
Get-WeeklyBodyMetrics -CsvFile 'C:\Users\Public\GCCare\bodydata.csv'
```

### Upload FIT files to Garmin Connect

```powershell
Send-FitFileToGarminConnect -ImportDirectory 'C:\Users\Public\GCCare\FitFiles'
```

### Inspect the latest Garmin activity

```powershell
Get-GarminLastActivity
```

### Analyze a TCX file

```powershell
Invoke-TCXFileAnalysis -tcxFile 'C:\Users\Public\GCCare\activity.tcx'
```

### Update a TCX file

```powershell
Update-TCXFile -tcxFile 'C:\Users\Public\GCCare\activity.tcx'
```

## Public Commands

The module currently exports the following commands:

| Command | Alias | Purpose |
| --- | --- | --- |
| `Convert-TanitaExportToFitFile` | None | Convert Tanita CSV exports to Garmin-compatible weight FIT files and optionally upload them. |
| `Get-GarminBadges` | None | Return earned Garmin Connect badges with points and level, optionally grouped by year, month or name. |
| `Get-GarminLastActivity` | None | Return the most recent Garmin Connect activity. |
| `Get-GarminToken` | None | Sign in to Garmin Connect and create or refresh the token store. |
| `Get-GarminUser` | None | Return the Garmin Connect user profile and personal settings. |
| `Get-WeeklyBodyMetrics` | None | Aggregate Tanita body-composition data by ISO week and return average values. |
| `Invoke-TCXFileAnalysis` | None | Inspect a TCX file and return lap-by-lap distance, time, pace, elevation, and heart-rate metrics. |
| `Send-FitFileToGarminConnect` | None | Upload local FIT files to Garmin Connect and report the status per file. |
| `Update-TCXFile` | None | Recalculate and rewrite distance/elevation values in a TCX file. |

Use `Get-Help` for detailed command documentation:

```powershell
Get-Help Get-GarminToken -Full
Get-Help Get-GarminUser -Full
Get-Help Get-GarminBadges -Full
Get-Help Get-GarminLastActivity -Full
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
5. Check badges, user profile or the latest activity with `Get-GarminBadges`, `Get-GarminUser` and `Get-GarminLastActivity`.
6. Analyze or update TCX files when you need corrected lap distance or elevation values.

## Logging and Output

Most public functions use the module's common output helpers and support optional logging switches where appropriate.

- Use `-EnableLogging` when available to write detailed execution output to `C:\Users\Public\GCCare\Logs\GCCare.log`.
- Review generated FIT files in `C:\Users\Public\GCCare\FitFiles`.
- Keep a clean backup of your source CSV, FIT, or TCX files before processing them.

## Recommended Safety Practices

- Use your own Garmin account and valid test data.
- Keep the token file `garmin_tokens.json` private and never commit it to a repository - it grants access to your Garmin account.
- Keep backups of source files before conversion or update operations.
- Test a conversion with `-LastX 1` before uploading many files to Garmin Connect.
- Store all generated data in `C:\Users\Public\GCCare` to keep the working directory consistent and easy to back up.

## Contributing

Issues and pull requests are welcome.

If you contribute changes, please include:

- Reproduction steps
- Expected and actual behavior
- Relevant sample files or sanitized screenshots where useful

## Acknowledgments

Thanks to the Garmin Connect and FIT tooling ecosystem, and to the open-source projects that document the Garmin Connect API and the FIT protocol.
