<#
.SYNOPSIS
    Module for loading and validating the automation tool configuration.
#>

function Get-Config {
    [CmdletBinding()]
    param(
        [string]$ConfigPath   = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'config\config.psd1'),
        [string]$TemplatePath = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'config\config.psd1.example')
    )

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath) -and (Test-Path -Path $ConfigPath)) {
        Write-Verbose "Loading configuration from $ConfigPath"
        try {
            $config = Import-PowerShellDataFile -Path $ConfigPath
        } catch {
            Throw "Failed to import configuration from $ConfigPath. Error: $_"
        }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($TemplatePath) -and (Test-Path -Path $TemplatePath)) {
        Write-Warning "Configuration file not found at $ConfigPath. Loading example configuration from $TemplatePath."
        try {
            $config = Import-PowerShellDataFile -Path $TemplatePath
        } catch {
            Throw "Failed to import example configuration from $TemplatePath. Error: $_"
        }
    }
    else {
        Throw "No configuration file found at $ConfigPath or $TemplatePath"
    }

    Normalize-GitHubConfig -Config $config
    return $config
}

function Validate-Config {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    Normalize-GitHubConfig -Config $Config

    $errors = @()

    # Required top-level keys
    $requiredKeys = @('Tools', 'Paths', 'ApiBaseUrls', 'DefectDojo', 'GitHub', 'Webhooks')
    foreach ($key in $requiredKeys) {
        if (-not $Config.ContainsKey($key)) {
            $errors += "Missing required top-level configuration key: $key"
        }
    }

    # Validate Tools keys
    $requiredToolKeys = @('TenableWAS','SonarQube','BurpSuite','DefectDojo','GitHub')
    foreach ($t in $requiredToolKeys) {
        if ($Config.Tools -isnot [hashtable] -or -not $Config.Tools.ContainsKey($t)) {
            $errors += "Configuration.Tools missing key: $t"
        }
    }

    $gitHubFeatureKeys = @('CodeQL','SecretScanning','Dependabot')
    if ($Config.Tools.ContainsKey('GitHub')) {
        if ($Config.Tools.GitHub -isnot [hashtable]) {
            $errors += 'Configuration.Tools.GitHub must be a hashtable with feature toggles (CodeQL, SecretScanning, Dependabot).'
        }
        else {
            foreach ($feature in $gitHubFeatureKeys) {
                if (-not $Config.Tools.GitHub.ContainsKey($feature)) {
                    $errors += "Configuration.Tools.GitHub missing key: $feature"
                }
            }
        }
    }

    # Validate Paths keys
    if ($Config.Paths -isnot [hashtable] -or -not $Config.Paths.ContainsKey('BurpSuiteXmlFolder')) {
        $errors += "Configuration.Paths missing key: BurpSuiteXmlFolder"
    }

    # Validate ApiBaseUrls keys
    foreach ($api in $requiredToolKeys) {
        if ($Config.ApiBaseUrls -isnot [hashtable] -or -not $Config.ApiBaseUrls.ContainsKey($api)) {
            $errors += "Configuration.ApiBaseUrls missing key: $api"
        }
    }

    # Validate GitHub keys
    if ($Config.GitHub -isnot [hashtable] -or -not $Config.GitHub.ContainsKey('Orgs')) {
        $errors += "Configuration.GitHub missing key: Orgs"
    }
    else {
        $orgs = $Config.GitHub.Orgs
        if ($orgs -isnot [System.Collections.IEnumerable] -or $orgs -is [string]) {
            $errors += 'Configuration.GitHub.Orgs must be an array of organization names'
        }
        else {
            $orgList = @($orgs)
            if ($orgList.Count -eq 0) {
                $errors += 'Configuration.GitHub.Orgs must contain at least one organization'
            }
            elseif ($orgList | Where-Object { [string]::IsNullOrWhiteSpace($_) }) {
                $errors += 'Configuration.GitHub.Orgs contains blank organization names'
            }
        }
    }

    # Validate Webhooks keys
    if ($Config.ContainsKey('Webhooks') -and $Config.Webhooks -isnot [hashtable]) {
        $errors += "Configuration.Webhooks must be a hashtable."
    }

    if ($errors.Count -gt 0) {
        Throw ($errors -join '; ')
    }

    Write-Verbose "Configuration validation passed."
    return $true
}

function Save-Config {
    <#
    .SYNOPSIS
        Saves the configuration hashtable to a PowerShell data file (.psd1).
    .DESCRIPTION
        Writes the provided configuration hashtable back to the config.psd1 file,
        preserving the PowerShell data file format. Overwrites any existing file.
    .PARAMETER Config
        The configuration hashtable to serialize and save.
    .PARAMETER ConfigPath
        The file path to write the configuration to. Defaults to config\config.psd1 in the repo root.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Config,

        [string]$ConfigPath = (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'config\config.psd1')
    )

    Normalize-GitHubConfig -Config $Config

    # Build the PS data file content
    $sb = New-Object System.Text.StringBuilder
    $sb.AppendLine('@{') | Out-Null
    # Tools
    $sb.AppendLine('    Tools = @{') | Out-Null
    foreach ($tool in $Config.Tools.Keys) {
        $val = $Config.Tools[$tool]
        if ($val -is [hashtable]) {
            $sb.AppendLine("        $tool = @{") | Out-Null
            foreach ($feature in $val.Keys) {
                $featureValue = if ($val[$feature]) { '$true' } else { '$false' }
                $sb.AppendLine("            $feature = $featureValue") | Out-Null
            }
            $sb.AppendLine('        }') | Out-Null
        }
        else {
            $boolStr = if ($val) { '$true' } else { '$false' }
            $sb.AppendLine("        $tool = $boolStr") | Out-Null
        }
    }
    $sb.AppendLine('    }') | Out-Null
    $sb.AppendLine('') | Out-Null
    # Paths
    $sb.AppendLine('    Paths = @{') | Out-Null
    foreach ($pathKey in $Config.Paths.Keys) {
        $escaped = ($Config.Paths[$pathKey] -replace '\\','\')
        $sb.AppendLine("        $pathKey = '$escaped'") | Out-Null
    }
    $sb.AppendLine('    }') | Out-Null
    $sb.AppendLine('') | Out-Null
    # ApiBaseUrls
    $sb.AppendLine('    ApiBaseUrls = @{') | Out-Null
    foreach ($api in $Config.ApiBaseUrls.Keys) {
        $url = ($Config.ApiBaseUrls[$api] -replace '\\','\\')
        $sb.AppendLine("        $api = '$url'") | Out-Null
    }
    $sb.AppendLine('    }') | Out-Null
    #TenableWAS ScanId
    if ($Config.ContainsKey('TenableWASScanId')) {
        $sb.AppendLine('') | Out-Null
        $scanId = $Config.TenableWASScanId
        if ($null -ne $scanId) {
            $sb.AppendLine("    TenableWASScanId = '$scanId'") | Out-Null
        } else {
            $sb.AppendLine('    TenableWASScanId = $null') | Out-Null
        }
    }
    # DefectDojo selections
    if ($Config.ContainsKey('DefectDojo')) {
        $sb.AppendLine('') | Out-Null
        $sb.AppendLine('    DefectDojo = @{') | Out-Null
        foreach ($key in $Config.DefectDojo.Keys) {
            $val = $Config.DefectDojo[$key]
            if ($null -eq $val -or $val -is [string]) {
                $inner = if ($null -eq $val) { '' } else { $val }
                $sb.AppendLine("        $key = '$inner'") | Out-Null
            } else {
                $sb.AppendLine("        $key = $val") | Out-Null
            }
        }
        $sb.AppendLine('    }') | Out-Null
    }
    
    # GitHub configuration
    if ($Config.ContainsKey('GitHub')) {
        $sb.AppendLine('') | Out-Null
        $sb.AppendLine('    GitHub = @{') | Out-Null

        # Define preferred order for GitHub keys
        $preferredOrder = @('Orgs', 'SkipArchivedRepos', 'IncludeRepos', 'ExcludeRepos')

        # Process keys in preferred order first
        foreach ($key in $preferredOrder) {
            if (-not $Config.GitHub.ContainsKey($key)) { continue }

            $val = $Config.GitHub[$key]
            if ($null -eq $val) {
                $sb.AppendLine("        $key = @()") | Out-Null
                continue
            }

            if ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) {
                $sb.AppendLine("        $key = @(") | Out-Null
                foreach ($entry in $val) {
                    $sb.AppendLine("            '$entry'") | Out-Null
                }
                $sb.AppendLine('        )') | Out-Null
            }
            elseif ($val -is [string]) {
                $sb.AppendLine("        $key = '$val'") | Out-Null
            }
            elseif ($val -is [bool]) {
                $boolStr = if ($val) { '$true' } else { '$false' }
                $sb.AppendLine("        $key = $boolStr") | Out-Null
            }
            else {
                $sb.AppendLine("        $key = $val") | Out-Null
            }
        }

        # Process any remaining keys not in preferred order (for future extensibility)
        foreach ($key in $Config.GitHub.Keys | Sort-Object) {
            if ($key -in $preferredOrder) { continue }

            $val = $Config.GitHub[$key]
            if ($null -eq $val) {
                $sb.AppendLine("        $key = @()") | Out-Null
                continue
            }

            if ($val -is [System.Collections.IEnumerable] -and $val -isnot [string]) {
                $sb.AppendLine("        $key = @(") | Out-Null
                foreach ($entry in $val) {
                    $sb.AppendLine("            '$entry'") | Out-Null
                }
                $sb.AppendLine('        )') | Out-Null
            }
            elseif ($val -is [string]) {
                $sb.AppendLine("        $key = '$val'") | Out-Null
            }
            elseif ($val -is [bool]) {
                $boolStr = if ($val) { '$true' } else { '$false' }
                $sb.AppendLine("        $key = $boolStr") | Out-Null
            }
            else {
                $sb.AppendLine("        $key = $val") | Out-Null
            }
        }

        $sb.AppendLine('    }') | Out-Null
    }

    $sb.AppendLine('}') | Out-Null

    try {
        $sb.ToString() | Out-File -FilePath $ConfigPath -Encoding UTF8 -Force
        Write-Verbose "Configuration saved to $ConfigPath"
    } catch {
        Throw "Failed to save configuration to $ConfigPath. Error: $_"
    }
}

function Normalize-GitHubConfig {
    param([hashtable]$Config)

    if (-not $Config) { return }

    if (-not $Config.ContainsKey('Tools') -or $Config.Tools -isnot [hashtable]) {
        $Config.Tools = @{}
    }

    if (-not $Config.Tools.ContainsKey('GitHub') -or $Config.Tools.GitHub -isnot [hashtable]) {
        $Config.Tools.GitHub = @{}
    }

    $githubFeatures = @('CodeQL','SecretScanning','Dependabot')
    $legacyToolKeyMap = @{
        GitHubCodeQL         = 'CodeQL'
        GitHubSecret         = 'SecretScanning'
        GitHubSecretScanning = 'SecretScanning'
        GitHubDependabot     = 'Dependabot'
    }

    foreach ($legacyKey in $legacyToolKeyMap.Keys) {
        if ($Config.Tools.ContainsKey($legacyKey)) {
            $feature = $legacyToolKeyMap[$legacyKey]
            $Config.Tools.GitHub[$feature] = [bool]$Config.Tools[$legacyKey]
            $null = $Config.Tools.Remove($legacyKey)
        }
    }

    foreach ($feature in $githubFeatures) {
        if (-not $Config.Tools.GitHub.ContainsKey($feature)) {
            $Config.Tools.GitHub[$feature] = $false
        }
        else {
            $Config.Tools.GitHub[$feature] = [bool]$Config.Tools.GitHub[$feature]
        }
    }

    if (-not $Config.ContainsKey('ApiBaseUrls') -or $Config.ApiBaseUrls -isnot [hashtable]) {
        $Config.ApiBaseUrls = @{}
    }

    if (-not $Config.ApiBaseUrls.ContainsKey('GitHub')) {
        $Config.ApiBaseUrls.GitHub = 'https://api.github.com'
    }

    $legacyApiKeyMap = @{
        GitHubCodeQL         = 'CodeQL'
        GitHubSecret         = 'SecretScanning'
        GitHubSecretScanning = 'SecretScanning'
        GitHubDependabot     = 'Dependabot'
    }

    foreach ($legacyKey in $legacyApiKeyMap.Keys) {
        if ($Config.ApiBaseUrls.ContainsKey($legacyKey)) {
            $target = "GitHub$($legacyApiKeyMap[$legacyKey])"
            if (-not $Config.ApiBaseUrls.ContainsKey($target)) {
                $Config.ApiBaseUrls[$target] = $Config.ApiBaseUrls[$legacyKey]
            }
            $null = $Config.ApiBaseUrls.Remove($legacyKey)
        }
    }
}

#Save-Config -Config (Get-Config) -ConfigPath (Join-Path (Split-Path -Path $PSScriptRoot -Parent) 'config\config.psd1')
