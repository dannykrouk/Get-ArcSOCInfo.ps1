[CmdletBinding()]
param(
	[Parameter(Mandatory = $false)]
	[ValidateRange(1, 86400)]
	[int]$IntervalSeconds = 10,

	[Parameter(Mandatory = $false)]
	[ValidateRange(1, 525600)]
	[int]$DurationMinutes
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

if (Test-Path -Path $outputFile) {
	$archiveTimestamp = (Get-Item -Path $outputFile).LastWriteTime.ToString('yyyyMMdd_HHmmss')
	$archiveName = [System.IO.Path]::GetFileNameWithoutExtension($outputFile) + "_$archiveTimestamp.csv"
	$archivePath = Join-Path -Path $PSScriptRoot -ChildPath $archiveName
	Rename-Item -Path $outputFile -NewName $archivePath
	Write-Verbose "Existing output file renamed to '$archivePath'."
}

$expectedHeader = 'Timestamp,Cycle,ServiceName,ProcessCount,SumProcessorUtilization,SumPrivateBytes,SumVirtualBytes,SumThreadCount,SumHandleCount'

$expectedHeader | Set-Content -Path $outputFile

$cycle = 1
$endTime = if ($PSBoundParameters.ContainsKey('DurationMinutes')) { (Get-Date).AddMinutes($DurationMinutes) } else { $null }

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
	if ($null -ne $endTime -and (Get-Date) -ge $endTime) {
		Write-Verbose "DurationMinutes ($DurationMinutes) elapsed. Exiting."
		break
	}

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
