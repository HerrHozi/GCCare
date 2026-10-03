<#
.SYNOPSIS
Adds a single weight / body composition measurement to Garmin Connect.

.DESCRIPTION
`Add-GarminBodyComposition` creates a temporary FIT weight scale file in
`$env:USERPROFILE\GCCare\Temp` and uploads it to Garmin Connect (`/upload-service/upload`).
Only the values that are passed are written; all other body composition values stay empty.

The unit of `-Weight`, `-MuscleMass` and `-BoneMass` follows the measurement system of the
Garmin Connect user profile (`metric` = kg, `statute_us` / `statute_uk` = lbs) unless `-Unit`
is given. Values in lbs are converted to kg, the unit of FIT files.

Decimal numbers may be entered with '.' or ',' as decimal separator, e.g. `-BoneMass 3.4`,
`-BoneMass 3,4` or `-BoneMass '3,4'`.

Without `-Bmi`, the BMI is calculated from the weight and the height in the Garmin Connect
user profile.

After the upload, the function reads the weigh-ins of the day
(`/weight-service/weight/dayview/{date}`) and returns the new entry as Garmin Connect stores it.

Returns an object with these properties:
- Date:         Date and time of the measurement.
- Weight:       Weight in the input unit.
- Unit:         'kg' or 'lbs'.
- WeightKg, BodyFat, BodyWater, MuscleMassKg, BoneMassKg, Bmi, MetabolicAge, VisceralFat,
  PhysiqueRating: The values written to the FIT file (empty when not passed).
- Status:       `Uploaded`, `Duplicate`, `Failed` or `WhatIf`.
- Message:      Error or Garmin import message.
- SamplePk:     ID of the Garmin Connect weigh-in (empty when it was not found).
- FitFile:      Path of the FIT file when it was kept (`-KeepFitFile` or `-WhatIf`).

.PARAMETER Weight
Weight in kg or lbs. Mandatory.

.PARAMETER Date
Date and time of the measurement. Default: now.

.PARAMETER BodyFat
Body fat in percent.

.PARAMETER BodyWater
Body water in percent.

.PARAMETER MuscleMass
Muscle mass in kg or lbs.

.PARAMETER BoneMass
Bone mass in kg or lbs.

.PARAMETER Bmi
Body mass index. Default: calculated from the weight and the height in the user profile.

.PARAMETER MetabolicAge
Metabolic age in years.

.PARAMETER VisceralFat
Visceral fat rating (1-59).

.PARAMETER PhysiqueRating
Physique rating (1-9).

.PARAMETER Unit
Unit of `-Weight`, `-MuscleMass` and `-BoneMass`: `kg` or `lbs`. Default: measurement
system of the Garmin Connect user profile.

.PARAMETER KeepFitFile
Keeps the FIT file in `$env:USERPROFILE\GCCare\Temp` after the upload.

.PARAMETER TokenStore
Optional path to the Garmin Connect token store directory or `gctoken.json` file.
Defaults to `$env:GARMINTOKENS`, then `~\.garminconnect`.

.PARAMETER EnableLogging
Optional switch to enable module logging behavior (if supported by module logging helpers).

.OUTPUTS
System.Management.Automation.PSCustomObject

.NOTES
- Requires helper functions in module scope:
  `Get-FunctionName`, `Write-Log`, `Invoke-Output`, `Get-RunTime`, `Invoke-GarminConnectApi`,
  `New-GarminWeightFitFile`, `Send-FitFileToGarminConnect`, `Get-GCCareArgumentText`,
  `ConvertTo-GCCareDecimal`.
- Supports `-WhatIf`: the FIT file is created, but not uploaded.
- Alias: `Add-BodyComposition`.

.EXAMPLE
Add-GarminBodyComposition -Weight 94.5

Adds a weigh-in of 94.5 kg (metric profile) with the current date and time.

.EXAMPLE
Add-GarminBodyComposition -Weight 94,5 -BodyFat 26,7 -BodyWater 54,7 -MuscleMass 66,2 -BoneMass 3,4 -Date '2026-10-03 07:15'

Adds a complete body composition measurement; ',' is accepted as decimal separator.

.EXAMPLE
Add-GarminBodyComposition -Weight 208.3 -Unit lbs -WhatIf

Creates the FIT file for 208.3 lbs (94.48 kg) without uploading it.
#>
function Add-GarminBodyComposition {

    [CmdletBinding(SupportsShouldProcess = $true)]
    [Alias('Add-BodyComposition')]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [object]$Weight,
        [datetime]$Date = (Get-Date),
        [object]$BodyFat,
        [object]$BodyWater,
        [object]$MuscleMass,
        [object]$BoneMass,
        [object]$Bmi,
        [ValidateRange(1, 120)]
        [int]$MetabolicAge,
        [ValidateRange(1, 59)]
        [int]$VisceralFat,
        [ValidateRange(1, 9)]
        [int]$PhysiqueRating,
        [ValidateSet('kg', 'lbs')]
        [string]$Unit,
        [switch]$KeepFitFile,
        [string]$TokenStore,
        [switch]$EnableLogging
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    Invoke-Output -Type Header -Message "Adding body composition to Garmin Connect..."

    if ($Date -gt (Get-Date).AddMinutes(5)) {
        throw "-Date $($Date.ToString('yyyy-MM-dd HH:mm')) is in the future."
    }

    # Decimal values: '.' or ',' as separator (the typed text is used, see Get-GCCareArgumentText)
    $argumentText = Get-GCCareArgumentText -Invocation $MyInvocation
    $values = @{}
    foreach ($name in 'Weight', 'BodyFat', 'BodyWater', 'MuscleMass', 'BoneMass', 'Bmi') {
        if ($PSBoundParameters.ContainsKey($name)) {
            $values[$name] = ConvertTo-GCCareDecimal -Value $PSBoundParameters[$name] -Name $name -ArgumentText $argumentText[$name]
        }
    }

    # Unit and height from the Garmin Connect user profile
    $userData = (Invoke-GarminConnectApi -Path '/userprofile-service/userprofile/user-settings' -TokenStore $TokenStore).userData
    if (-not $Unit) {
        $Unit = if ($userData.measurementSystem -eq 'metric') { 'kg' } else { 'lbs' }
        Write-Log -Message "    >> Measurement system '$($userData.measurementSystem)' -> $Unit"
    }
    $toKg = if ($Unit -eq 'lbs') { 0.45359237 } else { 1.0 }

    $weightKg = [math]::Round($values.Weight * $toKg, 2)
    if ($weightKg -lt 1 -or $weightKg -gt 500) { throw "-Weight $($values.Weight) $Unit is out of range (1-500 kg)." }
    foreach ($name in 'BodyFat', 'BodyWater') {
        if ($values.ContainsKey($name) -and ($values[$name] -lt 0 -or $values[$name] -gt 100)) { throw "-$name $($values[$name]) is out of range (0-100 %)." }
    }
    foreach ($name in 'MuscleMass', 'BoneMass') {
        if ($values.ContainsKey($name)) {
            $values[$name] = [math]::Round($values[$name] * $toKg, 2)
            if ($values[$name] -le 0 -or $values[$name] -ge $weightKg) { throw "-$name is out of range (0 - weight)." }
        }
    }

    if (-not $values.ContainsKey('Bmi') -and $userData.height -gt 0) {
        $heightM = [double]$userData.height / 100.0
        $values.Bmi = [math]::Round($weightKg / ($heightM * $heightM), 1)
        Write-Log -Message "    >> BMI calculated with height $($userData.height) cm: $($values.Bmi)"
    }
    if ($values.ContainsKey('Bmi') -and ($values.Bmi -lt 5 -or $values.Bmi -gt 100)) { throw "-Bmi $($values.Bmi) is out of range (5-100)." }

    # FIT file with the passed values only
    $fitParams = @{
        Path      = Join-Path -Path $Script:GCCareTempDir -ChildPath ("weight_{0:yyyy-MM-dd_HH-mm-ss}.fit" -f $Date)
        Timestamp = $Date
        Weight    = $weightKg
    }
    if ($values.ContainsKey('BodyFat')) { $fitParams.PercentFat = $values.BodyFat }
    if ($values.ContainsKey('BodyWater')) { $fitParams.PercentHydration = $values.BodyWater }
    if ($values.ContainsKey('MuscleMass')) { $fitParams.MuscleMass = $values.MuscleMass }
    if ($values.ContainsKey('BoneMass')) { $fitParams.BoneMass = $values.BoneMass }
    if ($values.ContainsKey('Bmi')) { $fitParams.Bmi = $values.Bmi }
    if ($PSBoundParameters.ContainsKey('MetabolicAge')) { $fitParams.MetabolicAge = $MetabolicAge }
    if ($PSBoundParameters.ContainsKey('VisceralFat')) { $fitParams.VisceralFatRating = $VisceralFat }
    if ($PSBoundParameters.ContainsKey('PhysiqueRating')) { $fitParams.PhysiqueRating = $PhysiqueRating }

    $fitFile = New-GarminWeightFitFile @fitParams
    Write-Log -Message "    >> FIT file created: $($fitFile.FullName)"

    Invoke-Output -Type Bullet -Message "Date:     " -TextMaker $Date.ToString('yyyy-MM-dd HH:mm:ss') -NoExtraLines
    Invoke-Output -Type Bullet -Message "Weight:   " -TextMaker "$($values.Weight) $Unit$(if ($Unit -eq 'lbs') { " ($weightKg kg)" })" -NoExtraLines
    Invoke-Output -Type Bullet -Message "FIT file: " -TextMaker $fitFile.Name

    $status = 'WhatIf'
    $message = ''
    $samplePk = $null
    if ($PSCmdlet.ShouldProcess("Garmin Connect", "Upload weigh-in $($values.Weight) $Unit from $($Date.ToString('yyyy-MM-dd HH:mm:ss'))")) {
        $upload = Send-FitFileToGarminConnect -Path $fitFile.FullName -KeepFiles -TokenStore $TokenStore
        $status = $upload.Status
        $message = $upload.Message

        # Check the stored entry (Garmin may need a moment to process the upload)
        if ($status -ne 'Failed') {
            $timestampMs = [DateTimeOffset]::new($Date.ToUniversalTime()).ToUnixTimeSeconds() * 1000
            for ($attempt = 1; $attempt -le 5 -and -not $samplePk; $attempt++) {
                $dayView = Invoke-GarminConnectApi -Path "/weight-service/weight/dayview/$($Date.ToString('yyyy-MM-dd'))" -Query @{ includeAll = $true } -TokenStore $TokenStore
                $entry = @($dayView.dateWeightList) | Where-Object { [long]$_.timestampGMT -eq $timestampMs } | Select-Object -First 1
                if ($entry) { $samplePk = $entry.samplePk } else { Start-Sleep -Seconds 2 }
            }
            if ($samplePk) {
                Invoke-Output -Type Success -Message "Body composition added to Garmin Connect (samplePk $samplePk)."
            }
            else {
                Invoke-Output -Type Warning -Message "Upload finished ($status), but the weigh-in was not found in Garmin Connect yet."
            }
        }

        if (-not $KeepFitFile) {
            Remove-Item -LiteralPath $fitFile.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    $result = [pscustomobject][ordered]@{
        Date           = $Date
        Weight         = $values.Weight
        Unit           = $Unit
        WeightKg       = $weightKg
        BodyFat        = $values.BodyFat
        BodyWater      = $values.BodyWater
        MuscleMassKg   = $values.MuscleMass
        BoneMassKg     = $values.BoneMass
        Bmi            = $values.Bmi
        MetabolicAge   = if ($PSBoundParameters.ContainsKey('MetabolicAge')) { $MetabolicAge } else { $null }
        VisceralFat    = if ($PSBoundParameters.ContainsKey('VisceralFat')) { $VisceralFat } else { $null }
        PhysiqueRating = if ($PSBoundParameters.ContainsKey('PhysiqueRating')) { $PhysiqueRating } else { $null }
        Status         = $status
        Message        = $message
        SamplePk       = $samplePk
        FitFile        = if (Test-Path -LiteralPath $fitFile.FullName) { $fitFile.FullName } else { $null }
    }

    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"

    return $result
}
