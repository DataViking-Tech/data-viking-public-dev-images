<#
.SYNOPSIS
    Godot Render Watcher - GPU-accelerated Godot rendering for Linux container

.DESCRIPTION
    Monitors temp/godot-render-queue/ for render jobs from the Linux container
    and executes them with Godot on the Windows host (with GPU access).
    Supports parallel job processing for better GPU utilization.

.PARAMETER GodotPath
    Path to Godot executable. Auto-detected if not specified.

.PARAMETER ProjectPath
    Path to Godot project. Defaults to ./project

.PARAMETER PollInterval
    Seconds between queue checks. Default: 1

.PARAMETER MaxParallel
    Maximum concurrent Godot instances. Default: 4

.EXAMPLE
    .\godot_render_watcher.ps1
    .\godot_render_watcher.ps1 -MaxParallel 6
    .\godot_render_watcher.ps1 -GodotPath "C:\Godot\Godot.exe"
#>

param(
    [string]$GodotPath = "",
    [string]$ProjectPath = "",
    [int]$PollInterval = 1,
    [int]$JobTimeout = 120,
    [int]$MaxParallel = 4
)

$ErrorActionPreference = "Stop"

# Paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$QueueDir = Join-Path $ScriptDir "godot-render-queue"
$OutputDir = Join-Path $ScriptDir "godot-render-output"
$LockDir = Join-Path $ScriptDir "godot-render-locks"
$HeartbeatFile = Join-Path $ScriptDir "godot-watcher-heartbeat"
$LogFile = Join-Path $ScriptDir "godot-render-watcher.log"

if (-not $ProjectPath) {
    $ProjectPath = Join-Path $RepoRoot "project"
}

# Track active jobs
$script:ActiveJobs = @{}

# Ensure directories exist
New-Item -ItemType Directory -Force -Path $QueueDir | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
New-Item -ItemType Directory -Force -Path $LockDir | Out-Null

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $LogFile -Value $logMessage
}

function Find-Godot {
    param([string]$GodotPathParam)

    # Check if already specified
    if ($GodotPathParam -and (Test-Path $GodotPathParam)) {
        return $GodotPathParam
    }

    # Check environment variable
    if ($env:GODOT_PATH -and (Test-Path $env:GODOT_PATH)) {
        return $env:GODOT_PATH
    }

    # Common installation paths
    $searchPaths = @(
        "C:\Program Files\Godot\Godot.exe",
        "C:\Program Files (x86)\Godot\Godot.exe",
        "C:\Godot\Godot.exe",
        "$env:LOCALAPPDATA\Godot\Godot.exe",
        # Steam
        "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\Godot.exe",
        "C:\Program Files (x86)\Steam\steamapps\common\Godot\Godot.exe",
        # Scoop
        "$env:USERPROFILE\scoop\apps\godot\current\Godot.exe",
        # Chocolatey
        "C:\ProgramData\chocolatey\bin\godot.exe"
    )

    # Also search for versioned executables
    $versionedPaths = @(
        "C:\Program Files\Godot*\*.exe",
        "C:\Godot*\*.exe",
        "$env:LOCALAPPDATA\Godot*\*.exe"
    )

    foreach ($path in $searchPaths) {
        if (Test-Path $path) {
            return $path
        }
    }

    foreach ($pattern in $versionedPaths) {
        $found = Get-ChildItem -Path $pattern -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            return $found.FullName
        }
    }

    return $null
}

function Get-GpuName {
    try {
        $gpu = Get-WmiObject Win32_VideoController | Select-Object -First 1
        return $gpu.Name
    } catch {
        return "Unknown GPU"
    }
}

# Try to acquire a lock on a job file (returns $true if successful)
function Acquire-JobLock {
    param([string]$JobId)

    $lockFile = Join-Path $LockDir "$JobId.lock"

    try {
        # Try to create lock file exclusively
        $null = [System.IO.File]::Open($lockFile, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        return $true
    }
    catch {
        return $false
    }
}

# Release a job lock
function Release-JobLock {
    param([string]$JobId)

    $lockFile = Join-Path $LockDir "$JobId.lock"
    Remove-Item $lockFile -Force -ErrorAction SilentlyContinue
}

function Update-Heartbeat {
    param([string]$HeartbeatPath)
    Set-Content -Path $HeartbeatPath -Value (Get-Date -Format "o")
}

# Script block to process a single job (runs in background)
$ProcessJobScript = {
    param(
        [string]$JobFile,
        [string]$GodotExe,
        [string]$ProjectPath,
        [string]$OutputDir,
        [int]$JobTimeout
    )

    function Get-GpuName {
        try {
            $gpu = Get-WmiObject Win32_VideoController | Select-Object -First 1
            return $gpu.Name
        } catch {
            return "Unknown GPU"
        }
    }

    $jobId = [System.IO.Path]::GetFileNameWithoutExtension($JobFile)

    try {
        # Read job configuration
        $job = Get-Content $JobFile -Raw | ConvertFrom-Json

        # Build output path
        $outputFile = Join-Path $OutputDir "$jobId.png"
        $resultFile = Join-Path $OutputDir "${jobId}_result.json"

        # Build Godot command
        $bridgeScript = "res://tools/bridge_renderer.gd"

        $args = @(
            "--position", "10000,10000",
            "--path", $ProjectPath,
            "-s", $bridgeScript,
            "--",
            "--job-file=$JobFile",
            "--output=$outputFile"
        )

        $startTime = Get-Date

        # Run Godot with timeout
        $stdoutFile = Join-Path $OutputDir "${jobId}_stdout.txt"
        $stderrFile = Join-Path $OutputDir "${jobId}_stderr.txt"

        $process = Start-Process -FilePath $GodotExe -ArgumentList $args -WindowStyle Hidden -PassThru -Wait:$false `
            -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile

        $completed = $process.WaitForExit($JobTimeout * 1000)

        $endTime = Get-Date
        $renderTime = ($endTime - $startTime).TotalSeconds

        if (-not $completed) {
            $process.Kill()
            throw "Job timed out after $JobTimeout seconds"
        }

        # Check output file first - if it exists, the render succeeded
        if (Test-Path $outputFile) {
            # Success!
        }
        elseif ($process.ExitCode -ne 0) {
            $stderrContent = ""
            if (Test-Path $stderrFile) {
                $stderrContent = Get-Content $stderrFile -Raw -ErrorAction SilentlyContinue
            }
            $errorMsg = "Godot exited with code $($process.ExitCode)"
            if ($stderrContent) {
                $errorMsg += ": $stderrContent"
            }
            throw $errorMsg
        }
        else {
            throw "Output file not created: $outputFile"
        }

        # Write success result
        $result = @{
            job_id = $jobId
            status = "success"
            output_file = "$jobId.png"
            render_time_seconds = [math]::Round($renderTime, 2)
            gpu_name = Get-GpuName
            error = $null
        }

        $result | ConvertTo-Json | Set-Content $resultFile

        # Keep temp files for debugging animation captures
        # Remove-Item $stdoutFile -Force -ErrorAction SilentlyContinue
        # Remove-Item $stderrFile -Force -ErrorAction SilentlyContinue

        # Remove job from queue
        Remove-Item $JobFile -Force

        return @{ JobId = $jobId; Status = "success"; Time = $renderTime }

    } catch {
        # Write error result
        $result = @{
            job_id = $jobId
            status = "error"
            output_file = $null
            render_time_seconds = 0
            gpu_name = Get-GpuName
            error = $_.ToString()
        }

        $resultFile = Join-Path $OutputDir "${jobId}_result.json"
        $result | ConvertTo-Json | Set-Content $resultFile

        # Remove failed job from queue
        Remove-Item $JobFile -Force -ErrorAction SilentlyContinue

        return @{ JobId = $jobId; Status = "error"; Error = $_.ToString() }
    }
}

# Main
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Godot Render Watcher (Parallel)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Find Godot
$GodotPath = Find-Godot -GodotPathParam $GodotPath
if (-not $GodotPath) {
    Write-Host "ERROR: Godot not found!" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please specify the path:" -ForegroundColor Yellow
    Write-Host "  .\godot_render_watcher.ps1 -GodotPath 'C:\Path\To\Godot.exe'"
    Write-Host ""
    Write-Host "Or set the GODOT_PATH environment variable"
    exit 1
}

$GpuName = Get-GpuName

Write-Log "Godot found: $GodotPath"
Write-Log "Project path: $ProjectPath"
Write-Log "Queue directory: $QueueDir"
Write-Log "Output directory: $OutputDir"
Write-Log "Max parallel: $MaxParallel"
Write-Log "GPU: $GpuName"
Write-Host ""
Write-Host "Watching for render jobs (parallel mode)..." -ForegroundColor Green
Write-Host "Press Ctrl+C to stop" -ForegroundColor Gray
Write-Host ""

# Main loop
$jobsProcessed = 0
while ($true) {
    try {
        Update-Heartbeat -HeartbeatPath $HeartbeatFile

        # Clean up completed jobs
        $completedJobs = @()
        foreach ($jobId in $script:ActiveJobs.Keys) {
            $psJob = $script:ActiveJobs[$jobId]
            if ($psJob.State -eq 'Completed') {
                $result = Receive-Job $psJob
                Remove-Job $psJob
                Release-JobLock $jobId
                $completedJobs += $jobId
                $jobsProcessed++

                if ($result.Status -eq "success") {
                    Write-Log "[$jobId] Complete in $([math]::Round($result.Time, 1))s" "SUCCESS"
                } else {
                    Write-Log "[$jobId] Failed: $($result.Error)" "ERROR"
                }
            }
            elseif ($psJob.State -eq 'Failed') {
                $errorInfo = $psJob.ChildJobs[0].JobStateInfo.Reason.Message
                Remove-Job $psJob
                Release-JobLock $jobId
                $completedJobs += $jobId
                Write-Log "[$jobId] Job failed: $errorInfo" "ERROR"
            }
        }
        foreach ($jobId in $completedJobs) {
            $script:ActiveJobs.Remove($jobId)
        }

        # Check for new jobs if we have capacity
        $activeCount = $script:ActiveJobs.Count
        if ($activeCount -lt $MaxParallel) {
            $jobs = Get-ChildItem -Path $QueueDir -Filter "*.json" -ErrorAction SilentlyContinue |
                    Sort-Object CreationTime |
                    Select-Object -First ($MaxParallel - $activeCount)

            foreach ($jobFile in $jobs) {
                $jobId = [System.IO.Path]::GetFileNameWithoutExtension($jobFile.Name)

                # Skip if already processing
                if ($script:ActiveJobs.ContainsKey($jobId)) { continue }

                # Try to acquire lock
                if (-not (Acquire-JobLock $jobId)) { continue }

                Write-Log "[$jobId] Starting..." "INFO"

                # Start background job
                $psJob = Start-Job -ScriptBlock $ProcessJobScript -ArgumentList @(
                    $jobFile.FullName,
                    $GodotPath,
                    $ProjectPath,
                    $OutputDir,
                    $JobTimeout
                )

                $script:ActiveJobs[$jobId] = $psJob
            }
        }

        # Show status periodically
        if ($script:ActiveJobs.Count -gt 0) {
            $runningIds = $script:ActiveJobs.Keys -join ", "
            Write-Host "`rActive: $($script:ActiveJobs.Count)/$MaxParallel [$runningIds]     " -NoNewline
        }

        Start-Sleep -Seconds $PollInterval

    } catch {
        Write-Log "Error in main loop: $_" "ERROR"
        Start-Sleep -Seconds 5
    }
}
