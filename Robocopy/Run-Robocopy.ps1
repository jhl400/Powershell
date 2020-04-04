[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$File,
    [Parameter(Mandatory=$false)]
    [string[]]$Options=@("/copyall","/E","/ZB","/MT:20","/256"),
    [Parameter(Mandatory=$false)]
    [string]$LogPath="C:\Temp\",
    [Parameter(Mandatory=$false)]
    [string]$LogOption="/Log+:",
    [Parameter(Mandatory=$true)]
    [int]$NumberofCopyProccess
)

$folders = Import-Csv -Path $File

$LogFile = $LogOption + $LogPath

foreach($folder in $folders)
{
    $runningjobs = get-job | where{$_.State -eq "Running"}
    if($runningjobs.Count -lt $NumberofCopyProccess)
    {
        $logFileName = $folder.source.split("\")[-1]
        $log = $LogFile+$logFileName+".log"
        # $scriptBlock = "Robocopy.exe $($folder.source) $($folder.target) $Options $log"
        # Start-Job -ScriptBlock $scriptBlock
        Start-job {robocopy $args[0] $args[1] $args[2]  $args[3] } -ArgumentList $folder.Source, $folder.target, $Options, $log
        $runningjobs = get-job | where{$_.State -eq "Running"}
    }
    else
    {
        while($runningjobs.count -ge $NumberofCopyProccess)
        {
            $runningjobs = get-job | where{$_.State -eq "Running"}
        }
        $log = $LogFile+$logFileName
        # $scriptBlock = "Robocopy.exe $($folder.source) $($folder.target) $Options $log"
        # Start-Job -ScriptBlock $scriptBlock
        Start-job {robocopy $args[0] $args[1] $args[2]  $args[3] } -ArgumentList $folder.Source, $folder.target, $Options, $log
        $runningjobs = get-job | where{$_.State -eq "Running"}
    }
    
}