# Pester tests for TenableWAS module
$Global:TenableWasModuleDir = Join-Path $PSScriptRoot '../modules'
. (Join-Path $Global:TenableWasModuleDir 'Config.ps1')
. (Join-Path $Global:TenableWasModuleDir 'Logging.ps1')
. (Join-Path $Global:TenableWasModuleDir 'TenableWAS.ps1')

$Global:OriginalTenwasAccessKey = $env:TENWAS_ACCESS_KEY
$Global:OriginalTenwasSecretKey = $env:TENWAS_SECRET_KEY

Describe 'Export-TenableWASScan (Unit)' {
    BeforeAll {
        . (Join-Path $Global:TenableWasModuleDir 'Config.ps1')
        . (Join-Path $Global:TenableWasModuleDir 'Logging.ps1')
        . (Join-Path $Global:TenableWasModuleDir 'TenableWAS.ps1')
    }

    Context 'When no scan ID is provided via parameter' {
        It 'Throws an internal error' {
            { Export-TenableWASScan } | Should -Throw 'No TenableWAS ScanId specified. Internal calling error.'
        }
    }

    Context 'When credentials are missing' {
        BeforeAll {
            Initialize-Log -LogDirectory (Join-Path $TestDrive 'logs') -LogFileName 'unit-missingcreds.log' -Overwrite
            $Global:HeldAccessKey = $env:TENWAS_ACCESS_KEY
            $Global:HeldSecretKey = $env:TENWAS_SECRET_KEY
            Remove-Item Env:TENWAS_ACCESS_KEY -ErrorAction SilentlyContinue
            Remove-Item Env:TENWAS_SECRET_KEY -ErrorAction SilentlyContinue
            
            # Mock Get-Config to return valid URLs so we hit the cred check
            $script:OriginalGetConfig = (Get-Command Get-Config -CommandType Function -ErrorAction SilentlyContinue).ScriptBlock
            Set-Item function:Get-Config -Value { return @{ ApiBaseUrls = @{ TenableWAS = 'https://example.com' } } }
        }
        AfterAll {
             if ($Global:HeldAccessKey) { $env:TENWAS_ACCESS_KEY = $Global:HeldAccessKey }
             if ($Global:HeldSecretKey) { $env:TENWAS_SECRET_KEY = $Global:HeldSecretKey }
             if ($script:OriginalGetConfig) { Set-Item function:Get-Config -Value $script:OriginalGetConfig }
        }
        It 'Throws an error indicating missing credentials' {
            { Export-TenableWASScan -ScanId 'dummy-id' } | Should -Throw 'Missing Tenable WAS API credentials*'
        }
    }
}

if (-not ($env:TENWAS_ACCESS_KEY -and $env:TENWAS_SECRET_KEY)) {
    Write-Warning 'Skipping TenableWAS integration tests: TENWAS_ACCESS_KEY and TENWAS_SECRET_KEY environment variables must be set.'
    return
}

Describe 'Export-TenableWASScan (Integration)' {
    BeforeAll {
        . (Join-Path $Global:TenableWasModuleDir 'Config.ps1')
        . (Join-Path $Global:TenableWasModuleDir 'Logging.ps1')
        . (Join-Path $Global:TenableWasModuleDir 'TenableWAS.ps1')

        $tempLogDir = Join-Path ([System.IO.Path]::GetTempPath()) 'tenablewas-tests'
        Initialize-Log -LogDirectory $tempLogDir -LogFileName 'integration.log' -Overwrite

        $script:integrationConfig = Get-Config
        $script:integrationScanId = $null
        
        # Resolve Scan Name to ID for integration test using the actual API
        if ($script:integrationConfig.TenableWASScanNames -and $script:integrationConfig.TenableWASScanNames.Count -gt 0) {
            $targetName = $script:integrationConfig.TenableWASScanNames[0]
            Write-Host "Integration Test: Resolving ID for scan name '$targetName'..."
            
            try {
                $configs = Get-TenableWASScanConfigs
                $found = $configs | Where-Object { $_.Name -eq $targetName } | Select-Object -First 1
                if ($found) {
                    $script:integrationScanId = $found.Id
                    Write-Host "Integration Test: Found Scan ID: $($found.Id)"
                } else {
                    Write-Warning "Integration Test: configured scan name '$targetName' not found in Tenable account."
                }
            } catch {
                Write-Warning "Integration Test: Failed to fetch configs: $_"
            }
        }
        
        # Fallback for legacy checks (though likely removed from config)
        if (-not $script:integrationScanId -and $script:integrationConfig.TenableWASScanId) {
             $script:integrationScanId = $script:integrationConfig.TenableWASScanId
        }

        if (-not $script:integrationScanId) {
            Write-Warning 'ScanId could not be determined from configuration (TenableWASScanNames). Skipping export test.'
        }
    }

    It 'Generates and downloads a report CSV file' {
        if (-not $script:integrationScanId) {
            Set-ItResult -Skipped -Because 'No valid Scan ID found in config.'
        } else {
            $outPath = Export-TenableWASScan -ScanId $script:integrationScanId
            if ($outPath -is [System.IO.FileSystemInfo]) {
                $outPath = $outPath.FullName
            } elseif ($outPath) {
                $outPath = [string]$outPath
            }

            $expectedPath = Join-Path ([System.IO.Path]::GetTempPath()) ("${script:integrationScanId}-report.csv")
            $candidatePaths = @($outPath, $expectedPath) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
            $resolvedOutPath = $candidatePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
            if (-not $resolvedOutPath) {
                $resolvedOutPath = $candidatePaths | Select-Object -First 1
            }

            $resolvedOutPath | Should -Not -BeNullOrEmpty
            [System.IO.Path]::GetFileName($resolvedOutPath) | Should -Match "${script:integrationScanId}-report\.csv$"
            Test-Path $resolvedOutPath | Should -BeTrue
            (Get-Item $resolvedOutPath).Length | Should -BeGreaterThan 0
        }
    }
}
