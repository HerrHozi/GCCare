function Show-PiskelFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PiskelPath,
        [int]$LayerIndex = 0,
        [switch]$AddShadow,
        [int]$ShadowOffsetX = 1,
        [int]$ShadowOffsetY = 1,
        [int[]]$ShadowColor = @(20, 20, 20),
        [switch]$TreatBlackAsForeground
    )


    ################################################################################
    #####                                                                      ##### 
    #####    Description                ######                                 
    #####                                                                      #####
    ################################################################################

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    Add-Type -AssemblyName System.Drawing

    if ($PSVersionTable.PSVersion.Major -le 5 -and $env:OS -eq 'Windows_NT') {
        try {
            Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class VTConsole {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
    public static void EnableVT() {
        IntPtr handle = GetStdHandle(-11);
        uint mode;
        GetConsoleMode(handle, out mode);
        SetConsoleMode(handle, mode | 0x4);
    }
}
"@ -ErrorAction SilentlyContinue
            [VTConsole]::EnableVT()
        }
        catch {
        }
    }

    if ($ShadowColor.Count -ne 3) {
        throw "ShadowColor must contain exactly 3 integers: R,G,B"
    }
    
    $json = Get-Content -LiteralPath $PiskelPath -Raw | ConvertFrom-Json

    if (-not $json.piskel) {
        $JsonData = Get-Content -Path $Script:T0VRIFilePath -Raw | ConvertFrom-Json
        $json = $JsonData.PiskelLogo
    }
    else {
        $json = Get-Content -LiteralPath $PiskelPath -Raw | ConvertFrom-Json
    }

    $width = [int]$json.piskel.width
    $height = [int]$json.piskel.height

    if ($LayerIndex -ge $json.piskel.layers.Count) {
        throw "LayerIndex $LayerIndex out of range. Available layers: $($json.piskel.layers.Count)"
    }

    $layer = $json.piskel.layers[$LayerIndex] | ConvertFrom-Json

    if (-not $layer.chunks -or $layer.chunks.Count -eq 0) {
        throw "Layer does not contain any chunks."
    }

    $chunk = $layer.chunks[0]

    if (-not $chunk.base64PNG) {
        throw "Chunk does not contain base64PNG."
    }

    $base64Png = $chunk.base64PNG -replace '^data:image/png;base64,', ''
    $imageBytes = [Convert]::FromBase64String($base64Png)

    $memoryStream = [System.IO.MemoryStream]::new($imageBytes)
    $bitmap = [System.Drawing.Bitmap]::new($memoryStream)

    try {
        $sourceWidth = $bitmap.Width
        $sourceHeight = $bitmap.Height

        $scaleX = $sourceWidth / $width
        $scaleY = $sourceHeight / $height

        $ESC = [char]27
        $LowerHalfBlock = [char]0x2584

        function Get-TrueColorFg {
            param([int]$R, [int]$G, [int]$B)
            "$ESC[38;2;${R};${G};${B}m"
        }

        function Get-TrueColorBg {
            param([int]$R, [int]$G, [int]$B)
            "$ESC[48;2;${R};${G};${B}m"
        }

        function Get-LogicalPixelColor {
            param(
                [int]$X,
                [int]$Y
            )

            $sampleX = [int][math]::Floor((($X + 0.5) * $scaleX))
            $sampleY = [int][math]::Floor((($Y + 0.5) * $scaleY))

            if ($sampleX -ge $sourceWidth) { $sampleX = $sourceWidth - 1 }
            if ($sampleY -ge $sourceHeight) { $sampleY = $sourceHeight - 1 }

            $bitmap.GetPixel($sampleX, $sampleY)
        }

        function Test-IsBackgroundPixel {
            param(
                [Parameter(Mandatory)]
                [System.Drawing.Color]$Color
            )

            if ($Color.A -lt 32) {
                return $true
            }

            if ($TreatBlackAsForeground) {
                return $false
            }

            return ($Color.R -le 8 -and $Color.G -le 8 -and $Color.B -le 8)
        }

        function New-ShadowColor {
            [System.Drawing.Color]::FromArgb(
                255,
                [int]$ShadowColor[0],
                [int]$ShadowColor[1],
                [int]$ShadowColor[2]
            )
        }

        $pixels = New-Object 'System.Drawing.Color[,]' $width, $height

        for ($y = 0; $y -lt $height; $y++) {
            for ($x = 0; $x -lt $width; $x++) {
                $pixels[$x, $y] = Get-LogicalPixelColor -X $x -Y $y
            }
        }

        if ($AddShadow) {
            $shadowPixels = New-Object 'System.Drawing.Color[,]' $width, $height

            for ($y = 0; $y -lt $height; $y++) {
                for ($x = 0; $x -lt $width; $x++) {
                    $shadowPixels[$x, $y] = $pixels[$x, $y]
                }
            }

            for ($y = 0; $y -lt $height; $y++) {
                for ($x = 0; $x -lt $width; $x++) {
                    $srcColor = $pixels[$x, $y]

                    if (-not (Test-IsBackgroundPixel -Color $srcColor)) {
                        $sx = $x + $ShadowOffsetX
                        $sy = $y + $ShadowOffsetY

                        if ($sx -ge 0 -and $sx -lt $width -and $sy -ge 0 -and $sy -lt $height) {
                            $targetColor = $shadowPixels[$sx, $sy]

                            if (Test-IsBackgroundPixel -Color $targetColor) {
                                $shadowPixels[$sx, $sy] = New-ShadowColor
                            }
                        }
                    }
                }
            }

            for ($y = 0; $y -lt $height; $y++) {
                for ($x = 0; $x -lt $width; $x++) {
                    if (-not (Test-IsBackgroundPixel -Color $pixels[$x, $y])) {
                        $shadowPixels[$x, $y] = $pixels[$x, $y]
                    }
                }
            }

            $pixels = $shadowPixels
        }

        $oddHeight = ($height % 2) -eq 1
        $startY = if ($oddHeight) { -1 } else { 0 }
        $endY = if ($oddHeight) { $height - 1 } else { $height }

        for ($y = $startY; $y -lt $endY; $y += 2) {
            $line = ""

            for ($x = 0; $x -lt $width; $x++) {
                $topY = $y
                $bottomY = $y + 1

                if ($topY -lt 0) {
                    $topPixel = $null
                }
                else {
                    $topPixel = $pixels[$x, $topY]
                }

                $bottomPixel = $pixels[$x, $bottomY]

                $botR = if ($bottomPixel.A -lt 32) { 0 } else { [int]$bottomPixel.R }
                $botG = if ($bottomPixel.A -lt 32) { 0 } else { [int]$bottomPixel.G }
                $botB = if ($bottomPixel.A -lt 32) { 0 } else { [int]$bottomPixel.B }

                if ($null -eq $topPixel) {
                    $fg = Get-TrueColorFg -R $botR -G $botG -B $botB
                    $line += "${fg}${LowerHalfBlock}"
                }
                else {
                    $topR = if ($topPixel.A -lt 32) { 0 } else { [int]$topPixel.R }
                    $topG = if ($topPixel.A -lt 32) { 0 } else { [int]$topPixel.G }
                    $topB = if ($topPixel.A -lt 32) { 0 } else { [int]$topPixel.B }

                    $bg = Get-TrueColorBg -R $topR -G $topG -B $topB
                    $fg = Get-TrueColorFg -R $botR -G $botG -B $botB
                    $line += "${bg}${fg}${LowerHalfBlock}"
                }
            }

            $line += "$ESC[0m"
            Write-Host $line
        }

        Write-Host ""
    }
    finally {
        $bitmap.Dispose()
        $memoryStream.Dispose()
    }
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    #Add-SAFunctionRunTime -Function $CurrentFunction -Runtime $runtime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"
}



