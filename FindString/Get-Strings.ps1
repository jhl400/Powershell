[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [string[]]
    $Words,
    [Parameter(Mandatory=$true)]
    [string[]]
    $Paths,
    [Parameter(Mandatory=$true)]
    [string[]]
    $FileTypes,
    [Parameter(Mandatory=$false)]
    [Switch]
    $Save = $false
)

# Start Main
$results = @()

foreach($path in $Paths)
{
    foreach($fileType in $FileTypes)
    {
        Write-Verbose "Searching for $word in $path"
        $result = Get-ChildItem -Path $path "*.$($fileType)" -Recurse | Select-String -Pattern $Words -SimpleMatch
    }
    $results += $result
}

if($Save -eq $true)
{
    Write-Host "Output file will be save in C:\Temp"
    if(!(Test-Path -Path "C:\temp"))
    {
        New-Item -Path "C:\Temp" -ItemType Directory
    }
    $results | Select-Object Pattern, Path, LineNumber | Sort-Object -Property Pattern | Export-Csv -Path "C:\Temp\Pattern.csv" -NoTypeInformation
}
else
{
    $results | Select-Object Pattern, Path, LineNumber | Sort-Object -Property Pattern
}
# End Main