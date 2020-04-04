#-------------------------------------------------------------------------
# <copyright file="Run-WindowsUpdate.ps1" company="Microsoft">
#    Copyright (c) Microsoft Corporation.  All rights reserved.
# </copyright>
#-------------------------------------------------------------------------

<#
.SYNOPSIS
    A script for doing monthly patching on all servers owned by CE-Intune listed in the INTUNE-Teams OU.
    A server list can be provided for servers that need to be patched.

.DESCRIPTION
    A Run-WindowsUpdate.ps1 script used to check a resources status and run Run-WindowsUpdate if its not in use.

.PARAMETER ComputerName
    A ComputerName parameter - Provide computer name(s) that need to be patched.

.EXAMPLE
    PS C:\>$servers = Get-Content -Path E:\serverlist.txt
    PS C:\>.\Run-WindowsUpdate.ps1 -ComputerName $servers  -verbose -UpdateCategory Critical, Important

    Providing computer names to the script

.EXAMPLE
    PS C:\>.\Run-WindowsUpdate.ps1

    Run script without providing computer name which will get list from Intune-Teams OU

.NOTES
    Requirement)
        1. PSWindowsupdate Module from PSGallery on target computer
        2. Powershell Version 3.0 or higher (Version 5.1 is recommended)

    This script will scan all resources listed.
    The user will select options on how this script will run.
    1) Reboot servers (No Windows update will be applied)
    2) Update servers prior to patch day (No rebooting servers)
    3) Patch day update (Servers will be rebooted)
    4) Scan servers
    5) Exit
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingWriteHost", "", Justification="Write-Host is fine for our purpose and we mostly use PS 5.0+")]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "", Justification="We are not trying to change system state")]
[CmdletBinding()]
param(
    # Path to text file with server list
    [Parameter(HelpMessage="Please enter server name")]
    [string[]]
    $ComputerName = (Get-Content -Path D:\WorkingScripts\MonthlyPatch\serverlist.txt), #(Get-ADComputer -filter * -SearchBase 'OU=Intune-Team,OU=Resources,DC=Redmond,DC=Corp,DC=Microsoft,DC=Com' -Server CO1-RED-DC-33 | Select-Object -ExpandProperty name),
    [Parameter(HelpMessage="Please enter severity")]
    [ValidateSet('Critical', 'Important', 'Moderate', 'Low', 'Unspecified')]
    [string[]]
    $UpdateCategory = ('Critical', 'Important')
)

$Global:ErrorActionPreference = 'Stop'
$listOfServersToReboot = "C:\PatchLogs\ServersToBeRebooted.txt"
$listOfServersReadyToPatch = "C:\PatchLogs\ServerReadyToBePatched.txt"
$offlineServerList = "C:\PatchLogs\OffLineServers.txt"
$script:passwordFile = "c:\temp\password.txt"
$script:taskPath = "\Maintenance\"
$script:taskName = "PSWindowsUpdate"
$script:updateProcess = "TiWorker"
$reboot = $null
$patch = $null
$message = "What would like to do?
1) Reboot servers (No Windows update will be applied)
2) Update servers prior to patch day (No rebooting servers)
3) Patch day update (Servers will be rebooted)
4) Scan servers
5) Exit

Please Enter Your Selection: "

function Test-ComputerPort
{
    [CmdletBinding()]
    Param(
        [string] $server,
        [int[]] $ports = 135,
        [int] $timeOut = 1000
    )

    foreach ($port in $ports)
    {
        #Write-Host "Test-Port - $Server`:$Port Start"
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $iar = $TcpClient.BeginConnect($server, $port, $null, $null)
        # Set the Wait time
        $wait = $iar.AsyncWaitHandle.WaitOne($timeOut, $false)
        # Check to see if the connection is done
        if (-not $Wait)
        {
            # Close the connection and report TimeOut
            $tcpClient.Close()
            Write-Host ("Test-Port - {0}:{1} Connection TimeOut" -f $server,$port)
            return $false
        }
        else
        {
            # Close the connection and report the error if there is one
            $error.Clear()
            try
            {
                $tcpClient.EndConnect($iar) | Out-Null
            }
            catch
            {
                Write-Host ("Test-Port - {0}:{1} Error: $($error[0])" -f $server, $port)
                $failed = $true
            }
            $tcpClient.Close()
        }
        
        
        
        if ($failed) 
            { 
                break 
            }
    }
	
    if ($failed)
	{
        return $false # Failed on all or just one of tested ports
    }
	else
	{
        return $true # Established
    }

}

# Check-Dependency checks target computer for Powershell version 5.0 or higher and installation of PSWindowsupdate module
function Check-Dependency
{
    param (
        [Parameter(Mandatory = $true)]
        [string[]]
        $servers
    )

    $moduleName = "PSWindowsUpdate"

    foreach ($server in $servers)
    {
        Write-Host ("Querying PSWindowsUpdate installation status for {0}" -f $server)
        $module = Invoke-Command -ComputerName $server -ScriptBlock { get-module -name $args[0] -ListAvailable } -ArgumentList $moduleName
        Write-Host ("Querying Powershell Version for {0}" -f $server)
        $PSVersion = Invoke-Command -ComputerName $server -ScriptBlock { $PSVersionTable.PSVersion }

        if ($null -eq $module)
        {
            Write-Host "$server doesn't have $moduleName installed" -ForegroundColor Red
            Write-Host "$server has powershell version $($PSVersion.Major).$($PSVersion.Minor)" -ForegroundColor Red
        }
    }

}
# Check-PendingReboot scans target computers for pending reboot flags in registry
function Check-PendingReboot
{
    param (
        [Parameter(Mandatory = $true)]
        [string[]]
        $serversToCheck
    )

    [System.Collections.ArrayList]$serversToBeRebooted = $serversToCheck
    [System.Collections.ArrayList]$serverReadyToBePatched = $serversToCheck
    [string[]]$offlineServers = @()

    foreach ($server in $serversToCheck)
    {
        Write-Verbose "Scanning $server"
        $isOnline = Test-Connection -ComputerName $server -Count 1 -Quiet
        if ($isOnline.Equals($true))
        {
            Write-Verbose "Testing Port on $server"
            if (Test-ComputerPort -Server $server -Ports 5985)
            {
                $CBS = 'hklm:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending'
                $WU =  'hklm:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'

                try
                {
                    Write-Verbose "Scanning Registry on $server"
                    $pendingRebootCBS = Invoke-Command -ComputerName $server -ScriptBlock {Test-Path -path $args[0]} -ArgumentList $CBS -ErrorAction Stop
                    $pendingRebootWU = Invoke-Command -ComputerName $server -ScriptBlock {Test-Path -path $args[0]} -ArgumentList $WU -ErrorAction Stop

                    if ($pendingRebootCBS -or $pendingRebootWU)
                    {
                        $serverReadyToBePatched.RemoveAt($ServerReadyToBePatched.IndexOf($server)) #Remove computername from ready to be patched list
                    }
                    else
                    {
                        $serversToBeRebooted.RemoveAt($serversToBeRebooted.IndexOf($server)) #Remove computername from ready to be rebooted list
                    }
                }
                catch
                {
                    Write-Warning "$server is online but not responding to remoting.  Try it later...."
                    $serverReadyToBePatched.RemoveAt($ServerReadyToBePatched.IndexOf($server)) #Remove computername from ready to be patched list
                    $serversToBeRebooted.RemoveAt($serversToBeRebooted.IndexOf($server)) #Remove computername from ready to be rebooted list
                    $offlineServers += $server
                }
            }
            else
            {
                Write-Host "$server might be online but WinRM service not responding"
                $serverReadyToBePatched.RemoveAt($ServerReadyToBePatched.IndexOf($server)) #Remove computername from ready to be patched list
                $serversToBeRebooted.RemoveAt($serversToBeRebooted.IndexOf($server)) #Remove computername from ready to be rebooted list
                $offlineServers += $server
            }
        }
        else
        {
            Write-Host "$server is offline"
            $serverReadyToBePatched.RemoveAt($ServerReadyToBePatched.IndexOf($server)) #Remove computername from ready to be patched list
            $serversToBeRebooted.RemoveAt($serversToBeRebooted.IndexOf($server)) #Remove computername from ready to be rebooted list
            $offlineServers += $server
        }
    }
    $serversToBeRebooted | Out-File -FilePath $listOfServersToReboot -Force
    $serverReadyToBePatched | Out-File -FilePath $listOfServersReadyToPatch -Force
    $offlineServers | Out-File -FilePath $offlineServerList -Force

}
# Get-UpdateScheduledTask scans target computers for PSWindowsupdate scheduled task and returns list of computers with no scheduled task
function Get-UpdateScheduledTask
{
    param (
        [Parameter(Mandatory = $true)]
        [string[]]
        $servers
    )

    [string[]]$serversToCreate = $null

    foreach ($server in $servers)
    {
        try
        {
            invoke-command -ComputerName $server -ScriptBlock {Get-ScheduledTask -TaskPath $args[0] -TaskName $args[1]} -ArgumentList $taskPath, $taskName -ErrorAction Stop | Out-Null
        }
        catch
        {
            $serversToCreate += $server
        }
    }

    return $serversToCreate

}

# New-UpdateScheduledTask function will create pwwindowsupdate scheduled task on the list of servers.
function New-UpdateScheduledTask
{
    param (
        [Parameter(Mandatory = $true)]
        [string[]]
        $servers
    )

    if (-not (Test-Path -Path "c:\temp"))
    {
        New-Item -Path "C:\temp" -ItemType Directory
    }

    $cred = Get-Credential
    try
    {
        $ErrorActionPreference = "Stop"
        $cred.password | ConvertFrom-SecureString | set-content -Path $passwordFile
        $password = Get-Content $passwordFile | ConvertTo-SecureString
        $password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))
        $userName = $cred.UserName
    }
    catch
    {
        Write-Warning "Something is not right with password"
    }

    foreach ($server in $servers)
    {
        try
        {
            Invoke-Command -ComputerName $server -ScriptBlock {
                $logFolder = "C:\Patchlogs\"
                $category = $args[4]
                #$category = $category -join ","
                if (-not (Test-Path -Path $logFolder))
                {
                    New-Item -ItemType Directory -Force -Path $logFolder
                }

                $runAt = (Get-Date).AddMinutes(-8) # add -8 minutes to prevent scheduled task from running automatically
                $argument= "-command Get-Windowsupdate -MicrosoftUpdate -Install -IgnoreReboot -AcceptAll -Severity $($category -join ",") | Out-File C:\PatchLogs\PSWindowsUpdate.log"
                $action = New-ScheduledTaskAction -Execute 'C:\windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Argument $argument  -WorkingDirectory $logFolder
                $trigger = New-ScheduledTaskTrigger -Once -At $runAt
                Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $args[0] -Description "Monthly Patching Script" -TaskPath $args[1] -User $args[2] -Password $args[3]
            } -ArgumentList $taskName, $taskPath, $userName, $password, $UpdateCategory -ErrorAction Stop
        }
        catch
        {
            Write-Warning ($_.exception.message)
        }
    }

}

#Run-UpdateScheduledTask will apply patch using Get-WindowsUpdate through scheduled task but won't reboot server.
function Run-UpdateScheduledTask
{
    param (
        [Parameter(Mandatory = $true)]
        [string[]]
        $servers
    )

    foreach ($server in $servers)
    {
        try
        {
            Write-Host "Starting PSWindowsUpdate"
            Invoke-Command -ComputerName $server -ScriptBlock {Start-ScheduledTask -TaskPath $args[0] -taskname $args[1]} -ArgumentList $taskPath, $taskName -ErrorAction Continue
        }
        catch
        {
            Write-Warning ($_.exception.message)
        }
    }

    Start-Sleep -second 30

    $updateRunning = $servers.count

    while ($updateRunning -gt 0)
    {
        $updateRunning = invoke-command -ComputerName $servers -ScriptBlock {Get-Process -Name $args[0]} -ArgumentList $script:updateProcess -ErrorAction SilentlyContinue
        Write-Verbose "Following Servers are running Windows Update"
        Write-Verbose $updateRunning.psComputerName
        if ($($updateRunning.count) -gt 0)
        {
            Start-Sleep -Seconds 60
        }
    }

}

# Begining of Main
Write-Host $message -ForegroundColor Yellow -NoNewline

[int]$selection = Read-Host

while (-not ($selection -gt 0 -and $selection -lt 6))
{
    Write-Host "You have entered invalid option.  Please enter your option again: " -ForegroundColor Yellow -NoNewline
    $selection = Read-Host
}

while ($selection -ne 5)
{
    switch ($selection)
    {
        1 {$reboot = $true; $patch = $false}
        2 {$reboot = $false; $patch = $true}
        3 {$reboot = $true; $patch = $true}
        4 {$reboot = $false; $patch = $false}
    }

    if ($reboot) #Option 1 Reboot
    {
        Write-Host 'Scanning Servers for pending reboot (Option 1)'
        Check-PendingReboot -serversToCheck $ComputerName
        $rebootServers = Get-Content -Path $listOfServersToReboot
        if ($null -ne $rebootServers)
        {
            Write-Host 'Rebooting Servers for 1st time'
            Restart-Computer -ComputerName $rebootServers -Wait -For WinRM -Force
            Write-Host 'First reboot finished.  Updating ready to be patched server list'
            Add-Content -Path $listOfServersReadyToPatch -Value $rebootServers
            # Remove-Item -path $listOfServersToReboot
        }
        else
        {
            Write-Host "No server needs to be rebooted."
        }
    }

    if ($patch)
    {
        Write-Host 'Scanning Servers for pending reboot (Option 2)'
        Check-PendingReboot -serversToCheck $ComputerName

        $patchServers = Get-Content -Path $listOfServersReadyToPatch

        Write-Host 'Scanning servers for scheduled task'
        $needUpdateScheduledTask = Get-UpdateScheduledTask -servers $patchServers
        if ($null -ne $needUpdateScheduledTask)
        {
            Write-Host 'Creating scheduled tasks on servers'
            Write-Host "Creating scheduled tasks for following servers: $needUpdateScheduledTask"
            New-UpdateScheduledTask -servers $needUpdateScheduledTask | Select-Object psComputerName, Description, TaskName | Format-Table
        }

        if ($reboot)
        {
            Write-Host 'Getting Windows Update Lists (Option 3)'
            $updates = Invoke-Command -ComputerName $patchServers -ScriptBlock {Get-WindowsUpdate -MicrosoftUpdate -Severity ($args[0] -join ",")} -ArgumentList $UpdateCategory
            Write-Host 'Completed Update Scan (Option 3)'
            while (($updates.kb).Count -gt 0)
            {
                Write-Host 'Installing Updates (Option 3)'
                Run-UpdateScheduledTask -Servers $patchServers
                Write-Host 'Checking Pending Reboot'
                Check-PendingReboot -serversToCheck $patchServers

                $rebootServers = Get-Content -Path $listOfServersToReboot
                if ($null -ne $rebootServers)
                {
                    Write-Host 'Rebooting Servers after patch (option 3)'
                    Restart-Computer -ComputerName $rebootServers -Wait -For WinRM -Force
                    Write-Host 'All servers are online'
                    Add-Content -Path $listOfServersReadyToPatch -Value $rebootServers
                }
                $computers = Get-Content -path $listOfServersReadyToPatch
                Write-Host 'Checking for additional updates'
                $updates = Invoke-Command -ComputerName $computers -ScriptBlock {Get-WindowsUpdate -MicrosoftUpdate -Severity ($args[0] -join ",")} -ArgumentList $UpdateCategory
                Write-Host "following updates left"
                Write-Host $updates
            }
            Write-Host "All servers have been pathched!!!" -ForegroundColor Green
        }
        elseif (-not $reboot)
        {
            Write-Host 'Getting Windows Update Lists (Option 2)'
            foreach($patchServer in $patchServers)
            {
                try
                {
                    Write-Host "Getting Patch List  from $patchServer"
                    $updates = Invoke-Command -ComputerName $patchServer -ScriptBlock {Get-WindowsUpdate -MicrosoftUpdate -Severity ($args[0] -join ",")} -ArgumentList $UpdateCategory -ErrorAction Continue
                }
                catch
                {
                    Write-Host $_.exception.message -ForegroundColor Red
                }
            }

            Write-Host 'Completed Update Scan (Option 2)'
            $updates | Format-Table -AutoSize

            if (($updates.kb).Count -gt 0)
            {
                Write-Host 'Installing Updates (Option 2)'
                Run-UpdateScheduledTask -servers $patchServers
                Write-Host 'Updates completed but not rebooting servers'
                Check-PendingReboot -serversToCheck $patchServers
                Get-Content -Path $listOfServersToReboot | Out-GridView -Title "Pending Reboot"
                Get-Content -Path $listOfServersReadyToPatch | Out-GridView -Title "Ready To be Patched"
            }
            else
            {
                Write-Host "All servers are up-to-date!!!" -ForegroundColor Green
            }

        }
    }

    if ((-not $reboot) -and (-not $patch))
    {
        Write-Host 'Scanning Servers for pending reboot (Option 4)'
        Check-PendingReboot -serversToCheck $ComputerName

        Get-Content -Path $listOfServersToReboot | Out-GridView -Title "Pending Reboot"
        Get-Content -Path $listOfServersReadyToPatch | Out-GridView -Title "Ready To be Patched"
        Get-Content -Path $offlineServerList | Out-GridView -Title "Inaccessible Servers"

        Write-Host "Do you want to scan servers for updates? (Y for Yes, N for No)" -ForegroundColor Yellow -NoNewline
        $updatescan = (Read-Host).ToUpper()

        if ($updatescan -eq "Y")
        {
            $scanForPatch = Get-Content -Path $listOfServersReadyToPatch
            foreach($computer in $scanForPatch)
            {
                try
                {
                    Write-Host "Getting Patch List  from $computer"
                    $updates = Invoke-Command -ComputerName $computer -ScriptBlock {Get-WindowsUpdate -MicrosoftUpdate -Severity ($args[0] -join ",")} -ArgumentList $UpdateCategory -ErrorAction Continue
                }
                catch
                {
                    Write-Host $_.exception.message -ForegroundColor Red
                }
            }

            
            if ($($updates.KB).Count -gt 0)
            {
                for($i = 0;$i -lt $updates.count; $i++)
                {
                    $title = $updates[$i].psComputerName
                    $updates[$i] | Out-GridView -Title $title
                }
            }
            else
            {
                Write-Host "No Patch is needed." -ForegroundColor Green
            }
        }
    }
    
    Write-Host $message -ForegroundColor Yellow -NoNewline

    [int]$selection = Read-Host

    while (-not ($selection -gt 0 -and $selection -lt 6))
    {
        Write-Host "You have entered invalid option.  Please enter your option again: " -ForegroundColor Yellow -NoNewline
        $selection = Read-Host
    }

    #Cleaning up
    if ($selection -eq 5)
    {
        try
        {
            Invoke-Command -ComputerName $patchServers -ScriptBlock {Unregister-ScheduledTask -TaskName $args[0] -TaskPath $args[1] -Confirm:$false} -ArgumentList $taskName, $taskPath -ErrorAction SilentlyContinue
            Remove-item -Path $passwordFile -ErrorAction SilentlyContinue
        }
        catch
        {
            Write-Host "Cleaning up"
        }
    }
}
# End of main