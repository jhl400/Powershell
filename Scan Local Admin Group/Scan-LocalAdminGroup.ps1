#-------------------------------------------------------------------------
<#
.SYNOPSIS
    A script to scan local Administrators group and list all of its members

.DESCRIPTION
    Run Get-LocalGroupMember on remote machine and run Get-CimInstance command when Get-LocalGroupMember fails due to orphan SID

.PARAMETER Name
    A Name parameter - give a group name to scan. Default value is Administrators

.PARAMETER Servers
    A servers parameter - give name of server(s) to scan

.EXAMPLE
    PS C:\> .\Scan-LocalAdminGroup.ps1 -Servers "srv01", "srv02" -Name "Administrators"

#>


[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$Name="Administrators",
    [Parameter(Mandatory=$true)]
    [string[]]$Servers
)

$Global:ErrorActionPreference = 'Stop'
$results = @()

foreach($server in $servers)
{
    $connection = Test-WSMan -ComputerName $server -ErrorAction Continue
    if($connection)
    {
        try
        {
            $admins = invoke-command -ComputerName $server -ScriptBlock {Get-LocalGroupMember -Name "Administrators"}
            foreach($admin in $admins)
            {
                $result = [PSCustomObject]@{
                    ComputerName = $server
                    UserName = $admin.Name
                    Type = $admin.ObjectClass
                    Note = ""
                }
                $results += $result
            }
        }
        catch
        {
            $result = [PSCustomObject]@{
                ComputerName = $server
                UserName = ""
                Type = ""
                Note = "Orphan Account Exists"
            }
            $results += $result
            $admins = Get-CimInstance -ComputerName $server Win32_GroupUser | Where-Object{$_.GroupComponent.Name -eq $Name}
            foreach($admin in $admins)
            {
                $result = [PSCustomObject]@{
                    ComputerName = $server
                    UserName = "$($admin.partcomponent.domain)\$($admin.partcomponent.name)"
                    Type = $admin.partcomponent
                    Note = ""
                }
                $results += $result
            }
        }
        
    }
    else
    {
        Write-Host "$server is offline or WinRM Service is not running"    
    }
}

$results | Export-Csv -Path "d:\temp\LocalAdminScanReport_$(Get-Date -Format yyyy_MM_dd).csv" -NoTypeInformation -Verbose -Force