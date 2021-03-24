# ScriptBlock Generalized
Param($api, $user, $path)

Function Invoke-CustomWeb {
  Param ($uri, $method, $header, $body)

  $response = @{}
  $response = try {     
    Invoke-WebRequest -Uri $uri -body $body -Method $method -ContentType 'application/json' -Headers $header

  }
  Catch [System.Net.WebException]
  {
    #("$_" -replace '"', '') # -> $_.ErrorDetails.Message without quotes
    
    @{'Message' = $_.ErrorDetails.Message -replace '"', ''}
    $_.Exception.Response
    $_
    
  }
  Catch {
    @{'Message' = $_.Exception.Message }
    @{'StatusCode' = 'Param ?!'}
  }
  #>

 # $response = @{ "Message" = "HELLO" }
  $response
}


 #$response = try {
 #         Invoke-WebRequest -Uri "$($Config.API_endpoint)\$($userData.userName)" -Method $method -ContentType 'application/json' -Headers $hdrs
 #     }
 #     catch [System.Net.WebException] { 
 #       Write-Log "An exception was caught: $($_.Exception.Message)"
 #       $_.Exception.Response 
  #    }



Function Write-Timestamp {
  Param ($msg)
  Write-Output "$($(Get-Date -format "o").Remove(22,5)) - $msg`r`n"
}

$uri = $api.uri

if($api.method -eq "DELETE")
{
    $uri = $api.uri + "/" + $user.userName

   # $message += "uri = $uri`n"

    $body = ""
}

$message = @() 

$body = (ConvertTo-Json $user)

#$message = "body type = $($user.getType())`r`n"
$message = Write-Timestamp "[ REST ] - Sending $($api.method) to $uri`r`n$body"

$timeTaken = Measure-Command {
  $response = Invoke-CustomWeb -Uri $uri -Header $api.hdr -Method $api.method -Body $body
}

# Get more details:
#$message += '"START"' + ($response | Out-String) + '"END"'


# General rule
$jsonResponse = (ConvertTo-Json $response.Message) | % { [System.Text.RegularExpressions.Regex]::Unescape($_) }

# Edge case #1 - For HTTP POST 201 response, i.e. when user create successful
# Refer to $_.Content since empty $response.Message => $response.Message generates only in catch all.
if($response.StatusCode -eq 201){
    #$jsonResponse = (ConvertTo-Json @(($response.Content).SubString(0,$response.Content.Length-1))) | % { [System.Text.RegularExpressions.Regex]::Unescape($_) }
    $jsonResponse = $response.Content | ConvertFrom-Json | ConvertTo-Json
   # $message += , "Adding info about jsonresp = $($response.Content.getType()).`r`n"
}

$message += Write-Timestamp "[ REST ] - Result - $($response.StatusCode) : $jsonResponse" # unescape for exception
$message += Write-Timestamp "Actual time taken (in milliseconds): $($timeTaken.TotalMilliseconds)"
$message += ("-"*120 + "`r`n")
$message
