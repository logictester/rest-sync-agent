############################################################################################################
#
# REST-Sync-Agent.ps1 (v0.1-test)
#
# Synchronize Active Directory users to SafeNet Trusted Access via REST API
#
############################################################################################################
[CmdletBinding()]
Param()
############################################################################################################

$API_key = "cZN1CbACpSN5jYWpFkMvWNBrhHsq4MIu"
$API_endpoint = 'https://api.us.safenetid.com/api/v1/tenasnts/OFG56DOGVZ/users'
$Groups = "MFA Secured Users", "Administrators"
$LocalCacheFile = "C:\tmp\UserHash7.json"

############################################################################################################

$AttributeMapping = @{ 
#####                  'REST'         =   'AD'
                       'userName'     =   'SamAccountName' 
                       'email'        =   'EmailAddress'   
                       'lastName'     =   'SurName'        
                       'firstName'    =   'GivenName'     
                     } 

$AnchorMapping = "ObjectGUID"

$DebugPreference = "continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

############################################################################################################

# Use calculated properties to remap attributes between source and destination
$FilterExpression = @()

# https://stackoverflow.com/questions/9015138/looping-through-a-hash-or-using-an-array-in-powershell
$AttributeMapping.keys | % { 
 $FilterExpression += @{Label = "$_"; Expression = $($AttributeMapping.Item($_))}
}

$FilterExpression += $AnchorMapping

############################################################################################################
# Phase 0 - Load up cache
############################################################################################################

$UserCacheHash = @{}

# check for 1st run
if( Test-Path $LocalCacheFile ) {

    $UserCacheRaw = Get-Content -Raw $LocalCacheFile
    (ConvertFrom-Json $UserCacheRaw).psobject.properties | foreach { $UserCacheHash[$_.Name] = $_.Value }

} else {
    Write-Host "[INFO] First run?... Clean cache?..."
}

$UsersToAdd = [System.Collections.ArrayList]::new() # any users found in ad but not in cache
$UsersToUpdate = [System.Collections.ArrayList]::new() # any users found in ad which have a different attribute than from cache
$UsersToDelete = [System.Collections.ArrayList]$UserCacheHash.Keys # reverse logic, start with all users, then remove the ones we find in ad as we process

############################################################################################################
# Phase 1 - Query AD source
############################################################################################################

#TODO: Remove UserHashTable and all dependencies. Use $UserToAdd Collection + User "Cache" HashTable instead.
$UserHashTable = @{}

Try {

    $(ForEach ($Group in $Groups) {

        Get-ADGroupMember -Identity $Group -Recursive `
          | Get-ADUser -Properties * `
          | Select-Object $FilterExpression `
 
  
    }) | ForEach {

       # $_ | fl
        $tmp = $($_.$AnchorMapping)

        #Write-Host "tmp =  $tmp"
        #TODO: Find out where the $tmp.guid comes from... to fix...

        # IF user exists in multiple groups, takes first
        #If($UserHashTable.ContainsKey($_.userName))
        If($UserHashTable.ContainsKey($tmp.guid))
        {
            Write-Warning "[Local Cache] - User $($_.userName) already exists"

        }

        # IF user exists in cache
        ElseIf($UserCacheHash.ContainsKey($tmp.guid))
        {
            Write-Host "[INFO] User $($_.userName) exists in cache, not deleting"
            $UsersToDelete.Remove($tmp.guid)
        }
        
        Else
        {
            $UserHashTable["$($_.$AnchorMapping)"] = ($_ | Select-Object -Property * -ExcludeProperty $AnchorMapping)
#           $UsersToAdd.Add($_.userName) | Out-Null  #added out-null to mask output
            $UsersToAdd.Add("$($_.$AnchorMapping)") | Out-Null  #added out-null to mask output

            #TODO: tmp location - move once user added
            $UserCacheHash["$($_.$AnchorMapping)"] = ($_ | Select-Object -Property * -ExcludeProperty $AnchorMapping)

        }

    }
    
}
Catch
{
    $_
}

# TODO: Refactor
If($UsersToDelete.Count -eq 0) { Write-Host "[INFO] There are *no* users to delete." }
Else
{
    Write-Host "[INFO] Deleting the following *$($UsersToDelete.Count)* users:"
    $UsersToDelete
}


If($UsersToAdd.Count -eq 0) { Write-Host "[INFO] There are *no* users to add." }
Else
{
    Write-Host "[INFO] Adding the following *$($UsersToAdd.Count)* users:"
    $UsersToAdd
}


############################################################################################################
# Phase 2 - Make changes to Cloud
############################################################################################################

# Add users
# TODO: Add check when added. 
# TODO: Move away from UserHashTable to UsersToAdd
ForEach ($person in $UserHashTable.Values) {

   $body = (ConvertTo-Json $person)
   Write-Host "[REST] - Sending data`n $body"

   $hdrs = @{}
   $hdrs.Add("apikey",$API_key)
   $hdrs.Add("accept","application/json")

   $method = "POST"

   Try {
       Invoke-RestMethod -Uri "$API_endpoint" -body $body -Method $method -ContentType 'application/json' -Headers $hdrs
   }
   Catch
   {
       Write-Warning "[STA Cloud] - $_[0]"
   }
}

# Delete users
# TODO: Move order: delete before add (for better capacity conservation)
ForEach ($key in $UsersToDelete) {
  #$jsonUserData = ConvertTo-Json $UserCacheHash.$key
  $userData = $UserCacheHash[$key]

  Write-Host "[REST] Deleting $key `($($userData.userName)`)"

  $hdrs = @{}
  $hdrs.Add("apikey",$API_key)
  $hdrs.Add("accept","application/json")
  $method = "DELETE"

  # Send delete as webrequest, invoke-restmethod drops rc
  $response = try {
    (Invoke-WebRequest -Uri $API_endpoint\$($userData.userName) -Method $method -ContentType 'application/json' -Headers $hdrs)
  }
  catch [System.Net.WebException] { 
    Write-Host "An exception was caught: $($_.Exception.Message)"
    $_.Exception.Response 
  }

  # Convert status code enum to int by doing this:
  $statusCodeInt = [int]$response.StatusCode
  #  $response.StatusCode.Value__
  Write-Debug "REST DELETE return code => $statuscodeInt"

  if($statusCodeInt -eq 404)
  {
      # STA did not find user (rc = 404)
      # Abnormal state in script cache: user found in cache but not in sta, resolve by delete from cache
      Write-Host "[LOCAL] Cleaning up $($userData.userName) from cache"
      $UserCacheHash.Remove($key)
  }

  if($statusCodeInt -eq 204)
  {
      # STA delete successful (rc = 204)
      Write-Host "[REST] STA Cloud - Successfully deleted $($userData.userName)"
      Write-Host "[LOCAL] Deleting $($userData.username) from cache"
      $UserCacheHash.Remove($key)
  }

}

# TODO: Update users
ForEach ($key in $UsersToUpdate) {
  # ...
}

############################################################################################################

# Store latest cache
$UserCacheHash | ConvertTo-Json | out-file $LocalCacheFile
Write-Output "Storing cache to $LocalCacheFile."  
