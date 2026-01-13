$ModulesDir = Join-Path (Get-Location).Path 'modules'
Write-Host "Modules Directory: $ModulesDir"
if (-not (Test-Path $ModulesDir)) { throw "Modules directory not found!" }

Describe 'Invoke-TenableWASWorkflow (Scan Name Resolution)' {
    BeforeAll {
        # Mock Logging
        function Write-Log { param($Message, $Level) Write-Host "[$Level] $Message" }
        
        # Source Modules
        . (Join-Path $ModulesDir 'TenableWAS.ps1')
        . (Join-Path $ModulesDir 'AutomationWorkflow.ps1')

        # Mock Config
        function Get-Config {
            return @{
                TenableWASScanNames = @('Scan A', 'Scan B')
                ApiBaseUrls = @{ TenableWAS = 'https://mock-tenable.com' }
                Tools = @{ DefectDojo = $false }
            }
        }
    }

    Context 'When Scan Names are provided' {
        Mock Invoke-RestMethod {
            param($Uri, $Method)
            if ($Uri -match '/was/v2/configs/search') {
                return [PSCustomObject]@{
                    items = @(
                        @{ config_id = 'id-a'; name = 'Scan A' },
                        @{ config_id = 'id-b'; name = 'Scan B' },
                        @{ config_id = 'id-trash'; name = 'Scan Trash'; in_trash = $true }
                    )
                }
            }
            return $null
        }

        Mock Export-TenableWASScan {
            param($ScanId)
            return "report-$ScanId.csv"
        }

        Mock Upload-DefectDojoScan { } # Should not be called in this test config

        It 'Should resolve names to IDs and export scans' {
            $config = Get-Config
            $results = Invoke-TenableWASWorkflow -Config $config

            $results.Count | Should -Be 2
            $results[0].Status | Should -Be 'Success'
            $results[1].Status | Should -Be 'Success'

            Assert-MockCalled Export-TenableWASScan -Times 1 -ParameterFilter { $ScanId -eq 'id-a' }
            Assert-MockCalled Export-TenableWASScan -Times 1 -ParameterFilter { $ScanId -eq 'id-b' }
        }
    }
    
    Context 'When Scan Name is not found' {
        # Override config for this context
        Mock Get-Config {
            return @{
                TenableWASScanNames = @('NonExistentScan')
                ApiBaseUrls = @{ TenableWAS = 'https://mock-tenable.com' }
                Tools = @{ DefectDojo = $false }
            }
        }

        It 'Should return error status' {
            $config = Get-Config
            $results = Invoke-TenableWASWorkflow -Config $config

            $results.Count | Should -Be 1
            $results[0].Status | Should -Be 'Error'
            $results[0].Message | Should -Like "*not found*"
        }
    }
}
