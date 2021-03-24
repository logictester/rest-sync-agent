# Path of script being multi-threaded:
$PATH_SCRIPTBLOCK = "$PSScriptRoot\scriptblock.ps1"

Function Sync-Users($Method, $Users, $UserCache, $Config) {

  $ScriptBlock = [Scriptblock]::Create((Get-Content -Path $PATH_SCRIPTBLOCK -Raw))

  $RunspacePool = [Runspacefactory]::CreateRunspacePool(1, $Config.MaxThreadCount)
  $RunspacePool.Open()
  
  [System.Collections.ArrayList]$Jobs = @()   # Keep track of threads

  $api = @{
        uri = $Config.API_endpoint
        hdr = @{
                apikey = $Config.API_key
                accept = "application/json"
        }
        method = $Method
  }

  $Users | % {

        $PowerShell = [powershell]::Create().AddScript($ScriptBlock)

        $ParamList = @{
            user = $UserCache.Value[$_]
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
          Write-Host $Runspace.PowerShell.EndInvoke($Runspace.Pipe) -NoNewLine # print results to host
          $Runspace.PowerShell.Dispose()
          $Jobs.Remove($Runspace)
      }
    }
  }
  
  $stopWatch.Stop()
  $timeElapsed = [System.Math]::Round($stopWatch.Elapsed.TotalSeconds, 3)
  Write-Log "[ SYNC ] - Total time elapsed (in seconds): $timeElapsed" -TextColor Cyan


} # End Sync-Users
