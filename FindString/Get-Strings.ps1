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
    $Save = $false,
    [Parameter(Mandatory=$false)]
    $NewWord
)

# Start Main
$files = @()
$folders = @()
$NewWord = "Replaced"

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

$results = Select-String -Path $files -Pattern $Words -SimpleMatch | Select-Object Pattern, Filename, LineNumber, Path #@{name = 'Path'; e=(Split-Path -path $_.Path)}
$results

if($NewWord -and ($results -ne $null))
{
    foreach($result in $results)
    {
        Copy-Item -Path $result.Path ($result.Path).Replace(".","_back.") -Force
        foreach($word in $Words)
        {
            [regex]::Replace((Get-Content -Path $result.Path), [regex]::Escape($word), $NewWord, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) | Set-Content -Path $result.Path
        }
        
    }
}


