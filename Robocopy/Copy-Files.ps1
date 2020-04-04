function copy-folders{
[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string]$File,
    [Parameter(Mandatory=$false)]
    $Options=@("/copyall","/E","/ZB","/MT:20","/256"),
    [Parameter(Mandatory=$false)]
    [string]$LogPath="C:\Robocopy.log",
    [Parameter(Mandatory=$false)]
    [string]$LogOption="/Log+:$LogPath",
    [Parameter(Mandatory=$true)]
    [int]$NumberofCopyProccess
)

    # $folders = Import-Csv -Path $File

    # $LogFile = $LogOption + $LogPath
    # $copyCount = 0    
    # foreach($folder in $folders)
    # {
    #     if($copyCount -le $NumberofCopyProccess)
    #     {
    #         Start-Job -ScriptBlock {Robocopy.exe $folders.source $folders.target $Options $LogFile}
    #         $copyCount += 1
    #     }
    #     else
    #     {
    #         while($($runningjobs.count) -ge $NumberofCopyProccess)
    #         {
    #             $runningjobs = get-job
    #             Start-Sleep -Seconds 300
    #         }
    #     }
        
    # }

    $folders = Import-Csv -Path $File

    $LogFile = $LogOption + $LogPath

    foreach($folder in $folders)
    {
        $runningjobs = get-job | where{$_.State -eq "Running"}
        if($runningjobs.Count -le $NumberofCopyProccess)
        {
            Start-Job -ScriptBlock {Robocopy.exe $folders.source $folders.target $Options $LogFile}
            $runningjobs = get-job | where{$_.State -eq "Running"}
        }
        else
        {
            while($runningjobs.count -ge $NumberofCopyProccess)
            {
                $runningjobs = get-job | where{$_.State -eq "Running"}
            }
            Remove-Job -State Completed
            Start-Job -ScriptBlock {Robocopy.exe $folders.source $folders.target $Options $LogFile}
            $runningjobs = get-job | where{$_.State -eq "Running"}
        }
        
    }
}