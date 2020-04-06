Param(
    
    [Parameter(Mandatory=$true)]
    [string[]]$Paths,
    [Parameter(Mandatory=$true)]
    [int]$Days,
    [Parameter(Mandatory=$true)]
    [int]$NumberofDeleteProccess,
    [Parameter(Mandatory=$false)]
    [string[]]$LogFile="D:\Temp\"
)

# Set parameters
$errorLogFile = $LogFile + "DeleteError_" + (Get-Date -format yyyymmdd) + ".log"
$deleteLogFile = $LogFile + "Delete_" + (Get-Date -format yyyymmdd) + ".log"
$exclusions = @("latest.tst","private")
$folders = @()

New-Item -Path $errorLogFile, $deleteLogFile -ItemType File -Force

# Get folder lists
Write-Verbose "Testing folder path"
foreach($path in $Paths)
{
    Write-Verbose "Getting folder list created longer than $Days ago"
    if(Test-Path -Path $path)
    {
        $subfolders = Get-ChildItem -Path $path -Directory | Where-Object{($_.CreationTime -lt (Get-Date).AddDays(-($Days))) -and ($_.Name -notin $exclusions)} | Select-Object FullName
        $folders += $subfolders
    }
    else
    {
        Write-Host "The $path doesn't exist" -ForegroundColor Red    
    }
}


$runningjobs = get-job | Where-Object{$_.State -eq "Running"}

# Deleting folders as background job

do
{
    
    while($runningjobs.count -lt $NumberofDeleteProccess)
    {
        Start-job {Remove-Item -Path $args[0] -Recurse -Force } -ArgumentList $folder.FullName
        #Remove-item -Path $folder.FullName -Recurse -Force
        $runningjobs = get-job | Where-Object{$_.State -eq "Running"}
        $failedjob = Get-Job | Where-Object{$_.state -eq "Completed" -and $_.HasMoreData -eq $True}
        $failedjob.ChildJobs[0].Error.Exception | out-file -FilePath $errorLogFile -Append
    }
    
    $erroredjobs = Get-Job | Where-Object{($_.state -eq "completed") -and ($_.HasMoreData -eq $true)}

    for($i = 0; $i -lt $erroredjobs.count; $i++)
    {
        $erroredjobs.ChildJobs[$i].Error.Exception | Out-File -FilePath $errorLogFile  -Append
    }

}while((Get-Job | Where-Object{$_.state -eq "Completed"}).Count -lt $folders.Count)

Remove-Job -State Completed