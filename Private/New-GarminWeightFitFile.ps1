################################################################################
#####                                                                      #####
#####    Pure PowerShell FIT encoder for Garmin weight scale files         #####
#####    (file_id + weight_scale message)                                  #####
#####                                                                      #####
################################################################################

function Get-FitCrc {
    # FIT CRC-16 (nibble table from the FIT SDK)
    param(
        [Parameter(Mandatory = $true)]
        [byte[]]$Bytes
    )

    $table = [uint16[]](0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
        0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400)

    [uint16]$crc = 0
    foreach ($b in $Bytes) {
        $tmp = $table[$crc -band 0xF]
        $crc = (($crc -shr 4) -band 0x0FFF) -bxor $tmp -bxor $table[$b -band 0xF]
        $tmp = $table[$crc -band 0xF]
        $crc = (($crc -shr 4) -band 0x0FFF) -bxor $tmp -bxor $table[($b -shr 4) -band 0xF]
    }
    return $crc
}

function ConvertTo-FitTimestamp {
    # FIT timestamps are seconds since 1989-12-31 00:00:00 UTC
    param(
        [Parameter(Mandatory = $true)]
        [datetime]$Date
    )

    $fitEpoch = [datetime]::new(1989, 12, 31, 0, 0, 0, [DateTimeKind]::Utc)
    return [uint32][math]::Floor(($Date.ToUniversalTime() - $fitEpoch).TotalSeconds)
}

function Write-FitMessage {
    # Writes a definition record and a data record (local message 0, little endian)
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.BinaryWriter]$Writer,

        [Parameter(Mandatory = $true)]
        [uint16]$GlobalMessageNumber,

        # Each field: @{ Num = <field number>; Type = 'uint8' | 'uint16' | 'uint32' | 'enum'; Value = <raw value> }
        [Parameter(Mandatory = $true)]
        [object[]]$Fields
    )

    $baseTypes = @{
        enum   = @{ Size = 1; Id = 0x00 }
        uint8  = @{ Size = 1; Id = 0x02 }
        uint16 = @{ Size = 2; Id = 0x84 }
        uint32 = @{ Size = 4; Id = 0x86 }
    }

    # Definition record
    $Writer.Write([byte]0x40)
    $Writer.Write([byte]0)
    $Writer.Write([byte]0)
    $Writer.Write([uint16]$GlobalMessageNumber)
    $Writer.Write([byte]$Fields.Count)
    foreach ($field in $Fields) {
        $baseType = $baseTypes[$field.Type]
        $Writer.Write([byte]$field.Num)
        $Writer.Write([byte]$baseType.Size)
        $Writer.Write([byte]$baseType.Id)
    }

    # Data record
    $Writer.Write([byte]0x00)
    foreach ($field in $Fields) {
        switch ($field.Type) {
            { $_ -in 'enum', 'uint8' } { $Writer.Write([byte]$field.Value) }
            'uint16' { $Writer.Write([uint16]$field.Value) }
            'uint32' { $Writer.Write([uint32]$field.Value) }
        }
    }
}

function New-GarminWeightFitFile {
    # Creates a Garmin weight FIT file (file_id + weight_scale message)
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [datetime]$Timestamp,

        [Parameter(Mandatory = $true)]
        [double]$Weight,

        [double]$PercentFat,
        [double]$PercentHydration,
        [double]$BoneMass,
        [double]$MuscleMass,
        [double]$Bmi,
        [int]$VisceralFatRating,
        [int]$MetabolicAge,
        [int]$PhysiqueRating,
        [double]$BasalMet = 2000,
        [double]$ActiveMet = 2000,
        [int]$UserProfileIndex = 0
    )

    # Scaled values are stored as integers (e.g. weight 93.40 kg -> 9340)
    function Get-Scaled([double]$Value, [int]$Scale) {
        [math]::Round($Value * $Scale)
    }

    $fitTime = ConvertTo-FitTimestamp -Date $Timestamp

    $stream = [System.IO.MemoryStream]::new()
    $writer = [System.IO.BinaryWriter]::new($stream)
    try {
        # file_id (global message 0)
        Write-FitMessage -Writer $writer -GlobalMessageNumber 0 -Fields @(
            @{ Num = 0; Type = 'enum'; Value = 9 }          # type = weight
            @{ Num = 1; Type = 'uint16'; Value = 1 }        # manufacturer = garmin
            @{ Num = 4; Type = 'uint32'; Value = $fitTime } # time_created
        )

        # weight_scale (global message 30)
        Write-FitMessage -Writer $writer -GlobalMessageNumber 30 -Fields @(
            @{ Num = 253; Type = 'uint32'; Value = $fitTime }                                # timestamp
            @{ Num = 0; Type = 'uint16'; Value = (Get-Scaled $Weight 100) }                 # weight [kg]
            @{ Num = 1; Type = 'uint16'; Value = (Get-Scaled $PercentFat 100) }             # percent_fat [%]
            @{ Num = 2; Type = 'uint16'; Value = (Get-Scaled $PercentHydration 100) }       # percent_hydration [%]
            @{ Num = 4; Type = 'uint16'; Value = (Get-Scaled $BoneMass 100) }               # bone_mass [kg]
            @{ Num = 5; Type = 'uint16'; Value = (Get-Scaled $MuscleMass 100) }             # muscle_mass [kg]
            @{ Num = 7; Type = 'uint16'; Value = (Get-Scaled $BasalMet 4) }                 # basal_met [kcal/day]
            @{ Num = 8; Type = 'uint8'; Value = $PhysiqueRating }                           # physique_rating
            @{ Num = 9; Type = 'uint16'; Value = (Get-Scaled $ActiveMet 4) }                # active_met [kcal/day]
            @{ Num = 10; Type = 'uint8'; Value = $MetabolicAge }                            # metabolic_age [years]
            @{ Num = 11; Type = 'uint8'; Value = $VisceralFatRating }                       # visceral_fat_rating
            @{ Num = 12; Type = 'uint16'; Value = $UserProfileIndex }                       # user_profile_index
            @{ Num = 13; Type = 'uint16'; Value = (Get-Scaled $Bmi 10) }                    # bmi [kg/m2]
        )
        $writer.Flush()
        $records = $stream.ToArray()
    }
    finally {
        $writer.Dispose()
        $stream.Dispose()
    }

    # 12-byte header: size, protocol 2.3, profile 21.212, data size, ".FIT"
    $header = [System.IO.MemoryStream]::new()
    $headerWriter = [System.IO.BinaryWriter]::new($header)
    $headerWriter.Write([byte]12)
    $headerWriter.Write([byte]0x23)
    $headerWriter.Write([uint16]21212)
    $headerWriter.Write([uint32]$records.Length)
    $headerWriter.Write([Text.Encoding]::ASCII.GetBytes('.FIT'))
    $headerWriter.Flush()
    $content = $header.ToArray() + $records
    $headerWriter.Dispose()
    $header.Dispose()

    $crc = Get-FitCrc -Bytes $content
    $fileBytes = $content + [BitConverter]::GetBytes([uint16]$crc)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    [System.IO.File]::WriteAllBytes($fullPath, $fileBytes)
    return Get-Item -LiteralPath $fullPath
}
