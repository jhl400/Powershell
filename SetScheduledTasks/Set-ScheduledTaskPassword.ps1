Param(
  [Parameter(Mandatory=$true,ValueFromPipeline=$true)][string[]]$ComputerName,
  [Parameter(Mandatory=$true)][PSCredential]$TaskCredential
)

#Invoke-command -ComputerName $ComputerName -ScriptBlock {Get-ScheduledTask | Where-Object {$_.Principal.UserId -eq ($using:TaskCredential).UserName}}

Invoke-Command -ComputerName $ComputerName -ScriptBlock {
    Get-ScheduledTask | Where-Object { $_.Principal.UserId -eq ($using:TaskCredential).UserName } `
    | Set-ScheduledTask -User ($using:TaskCredential).UserName -Password ($using:TaskCredential).GetNetworkCredential().Password
  }