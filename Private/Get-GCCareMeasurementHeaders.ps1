function Get-GCCareMeasurementHeaders {

    ################################################################################
    #####                                                                      #####
    #####    Returns the CSV column name for each body measurement value       #####
    #####    (defaults < GCCare.json "MeasurementHeaders" < -Mapping)          #####
    #####                                                                      #####
    ################################################################################

    [CmdletBinding()]
    param(
        [string]$ConfigFile = $Script:ConfigFile,
        [hashtable]$Mapping
    )

    # Logical keys used by Convert-TanitaExportToFitFile; default = Tanita (English) export headers
    $headers = [ordered]@{}
    foreach ($key in 'Date', 'Weight (kg)', 'Body Fat (%)', 'Body Water (%)', 'Muscle Mass (kg)', 'Metab Age', 'Visc Fat', 'Physique Rating', 'BMR (kcal)', 'BMI') {
        $headers[$key] = $key
    }

    # Overrides from the user configuration; keys missing in the file keep their default
    if ($ConfigFile -and (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) {
        try {
            $config = Get-Content -LiteralPath $ConfigFile -Raw | ConvertFrom-Json
            if ($config.PSObject.Properties['MeasurementHeaders']) {
                foreach ($entry in $config.MeasurementHeaders.PSObject.Properties) {
                    if ($headers.Contains($entry.Name) -and -not [string]::IsNullOrWhiteSpace([string]$entry.Value)) {
                        $headers[$entry.Name] = [string]$entry.Value
                    }
                }
                Write-Log -Message "    >> MeasurementHeaders loaded from $ConfigFile"
            }
            else {
                Write-Log -Message "    >> No MeasurementHeaders in $ConfigFile, using defaults"
            }
        }
        catch {
            Invoke-Output -Type Warning -Message "Could not read MeasurementHeaders from '$ConfigFile', using default column names: $($_.Exception.Message)"
        }
    }

    # Overrides passed directly to the function
    if ($Mapping) {
        foreach ($key in $Mapping.Keys) {
            if (-not $headers.Contains($key)) {
                throw "Unknown measurement key '$key'. Valid keys: $($headers.Keys -join ', ')"
            }
            $headers[$key] = [string]$Mapping[$key]
        }
    }

    return $headers
}
