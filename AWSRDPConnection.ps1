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

function Start-AWS {
    [Alias("SAWSs")]
    Param (
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet([AWSUsers], ErrorMessage = "Invalid entry {0} - Please enter a valid entry: {1}")]
        [String]$AWSProfile,
        [Parameter(ParameterSetName = "Search", Position = 1)]
        [String]$SearchTerm
    )
    
    Clear-Host
    Set-TabTitle -TabTitle "Not Connected 🔴"
    Set-AWSENV -AWSProfile $AWSProfile
    Clear-Jobs

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

function Clear-Jobs { 
    $CurrentJobs = (Get-Job | Foreach-Object { $_.id })

    $CurrentJobs | Foreach-Object { 
        Stop-Job -id $_
        Remove-Job -id $_
    }
}

function Start-RDP {
    Param ( 
        [string]$PortToUse
    )

    if ($Host.UI.RawUI.WindowTitle -match '[0-9]') { 
        $PortToUse = $(($Host.UI.RawUI.WindowTitle).Split(': ')[1].split(" ")[0])
    }

    mstsc "G:\Documents\Development\RDP Sessions\AWS\RDP_$($ENV:AWS_Profile).rdp" /v:localhost:$PortToUse
}

function New-RDPConnectionFile { 
    New-Item .\RDPConnections.json
}

function Write-RDPConnectionFile { 
    Param (
        [string]$Port,
        [string]$InstanceId
    )

    if(Test-Path ".\RDPConnections.json") {
        $CurrentConnections = Get-Content .\RDPConnections.json | ConvertFrom-Json

        $Conn = @()
        $Connection = New-Object psobject
        $Connection | Add-Member -MemberType NoteProperty -Name "id" -Value "10"
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
        New-RDPConnectionFile
        Write-RDPConnectionFile -Port $Port -InstanceId $InstanceId
    }
}

function Get-RDPConnectionFile {
    [Alias("PAWS")]
    Param()
    
    if (Test-Path ".\RDPConnections.json") { 
        $Connections = (Get-Content .\RDPConnections.json) | ConvertFrom-Json

        $Connections | ForEach-Object { 
            Write-Host "Id: $($_.id) $($_.Environment) Instance $($_.InstanceID) | $($_.Port) | $($_."Connection Time")" -ForegroundColor (Get-Colour)
        }

        $id = Read-Host "Would you like to connect to a previous connection?"

        if ($id) {

            $results = $Connections[$id]

            Start-PreviousRDPConnection -AWSProfile $($results.Environment)  -SelectedSever $($results.InstanceID)
        }
    } else { 
        Write-Host "There are no previous connections"
    }
}

function Start-PreviousRDPConnection { 
    Param (
        [string]$AWSProfile,
        [string]$SelectedSever
    )
    Set-AWSENV -AWSProfile $($AWSProfile)

    $PortToUse = Get-Port
    Set-TabTitle -TabTitle "$SelectedServer : $PortToUse 🟢"
    Start-Job -ScriptBlock $StartSSM -ArgumentList @($($SelectedServer, $PortToUse)) | Out-Null

    Start-RDP -PortToUse $PortToUse
}

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