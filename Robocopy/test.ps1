$NumberofCopyProccess = 3
$counts = "1","2","3","4","5","6","7","8","9","10"

    foreach($count in $counts)
    {
        $runningjobs = get-job | where{$_.State -eq "Running"}
        if($runningjobs.count -lt $NumberofCopyProccess)
        {
            Start-Job -ScriptBlock {start-sleep -Seconds 3}
            $runningjobs = get-job | where{$_.State -eq "Running"}
        }
        else
        {
            while($runningjobs.count -ge $NumberofCopyProccess)
            {
                $runningjobs = get-job | where{$_.State -eq "Running"}
            }
            Start-Job -ScriptBlock {start-sleep -Seconds 3}
            $runningjobs = get-job | where{$_.State -eq "Running"}
        }
        
    }

    # do{
    #     $runningjobs = get-job | where{$_.State -eq "Running"}
    #     if($runningjobs.count -lt $NumberofCopyProccess)
    #     {
    #         Start-Job -ScriptBlock {start-sleep -Seconds 10}
    #         $runningjobs = get-job | where{$_.State -eq "Running"}
    #     }
    #     else
    #     {
    #         while($runningjobs.count -ge $NumberofCopyProccess)
    #         {
    #             $runningjobs = get-job | where{$_.State -eq "Running"}
    #             $runningjobs
    #             Start-Sleep -Seconds 5
    #             Clear-Host
    #         }
    #     }
    # } while($runningjobs.count -ne 0)

