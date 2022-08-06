# This file will deal with all settings for all scripts. 
function Test-SettingsJson {
    if (!(Test-Path Settings.json)) { 
        $DefaultSettings = @()

        $Default = New-Object psobject
        $Default | Add-Member "NoteProperty" -Name "Previous_Connection_Total" -Value "5"
        $Default | Add-Member "NoteProperty" -Name "ColourProfile" -Value "Rainbow"
        $DefaultSettings += $Default

        $DefaultSettings | ConvertTo-Json | Out-File Settings.json | Out-Null
    }
}

function Get-Settings { 
    # $Settings = Get-Content .\Settings.json -Raw | ConvertFrom-Json

    Write-Host "Settings:"
    Write-Host "PropertyName               | Value"
    $ProfileSettings.PSobject.Properties | Foreach-Object { 
        Write-Host "$($_.Name)  | $($_.Value)" 
    }
}

function Update-Settings {
    param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet([Settings], ErrorMessage = "Invalid entry {0} - Please enter a valid entry: {1}")]
        [String]$SettingName,
        [String]$SettingValue
    )

    $ProfileSettings = Get-Content .\Settings.json | ConvertFrom-Json

    # This is where setting values can be amended.
    $oldValue = $ProfileSettings.$SettingName

    if ($oldValue -match $SettingValue) { 
        Write-Host "No changes made value matches old value"
    } else {
        $ProfileSettings.$SettingName = $SettingValue
        $ProfileSettings | ConvertTo-Json | Out-File .\Settings.json
        $Global:ProfileSettings = Get-Content .\Settings.json | ConvertFrom-Json
    }
}

function Get-Colour {
    $ColourList = @{
        1  = "DarkBlue"
        2  = "DarkGreen"
        3  = "DarkCyan"
        4  = "DarkRed"
        5  = "DarkMagenta"
        6  = "DarkYellow"
        7  = "Blue"
        8  = "Green"
        9  = "Cyan"
        10 = "Red"
        11 = "Magenta"
        12 = "Yellow"
    }

    if ("$($ProfileSettings.ColourProfile)" -match "Rainbow") {
        $Number = Get-Random -Maximum $ColourList.Count -Minimum 1
        return (($ColourList.GetEnumerator() | Where-Object {$_.Key -eq $Number}).Value)
    }

    if ($ProfileSettings.ColourProfile -notin $Colourlist.Values) {
        $Number = Get-Random -Maximum $ColourList.Count -Minimum 1
        return (($ColourList.GetEnumerator() | Where-Object {$_.Key -eq $Number}).Value)
    }

    return $ProfileSettings.ColourProfile
}


$Global:ProfileSettings = Get-Content .\Settings.json -Raw | ConvertFrom-Json

Test-SettingsJson

# return (Get-Content Settings.json | ConvertFrom-Json)
return $ProfileSettings