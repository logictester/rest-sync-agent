# This is the script being multi-threaded
Param($api, $user, $path)

Function Invoke-CustomWeb {
  Param ($uri, $method, $header, $body)

  $response = @{}
  $response = try {     
    Invoke-WebRequest -Uri $uri -body $body -Method $method -ContentType 'application/json' -Headers $header

  }
  Catch [System.Net.WebException]
  {
    # TODO: Cleanup return variable  
    @{'Message' = $_.ErrorDetails.Message -replace '"', ''}
    $_.Exception.Response
    $_
    
  }
  Catch {
    @{'Message' = $_.Exception.Message }
    @{'StatusCode' = 'Param ?!'}
  }

  $response
}

Function Write-Timestamp {
  Param ($msg)
  Write-Output "$($(Get-Date -format "o").Remove(22,5)) - $msg`r`n"
}


###############################################################################
  #
  #       M a i n   b l o c k s c r i p t 
  #
###############################################################################

# TODO: Wrap function 

$uri = $api.uri

if($api.method -eq "DELETE")
{
    $uri = $api.uri + "/" + $user.userName
    $body = ""
}

$message = @() 

$body = (ConvertTo-Json $user)

$message = Write-Timestamp "[ REST ] - Sending $($api.method) to $uri`r`n$body"

$timeTaken = Measure-Command {
  $response = Invoke-CustomWeb -Uri $uri -Header $api.hdr -Method $api.method -Body $body
}

# General rule
$jsonResponse = (ConvertTo-Json $response.Message) | % { [System.Text.RegularExpressions.Regex]::Unescape($_) }

# Edge case #1 - For HTTP POST 201 response, i.e. when user create successful
# Refer to $_.Content since empty $response.Message => $response.Message generates only in catch all.
if($response.StatusCode -eq 201){
    $jsonResponse = $response.Content | ConvertFrom-Json | ConvertTo-Json
}

$message += Write-Timestamp "[ REST ] - Result - $($response.StatusCode) : $jsonResponse" # unescape for exception
$message += Write-Timestamp "Actual time taken (in milliseconds): $($timeTaken.TotalMilliseconds)"
$message += ("-"*120 + "`r`n")
$message