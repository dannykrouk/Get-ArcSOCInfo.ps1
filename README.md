# Get-ArcSocInfo

A PowerShell script that continuously monitors **ArcSOC.exe** processes and logs performance metrics to a CSV file.

## Description

`Get-ArcSocInfo.ps1` polls running `ArcSOC.exe` processes at a configurable interval and appends aggregated metrics — grouped by service name — to a CSV file named after the local machine and UTC offset (e.g., `MACHINENAME_arcsoc_info_gmt_-0700.csv`).

Each polling cycle records:

| Column | Description |
|---|---|
| `Timestamp` | Date/time of the sample (`yyyy-MM-dd HH:mm:ss`) |
| `Cycle` | Incrementing poll cycle number |
| `ServiceName` | ArcGIS service name parsed from the process command line |
| `ProcessCount` | Number of `ArcSOC.exe` processes for this service |
| `SumProcessorUtilization` | Combined CPU utilization (%) across processes |
| `SumPrivateBytes` | Combined private memory (bytes) |
| `SumVirtualBytes` | Combined virtual memory (bytes) |
| `SumThreadCount` | Combined thread count |
| `SumHandleCount` | Combined handle count |

If no `ArcSOC.exe` processes are found during a cycle, a null row is written to preserve the timeline.

## Requirements

- Windows PowerShell 5.1 or PowerShell 7+
- Must be run on the ArcGIS Server machine being monitored
- Requires permission to query WMI/CIM (`Win32_Process`, `Win32_PerfFormattedData_PerfProc_Process`)

## Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `-IntervalSeconds` | `int` | `10` | Seconds to wait between polling cycles (1–86400). |
| `-DurationMinutes` | `int` | *(none)* | If specified, the script runs for this many minutes then exits gracefully (1–525600). Omit to run indefinitely. |

## Usage

```powershell
# Run indefinitely with the default 10-second polling interval
.\Get-ArcSocInfo.ps1

# Run with a custom interval
.\Get-ArcSocInfo.ps1 -IntervalSeconds 30

# Run for a fixed duration (e.g., 30 minutes) then exit
.\Get-ArcSocInfo.ps1 -DurationMinutes 30

# Custom interval and fixed duration
.\Get-ArcSocInfo.ps1 -IntervalSeconds 15 -DurationMinutes 60
```

When no `-DurationMinutes` is specified the script runs indefinitely. Press `Ctrl+C` to stop it early.


## Output

The CSV is written to the same directory as the script. The file name encodes the machine name and UTC offset:

```
MACHINENAME_arcsoc_info_gmt_-0700.csv
```

> **Note:** CSV output files are excluded from this repository via `.gitignore`.

## Archiving Existing Output

On startup, if an output CSV from a previous run already exists, the script renames it by appending the file's last-write timestamp before creating a fresh file. For example:

```
MACHINENAME_arcsoc_info_gmt_-0700.csv  →  MACHINENAME_arcsoc_info_gmt_-0700_20260709_143022.csv
```

This means each run produces its own unmodified CSV, making it safe to run the script repeatedly without losing prior data.
