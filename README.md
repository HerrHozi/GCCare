# GCCare (Garmin Connect Care)

![Module Type](https://img.shields.io/badge/type-PowerShell%20Module-orange)
![PowerShellGallery](https://img.shields.io/powershellgallery/v/GCCare)
![PowerShell](https://img.shields.io/badge/PowerShell-7.1%2B-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Maintenance](https://img.shields.io/badge/status-active-brightgreen)
[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/HerrHozi/GCCare)

```Text
Author:          Holger Zimmermann | zimmermann.holger@live.de
Current Version: 2026.8.25.777
Last Update:     2026-08-25
```

GCCare is a PowerShell module for Garmin Connect workflows, Tanita body-composition exports, and FIT/TCX file handling. It combines PowerShell command wrappers with bundled Python helpers to authenticate to Garmin Connect, upload FIT files, convert body-data CSV exports, calculate weekly averages, inspect the latest activity, analyze TCX files, and adjust workout files.

## Project Information

- Author: Holger Zimmermann
- Project: <https://github.com/HerrHozi/GCCare>
- Blog: <https://herrhozi.com>
- License: MIT

## What GCCare Does

GCCare currently provides the following capabilities:

- Start or restore a Garmin Connect session from PowerShell.
- Use the `Connect-GC` alias for the standard Garmin session helper.
- Upload FIT files to Garmin Connect from a shared public workspace folder.
- Convert Tanita CSV exports into Garmin-compatible FIT files.
- Calculate weekly averages from body-composition data.
- Query the last Garmin activity for the active session.
- Analyze TCX lap metrics such as distance, time, moving time, ascent, descent, pace, and heart rate.
- Update TCX files with recalculated lap distance and elevation values.
- Install Python when it is missing on the machine.

By default, GCCare stores generated data and intermediate files under `C:\Users\Public\GCCare`.

## Module Structure

- `Public/`: exported PowerShell entry points
- `Corefunctions/`: Python helpers and standalone scripts used by the PowerShell wrappers
- `Private/`: internal PowerShell helper functions
- `Examples/`: sample FIT, TCX, and CSV files
- `Corefunctions/test_data/`: small test data used during development
- `C:\Users\Public\GCCare`: default shared workspace for generated FIT files, exported data, and session-related output

## Requirements

### Platform

- Windows
- PowerShell 7.1 or later
- Python available through `py.exe` or `python.exe`

### Python Dependencies

The Python-based workflows typically rely on the following packages:

- `garminconnect`
- `fit-tool`
- `curl_cffi`

Some scripts may also depend on `readchar` depending on the selected workflow and Python environment.

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

### Default data folder

All generated data and working files are expected to be stored under the shared public folder:

```powershell
$env:GCCARE_DATA_PATH = 'C:\Users\Public\GCCare'
```

If the folder does not exist yet, create it first:

```powershell
New-Item -ItemType Directory -Path 'C:\Users\Public\GCCare' -Force | Out-Null
```

### Optional Python setup

If Python is not available on the machine, use:

```powershell
Install-GCPython
```

## Quick Start

### Authenticate to Garmin Connect

```powershell
Connect-GC
```

### Start a session with explicit credentials

```powershell
$cred = Get-Credential
New-GarminConnectSession -Email $cred.UserName -SecurePassword $cred.Password
```

### Convert Tanita measurements to FIT files

```powershell
$fitFolder = 'C:\Users\Public\GCCare\Fit'
Convert-TanitaExportToFitFile -csvFile 'C:\Users\Public\GCCare\bodydata.csv' -outputDirectory $fitFolder
```

### Calculate weekly averages from body data

```powershell
Get-WeeklyBodyMetrics -CsvFile 'C:\Users\Public\GCCare\bodydata.csv'
```

### Upload FIT files to Garmin Connect

```powershell
Send-FitFileToGarminConnect -ImportDirectory 'C:\Users\Public\GCCare\Fit'
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
| `Convert-TanitaExportToFitFile` | None | Convert Tanita CSV exports to Garmin-compatible FIT files. |
| `Get-GarminLastActivity` | None | Query the most recent data from the active Garmin Connect session. |
| `Get-WeeklyBodyMetrics` | None | Aggregate Tanita body-composition data by ISO week and return average values. |
| `Install-GCPython` | None | Install Python when it is missing from the machine. |
| `Invoke-TCXFileAnalysis` | None | Inspect a TCX file and return lap-by-lap distance, time, pace, elevation, and heart-rate metrics. |
| `New-GarminConnectSession` | `Connect-GC` | Start or restore a Garmin Connect session using the bundled Python helper. |
| `Send-FitFileToGarminConnect` | None | Upload local FIT files to Garmin Connect. |
| `Update-TCXFile` | None | Recalculate and rewrite distance/elevation values in a TCX file. |

Use `Get-Help` for detailed command documentation:

```powershell
Get-Help New-GarminConnectSession -Full
Get-Help Convert-TanitaExportToFitFile -Full
Get-Help Get-WeeklyBodyMetrics -Full
Get-Help Invoke-TCXFileAnalysis -Full
Get-Help Send-FitFileToGarminConnect -Full
Get-Help Update-TCXFile -Full
Get-Help Get-GarminLastActivity -Full
```

## Typical Workflows

1. Import the module.
2. Authenticate with Garmin Connect using `Connect-GC` or `New-GarminConnectSession`.
3. Convert Tanita exports or inspect weekly averages from your CSV source files.
4. Upload generated FIT files to Garmin Connect.
5. Analyze or update TCX files when you need corrected lap distance or elevation values.

## Logging and Output

Most public functions use the module’s common output helpers and support optional logging switches where appropriate.

- Use `-EnableLogging` when available to capture more detailed execution output.
- Review generated FIT and TCX files in `C:\Users\Public\GCCare` or subfolders such as `Fit`.
- Keep a clean backup of your source CSV, FIT, or TCX files before processing them.

## Recommended Safety Practices

- Use your own Garmin account and valid test data.
- Keep backups of source files before conversion or update operations.
- Validate the output of the Python helpers before uploading anything important.
- Prefer a dedicated test machine or VM when experimenting with new workflows.
- Store all generated data in `C:\Users\Public\GCCare` to keep the working directory consistent and easy to back up.

## Contributing

Issues and pull requests are welcome.

If you contribute changes, please include:

- Reproduction steps
- Expected and actual behavior
- Relevant sample files or sanitized screenshots where useful

## Acknowledgments

Thanks to the Garmin Connect and FIT tooling ecosystem, and to the open-source projects that make these workflows easier to automate from PowerShell.
