# ScriptBlock Generalized
Param($api, $user, $path)

Import-Module "$path\..\general\basic-helpers" -Force

$body = (ConvertTo-Json $user)
$message = Write-Timestamp "[ REST ] - Sending $($api.method) - $body`n"

$timeTaken = Measure-Command {
  $response = Add-User -Uri $api.uri -Header $api.hdr -Method $api.method -Body $body
}
      
$jsonResponse = ConvertTo-Json $response | % { [System.Text.RegularExpressions.Regex]::Unescape($_) }
$message += Write-Timestamp "[ REST ] - Result - $jsonResponse`n" # unescape for exception
$message += Write-Timestamp "Actual time taken (in milliseconds): $($timeTaken.TotalMilliseconds)`n" 
$message += "" + "-"*120
$message
