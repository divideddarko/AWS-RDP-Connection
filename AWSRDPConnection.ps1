<#
.SYNOPSIS
Adds a file name extension to a supplied name.

.DESCRIPTION
This is a PowerShell script to allow multiple RDP sessions to be started within AWS.

.EXAMPLE
PS> SAWS 

.LINK
http://www.NerdRays.com

Scott Barton 25/3/2022
#>


class AWSUsers : System.Management.Automation.IValidateSetValuesGenerator {
    [String[]] GetValidValues() {
        $Global:AWSUserList = @()
        Get-Content -path $ENV:USERPROFILE\.aws\credentials | Foreach-Object {
            if ($_ -match '[[].+]') {
                $Global:AWSUserList += $(($_ -replace "\[" , "" -replace "\]", "").Trim())
            }
        }
        return $Global:AWSUserList
    }
}

class Settings : System.Management.Automation.IValidateSetValuesGenerator {
    [String[]] GetValidValues() {
        $Global:SettingsList = @()
        Get-Content .\Settings.json | ConvertFrom-Json | Foreach-Object {
            $Global:SettingsList += $_.PSobject.Properties.Name
        }
        return $Global:SettingsList
    }
}

# $Global:ProfileSettings = Import-Module .\Settings.psm1
Import-Module .\Settings.psm1 -Force

function Update-PAWS {
    [cmdletbinding(SupportsShouldProcess)]
    param()

    if (Test-Path .\RDPConnections.json) {
        $CurrentConnections = Get-Content .\RDPConnections.json

        if ($CurrentConnections -match "null") {
            $id = 1
        } elseif ($CurrentConnections.Count -ge ($Settings.Previous_Connection_Total)) {

            if($CurrentConnections.Count -gt $Settings.Previous_Connection_Total) {
                $CurrentConnections | ForEach-Object {
                    if ($_.id -le ($CurrentConnections.Count - $Settings.Previous_Connection_Total)) {
                        $_.id = "0"
                    }
                }
            }

            $i = 1
            $CurrentConnections += $CurrentConnections | ForEach-Object {
                if ($_.id -ne "0") {
                    $_.id = $i
                    $i++
                }
            }

            $CurrentConnections = $CurrentConnections | Where-Object {($_.id -ne "0")}
            $id = ($CurrentConnections.Count + 1)
            $CurrentConnections | ConvertTo-Json | Out-File .\RDPConnections.json

        } else {
            $id = ($CurrentConnections.Count + 1)
        }
    }

    return $id
}

function Start-AWS {
    [Alias("SAWSs")]
    Param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet([AWSUsers], ErrorMessage = "Invalid entry {0} - Please enter a valid entry: {1}")]
        [String]$AWSProfile,
        [Parameter(ParameterSetName = "Search", Position = 1)]
        [String]$SearchTerm
    )
    Update-PAWS   
    Clear-Host
    Set-TabTitle -TabTitle "Not Connected 🔴"
    Set-AWSENV -AWSProfile $AWSProfile
    Clear-Job

    $Result = Read-AWSInstall
    
    if ($Result -like "* installed *") {
        if ($PSCmdlet.ParameterSetName -eq "search") {
            Read-AWSSelect -Search $SearchTerm
        } else { 
            Read-AWSSelect
        }
    }
}

function Set-AWSENV { 
    Param (
        [Parameter(Mandatory)]
        [ValidateSet([AWSUsers], ErrorMessage = "Invalid entry {0} - Please enter a valid entry: {1}")]
        [String]$AWSProfile
    )

    if ($ENV:AWS_Profile -ne $AWSProfile) { 
        $ENV:AWS_Profile = $($AWSProfile)
    }
}

function Read-AWSInstall { 
    $Result = & 'C:\Program Files\Amazon\SessionManagerPlugin\bin\session-manager-plugin.exe'
    return $Result
}

function Set-TabTitle { 
    Param (
        [string]$TabTitle
    )
    $Host.UI.RawUI.WindowTitle = $TabTitle
}

$StartSSM = {
    Param (                      
        [Parameter(Mandatory=$true)] 
        [String]$target,
        [String]$PortToUse
    )
    aws ssm start-session --target $target --document-name AWS-StartPortForwardingSession --parameters portNumber=3389,localPortNumber=$($PortToUse) --profile $($ENV:AWS_Profile)
}

$GetAWSInstance = {
    Param (
        [string]$Search
    )
    $AWSInstances = (aws ec2 describe-instances --region eu-west-2 --filters "Name=tag:Name,Values=*$($Search)*"| ConvertFrom-Json).Reservations
    return $AWSInstances
}

function Read-AWSSelect { 
    Param (
        [string]$Search
    )
    
    Write-host "Retreiving AWS instances."
    Start-Job -ScriptBlock $GetAWSInstance -Name GetAWSInstance -ArgumentList @($Search) | Out-Null

    $i = 0
    Do {
        Write-host $("`r").PadRight($i, '.') -NoNewLine
        Start-Sleep -Milliseconds 250
        $i++
    } while ((Get-Job -State Running -Newest 1).State -eq "Running")

    Show-AWSInstances
}

function Show-AWSInstances {
    $AWSInstances = Receive-Job -Name GetAWSInstance
    
    $Servers = @()

    $AWSInstances | Select-Object -ExpandProperty Instances | Foreach-Object {
        $ServerDetails = New-Object psobject
        $ServerDetails | Add-Member "NoteProperty" -Name "InstanceId" -Value $_.InstanceId
        $ServerDetails | Add-Member "NoteProperty" -Name "ServerName" -Value ($_ | Select-Object -ExpandProperty Tags | Where-Object {$_.Key -eq "Name"} | Select-Object -ExpandProperty Value)
        $ServerDetails | Add-Member "NoteProperty" -Name "ServerState" -Value ($_ | Select-Object -ExpandProperty State | Select-Object -ExpandProperty Name)
        $Servers += $ServerDetails
    }

    $AWSENV = $(Write-Host "`nSetup connection to $($ENV:AWS_Profile) select an instance?" -ForeGroundColor Green
        Write-host "ID  | InstanceID `t`t | Server State | Server Name"
        Write-Host "".PadRight((("ID  | InstanceID               | Server State | Server Name      ").Length), '‾')

        $i = 0
        $Servers | Sort-object ServerName | Foreach-Object {
        
            $Iid = $_.InstanceId
            $SN = $_.ServerName
            $SS = $_.ServerState

            if ($SS -eq "running") { 
                $SS = "$($SS) 🟢"
            } else { 
                $SS = "$($SS) 🔴"
            }

            if ($i -lt 10) { 
                $Iid = " $($Iid)"
            }

            Write-Host "$($i)    $($Iid) `t   $($SS)     $($SN)" -ForegroundColor (Get-Colour)
            $i++
        }
        Write-host "Selection ID: " -NoNewLine
    Read-Host)

    if ($AWSENV -match "[0-9]") {
        $PortToUse = Get-Port
        $SelectedServer = $(($Servers | Sort-Object ServerName))[$AWSENV].InstanceID
        Write-RDPConnectionFile -Port $PortToUse -InstanceId $SelectedServer
        Set-TabTitle -TabTitle "$SelectedServer : $PortToUse 🟢"
        Start-Job -ScriptBlock $StartSSM -ArgumentList @($($SelectedServer, $PortToUse)) | Out-Null

        Start-RDP -PortToUse $PortToUse
    } else { 
        Read-AWSSelect
    }
}

function Get-Port {
    $PortToUse = 4460 .. 4480 | Get-Random

    $UsedPorts = Get-NetTCPConnection | Where-Object {$_.LocalPort -Match '^44..$'} | Select-Object LocalPort

    if ($PortToUse -in $UsedPorts) { 
        Get-Port
    }

    return $PortToUse
}

function Clear-Job {
<#
.DESCRIPTION
    Stop and remove all current running PowerShell Jobs

.EXAMPLE
    Clear-Job

.NOTES
    Author:  Scott Barton
    Website: http://Nerdrays.com
#>
    Begin {
        Write-Verbose "Removing all PowerShell Jobs" -Verbose
    }

    Process {
        $CurrentJobs = (Get-Job | Select-Object Id, Name)

        $CurrentJobs | Foreach-Object {
            Write-Information "Removing job $($_.Name)" -Verbose

            try {
                Stop-Job -Id $_.Id -ErrorAction Stop
            } catch {
                Write-Warning "Failed to stop $($_.Name) $($_.Exception.Message)" -Verbose
            }

            try {
                Remove-Job -Id $_.Id -ErrorAction Stop
            } catch { 
                Write-Warning "Failed to remove $($_.Name) $($_.Exception.Message)" -Verbose
            }
        }
    }
}

function Start-RDP {
<#
.DESCRIPTION
    Starts and RDP Conncetion with a specified port.

.PARAMETER PortToUse
    The number of the Port that's going to be used for the RDP Connection

.EXAMPLE
    Start-RDP -PortToUse 1234

.INPUTS
    int32

.NOTES
    Author:  Scott Barton
    Website: http://Nerdrays.com
#>
    [CmdletBinding(SupportsShouldProcess)]
    Param (
        [Parameter(Mandatory = $true, Position = 0, HelpMessage = "The Port to connect with")]
        [ValidatePattern("[0-9]{4}")]
        [int32]$PortToUse
    )

    Begin {
        Write-Output "Starting RDP Session"
    }

    Process {
        if ($Host.UI.RawUI.WindowTitle -match '[0-9]') {
            $PortToUse = $(($Host.UI.RawUI.WindowTitle).Split(': ')[1].split(" ")[0])
        }
    }

    End {
        if ($PSCmdlet.ShouldProcess($PortToUse)) { 
            mstsc "G:\Documents\Development\RDP Sessions\AWS\RDP_$($ENV:AWS_Profile).rdp" /v:localhost:$PortToUse
        }
        Write-Output "Connection started with Port: $($PortToUse)"
    }
}

function New-File {
<#
.DESCRIPTION
    Create a specified file

.PARAMETER FileName
    Give the required name of the file

.PARAMETER Path
    Give the name of the path

.EXAMPLE
    New-File -Path C:\users\users\desktop -Name NewFile.txt

.INPUTS
    String

.NOTES
    Author:  Scott Barton
    Website: http://Nerdrays.com
#>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false, Position = 0, HelpMessage = "Path to file destination")]
        [string]$Path,
        [Parameter(Mandatory = $true, Position = 1, HelpMessage = "Name of the file")]
        [ValidatePattern("[a-zA-Z0-9].+[.](json|csv)",ErrorMessage="Value {0} is an invalid file name")]
        [String]$FileName
    )

    Begin {
        Write-Verbose " Creating a new file `nPATH: `t  $($Path) `nNAME: `t  $($FileName)" -Verbose

        if ($Path.Substring($Path.Length -1) -match '\\') {
            $Path = $Path.SubString(0, $Path.Length -1)
        }
    }

    Process {
        $results = Test-Path -Path "$Path\$FileName"

        if ($results -eq $false) {
            try {
                New-Item -ItemType File -Path $Path -Name $FileName -ErrorAction Stop -OutVariable FileStatus | Out-Null
            } catch {
                Write-Warning " Failed to create file `nPATH: `t  $($Path) `nNAME: `t  $($FileName)`nERROR:    $($_.Exception.Message)" -Verbose
            }
        }
    }

    End {
        if ($FileStatus) {
            Write-Verbose " Creating file was SUCCESSFUL" -Verbose
        } else {
            Write-Error "Creating file '$Path\$FileName' failed"
        }
    }
}

function Write-RDPConnectionFile {
    Param (
        [string]$Port,
        [string]$InstanceId
    )

    if(Test-Path ".\RDPConnections.json") {
        $id = Update-PAWS

        $CurrentConnections = Get-Content .\RDPConnections.json | ConvertFrom-Json

        $Conn = @()
        $Connection = New-Object psobject
        $Connection | Add-Member -MemberType NoteProperty -Name "id" -Value "$($id)"
        $Connection | Add-Member -MemberType NoteProperty -Name "Environment" -Value $($ENV:AWS_Profile)
        $Connection | Add-Member -MemberType NoteProperty -Name "InstanceID" -Value "$($InstanceID)"
        $Connection | Add-Member -MemberType NoteProperty -Name "Port" -Value "$($Port)"
        $Connection | Add-Member -MemberType NoteProperty -Name "Connection Time" -Value "$(Get-Date -format "dd/MM/yyyy HH:mm:ss")"
        $Conn += $Connection

        $CombineLists = @()
        $CombineLists += $CurrentConnections
        $CombineLists += $Conn
        $CombineLists | ConvertTo-Json | Out-File .\RDPConnections.json

    } else {
        New-File
        Write-RDPConnectionFile -Port $Port -InstanceId $InstanceId
    }
}

function Get-RDPConnectionFile {
    [Alias("PAWS")]
    Param()
    
    if (Test-Path ".\RDPConnections.json") { 
        Update-PAWS
        $Connections = (Get-Content .\RDPConnections.json) | ConvertFrom-Json

        Write-host "ID| InstanceID `t`t | Port | Connection Date"
        Write-Host "".PadRight((("ID  | InstanceID               | Port | Connection Date      ").Length), '‾')

        $Connections | ForEach-Object {
            Write-Host "$($_.id)   $($_.InstanceId)    $($_.Port)   $($_."Connection Time")" -ForegroundColor (Get-Colour)
        }

        $id = Read-Host "Would you like to connect to a previous connection?"

        if ($id) {
            $results = $Connections[$id - 1]
            Start-PreviousRDPConnection -AWSProfile $($results.Environment) -SelectedServer $($results.InstanceId)
        }
    } else { 
        Write-Host "There are no previous connections"
    }
}

function Start-PreviousRDPConnection { 
    Param (
        [string]$AWSProfile,
        [string]$SelectedServer
    )

    Write-Host "Attempting to start $($AWSProfile) $($SelectedServer)"

    Set-AWSENV -AWSProfile $($AWSProfile)

    $PortToUse = Get-Port
    Set-TabTitle -TabTitle "$SelectedServer : $PortToUse 🟢"
    Write-RDPConnectionFile -Port $PortToUse -InstanceId $SelectedServer
    Start-Job -ScriptBlock $StartSSM -ArgumentList @($($SelectedServer, $PortToUse)) | Out-Null

    Start-RDP -PortToUse $PortToUse
}