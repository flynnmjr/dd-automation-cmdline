<#
.SYNOPSIS
    Core automation workflow logic extracted from Launch.ps1.
    Decoupled from GUI dependencies for headless execution.
.DESCRIPTION
    Contains functions to orchestrate TenableWAS, SonarQube, BurpSuite, and GitHub automation tasks.
    Each function logs progress (via Write-Log) and returns a status object for webhook reporting.
#>

function Invoke-TenableWASWorkflow {
    param([hashtable]$Config)
    
    $result = @{
        Tool = 'TenableWAS'
        Status = 'Success'
        Message = "Processing started"
    }

    Write-Log -Message "Starting TenableWAS scan export (Scan ID: $($Config.TenableWASScanId))" -Level 'INFO'
    try {
        $exportedFile = Export-TenableWASScan -ScanId $Config.TenableWASScanId
        Write-Log -Message "TenableWAS scan export completed: $exportedFile" -Level 'INFO'

        if ($Config.Tools.DefectDojo) {
            Write-Log -Message "Uploading TenableWAS scan report to DefectDojo..." -Level 'INFO'

            if (-not $Config.DefectDojo.TenableWASTestId) {
                Write-Log -Message "No TenableWAS test ID configured for DefectDojo upload" -Level 'WARNING'
                $result.Status = 'Warning'
                $result.Message = "Export successful, but upload skipped (No Test ID configured)."
                return $result
            }

            # Ensure file path is explicitly converted to string
            $filePathString = ([string]$exportedFile).Trim()

            # Upload directly to the TenableWAS test only
            Upload-DefectDojoScan -FilePath $filePathString -TestId $Config.DefectDojo.TenableWASTestId -ScanType 'Tenable Scan' -CloseOldFindings $true
            
            $msg = "TenableWAS scan report uploaded successfully to DefectDojo Test ID: $($Config.DefectDojo.TenableWASTestId)"
            Write-Log -Message $msg -Level 'INFO'
            $result.Message = $msg
        } else {
             $result.Message = "Export successful. Upload disabled in config."
        }
    } catch {
        $errMsg = "TenableWAS processing failed: $_"
        Write-Log -Message $errMsg -Level 'ERROR'
        $result.Status = 'Error'
        $result.Message = $errMsg
    }
    return $result
}

function Invoke-SonarQubeWorkflow {
    param([hashtable]$Config)
    
    $result = @{
        Tool = 'SonarQube'
        Status = 'Success'
        Message = "Processing started"
    }

    Write-Log -Message "Processing SonarQube scan..." -Level 'INFO'
    try {
        if (-not $Config.DefectDojo.APIScanConfigId -or -not $Config.DefectDojo.SonarQubeTestId) {
             $errMsg = "SonarQube processing requires APIScanConfigId and SonarQubeTestId in DefectDojo config."
             Write-Log -Message $errMsg -Level 'ERROR'
             $result.Status = 'Error'
             $result.Message = $errMsg
             return $result
        }

        Invoke-SonarQubeProcessing -ApiScanConfiguration $Config.DefectDojo.APIScanConfigId -Test $Config.DefectDojo.SonarQubeTestId
        
        $msg = "SonarQube processing completed for Test ID: $($Config.DefectDojo.SonarQubeTestId)"
        Write-Log -Message $msg -Level 'INFO'
        $result.Message = $msg

    } catch {
        $errMsg = "SonarQube processing failed: $_"
        Write-Log -Message $errMsg -Level 'ERROR'
        $result.Status = 'Error'
        $result.Message = $errMsg
    }
    return $result
}

function Invoke-BurpSuiteWorkflow {
    param([hashtable]$Config)
    
    $result = @{
        Tool = 'BurpSuite'
        Status = 'Success'
        Message = "Processing started"
    }

    Write-Log -Message "Starting BurpSuite XML report processing..." -Level 'INFO'
    try {
        # Get XML files from configured folder
        $xmlFiles = Get-BurpSuiteReports -FolderPath $Config.Paths.BurpSuiteXmlFolder

        if (-not $xmlFiles -or $xmlFiles.Count -eq 0) {
            $msg = "No BurpSuite XML files found in folder: $($Config.Paths.BurpSuiteXmlFolder)"
            Write-Log -Message $msg -Level 'WARNING'
            $result.Status = 'Warning'
            $result.Message = $msg
            return $result
        }

        Write-Log -Message "Found $($xmlFiles.Count) BurpSuite XML report(s)" -Level 'INFO'

        if ($Config.Tools.DefectDojo) {
            Write-Log -Message "Uploading BurpSuite report to DefectDojo..." -Level 'INFO'

            if (-not $Config.DefectDojo.BurpSuiteTestId) {
                $msg = "No BurpSuite test ID configured for DefectDojo upload"
                Write-Log -Message $msg -Level 'WARNING'
                $result.Status = 'Warning'
                $result.Message = $msg
                return $result
            }

            # Upload only the first XML file found
            $xmlFile = $xmlFiles[0]
            $fileName = [System.IO.Path]::GetFileName($xmlFile)

            if ($xmlFiles.Count -gt 1) {
                Write-Log -Message "Multiple XML files found. Uploading only: $fileName. Other files will be ignored." -Level 'WARNING'
            }

            try {
                Write-Log -Message "Uploading $fileName to DefectDojo Test ID: $($Config.DefectDojo.BurpSuiteTestId)" -Level 'INFO'

                # Ensure file path is explicitly converted to string
                $filePathString = ([string]$xmlFile).Trim()

                # Upload to DefectDojo using Burp Scan type
                Upload-DefectDojoScan -FilePath $filePathString -TestId $Config.DefectDojo.BurpSuiteTestId -ScanType 'Burp Scan'
                
                $msg = "Successfully uploaded $fileName to DefectDojo Test ID: $($Config.DefectDojo.BurpSuiteTestId)"
                Write-Log -Message $msg -Level 'INFO'
                $result.Message = $msg

            } catch {
                $errMsg = "Failed to upload $fileName : $_"
                Write-Log -Message $errMsg -Level 'ERROR'
                $result.Status = 'Error'
                $result.Message = $errMsg
            }
        } else {
             $result.Message = "Files found, but DefectDojo upload disabled in config."
        }
    } catch {
        $errMsg = "BurpSuite processing failed: $_"
        Write-Log -Message $errMsg -Level 'ERROR'
        $result.Status = 'Error'
        $result.Message = $errMsg
    }
    return $result
}

function Invoke-GitHubWorkflow {
    param([hashtable]$Config)

    $results = @()

    # CodeQL
    if (Get-GitHubFeatureState -Config $Config -ToolKey 'GitHubCodeQL') {
        $results += Invoke-GitHubCodeQLWorkflow -Config $Config
    }

    # Secret Scanning
    if (Get-GitHubFeatureState -Config $Config -ToolKey 'GitHubSecretScanning') {
        $results += Invoke-GitHubSecretScanningWorkflow -Config $Config
    }

    # Dependabot
    if (Get-GitHubFeatureState -Config $Config -ToolKey 'GitHubDependabot') {
        $results += Invoke-GitHubDependabotWorkflow -Config $Config
    }

    return $results
}

function Invoke-GitHubCodeQLWorkflow {
    param([hashtable]$Config)

    $result = @{
        Tool = 'GitHub CodeQL'
        Status = 'Success'
        Message = "Processing started"
    }

    Write-Log -Message "Starting GitHub CodeQL download..." -Level 'INFO'
    try {
        $orgs = @($Config.GitHub.Orgs)
        if (-not $orgs -or $orgs.Count -eq 0) {
            $msg = "No GitHub organizations configured. Skipping GitHub CodeQL."
            Write-Log -Message $msg -Level 'WARNING'
            $result.Status = 'Warning'
            $result.Message = $msg
            return $result
        }

        Write-Log -Message ("Processing GitHub organizations: {0}" -f ($orgs -join ', ')) -Level 'INFO'

        GitHub-CodeQLDownload -Owners $orgs
        Write-Log -Message "GitHub CodeQL download completed." -Level 'INFO'

        if ($Config.Tools.DefectDojo) {
            Write-Log -Message "Uploading GitHub CodeQL reports to DefectDojo..." -Level 'INFO'
            $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) 'GitHubCodeScanning'
            $sarifFiles = Get-ChildItem -Path $downloadRoot -Filter '*.sarif' -Recurse | Select-Object -ExpandProperty FullName
            $uploadErrors = 0
            
            if (-not $Config.DefectDojo.EngagementId) {
                 $msg = "No Engagement ID configured. Skipping uploads."
                 Write-Log -Message $msg -Level 'WARNING'
                 $result.Status = 'Warning'
                 $result.Message = $msg
                 return $result
            }

            # We need to fetch tests to check for existence, similar to Launch.ps1 logic
            # However, AutomationWorkflow shouldn't rely on UI state ($script:cmbDDEng).
            # Logic here tries to auto-create tests. We use engagementId from config.
            
            $engagementId = $Config.DefectDojo.EngagementId
            $existingTests = @(Get-DefectDojoTests -EngagementId $engagementId)
            
            foreach ($file in $sarifFiles) {
                try {
                    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file)
                    $baseServiceName = $fileName -replace '-\d+$', ''
                    $repoNameOnly = $baseServiceName
                    if ($baseServiceName -match '^(?<org>[^-]+)-(?<repo>.+)$') {
                        $repoNameOnly = $Matches['repo']
                    }

                    $serviceNameCore = $repoNameOnly
                    $serviceName = "$serviceNameCore (CodeQL)"

                    $existingTest = $existingTests | Where-Object { $_.title -in @($serviceName, $serviceNameCore, $repoNameOnly) } | Select-Object -First 1

                    $testId = 0
                    if (-not $existingTest) {
                        Write-Log -Message "Creating new test: $serviceName" -Level 'INFO'
                        try {
                            $newTest = New-DefectDojoTest -EngagementId $engagementId -TestName $serviceName -TestType 20
                            Write-Log -Message "Test created successfully: $serviceName (ID: $($newTest.Id))" -Level 'INFO'
                            $existingTests = @($existingTests) + $newTest
                            $testId = $newTest.Id
                        } catch {
                            Write-Log -Message "Failed to create test $serviceName : $_" -Level 'ERROR'
                            continue
                        }
                    } else {
                        Write-Log -Message "Using existing test: $($existingTest.Title) (ID: $($existingTest.Id))" -Level 'INFO'
                        $testId = $existingTest.Id
                    }

                    Upload-DefectDojoScan -FilePath $file -TestId $testId -ScanType 'SARIF'

                } catch {
                    $uploadErrors++
                    Write-Log -Message "Failed to upload $file to DefectDojo: $_" -Level 'ERROR'
                }
            }

            if ($uploadErrors -eq 0) {
                $msg = "GitHub CodeQL reports processed and uploaded successfully."
                Write-Log -Message $msg -Level 'INFO'
                $result.Message = $msg
                
                # Cleanup
                 try {
                    Remove-Item -Path $downloadRoot -Recurse -Force
                    Write-Log -Message "GitHub CodeQL download directory cleaned up successfully" -Level 'INFO'
                } catch {
                    Write-Log -Message "Failed to clean up download directory: $_" -Level 'WARNING'
                }
            } else {
                $msg = "GitHub CodeQL upload completed with $uploadErrors error(s)."
                Write-Log -Message $msg -Level 'WARNING'
                $result.Status = 'Warning'
                $result.Message = $msg
            }
        }
    } catch {
        $errMsg = "GitHub CodeQL processing failed: $_"
        Write-Log -Message $errMsg -Level 'ERROR'
        $result.Status = 'Error'
        $result.Message = $errMsg
    }
    return $result
}

function Invoke-GitHubSecretScanningWorkflow {
    param([hashtable]$Config)

    $result = @{
        Tool = 'GitHub Secret Scanning'
        Status = 'Success'
        Message = "Processing started"
    }

    Write-Log -Message "Starting GitHub Secret Scanning download..." -Level 'INFO'
    try {
        $orgs = @($Config.GitHub.Orgs)
        if (-not $orgs -or $orgs.Count -eq 0) {
            $msg = "No GitHub organizations configured. Skipping Secret Scanning."
            Write-Log -Message $msg -Level 'WARNING'
            $result.Status = 'Warning'
            $result.Message = $msg
            return $result
        }

        Write-Log -Message ("Processing GitHub organizations for secret scanning: {0}" -f ($orgs -join ', ')) -Level 'INFO'
        GitHub-SecretScanDownload -Owners $orgs
        Write-Log -Message "GitHub Secret Scanning download completed." -Level 'INFO'

        if ($Config.Tools.DefectDojo) {
            Write-Log -Message "Uploading GitHub Secret Scanning reports to DefectDojo..." -Level 'INFO'
            $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) 'GitHubSecretScanning'
            $jsonFiles = Get-ChildItem -Path $downloadRoot -Filter '*-secrets.json' -Recurse | Select-Object -ExpandProperty FullName
            $uploadErrors = 0

            if (-not $Config.DefectDojo.EngagementId) {
                 $msg = "No Engagement ID configured. Skipping uploads."
                 Write-Log -Message $msg -Level 'WARNING'
                 $result.Status = 'Warning'
                 $result.Message = $msg
                 return $result
            }
            
            $engagementId = $Config.DefectDojo.EngagementId
            $existingTests = Get-DefectDojoTests -EngagementId $engagementId

            foreach ($file in $jsonFiles) {
                try {
                    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($file)
                    $repoName = $fileName -replace '-secrets$', ''
                    $baseServiceName = $repoName -replace '-\d+$', ''
                    $repoNameOnly = $baseServiceName
                    if ($baseServiceName -match '^(?<org>[^-]+)-(?<repo>.+)$') {
                        $repoNameOnly = $Matches['repo']
                    }

                    $serviceName = "$repoNameOnly (Secret Scanning)"
                    
                    $existingTest = $existingTests | Where-Object {
                        $_.title -in @(
                            $serviceName,
                            "$baseServiceName (Secret Scanning)",
                            "$repoName (Secret Scanning)"
                        )
                    } | Select-Object -First 1

                    $testId = 0
                    if (-not $existingTest) {
                        Write-Log -Message "Creating new test: $serviceName" -Level 'INFO'
                        try {
                            $newTest = New-DefectDojoTest -EngagementId $engagementId -TestName $serviceName -TestType 215
                            Write-Log -Message "Test created successfully: $serviceName (ID: $($newTest.Id))" -Level 'INFO'
                            $testId = $newTest.Id
                        } catch {
                            Write-Log -Message "Failed to create test $serviceName : $_" -Level 'ERROR'
                            continue
                        }
                    } else {
                        Write-Log -Message "Using existing test: $serviceName (ID: $($existingTest.Id))" -Level 'INFO'
                        $testId = $existingTest.Id
                    }
                    
                    Upload-DefectDojoScan -FilePath $file -TestId $testId -ScanType 'Universal Parser - GitHub Secret Scanning'

                } catch {
                    $uploadErrors++
                    Write-Log -Message "Failed to upload $file to DefectDojo: $_" -Level 'ERROR'
                }
            }

             if ($uploadErrors -eq 0) {
                $msg = "GitHub Secret Scanning reports uploaded successfully."
                Write-Log -Message $msg -Level 'INFO'
                $result.Message = $msg
                
                try {
                    Remove-Item -Path $downloadRoot -Recurse -Force
                    Write-Log -Message "GitHub Secret Scanning download directory cleaned up successfully" -Level 'INFO'
                } catch {
                    Write-Log -Message "Failed to clean up download directory: $_" -Level 'WARNING'
                }
            } else {
                $msg = "GitHub Secret Scanning upload completed with $uploadErrors error(s)."
                Write-Log -Message $msg -Level 'WARNING'
                $result.Status = 'Warning'
                $result.Message = $msg
            }
        }
    } catch {
        $errMsg = "GitHub Secret Scanning processing failed: $_"
        Write-Log -Message $errMsg -Level 'ERROR'
        $result.Status = 'Error'
        $result.Message = $errMsg
    }
    return $result
}

function Invoke-GitHubDependabotWorkflow {
    param([hashtable]$Config)

    $result = @{
        Tool = 'GitHub Dependabot'
        Status = 'Success'
        Message = "Processing started"
    }

    Write-Log -Message "Starting GitHub Dependabot download..." -Level 'INFO'
    try {
        $orgs = @($Config.GitHub.Orgs)
        if (-not $orgs -or $orgs.Count -eq 0) {
            $msg = "No GitHub organizations configured. Skipping Dependabot."
             Write-Log -Message $msg -Level 'WARNING'
            $result.Status = 'Warning'
            $result.Message = $msg
            return $result
        }

        Write-Log -Message ("Processing GitHub organizations for Dependabot: {0}" -f ($orgs -join ', ')) -Level 'INFO'
        $dependabotFiles = GitHub-DependabotDownload -Owners $orgs
        Write-Log -Message "GitHub Dependabot download completed." -Level 'INFO'

        if (-not $dependabotFiles -or $dependabotFiles.Count -eq 0) {
            $msg = "No open Dependabot alerts downloaded; skipping uploads."
            Write-Log -Message $msg -Level 'INFO'
            $result.Message = $msg
            return $result
        }

        if ($Config.Tools.DefectDojo) {
            Write-Log -Message "Uploading GitHub Dependabot JSON files to DefectDojo..." -Level 'INFO'
            
            if (-not $Config.DefectDojo.GitHubDependabotTestId) {
                $msg = "No DefectDojo Dependabot test configured; skipping uploads."
                Write-Log -Message $msg -Level 'WARNING'
                $result.Status = 'Warning'
                $result.Message = $msg
                return $result
            }

            $uploadErrors = 0
            foreach ($file in $dependabotFiles) {
                try {
                    Upload-DefectDojoScan -FilePath $file -TestId $Config.DefectDojo.GitHubDependabotTestId -ScanType 'Universal Parser - GitHub Dependabot Aert5s'
                    Write-Log -Message "Uploaded Dependabot JSON: $([System.IO.Path]::GetFileName($file)) to test ID: $($Config.DefectDojo.GitHubDependabotTestId)" -Level 'INFO'
                } catch {
                    $uploadErrors++
                    Write-Log -Message "Failed to upload $file to DefectDojo: $_" -Level 'ERROR'
                }
            }

             if ($uploadErrors -eq 0) {
                $msg = "GitHub Dependabot JSON files uploaded successfully."
                Write-Log -Message $msg -Level 'INFO'
                $result.Message = $msg
                
                $downloadRoot = Join-Path ([IO.Path]::GetTempPath()) 'GitHubDependabot'
                try {
                    Remove-Item -Path $downloadRoot -Recurse -Force
                    Write-Log -Message "GitHub Dependabot download directory cleaned up successfully" -Level 'INFO'
                } catch {
                    Write-Log -Message "Failed to clean up Dependabot download directory: $_" -Level 'WARNING'
                }
            } else {
                $msg = "Dependabot uploads completed with $uploadErrors error(s)."
                Write-Log -Message $msg -Level 'WARNING'
                $result.Status = 'Warning'
                $result.Message = $msg
            }
        }
    } catch {
         $errMsg = "GitHub Dependabot processing failed: $_"
         Write-Log -Message $errMsg -Level 'ERROR'
         $result.Status = 'Error'
         $result.Message = $errMsg
    }
    return $result
}

# Helper to avoid circular dependency or code duplication if Launch.ps1 also used this logic.
# But since we are deprecating Launch.ps1, we can rely on Config structure.
function Get-GitHubFeatureState {
    param(
        [hashtable]$Config,
        [string]$ToolKey
    )
    if (-not $Config -or -not $Config.Tools -or -not $Config.Tools.GitHub) { return $false }

    # Map tool key to config sub-key
    $map = @{
        'GitHubCodeQL'         = 'CodeQL'
        'GitHubSecretScanning' = 'SecretScanning'
        'GitHubDependabot'     = 'Dependabot'
    }
    
    if (-not $map.ContainsKey($ToolKey)) { return $false }
    $feature = $map[$ToolKey]
    
    if ($Config.Tools.GitHub.ContainsKey($feature)) {
        return [bool]$Config.Tools.GitHub[$feature]
    }
    return $false
}
