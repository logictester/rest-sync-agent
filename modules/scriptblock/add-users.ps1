# ScriptBlockAddUser
Param($api, $user, $path)

Import-Module "$path\modules\basic-helpers" -Force

$body = (ConvertTo-Json $user)
$message = Write-Timestamp "[REST] - Sending data - $body`n"

$timeTaken = Measure-Command {
  $response = Add-User -Uri $api.uri -Header $api.hdr -Method $api.method -Body $body
}
      
$jsonResponse = ConvertTo-Json $response | % { [System.Text.RegularExpressions.Regex]::Unescape($_) }
$message += Write-Timestamp "[REST] - Server response - $jsonResponse`n" # unescape for exception
$message += Write-Timestamp "Actual time taken: $($timeTaken.TotalMilliseconds) milliseconds`n" 
$message += "" + "-"*120
$message