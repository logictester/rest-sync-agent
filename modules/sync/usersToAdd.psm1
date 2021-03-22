# Import scriptblocks used during multi-threading
$PATHSCRIPT_ADDUSERS = "$PSScriptRoot\scriptblock\usersToAddBlock.ps1"
$PATHSCRIPT_DELUSERS = "$PSScriptRoot\scriptblock\del-users.ps1"
$PATHSCRIPT_UPDATEUSERS = "$PSScriptRoot\scriptblock\update-users.ps1"

Function Sync-UsersToAdd($UsersToAdd, $UserCache, $Config) {

  $ScriptBlockAddUser = [Scriptblock]::Create((Get-Content -Path $PATHSCRIPT_ADDUSERS -Raw))
  
  # Keep track of threads
  [System.Collections.ArrayList]$Jobs = @()

  #[System.Collections.ArrayList]$qwResults = @()

  $api = @{
        uri = $Config.API_endpoint
        hdr = @{
                apikey = $Config.API_key
                accept = "application/json"
        }
        method = "POST"
  }

 # Write-Host "BLOBLB" $UsersToAdd
  $UsersToAdd | % {

        $PowerShell = [powershell]::Create().AddScript($ScriptBlockAddUser)

        $ParamList = @{
            user = $UserCache[$_]
            api  = $api
            path = $PSScriptRoot
        }

        [void]$PowerShell.AddParameters($ParamList)

        $PowerShell.RunspacePool = $RunspacePool
    
        $Jobs += New-Object -TypeName PSObject -Property @{
            Pipe = $PowerShell.BeginInvoke()
            PowerShell = $PowerShell
        }
  }
  
  $stopWatch = [system.diagnostics.stopwatch]::StartNew()
  
  While($Jobs) {
    ForEach ($Runspace in $Jobs.ToArray()) {
      If ($Runspace.Pipe.IsCompleted) {
            #[void]$qwResults.Add($Runspace.PowerShell.EndInvoke($Runspace.Pipe))
          Write-Host $Runspace.PowerShell.EndInvoke($Runspace.Pipe)  # get results
          $Runspace.PowerShell.Dispose()
          $Jobs.Remove($Runspace)
      }
    }
  }
  
  $timeElapsed = $stopWatch.Elapsed.TotalSeconds
  Write-Log "Total time elapsed (in seconds): $timeElapsed" -TextColor Cyan
  #Write-Host "The results for qWresults:" $qwResults
}
