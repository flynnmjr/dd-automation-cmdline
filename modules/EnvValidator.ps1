
<#
.SYNOPSIS
    Validates that required environment variables are set for enabled tools.

.DESCRIPTION
    Checks for presence of required environment variables based on which tools are enabled in the configuration.
    Only validates environment variables for tools that are enabled.
    The `$Test` switch can be used to enable debug logging, providing additional details about the validation process.
#>

. (Join-Path $PSScriptRoot 'Logging.ps1')
. (Join-Path $PSScriptRoot 'Config.ps1')

# Define tool-specific environment variable requirements
$TOOL_ENV_VARS = @{
    'DefectDojo' = @('DOJO_API_KEY')
    'TenableWAS' = @('TENWAS_ACCESS_KEY', 'TENWAS_SECRET_KEY')
    #'SonarQube'  = @('SONARQUBE_API_TOKEN')
    'BurpSuite'  = @('BURP_API_KEY')
    'GitHub'     = @('GITHUB_PAT')
}

#TODO: Possibly needed for pester tests. Validate when Pester working
#Initialize-Log -LogDirectory (Join-Path $scriptDir '..\logs') -LogFileName 'EnvValidator.log' -Overwrite

function Ensure-TypeAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TypeName,
        [Parameter(Mandatory = $false)]
        [string]$AssemblyName
    )

    if ($TypeName -as [type]) {
        return $true
    }

    if (-not $AssemblyName) {
        return $false
    }

    try {
        Add-Type -AssemblyName $AssemblyName -ErrorAction Stop | Out-Null
        return ($TypeName -as [type]) -ne $null
    } catch {
        Write-Log -Message "Failed to load assembly '$AssemblyName' for type '$TypeName': $_" -Level 'DEBUG'
        return $false
    }
}

function Show-MissingVarsPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$MissingVars
    )

    $message = "Missing API keys: $($MissingVars -join ', ')`n`nWould you like to enter them now? They will be saved to your user environment."
    $title = 'Missing Environment Variables'

    if (Ensure-TypeAvailable -TypeName 'System.Windows.Forms.MessageBox' -AssemblyName 'System.Windows.Forms') {
        $result = [System.Windows.Forms.MessageBox]::Show(
            $message,
            $title,
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Question
        )

        return $result.ToString()
    }

    Write-Log -Message 'System.Windows.Forms assembly not available. Falling back to console prompt.' -Level 'DEBUG'

    while ($true) {
        $response = Read-Host -Prompt "$message (Y/N)"
        if ([string]::IsNullOrWhiteSpace($response)) {
            continue
        }

        switch ($response.Trim().ToUpperInvariant()) {
            'Y' { return 'Yes' }
            'N' { return 'No' }
            default { Write-Host "Please enter 'Y' or 'N'." -ForegroundColor Yellow }
        }
    }
}

function Get-ApiKeyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$VariableName
    )

    if (Ensure-TypeAvailable -TypeName 'Microsoft.VisualBasic.Interaction' -AssemblyName 'Microsoft.VisualBasic') {
        return [Microsoft.VisualBasic.Interaction]::InputBox(
            "Enter API key for $VariableName",
            'API Key Input',
            ''
        )
    }

    Write-Log -Message 'Microsoft.VisualBasic assembly not available. Falling back to console input.' -Level 'DEBUG'
    return Read-Host -Prompt "Enter API key for $VariableName"
}

function Set-EnvironmentValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Value,
        [Parameter(Mandatory = $true)]
        [System.EnvironmentVariableTarget]$Target
    )

    [Environment]::SetEnvironmentVariable($Name, $Value, $Target)
}

function Get-EnvVariables {
    [CmdletBinding()]
    param()

    $config = Get-Config
    $requiredVars = @()

    foreach ($tool in $TOOL_ENV_VARS.Keys) {
        if ($config.Tools[$tool] -eq $true) {
            $requiredVars += $TOOL_ENV_VARS[$tool]
        }
    }

    return $requiredVars
}

function Validate-Environment {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$RequiredVariables = (Get-EnvVariables),
        [switch]$Test
    )

    if ($Test) {
        Write-Log -Message "Checking environment variables for enabled tools..." -Level 'INFO'
    }

    $missing = @()
    foreach ($var in $RequiredVariables) {
        $value = [Environment]::GetEnvironmentVariable($var)
        if (-not $value) {
            $missing += $var
        }
        elseif ($Test) {
            Write-Log -Message "Environment variable '$var' is set." -Level 'INFO'
        }
    }

    if ($missing.Count -gt 0) {
        $response = Show-MissingVarsPrompt -MissingVars $missing

        if ($response -eq 'Yes') {
            Request-MissingApiKeys -MissingVars $missing
        } else {
            $msg = "Required environment variables missing: $($missing -join ', ')"
            Write-Log -Message $msg -Level 'ERROR'
            Write-Host $msg -ForegroundColor Red
            Throw $msg
        }
    }
    
    Write-Log -Message 'All required environment variables are set.' -Level 'INFO'
}

function Request-MissingApiKeys {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$MissingVars
    )

    foreach ($var in $MissingVars) {
        try {
            $value = Get-ApiKeyValue -VariableName $var
            
            if ([string]::IsNullOrWhiteSpace($value)) {
                Write-Log -Message "No value provided for $var, skipping..." -Level 'WARNING'
                continue
            }
            
            # Set environment variable at User scope for persistence
            Set-EnvironmentValue -Name $var -Value $value -Target ([EnvironmentVariableTarget]::User)
            # Also set for current process so it's immediately available
            Set-EnvironmentValue -Name $var -Value $value -Target ([EnvironmentVariableTarget]::Process)
            
            Write-Log -Message "Successfully set environment variable: $var" -Level 'INFO'
            Write-Host "✓ Set $var" -ForegroundColor Green
            
        } catch {
            Write-Log -Message "Failed to set environment variable $var`: $_" -Level 'ERROR'
            Write-Host "✗ Failed to set $var" -ForegroundColor Red
        }
    }
    
    Write-Host "`nEnvironment variables have been saved to your user profile and will persist across sessions." -ForegroundColor Cyan
}
