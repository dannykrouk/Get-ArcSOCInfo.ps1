[CmdletBinding()]
param(
	[Parameter(Mandatory = $false)]
	[ValidateRange(1, 86400)]
	[int]$IntervalSeconds = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$machineName = $env:COMPUTERNAME
$utcOffset = [TimeZoneInfo]::Local.GetUtcOffset((Get-Date))
$offsetSign = if ($utcOffset.Ticks -lt 0) { '-' } else { '+' }
$offsetTotalMinutes = [int][math]::Abs($utcOffset.TotalMinutes)
$offsetHours = [int]($offsetTotalMinutes / 60)
$offsetMinutes = $offsetTotalMinutes % 60
$gmtOffset = "{0}{1:00}{2:00}" -f $offsetSign, $offsetHours, $offsetMinutes
$outputFile = Join-Path -Path $PSScriptRoot -ChildPath ("{0}_arcsoc_info_gmt_{1}.csv" -f $machineName, $gmtOffset)
$expectedHeader = 'Timestamp,Cycle,ServiceName,ProcessCount,SumProcessorUtilization,SumPrivateBytes,SumVirtualBytes,SumThreadCount,SumHandleCount'
$expectedQuotedHeader = '"Timestamp","Cycle","ServiceName","ProcessCount","SumProcessorUtilization","SumPrivateBytes","SumVirtualBytes","SumThreadCount","SumHandleCount"'
$legacyHeaderV1 = 'Timestamp,ServiceName,ProcessCount,SumProcessorUtilization,SumPrivateBytes,SumVirtualBytes'
$legacyHeaderV2 = 'Timestamp,ServiceName,ProcessCount,SumProcessorUtilization,SumPrivateBytes,SumVirtualBytes,SumThreadCount,SumHandleCount'

if (-not (Test-Path -Path $outputFile)) {
	$expectedHeader | Set-Content -Path $outputFile
}
else {
	$headerLine = Get-Content -Path $outputFile -TotalCount 1
	if ($headerLine -eq $legacyHeaderV1 -or $headerLine -eq $legacyHeaderV2) {
		$legacyData = Import-Csv -Path $outputFile
		$cycleValue = 1
		$upgradedObjects = foreach ($row in $legacyData) {
			$obj = [ordered]@{
				Timestamp = $row.Timestamp
				Cycle = $cycleValue
				ServiceName = $row.ServiceName
				ProcessCount = $row.ProcessCount
				SumProcessorUtilization = $row.SumProcessorUtilization
				SumPrivateBytes = $row.SumPrivateBytes
				SumVirtualBytes = $row.SumVirtualBytes
				SumThreadCount = $null
				SumHandleCount = $null
			}

			if ($headerLine -eq $legacyHeaderV2) {
				$obj.SumThreadCount = $row.SumThreadCount
				$obj.SumHandleCount = $row.SumHandleCount
			}

			$cycleValue++
			[pscustomobject]$obj
		}

		if (@($upgradedObjects).Count -gt 0) {
			$upgradedObjects | Export-Csv -Path $outputFile -NoTypeInformation
		}
		else {
			$expectedHeader | Set-Content -Path $outputFile
		}
	}
}

if ((Get-Content -Path $outputFile -TotalCount 1) -notin @($expectedHeader, $expectedQuotedHeader)) {
	throw "Unexpected CSV header in '$outputFile'."
}

$cycle = 1

function Get-ServiceNameFromCommandLine {
	param(
		[Parameter(Mandatory = $false)]
		[string]$CommandLine
	)

	if ([string]::IsNullOrWhiteSpace($CommandLine)) {
		return 'UnknownService'
	}

	$pattern = '(?i)-DService(?:=|\s+)(?:"([^"]+)"|''([^'']+)''|([^\s]+))'
	$match = [regex]::Match($CommandLine, $pattern)

	if (-not $match.Success) {
		return 'UnknownService'
	}

	foreach ($groupIndex in 1, 2, 3) {
		$value = $match.Groups[$groupIndex].Value
		if (-not [string]::IsNullOrWhiteSpace($value)) {
			return $value
		}
	}

	return 'UnknownService'
}

while ($true) {
	$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

	$arcSocProcesses = Get-CimInstance -ClassName Win32_Process -Filter "Name = 'ArcSOC.exe'"
	if (-not $arcSocProcesses) {
		[pscustomobject]@{
			Timestamp = $timestamp
			Cycle = $cycle
			ServiceName = $null
			ProcessCount = $null
			SumProcessorUtilization = $null
			SumPrivateBytes = $null
			SumVirtualBytes = $null
			SumThreadCount = $null
			SumHandleCount = $null
		} | Export-Csv -Path $outputFile -NoTypeInformation -Append

		Start-Sleep -Seconds $IntervalSeconds
		$cycle++
		continue
	}

	$perfRows = Get-CimInstance -ClassName Win32_PerfFormattedData_PerfProc_Process

	$perfByPid = @{}
	foreach ($row in $perfRows) {
		if ($row.IDProcess -gt 0) {
			$perfByPid[[int]$row.IDProcess] = [double]$row.PercentProcessorTime
		}
	}

	$records = foreach ($process in $arcSocProcesses) {
		$serviceName = Get-ServiceNameFromCommandLine -CommandLine $process.CommandLine

		[pscustomobject]@{
			ServiceName = $serviceName
			ProcessorUtilization = if ($perfByPid.ContainsKey([int]$process.ProcessId)) { $perfByPid[[int]$process.ProcessId] } else { 0.0 }
			PrivateBytes = [double]$process.PrivatePageCount
			VirtualBytes = [double]$process.VirtualSize
			ThreadCount = [int64]$process.ThreadCount
			HandleCount = [int64]$process.HandleCount
		}
	}

	if (@($records).Count -gt 0) {
		$rowsToAppend = $records |
			Group-Object -Property ServiceName |
			ForEach-Object {
				[pscustomobject]@{
					Timestamp = $timestamp
					Cycle = $cycle
					ServiceName = $_.Name
					ProcessCount = $_.Count
					SumProcessorUtilization = [math]::Round((($_.Group | Measure-Object -Property ProcessorUtilization -Sum).Sum), 2)
					SumPrivateBytes = [int64](($_.Group | Measure-Object -Property PrivateBytes -Sum).Sum)
					SumVirtualBytes = [int64](($_.Group | Measure-Object -Property VirtualBytes -Sum).Sum)
					SumThreadCount = [int64](($_.Group | Measure-Object -Property ThreadCount -Sum).Sum)
					SumHandleCount = [int64](($_.Group | Measure-Object -Property HandleCount -Sum).Sum)
				}
			}

		$rowsToAppend | Export-Csv -Path $outputFile -NoTypeInformation -Append
	}

	Start-Sleep -Seconds $IntervalSeconds
	$cycle++
}
