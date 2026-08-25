Function Install-GCPython {

    [CmdletBinding()]
    param()

    if (-not (Test-PythonInstalled)) {
        Write-StatusByPrefix '[+] Installing Python 3.13...'
        $pythonInstallerUrl = "https://www.python.org/ftp/python/3.12.6/python-3.12.6-amd64.exe"
        $installerPath = "$env:TEMP\python-installer.exe"

        Write-Host "Downloading Python installer from $pythonInstallerUrl..."
        Invoke-WebRequest -Uri $pythonInstallerUrl -OutFile $installerPath

        Write-Host "Running Python installer..."
        Start-Process -FilePath $installerPath -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1" -Wait

        Write-Host "Cleaning up installer..."
        Remove-Item -LiteralPath $installerPath -Force

        Write-Host "Python installation completed."
    }

}


# https://github.com/Jacopo1891/fit2garmin
# https://github.com/cyberjunky/python-garminconnect
# https://www.fitfiletools.com/debug

# https://pypi.org/project/garminconnect/#files
# https://pypi.org/project/fit-tool/#description



#C:\Users\HoZi\AppData\Local\Programs\Python\Python310\Lib\site-packages\fit_tool\profile\messages
#C:\Users\adsa\AppData\Roaming\Python\Python312\site-packages\fit_tool\profile\messages
# replace .\Lib\site-packages\fit_tool\profile\messages\weight_scale_message.py"

#pip install matplotlib networkx pillow scipy lxml requests
#py -m pip --version
#py -m pip install --upgrade pip
#py -m pip install --upgrade fit-tool
#py -m pip install fit-tool --no-warn-script-location
#py -m pip install garminconnect
#py -m pip install readchar


