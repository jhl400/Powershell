[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [String[]]
    $ComputerName = (Get-ADComputer -Filter * -server co1-red-dc-01 -SearchBase  'OU=InTune-Team,OU=NoSync,OU=MLS,DC=redmond,DC=corp,DC=microsoft,DC=com' | Select-Object Name)
)

function Compare-Password
{
    param (
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]
        $PWD1,
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]
        $PWD2
    )
    $pwd1_text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwd1))
    $pwd2_text = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwd2))

    if ($pwd1_text -ceq $pwd2_text)
    {
        return $true
    }
    else
    {
        return $false
    }
}

Write-Host "Checking Local Administrator Account Name for following servers"
Write-Host $ComputerName
$LocalAdmins = @()

Foreach ($computer in $ComputerName)
{
    Write-Debug "Retreiving Built-in Administrator from $computer"
    if(Test-Connection $computer -Count 1 -ErrorAction SilentlyContinue)
    {
        $LocalAdmin = Invoke-Command -ComputerName $computer -scriptblock {Get-LocalUser | Where-Object{$_.description -match "Built-in account for administering"}} | Select-Object Name, PSComputername
    }
    $user = [PSCustomobject][ordered]@{
        Name = $LocalAdmin.Name
        Computername = $LocalAdmin.PSComputerName
        }
    
    If($user.Name -ne $null)
    {
        $LocalAdmins += $user
    }    
}

$LocalAdmins
$LocalAdmins | Out-File -FilePath C:\temp\LocalAdmin.txt -Force
$username = Read-Host "Please Enter New Local Administrator's Name: "

do
{
    $pwd1 = Read-Host "Please Enter New Password" -AsSecureString
    $pwd2 = Read-Host "Please Re-enter" -AsSecureString
    
}
while(-not(Compare-Password -PWD1 $pwd1 -PWD2 $pwd2))

Foreach($admin in $LocalAdmins)
{
    If($admin.name -ne $username)
    {
        Rename-LocalUser -Name $user.name -NewName $username
    }
    Invoke-Command -ComputerName $admin.Computername -ScriptBlock {Set-Localuser -name $args[0] -password $args[1]} -ArgumentList $username, $pwd1
}


