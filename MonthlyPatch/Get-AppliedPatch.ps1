[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string[]] $computerNames,
    [Parameter(Mandatory = $true)]
    [string[]] $patchList
)

Foreach($computer in $computerNames)
{
    Try{
        $appliedPatches = Get-HotFix -ComputerName $computer -ErrorAction Stop
        Foreach($patch in $patchList)
        {
            if($appliedPatches.HotFixID -contains $patch)
            {
                $appliedDate = $appliedPatches | Where-Object {$_.HotFixID -eq $patch} | Select InstalledOn 
                Write-Host ("$computer has $patch applied on $($appliedDate.InstalledOn)")
            }
            else
            {
                Write-Host "$computer doesn't have $patch applied" -ForegroundColor Yellow
            }
        }
    }
    Catch{
        Write-Host "$computer has following error" -ForegroundColor Yellow
        Write-Error $error[0].exception
    }
    Write-Host ""
}