Param(
    
    [Parameter(Mandatory=$true)]
    [string[]]$Path,
    [Parameter(Mandatory=$true)]
    [int]$Days,
    [Parameter(Mandatory=$true)]
    [int]$NumberofCopyProccess,
    [Parameter(Mandatory=$false)]
    [string[]]$LogFile="D:\Temp\"
)

$LogFile = $LogFile + "DeleteError_" + (Get-Date -format yyyymmdd) + ".log"
$exclusions = ("latest.tst","private")

if(Test-Path -Path $Path)
{
    $folders = Get-ChildItem -Path $Path -Directory | Where-Object{($_.CreationTime -lt (Get-Date).AddDays($Days)) -and ($_.Name -notin $exclusions)}
    $folders | Select-Object FullName, CreationTime
}
else
{
    Write-Host "The $path doesn't exist" -ForegroundColor Red    
}

$runningjobs = get-job | Where-Object{$_.State -eq "Running"}

foreach($folder in $folders)
{
    
    while($runningjobs.count -ge $NumberofCopyProccess)
    {
        Start-job {Remove-Item -Path $args[0] -Recurse -Force } -ArgumentList $folder.FullName
        #Remove-item -Path $folder.FullName -Recurse -Force
        $runningjobs = get-job | Where-Object{$_.State -eq "Running"}
        $failedjob = Get-Job | Where-Object{$_.state -eq "Completed" -and $_.HasMoreData -eq $True}
        $failedjob.ChildJobs[0].Error.Exception | out-file -FilePath $LogFile
        Get-Job | Where-Object {$_.State -eq "Completed"} | Remove-Job
    }
    
    $erroredjobs = Get-Job | Where-Object{($_.state -eq "completed") -and ($_.HasMoreData -eq $true)}

    for($i = 0; $i -lt $erroredjobs.count; $i++)
    {
        $erroredjobs.ChildJobs[$i].Error.Exception | Out-File -FilePath d:\temp\error.txt -Append
    }
    # if($runningjobs.Count -lt $NumberofCopyProccess)
    # {
    #     Start-job {Remove-Item -Path $args[0] -Recurse -Force } -ArgumentList $folder.FullName
    #     #Remove-item -Path $folder.FullName -Recurse -Force
    #     $runningjobs = get-job | Where-Object{$_.State -eq "Running"}
    # }
    # else
    # {
    #     while($runningjobs.count -ge $NumberofCopyProccess)
    #     {
    #         $runningjobs = get-job | Where-Object{$_.State -eq "Running"}
    #     }
    # }
}

