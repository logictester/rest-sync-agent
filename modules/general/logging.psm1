#https://stackoverflow.com/questions/4647756/is-there-a-way-to-specify-a-font-color-when-using-write-output
function Write-ColorOutput
{
    [CmdletBinding()]
    Param(
         [Parameter(Mandatory=$False,Position=1,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)][Object] $Object,
         [Parameter(Mandatory=$False,Position=2,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)][ConsoleColor] $ForegroundColor,
         [Parameter(Mandatory=$False,Position=3,ValueFromPipeline=$True,ValueFromPipelinebyPropertyName=$True)][ConsoleColor] $BackgroundColor,
         [Switch]$NoNewline
    )    

    # Save previous colors
    $previousForegroundColor = $host.UI.RawUI.ForegroundColor
    $previousBackgroundColor = $host.UI.RawUI.BackgroundColor

    # Set BackgroundColor if available
    if($BackgroundColor -ne $null)
    { 
       $host.UI.RawUI.BackgroundColor = $BackgroundColor
    }

    # Set $ForegroundColor if available
    if($ForegroundColor -ne $null)
    {
        $host.UI.RawUI.ForegroundColor = $ForegroundColor
    }

    # Always write (if we want just a NewLine)
    if($Object -eq $null)
    {
        $Object = ""
    }

    if($NoNewline)
    {
        [Console]::Write($Object)
    }
    else
    {
        Write-Output $Object
    }

    # Restore previous colors
    $host.UI.RawUI.ForegroundColor = $previousForegroundColor
    $host.UI.RawUI.BackgroundColor = $previousBackgroundColor
}

# Adds timestamps 
Function Write-Log {
  Param([Parameter(Mandatory=$false)] [String]$message = "",
        [Parameter(Mandatory=$false)] [String]$TextColor = (get-host).ui.rawui.ForegroundColor,
        [Switch]$NoNewline)

      $timestamp = (Get-Date -format "o").Remove(22,5) # Remove 5 characters starting index 22 
      if($NoNewline)
      {
        Write-ColorOutput "$timestamp - $message" -ForegroundColor $TextColor -NoNewline
      }
      else {
        Write-ColorOutput "$timestamp - $message" -ForegroundColor $TextColor
      }
}

# Check and create  folder
Function Confirm-Folder {
Param($Name, $Path)
    if(!(Test-Path -Path $Path )){
        New-Item -ItemType directory -Path $Path -ErrorAction Stop | Out-Null
        Write-Warning "$Name folder does not exist."
        Write-Warning "$Name folder created: $Path"
    }
}

Function Get-LogLocation {
Param($Path, 
      $CustomName = "rest-sync")
  Confirm-Folder -Name "Log" -Path $Path
  $LogFile = $Path + $(get-date -format "yyyyMMddTHHmmss") + "_" + $CustomName + ".log"
  $LogFile
}

Function Get-HostDetails {

  $Result = @()
  $CombinedResults = New-Object -TypeName PSObject

  $PropertyList1 = 'PSComputerName', 'Name', 'Manufacturer', 'MaxClockSpeed', 'NumberOfCores', 'NumberOfLogicalProcessors'
  $HostDetails1 = Get-WmiObject -Class Win32_Processor | Select-Object $PropertyList1

  $PropertyList2 = 'Caption', 'Version', 'BuildNumber', 'Organization', 'CSName', 'Status'
  $HostDetails2 = [pscustomobject](GET-CIMInstance Win32_OperatingSystem | Select-Object $PropertyList2)

  $PropertyList3 = 'TotalVirtualMemorySize', 'TotalVisibleMemorySize', 'FreePhysicalMemory', 'FreeSpaceInPagingFiles', 'FreeVirtualMemory'
  $HostDetails3 = [pscustomobject](GET-CIMInstance Win32_OperatingSystem | Select-Object $PropertyList3)

  $PropertyList1 | % {
   Add-Member -InputObject $CombinedResults -MemberType NoteProperty -Name $_ -Value $HostDetails1.$_
  }

  $PropertyList2 | % {
    $CombinedResults | Add-Member -MemberType NoteProperty -Name $_  -Value $HostDetails2.$_
  }

  $PropertyList3 | % {
    $CombinedResults | Add-Member -MemberType NoteProperty -Name $_  -Value (Format-Memory $HostDetails3.$_)
  }

  Write-Delimiter
  Write-Output " SYSTEM INFORMATION"
  Write-Delimiter
  ($CombinedResults | Out-String).Trim()
  Write-Delimiter
  #(ConvertTo-Json $CombinedResults) -replace '"', '' -replace ',',''

}

Function Write-Delimiter {
  Write-Output ("" + "-"*130)
}
#https://theposhwolf.com/howtos/Format-Bytes/
Function Format-Memory {
    Param
    (
        [Parameter(
            ValueFromPipeline = $true
        )]
        [ValidateNotNullOrEmpty()]
        [float]$number
    )
    Begin{
        $sizes = 'KB','MB','GB','TB','PB'
    }
    Process {
        # New for loop
        for($x = 0;$x -lt $sizes.count; $x++){
            if ($number -lt "1$($sizes[$x])"){
                if ($x -eq 0){
                    return "$number B"
                } else {
                    $num = $number / "1$($sizes[$x-1])"
                    $num = "{0:N2}" -f $num
                    return "$num $($sizes[$x])"
                }
            }
        }
        <# Original way
        if ($number -lt 1KB) {
            return "$number B"
        } elseif ($number -lt 1MB) {
            $number = $number / 1KB
            $number = "{0:N2}" -f $number
            return "$number KB"
        } elseif ($number -lt 1GB) {
            $number = $number / 1MB
            $number = "{0:N2}" -f $number
            return "$number MB"
        } elseif ($number -lt 1TB) {
            $number = $number / 1GB
            $number = "{0:N2}" -f $number
            return "$number GB"
        } elseif ($number -lt 1PB) {
            $number = $number / 1TB
            $number = "{0:N2}" -f $number
            return "$number TB"
        } else {
            $number = $number / 1PB
            $number = "{0:N2}" -f $number
            return "$number PB"
        }
        #>
    }
    End{}
}