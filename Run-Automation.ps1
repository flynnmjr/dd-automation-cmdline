<#
.SYNOPSIS
    Main entry point for DefectDojo Automation Command Line Interface (CLI).
.DESCRIPTION
    Runs configured security automation tasks (TenableWAS, SonarQube, BurpSuite, GitHub) 
    in a headless mode suitable for cron jobs or scheduled tasks.
    Sends completion status via webhook if configured.
.PARAMETER ConfigPath
    Optional path to a specific config.psd1 file. Defaults to config/config.psd1.
.EXAMPLE
    .\Run-Automation.ps1
.EXAMPLE
    .\Run-Automation.ps1 -ConfigPath "C:\Configs\project-a.psd1"
#>

[CmdletBinding()]
param(
    [string]$ConfigPath
)

# Enforce PowerShell 7.2+
if ($PSVersionTable.PSVersion -lt [version]"7.2") {
    Write-Error "PowerShell 7.2+ is required. Current version: $($PSVersionTable.PSVersion)"
    exit 1
}

$ErrorActionPreference = 'Stop'

# Load Modules
$scriptDir = $PSScriptRoot
. (Join-Path $scriptDir 'modules\Logging.ps1')
. (Join-Path $scriptDir 'modules\Config.ps1')
. (Join-Path $scriptDir 'modules\EnvValidator.ps1')
. (Join-Path $scriptDir 'modules\TenableWAS.ps1')
. (Join-Path $scriptDir 'modules\BurpSuite.ps1')
. (Join-Path $scriptDir 'modules\GitHub.ps1')
. (Join-Path $scriptDir 'modules\DefectDojo.ps1')
. (Join-Path $scriptDir 'modules\Sonarqube.ps1')
. (Join-Path $scriptDir 'modules\Uploader.ps1')
. (Join-Path $scriptDir 'modules\AutomationWorkflow.ps1')
. (Join-Path $scriptDir 'modules\Webhooks.ps1')

# Initialize Logging
try {
    Initialize-Log -LogDirectory (Join-Path $scriptDir 'logs') -LogFileName 'Run-Automation.log' -Overwrite
    Write-Log -Message "Run-Automation started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level 'INFO'
} catch {
    Write-Error "Failed to initialize logging: $_"
    exit 1
}

# Execution Block
try {
    # 1. Load Configuration
    if ($PSBoundParameters.ContainsKey('ConfigPath')) {
        Write-Log -Message "Loading configuration from User provided path: $ConfigPath" -Level 'INFO'
        $config = Get-Config -ConfigPath $ConfigPath
    } else {
        $config = Get-Config
    }
    
    # Valdiate Config
    try {
        Validate-Config -Config $config | Out-Null
    } catch {
        Write-Log -Message "Configuration validation failed: $_" -Level 'ERROR'
        # Can't send webhook if config is invalid, so just exit
        exit 1
    }

    # 2. Validate Environment
    try {
        Validate-Environment
    } catch {
        Write-Log -Message "Environment validation failed: $_" -Level 'ERROR'
        # Attempt to send webhook if we have a valid config object at this point
        if($config.Webhooks.Enabled) {
            $errResult = @{ Tool = 'Environment'; Status = 'Error'; Message = "Environment validation failed: $_" }
            Send-WebhookNotification -Results @($errResult) -Config $config
        }
        exit 1
    }

    $workflowResults = @()

    # 3. Run Tools
    
    # TenableWAS
    if ($config.Tools.TenableWAS) {
        $workflowResults += Invoke-TenableWASWorkflow -Config $config
    }

    # SonarQube
    if ($config.Tools.SonarQube) {
        $workflowResults += Invoke-SonarQubeWorkflow -Config $config
    }

    # BurpSuite
    if ($config.Tools.BurpSuite) {
        $workflowResults += Invoke-BurpSuiteWorkflow -Config $config
    }

    # GitHub (CodeQL, SecretScanning, Dependabot)
    if ($config.Tools.GitHub.Values -contains $true) {
        $githubResults = Invoke-GitHubWorkflow -Config $config
        if ($githubResults) {
            $workflowResults += $githubResults
        }
    }

    # 4. Final Reporting
    Write-Log -Message "All automation tasks completed." -Level 'INFO'
    
    if ($workflowResults.Count -gt 0) {
        Send-WebhookNotification -Results $workflowResults -Config $config
    } else {
        Write-Log -Message "No tools were enabled or ran." -Level 'WARNING'
    }

    Write-Log -Message "Run-Automation finished at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level 'INFO'

} catch {
    Write-Log -Message "An unexpected fatal error occurred: $_" -Level 'ERROR'
    try {
        if ($config -and $config.Webhooks.Enabled) {
             $fatalResult = @{ Tool = 'System'; Status = 'Error'; Message = "Fatal Script Error: $_" }
             Send-WebhookNotification -Results @($fatalResult) -Config $config
        }
    } catch {
        Write-Error "Failed to send fatal error webhook: $_"
    }
    exit 1
}
