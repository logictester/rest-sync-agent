
Function Add-User {
  Param ($uri, $method, $header, $body)
  Try {     
    Invoke-RestMethod -Uri $uri -body $body -Method $method -ContentType 'application/json' -Headers $header
  }
  Catch
  {
    ("$_" -replace '"', '') # -> $_.ErrorDetails.Message without quotes
  }
}

Function Write-Timestamp {
  Param ($msg)
  "$((Get-Date -format "o").Remove(22,5)) - $msg"
}
