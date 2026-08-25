function Edit-ActivityLapsInGrid {
    param (
        [Parameter(Mandatory = $true)]
        [object[]]$InputLaps,
        [object[]]$LapNodes,
        [int]$NumberOfLaps = 30
    )

    $CurrentFunction = Get-FunctionName
    Write-Log -Message "### Start Function $CurrentFunction ###"
    $StartRunTime = (Get-Date).ToString($Script:DateFormatLog)
    #################### main code | out- host #####################

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing

    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Edit Activity Laps | Option A: Calculate Distance/Ascent from Speed/Incline (Treadmill) | Option B: Use provided Distance/Ascent values (Stairmaster)"
    $form.StartPosition = "CenterScreen"
    $form.Size = New-Object System.Drawing.Size(1100, 700)

    $grid = New-Object System.Windows.Forms.DataGridView
    $grid.Dock = [System.Windows.Forms.DockStyle]::Fill
    $grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
    $grid.AutoGenerateColumns = $false
    $grid.AllowUserToAddRows = $false
    $grid.AllowUserToDeleteRows = $false
    $grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::CellSelect
    $grid.add_DataError({ param($eventSource, $e) $e.ThrowException = $false })

    $dataTable = New-Object System.Data.DataTable
    foreach ($columnName in @("Lap", "TotalTimeSeconds", "Option", "Speed", "Incline", "Distance", "Ascent", "ElevationGain", "Description")) {
        [void]$dataTable.Columns.Add($columnName, [string])
    }

    $counter = 0
    foreach ($lap in $InputLaps) {
        $row = $dataTable.NewRow()
        $row["Lap"] = [string]$lap.Lap
        $lapDurationSeconds = 0.0
        if ($LapNodes -and $counter -lt $LapNodes.Count) {
            $rawTotalTimeSeconds = [string]$LapNodes[$counter].TotalTimeSeconds
            if (-not [double]::TryParse($rawTotalTimeSeconds, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$lapDurationSeconds)) {
                [void][double]::TryParse($rawTotalTimeSeconds, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::CurrentCulture, [ref]$lapDurationSeconds)
            }
        }
        $row["TotalTimeSeconds"] = [TimeSpan]::FromSeconds($lapDurationSeconds).ToString("hh\:mm\:ss")
        $optionValue = ([string]$lap.Option)
        if ($optionValue -notin @("Treadmill", "Stairmaster")) {
            $optionValue = "Stairmaster"
        }
        $row["Option"] = $optionValue
        $row["Description"] = [string]$lap.Description
        $row["Speed"] = [string]$lap.Speed
        $row["Incline"] = [string]$lap.Incline
        $row["Distance"] = [string]$lap.Distance
        $row["Ascent"] = [string]$lap.Ascent
        $row["ElevationGain"] = if ([string]::IsNullOrWhiteSpace([string]$lap.ElevationGain)) { "36.0" } else { [string]$lap.ElevationGain }

        [void]$dataTable.Rows.Add($row)
        $counter++

        If ($counter -ge $NumberOfLaps) {
            break
        }
    }

    $grid.Columns.Clear()

    $lapColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $lapColumn.Name = "Lap"
    $lapColumn.HeaderText = "Lap"
    $lapColumn.DataPropertyName = "Lap"
    [void]$grid.Columns.Add($lapColumn)

    $timeColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $timeColumn.Name = "TotalTimeSeconds"
    $timeColumn.HeaderText = "Lap Time [hh:mm:ss]"
    $timeColumn.DataPropertyName = "TotalTimeSeconds"
    $timeColumn.ReadOnly = $true
    [void]$grid.Columns.Add($timeColumn)

    $descriptionColumn = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
    $descriptionColumn.Name = "Description"
    $descriptionColumn.HeaderText = "Exercise ²"
    $descriptionColumn.DataPropertyName = "Description"
    [void]$descriptionColumn.Items.Add("Warm Up")
    [void]$descriptionColumn.Items.Add("Hike")
    [void]$descriptionColumn.Items.Add("Run")
    [void]$descriptionColumn.Items.Add("Pause")
    [void]$descriptionColumn.Items.Add("Cool Down")
    [void]$grid.Columns.Add($descriptionColumn)

    $optionColumn = New-Object System.Windows.Forms.DataGridViewComboBoxColumn
    $optionColumn.Name = "Option"
    $optionColumn.HeaderText = "Exercise Machine"
    $optionColumn.DataPropertyName = "Option"
    [void]$optionColumn.Items.Add("Treadmill")
    [void]$optionColumn.Items.Add("Stairmaster")
    [void]$grid.Columns.Add($optionColumn)


    

    $speedColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $speedColumn.Name = "Speed"
    $speedColumn.HeaderText = "Speed [km/h]"
    $speedColumn.DataPropertyName = "Speed"
    [void]$grid.Columns.Add($speedColumn)

    $inclineColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $inclineColumn.Name = "Incline"
    $inclineColumn.HeaderText = "Incline [%]"
    $inclineColumn.DataPropertyName = "Incline"
    [void]$grid.Columns.Add($inclineColumn)

    $ascentColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $ascentColumn.Name = "Ascent"
    $ascentColumn.HeaderText = "Ascent [m]"
    $ascentColumn.DataPropertyName = "Ascent"
    [void]$grid.Columns.Add($ascentColumn)

    $elevationGainColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $elevationGainColumn.Name = "ElevationGain"
    $elevationGainColumn.HeaderText = "Elevation Gain [°]"
    $elevationGainColumn.DataPropertyName = "ElevationGain"
    [void]$grid.Columns.Add($elevationGainColumn)

    $distanceColumn = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $distanceColumn.Name = "Distance"
    $distanceColumn.HeaderText = "Distance [m]"
    $distanceColumn.DataPropertyName = "Distance"
    [void]$grid.Columns.Add($distanceColumn)

    $grid.DataSource = $dataTable

    $activeColor = [System.Drawing.Color]::FromArgb(230, 245, 255)
    $inactiveColor = [System.Drawing.Color]::FromArgb(242, 242, 242)

    $convertToDouble = {
        param(
            [string]$Value,
            [double]$Fallback = 0.0
        )

        $parsed = $Fallback
        if ([string]::IsNullOrWhiteSpace($Value)) {
            return $parsed
        }

        if (-not [double]::TryParse($Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$parsed)) {
            [void][double]::TryParse($Value, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::CurrentCulture, [ref]$parsed)
        }

        return $parsed
    }

    $updateDistanceFromAscent = {
        param($row)

        if ($null -eq $row -or $row.IsNewRow) {
            return
        }

        if ([string]$row.Cells["Option"].Value -ne "Stairmaster") {
            return
        }

        $ascentMeters = & $convertToDouble ([string]$row.Cells["Ascent"].Value) 0.0
        $inclineAngle = & $convertToDouble ([string]$row.Cells["ElevationGain"].Value) 72.0

        if ($inclineAngle -le 0 -or $inclineAngle -ge 90) {
            $row.Cells["Distance"].Value = "0"
            return
        }

        $metrics = Get-StairMasterMetrics -InclineAngle $inclineAngle -ElevationGain $ascentMeters
        $row.Cells["Distance"].Value = [string]$metrics.TotalDistance_Meters
    }

    $applyRowStyle = {
        param($row)

        if ($null -eq $row -or $row.IsNewRow) {
            return
        }

        $option = [string]$row.Cells["Option"].Value

        $speedCell = $row.Cells["Speed"]
        $inclineCell = $row.Cells["Incline"]
        $distanceCell = $row.Cells["Distance"]
        $ascentCell = $row.Cells["Ascent"]
        $elevationGainCell = $row.Cells["ElevationGain"]

        if ($option -eq "Treadmill") {
            $speedCell.Style.BackColor = $activeColor
            $inclineCell.Style.BackColor = $activeColor
            $distanceCell.Style.BackColor = $inactiveColor
            $ascentCell.Style.BackColor = $inactiveColor
            $elevationGainCell.Style.BackColor = $inactiveColor

            $speedCell.ReadOnly = $false
            $inclineCell.ReadOnly = $false
            $distanceCell.ReadOnly = $true
            $ascentCell.ReadOnly = $true
            $elevationGainCell.ReadOnly = $true
        }
        else {
            $speedCell.Style.BackColor = $inactiveColor
            $inclineCell.Style.BackColor = $inactiveColor
            $distanceCell.Style.BackColor = $inactiveColor
            $ascentCell.Style.BackColor = $activeColor
            $elevationGainCell.Style.BackColor = $activeColor

            $speedCell.ReadOnly = $true
            $inclineCell.ReadOnly = $true
            $distanceCell.ReadOnly = $true
            $ascentCell.ReadOnly = $false
            $elevationGainCell.ReadOnly = $false
        }
    }

    $grid.add_DataBindingComplete({
            param($gridControl, $e)
            foreach ($row in $gridControl.Rows) {
                & $applyRowStyle $row
            }
        })

    $grid.add_CellValueChanged({
            param($gridControl, $e)
            if ($e.RowIndex -lt 0) {
                return
            }

            $row = $gridControl.Rows[$e.RowIndex]
            $changedColumn = $gridControl.Columns[$e.ColumnIndex].Name

            if ($changedColumn -eq "Option") {
                & $applyRowStyle $row
                return
            }

            if ($changedColumn -in @("Ascent", "ElevationGain")) {
                & $updateDistanceFromAscent $row
            }
        })

    $grid.add_CurrentCellDirtyStateChanged({
            param($gridControl, $e)
            if ($gridControl.IsCurrentCellDirty -and $gridControl.CurrentCell -and $gridControl.CurrentCell.OwningColumn.Name -eq "Option") {
                $gridControl.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
            }
        })

    $buttonPanel = New-Object System.Windows.Forms.Panel
    $buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Bottom
    $buttonPanel.Height = 50

    $okButton = New-Object System.Windows.Forms.Button
    $okButton.Text = "OK"
    $okButton.Width = 120
    $okButton.Height = 30
    $okButton.Left = 10
    $okButton.Top = 10
    $okButton.DialogResult = [System.Windows.Forms.DialogResult]::OK

    $cancelButton = New-Object System.Windows.Forms.Button
    $cancelButton.Text = "Cancel"
    $cancelButton.Width = 120
    $cancelButton.Height = 30
    $cancelButton.Left = 140
    $cancelButton.Top = 10
    $cancelButton.DialogResult = [System.Windows.Forms.DialogResult]::Cancel

    $hintLabel = New-Object System.Windows.Forms.Label
    $hintLabel.Text = "² is for internal reference only"
    $hintLabel.AutoSize = $true
    $hintLabel.Left = 280
    $hintLabel.Top = 16
    $hintLabel.ForeColor = [System.Drawing.Color]::Red

    [void]$buttonPanel.Controls.Add($okButton)
    [void]$buttonPanel.Controls.Add($cancelButton)
    [void]$buttonPanel.Controls.Add($hintLabel)

    [void]$form.Controls.Add($grid)
    [void]$form.Controls.Add($buttonPanel)

    $form.AcceptButton = $okButton
    $form.CancelButton = $cancelButton

    $dialogResult = $form.ShowDialog()
    if ($dialogResult -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }

    $result = @()
    foreach ($row in $dataTable.Rows) {
        $result += [pscustomobject]@{
            Lap              = [string]$row.Lap
            TotalTimeSeconds = [string]$row.TotalTimeSeconds
            Option           = [string]$row.Option
            Speed            = [string]$row.Speed
            Incline          = [string]$row.Incline
            Distance         = [string]$row.Distance
            Ascent           = [string]$row.Ascent
            ElevationGain    = [string]$row.ElevationGain
            Description      = [string]$row.Description
        }
    }

    ######################## main code ############################
    $runtime = Get-RunTime -StartRunTime $StartRunTime
    Write-Log -Message "    Run Time: $runtime [h] ###"
    Write-Log -Message "### End Function $CurrentFunction ###"
    
    return $result
}