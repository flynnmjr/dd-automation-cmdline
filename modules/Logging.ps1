<#
.SYNOPSIS
    Provides logging capabilities for scripts.

.DESCRIPTION
    Contains functions to initialize a log file and write timestamped log entries with severity levels.
#>

# Private variable to store the current log file path
#$script:LogFilePath = $null

function Initialize-Log {
    [CmdletBinding()]
    param(
        [string]$LogDirectory = (Join-Path $PSScriptRoot '..\logs'),
        [string]$LogFileName = 'log.txt',
        [switch]$Overwrite
    )

    if (-not (Test-Path -Path $LogDirectory)) {
        New-Item -Path $LogDirectory -ItemType Directory -Force | Out-Null
    }
    $script:LogFilePath = Join-Path -Path $LogDirectory -ChildPath $LogFileName
    if ($Overwrite -and (Test-Path -Path $script:LogFilePath)) {
        Remove-Item -Path $script:LogFilePath -Force
    }
    $header = "===== Log started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ====="
    Add-Content -Path $script:LogFilePath -Value $header
}

function Write-Log {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO','WARNING','ERROR','DEBUG')]
        [string]$Level = 'INFO'
    )
    if (-not $script:LogFilePath) {
        Write-Host "Log file not initialized. Call Initialize-Log before writing logs." 
    }
    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "$timestamp [$Level] $Message"
    # Append entry to log file
    Add-Content -Path $script:LogFilePath -Value $entry
    # Also output to console
    switch ($Level) {
        'INFO'    { Write-Host $entry }
        'WARNING' { Write-Warning $Message }
        'ERROR'   { Write-Error $Message }
    }
}

