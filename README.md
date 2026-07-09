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

## Usage

```powershell
# Run with the default 10-second polling interval
.\Get-ArcSocInfo.ps1

# Run with a custom interval (e.g., 30 seconds)
.\Get-ArcSocInfo.ps1 -IntervalSeconds 30
```

The script runs indefinitely. Press `Ctrl+C` to stop it.

## Output

The CSV is written to the same directory as the script. The file name encodes the machine name and UTC offset:

```
MACHINENAME_arcsoc_info_gmt_-0700.csv
```

> **Note:** CSV output files are excluded from this repository via `.gitignore`.

## Legacy CSV Upgrade

If an existing CSV from a previous version (missing `Cycle`, `SumThreadCount`, or `SumHandleCount` columns) is detected, the script automatically upgrades it to the current schema before appending new data.
