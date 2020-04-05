[CmdletBinding()]
param (
    [Parameter(Mandatory=$true)]
    [validatescript({$_ -ne $null})]
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
$files = @()
$folders = @()

foreach ($path in $paths)
{
    if(Test-Path -Path $path)
    {
        $folders += $path
    }
    else
    {
        Write-Host "$path doesn't exist"    
    }
}

foreach ($type in $FileTypes)
{
    $file = Get-ChildItem -Path $folders  "*.$($type)" -Recurse | ForEach-Object {$_.FullName}
    $files += $file
}

$result = Select-String -Path $files -Pattern $Words -SimpleMatch | Select-Object Pattern, Filename, LineNumber, Path #@{name = 'Path'; e=(Split-Path -path $_.Path)}
$result

#$results | Format-Table -AutoSize
# if($Save -eq $true)
# {
#     Write-Host "Output file will be save in C:\Temp"
#     if(!(Test-Path -Path "C:\temp"))
#     {
#         New-Item -Path "C:\Temp" -ItemType Directory
#     }
#     $results | Select-Object Pattern, Path, LineNumber | Sort-Object -Property Pattern | Export-Csv -Path "C:\Temp\Pattern.csv" -NoTypeInformation
# }
# else
# {
#     $results | Select-Object Pattern, Path, LineNumber | Sort-Object -Property Pattern
# }
# End Main