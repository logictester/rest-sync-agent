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

# Import Sync-Users
Import-Module $PSScriptRoot\modules\sync\users -Force

Get-Content $ConfigFile | % -begin {$Config=@{}} -process { $k = [regex]::split($_,'='); if(($k[0].CompareTo("") -ne 0) -and ($k[0].StartsWith("[") -ne $True)) { $Config.Add($k[0], $k[1]) } }

#TODO: Move path to variable / add <default> 
$LANG = Get-Content $PSScriptRoot"\locale\en-US.json" | ConvertFrom-Json

# Resolve default paths
$Config.LocalCacheFile = ($Config.LocalCacheFile -replace "<default>", "$PSScriptRoot\db")
$Config.LogPath = ($Config.LogPath -replace "<default>", "$PSScriptRoot\log\")

# Set encoding to UTF-8 to avoid white-spaces in transcript logs
$PSDefaultParameterValues = @{ '*:Encoding' = 'utf8' }

# Start logging
Start-Transcript -Path (Get-LogLocation -Path $Config.LogPath)
# Catch and stop any exception
try {

# Get Host Details
Get-HostDetails
# Output Config
Write-Log "[ ARG ] Config - MAX CPU thread count set to : $($Config.MaxThreadCount)" -TextColor Cyan
Write-Log "[ ARG ] Config - User groups set to : $($Config.Groups)" -TextColor Cyan
Write-Delimiter

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

$FilterADUser = [String[]](($AttributeMapping.Values + $AnchorMapping) | % ToString)
###############################################################################
# Phase 0 - Load up cache
###############################################################################

$UserCache = [ordered]@{}

# Import cache into $UserCache variable. Checks for 1st run.
If(Test-Path $($Config.LocalCacheFile)) {

    Write-Log "Loading from cache $($Config.LocalCacheFile)"
    (ConvertFrom-Json (Get-Content -Raw $Config.LocalCacheFile)).PSObject.Properties | ForEach { $UserCache[$_.Name] = $_.Value }

} Else {

    Write-Log ($LANG.Log.Info + $LANG.Msg.FirstRun)

}

$UsersToAdd = [System.Collections.ArrayList]::new() # any users found in ad but not in cache
$UsersToUpdate = [System.Collections.ArrayList]::new() # any users found in ad which have a different attribute than from cache
$UsersToDelete = [System.Collections.ArrayList]$UserCache.Keys # reverse logic, start with all users, then remove the ones we find in ad as we process


###############################################################################
# PHASE 1 - Query AD source
###############################################################################

# TODO: Add better checking / fail-safes in case bad AD connection
Try {

  if($Config.Groups){
    $(ForEach ($Group in $Config.Groups.Split(",")) {

        Get-ADGroupMember -Identity $Group -Recursive `
          | Get-ADUser -Properties $FilterADUser `
          | Select-Object $FilterExpression `

    }) | % {

        $key = [string]$($_.$AnchorMapping)

        # IF user exists in cache
        If($UserCache.Contains($key))
        {
          # IF user already being added
          If($UsersToAdd.Contains($key))
          {
            Write-Warning ($LANG.General.User + " '" + $_.userName + "' " + $LANG.Warnings.ExistsTarget)
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

if($UsersToDelete) {
  Sync-Users -Method "DELETE" -Users $UsersToDelete -UserCache $UserCache -Config $Config
}
<#
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
#>

###############################################################################
# PART 2.2 - Add users
if($UsersToAdd) {
  Sync-Users -Method "POST" -Users $UsersToAdd -UserCache $UserCache -Config $Config
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

#Stop logging
}
finally 
{ 
  Stop-Transcript 
} 