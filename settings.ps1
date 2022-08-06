# This file will deal with all settings for all scripts. 

class Settings : System.Management.Automation.IValidateSetValuesGenerator { 
    [String[]] GetAllSettings() { 
        $Global:SettingsList = @()
        Get-Content -path .\Settings.json | ConvertFrom-Json | Select-Object -ExpandProperty Name | Foreach-Object {
            $Global:SettingsList += $_
        }
        return $Global:SettingsList
    }
}

# class Settings : System.Management.Automation.IValidateSetValuesGenerator { 
#     [String[]] GetAllSettings() { 
#         $Global:SettingsList = @()
#         Get-Content -path .\Settings.json | ConvertFrom-Json | Select-Object -ExpandProperty Name | Foreach-Object {
#             $Global:SettingsList += $_
#         }
#         return $Global:SettingsList
#     }
# }

function Test-SettingsJson {
    if (!(Test-Path Settings.json)) { 
        $DefaultSettings = @()

        $Default = New-Object psobject
        $Default | Add-Member "NoteProperty" -Name "Previous_Connection_Total" -Value "5"
        $DefaultSettings += $Default

        $DefaultSettings | ConvertTo-Json | Out-File Settings.json | Out-Null
    }
}

function Get-Settings { 
    $Settings = Get-Content .\Settings.json -Raw | ConvertFrom-Json

    Write-Host "Settings:"
    Write-Host "PropertyName               | Value"
    $Settings.PSobject.Properties | Foreach-Object { 
        Write-Host "$($_.Name)  | $($_.Value)" 
    } 

    $results = Read-Host "Would you like to update a value?"

    if ($results -notmatch "[y|Y|yes]") { 
        return
    } else { 
        $SettingName = Read-Host "Settings Name: "
        $SettingValue = Read-Host "Setting Value: "
        Update-Settings -SettingName $($SettingName) -SettingValue $($SettingValue) -Settings $($Settings)
    }
}

function Update-Settings {
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet([GetAllSettings], ErrorMessage = "Invalid entry {0} - Please enter a valid entry: {1}")]
        [String]$SettingName,
        [String]$SettingValue,
        [psobject]$Settings
    )

    # This is where setting values can be amended.
    $oldValue = $Settings.$SettingName

    if ($oldValue -match $SettingValue) { 
        Write-Host "No changes made value matches old value"
    } else {
        $Settings.$SettingName = $SettingValue
        $Settings | ConvertTo-Json | Out-File .\Settings.json
    }
}

Test-SettingsJson

return (Get-Content Settings.json | ConvertFrom-Json)



# set a random colour
function Get-Colour { 
    $ColourList = @{
        1 = "DarkBlue"
        2 = "DarkGreen"
        3 = "DarkCyan"
        4 = "DarkRed"
        5 = "DarkMagenta"
        6 = "DarkYellow"
        7 = "Blue"
        8 = "Green"
        9 = "Cyan"
        10 = "Red"
        11 = "Magenta"
        12 = "Yellow"
    }

    $Number = Get-Random -Maximum $ColourList.Count -Minimum 1
    return (($ColourList.GetEnumerator() | Where-Object {$_.Key -eq $Number}).Value)
}