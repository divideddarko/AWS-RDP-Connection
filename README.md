# Windows AWS RDP Connections

## Setup

You will need to create an RDP connection, ensure to name it RDP with the name of your AWS_Profile and save it locally. 

Look for the line: 

```
mstsc "G:\Documents\Development\RDP Sessions\AWS\RDP_$($ENV:AWS_Profile).rdp" /v:localhost:$PortToUse
```

Replace it with your save location: 

```
mstsc "C:\SavedLocation\RDP_$($ENV:AWS_Profile).rdp" /v:localhost:$PortToUse
```

## How to
PowerShell:
<small>Navigate to the save location of your script and import the tooling</small>
```
. .\AWSRDPConnection.ps1
```


## Commands

**Start-AWS || SAWS** 
- The full function name is **Start-AWS** but can be used by its alias **SAWS**

**SAWS -AWSProfile ProfileName -SearchTerm SERVERName**

| Command | Help | 
| - | - |
| AWSProfile | This is your AWS Profile Name |
| SearchTerm | A search input for the server you're after. <br />  - Can be left blank for all servers. <br /> - Can be a partial Name to wildcard the server you're after. | 

## Results
When you've ran the search you'd expect the following results.

## Login
Type in the associated server number ID and it will start to launch into your server instance.