# ScriptBlock Generalized
Param($api, $user, $path)

#Import-Module "$path\..\general\basic-helpers" -Force

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
  "$((Get-Date -format "o").Remove(22,5)) - $msg"
}

$uri = $api.uri

if($api.method -eq "DELETE")
{
    $uri = $api.uri + "/" + $user.userName

   # $message += "uri = $uri`n"

    $body = ""
}


$body = (ConvertTo-Json $user)
$message = Write-Timestamp "[ REST ] - Sending $($api.method) to $uri`r`n$body`r`n"

$timeTaken = Measure-Command {
  $response = Invoke-CustomWeb -Uri $uri -Header $api.hdr -Method $api.method -Body $body
}

$jsonResponse = ConvertTo-Json $response.Message | % { [System.Text.RegularExpressions.Regex]::Unescape($_) }
$message += Write-Timestamp "[ REST ] - Result - $($response.StatusCode) : $jsonResponse`r`n" # unescape for exception
$message += Write-Timestamp "Actual time taken (in milliseconds): $($timeTaken.TotalMilliseconds)`r`n" 
$message += "" + "-"*120
$message
