###############################################################################
#
# REST-Sync-Agent.ps1 (v0.12-test)
#
# Synchronize Active Directory users to SafeNet Trusted Access via REST API
#
###############################################################################
[CmdletBinding()]
Param([String] $ConfigFile = "config\agent.config")


##############################################################################


# Import Write-Log, Write-ColorOutput
Import-Module $PSScriptRoot\modules\general\logging -Force

# Import Sync-UsersToAdd
Import-Module $PSScriptRoot\modules\sync\usersToAdd -Force

Get-Content $ConfigFile | % -begin {$Config=@{}} -process { $k = [regex]::split($_,'='); if(($k[0].CompareTo("") -ne 0) -and ($k[0].StartsWith("[") -ne $True)) { $Config.Add($k[0], $k[1]) } }

# Resolve default cache path
$Config.LocalCacheFile = ($Config.LocalCacheFile -replace "<default>", "$PSScriptRoot\db")

# Import scriptblocks used during multi-threading
#$PATHSCRIPT_ADDUSERS = "$PSScriptRoot\modules\scriptblock\add-users.ps1"
#$PATHSCRIPT_DELUSERS = "$PSScriptRoot\modules\scriptblock\del-users.ps1"
#$PATHSCRIPT_UPDATEUSERS = "$PSScriptRoot\modules\scriptblock\update-users.ps1"

###############################################################################
  #
  #       A d v a n c e d   S e t t i n g s
  #
###############################################################################

$AttributeMapping = @{ 
#####                  'REST'         =   'AD'
                       'userName'     =   'SamAccountName' 
                       'email'        =   'EmailAddress'   
                       'lastName'     =   'SurName'        
                       'firstName'    =   'GivenName'     
                     } 

$AnchorMapping = "ObjectGUID"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

###############################################################################

# Use calculated properties to remap attributes between source and destination
$FilterExpression = @()

# https://stackoverflow.com/questions/9015138/looping-through-a-hash-or-using-an-array-in-powershell
$AttributeMapping.Keys | % { 
 $FilterExpression += @{Label = "$_"; Expression = $($AttributeMapping.Item($_))}
}

$FilterExpression += $AnchorMapping

###############################################################################
# Phase 0 - Load up cache
###############################################################################

$UserCache = @{}

# Import cache into $UserCache variable. Checks for 1st run.
If(Test-Path $($Config.LocalCacheFile)) {
    Write-Log "Loading from cache $($Config.LocalCacheFile)"
    (ConvertFrom-Json (Get-Content -Raw $Config.LocalCacheFile)).PSObject.Properties | ForEach { $UserCache[$_.Name] = $_.Value }

} Else {

    Write-Log "[ INFO ] - First run?... Clean cache?..."

}

$UsersToAdd = [System.Collections.ArrayList]::new() # any users found in ad but not in cache
$UsersToUpdate = [System.Collections.ArrayList]::new() # any users found in ad which have a different attribute than from cache
$UsersToDelete = [System.Collections.ArrayList]$UserCache.Keys # reverse logic, start with all users, then remove the ones we find in ad as we process


###############################################################################
  #
  #       M u l t i - t h r e a d i n g    
  #
###############################################################################

$RunspacePool = [Runspacefactory]::CreateRunspacePool(1, $Config.MaxThreadCount)
$RunspacePool.Open()

###############################################################################
# PHASE 1 - Query AD source
###############################################################################

# TODO: Add better checking / fail-safes in case bad AD connection
Try {

  if($Config.Groups){
    $(ForEach ($Group in $Config.Groups.Split(",")) {

        Get-ADGroupMember -Identity $Group -Recursive `
          | Get-ADUser -Properties * `
          | Select-Object $FilterExpression `

    }) | % {

        $key = [string]$($_.$AnchorMapping)

        # IF user exists in cache
        If($UserCache.ContainsKey($key))
        {
          # IF user already being added
          If($UsersToAdd.Contains($key))
          {
            Write-Warning "User '$($_.userName)' exists in more than one target group?"
          }
          Else
          {
            Write-Log "[ INFO ] - User '$($_.userName)' exists in cache, not deleting"
            $UsersToDelete.Remove($key)
          }

        }
        Else
        {
            Write-Log "[ INFO ] - User '$($_.userName)' will be added"
            $UsersToAdd.Add($key) | Out-Null  #added out-null to mask output

            #TODO: move location - store to cache after user added to STA
            $UserCache[$key] = ($_ | Select-Object -Property * -ExcludeProperty $AnchorMapping)

        }

    }
    }
    else {
        Write-Warning "No filter groups in config."
    }
}
Catch
{
    $_
}

# TODO: Refactor
If($UsersToDelete.Count -eq 0) { Write-Log "[ INFO ] - There are *no* users to delete." }
Else
{
    Write-Log "[ INFO ] - Deleting the following *$($UsersToDelete.Count)* users:"
    $UsersToDelete
}


If($UsersToAdd.Count -eq 0) { Write-Log "[ INFO ] - There are *no* users to add." }
Else
{
    Write-Log "[ INFO ] - Adding the following *$($UsersToAdd.Count)* users:"
    $UsersToAdd
}


###############################################################################
# PHASE 2 - Make changes to Cloud
###############################################################################
# PART 2.1 - Delete users
###############################################################################

ForEach ($key in $UsersToDelete)  {
  #$jsonUserData = ConvertTo-Json $UserCache.$key
  $userData = $UserCache[$key]

  Write-Log "[ REST ] - Deleting $key `($($userData.userName)`)"

  $hdrs = @{}
  $hdrs.Add("apikey",$Config.API_key)
  $hdrs.Add("accept","application/json")
  $method = "DELETE"

  # Send delete as webrequest, invoke-restmethod drops rc
  $timeTaken = Measure-Command { 
      $response = try {
          Invoke-WebRequest -Uri "$($Config.API_endpoint)\$($userData.userName)" -Method $method -ContentType 'application/json' -Headers $hdrs
      }
      catch [System.Net.WebException] { 
        Write-Log "An exception was caught: $($_.Exception.Message)"
        $_.Exception.Response 
      }
  } 

  Write-Log "Time taken (in milliseconds): $($timeTaken.TotalMilliseconds)" -TextColor Cyan

  # Convert status code enum to int by doing this:
  $statusCodeInt = [int]$response.StatusCode
  #  $response.StatusCode.Value__
  Write-Debug "[ REST ] - DELETE return code => $statuscodeInt"

  # STA did not find user (rc = 404)
  # Abnormal state in script cache: user found in cache but not in sta, resolve by delete from cache
  if($statusCodeInt -eq 404)
  {
      Write-Log "[ LOCL ] - Cleaning up '$($userData.userName)' from cache"
      $UserCache.Remove($key)
  }

  # STA delete successful (rc = 204)
  if($statusCodeInt -eq 204)
  {
      Write-Log "[ REST ] - Successful delete of user '$($userData.userName)' from STA"
      Write-Log "[ LOCL ] - Deleting '$($userData.username)' from cache"
      $UserCache.Remove($key)
  }

}

###############################################################################
# PART 2.2 - Add users
# TODO: Add check when added. 
#

if($UsersToAdd) {
  Sync-UsersToAdd -UsersToAdd $UsersToAdd -UserCache $UserCache -Config $Config
}

###############################################################################
# PART 2.3 - Update users
###############################################################################
ForEach ($key in $UsersToUpdate) {
  # ...
}

###############################################################################
# PHASE 3 - Store latest cache
###############################################################################
$UserCache | ConvertTo-Json | Out-File $Config.LocalCacheFile
Write-Log "Storing cache to $($Config.LocalCacheFile)."  