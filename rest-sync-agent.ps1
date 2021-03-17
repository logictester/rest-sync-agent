$API_key = "cZN1CbACpSN5jYWpFkMvWNBrhHsq4MIu"
$API_endpoint = 'https://api.us.safenetid.com/api/v1/tenants/OFG56DOGVZ/users'

$Groups = "MFA Secured Users", "Administrators"

$AttributeMapping = @{ 
#####                  'REST'         =   'AD'
                       'userName'     =   'SamAccountName' 
                       'email'        =   'EmailAddress'   
                       'lastName'     =   'SurName'        
                       'firstName'    =   'GivenName'     
                     } 

$AnchorMapping = "ObjectGUID"

$LocalCacheFile = "C:\tmp\UserHash7.json"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$FilterExpression = @()

$AttributeMapping.keys | % { 
 $FilterExpression += @{Label = "$_"; Expression = $($AttributeMapping.Item($_))}
}

$FilterExpression += $AnchorMapping
# https://stackoverflow.com/questions/62334577/variable-number-of-fields-to-output-in-select-object-cmdlet                  
#$FilterExprOG = 
#   @{Label = "userName"; Expression = {$_.($AttributeMapping.userName)}},
#   @{Label = "email"; Expression = {$_.($AttributeMapping.email)}}


#######################################
# Phase 0 - Load up cache
#######################################
$UserCacheHash = @{}

# check for 1st run
if( Test-Path $LocalCacheFile ) {

    $UserCacheRaw = Get-Content -Raw $LocalCacheFile
    (ConvertFrom-Json $UserCacheRaw).psobject.properties | foreach { $UserCacheHash[$_.Name] = $_.Value }

} else {
    Write-Host "Welcome you 1st timer... or have you cleaned up the cache?"
}

$UsersToAdd = [System.Collections.ArrayList]::new() # any users found in ad but not in cache
$UsersToUpdate = [System.Collections.ArrayList]::new() # any users found in ad which have a different attribute than from cache
$UsersToDelete = [System.Collections.ArrayList]$UserCacheHash.Keys # reverse logic, start with all users, then remove the ones we find in ad as we process

#######################################
# Phase 1 - Query AD source
#######################################
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
        #No idea where the $tmp.guid comes from... to fix...

        # IF user exists in cache
        If($UserCacheHash.ContainsKey($tmp.guid))
        {
            Write-Host "[INFO] User $($_.userName) exists in cache, not deleting"
            $UsersToDelete.Remove($tmp.guid)
        }
        
        # IF user exists in multiple groups, takes first
   #     If($UserHashTable.ContainsKey($_.userName))
        ElseIf($UserHashTable.ContainsKey($tmp.guid))
           {
            Write-Warning "[Local Cache] - User $($_.userName) already exists"

        }
        else
        {
            $UserHashTable["$($_.$AnchorMapping)"] = ($_ | Select-Object -Property * -ExcludeProperty $AnchorMapping)
#           $UsersToAdd.Add($_.userName) | Out-Null  #added out-null to mask output
            $UsersToAdd.Add("$($_.$AnchorMapping)") | Out-Null  #added out-null to mask output

            #tmp location - move once user added
            $UserCacheHash["$($_.$AnchorMapping)"] = ($_ | Select-Object -Property * -ExcludeProperty $AnchorMapping)

        }

    }
    
}
Catch
{
    $_
}

#$UsersToDelete

If($UsersToDelete.Count -eq 0) { Write-Host "[INFO] There are *no* users to delete." }
Else
{
    Write-Host "[INFO] Deleting the following *$($UsersToDelete.Count)* users:"
    $usersToDelete
}


If($UsersToAdd.Count -eq 0) { Write-Host "[INFO] There are *no* users to add." }
Else
{
    Write-Host "[INFO] Adding the following *$($UsersToAdd.Count)* users:"
    $usersToAdd
}



#######################################
# Phase 2 - Make changes to Cloud
#######################################

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


# Store latest table
$UserCacheHash | ConvertTo-Json | out-file $LocalCacheFile
Write-Output "Storing cache to $LocalCacheFile."  

#Patch:       Invoke-RestMethod -Uri "$API_endpoint\$($person.userName)" -Method $method -Body $body -ContentType 'application/json' -Headers $hdrs
#Delete Remove -Body (optional) + Patch
