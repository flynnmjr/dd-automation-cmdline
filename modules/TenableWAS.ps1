<#
.SYNOPSIS
    Generate and download a Tenable WAS scan report via API
.DESCRIPTION
    Uses the Tenable WAS v2 API to request generation of a scan report for a specified scan ID,
    then downloads the resulting CSV file to a temporary location and returns its path.
    This is a two-step process: a PUT request to initiate report generation followed by
    a GET request to retrieve the report.
#>

. (Join-Path $PSScriptRoot 'Logging.ps1')
. (Join-Path $PSScriptRoot 'Config.ps1')

function Export-TenableWASScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$ScanId
    )

    # Load configuration
    $config = Get-Config


    # Determine Scan ID from parameter
    if (-not $ScanId) {
        Throw "No TenableWAS ScanId specified. Internal calling error."
    }

    # Prepare API connection
    $apiUrl = $config.ApiBaseUrls.TenableWAS.TrimEnd('/')
    $accessKey = [Environment]::GetEnvironmentVariable('TENWAS_ACCESS_KEY')
    $secretKey = [Environment]::GetEnvironmentVariable('TENWAS_SECRET_KEY')
    if (-not $accessKey -or -not $secretKey) {
        Write-Log -Message "Missing Tenable WAS API credentials (TENWAS_ACCESS_KEY or TENWAS_SECRET_KEY)." -Level 'ERROR'
        Throw "Missing Tenable WAS API credentials (TENWAS_ACCESS_KEY or TENWAS_SECRET_KEY)."
    }

    # Build report endpoint URI
    $reportUri = "$apiUrl/was/v2/scans/$ScanId/report"

    # Common request headers
    $headers = @{ 
        "X-ApiKeys"    = "accessKey=$accessKey;secretKey=$secretKey" 
        "Content-Type" = "text/csv"
        "Accept"       = "application/json"
    }

    # Initiate report generation via PUT
    Write-Log -Message "Initiating report generation for Tenable WAS scan ID $ScanId" -Level 'INFO'
    Invoke-RestMethod -Method Put -Uri $reportUri -Headers $headers -UseBasicParsing

    # Allow time for report generation
    Start-Sleep -Seconds 2

    # Download the generated report via GET
    Write-Log -Message "Scan report URL: $reportUri" -Level 'INFO'
    Write-Log -Message "Downloading report for Tenable WAS scan ID $ScanId" -Level 'INFO'
    $tempPath = [System.IO.Path]::GetTempPath()
    $fileName = "$ScanId-report.csv"
    $outFile = Join-Path -Path $tempPath -ChildPath $fileName

        $headers = @{ 
        "X-ApiKeys"    = "accessKey=$accessKey;secretKey=$secretKey" 
        "Accept"       = "application/json"
    }
    Invoke-RestMethod -Method GET -Uri $reportUri -Headers $headers -OutFile $outFile -ContentType 'text/csv' -UseBasicParsing

    Write-Log -Message "Tenable WAS report saved to $outFile" -Level 'INFO'
    return $outFile
}

function Get-TenableWASScanConfigs {
    [CmdletBinding()]
    param()

    $config = Get-Config
    $apiUrl = $config.ApiBaseUrls.TenableWAS.TrimEnd('/')
    $accessKey = [Environment]::GetEnvironmentVariable('TENWAS_ACCESS_KEY')
    $secretKey = [Environment]::GetEnvironmentVariable('TENWAS_SECRET_KEY')

    if (-not $accessKey -or -not $secretKey) {
        Write-Log -Message "Missing Tenable WAS API credentials." -Level 'ERROR'
        return @()
    }

    $headers = @{ 
        "X-ApiKeys"    = "accessKey=$accessKey;secretKey=$secretKey" 
        "Content-Type" = "application/json"
        "Accept"       = "application/json"
    }

    $pageSize = 200
    $offset = 0

    try {
        Write-Log -Message "Fetching Tenable WAS scan configurations..." -Level 'INFO'

        $results = @()
        $seenIds = [System.Collections.Generic.HashSet[string]]::new()
        
        do {
            $searchUri = "$apiUrl/was/v2/configs/search?limit=$pageSize&offset=$offset"
            $response = Invoke-RestMethod -Method Post -Uri $searchUri -Headers $headers -UseBasicParsing

            $items = @()
            if ($null -ne $response.items) {
                $items = $response.items
            } elseif ($null -ne $response.data) {
                $items = $response.data
            }

            $addedThisPage = 0
            foreach ($item in $items) {
                # Skip trashed configs
                if ($item.in_trash) {
                    continue
                }
                
                $idStr = [string]$item.config_id
                if ($idStr -and $seenIds.Add($idStr)) {
                    $results += [PSCustomObject]@{
                        Id = $idStr
                        Name = $item.name
                    }
                    $addedThisPage++
                }
            }

            $offset += $pageSize
        } while ($items.Count -eq $pageSize)

        Write-Log -Message "Found $($results.Count) active Tenable WAS scan configurations." -Level 'INFO'
        return $results

    } catch {
        Write-Log -Message "Failed to fetch Tenable WAS scan configs: $_" -Level 'ERROR'
        return @()
    }
}

#DEBUG
#Export-TenableWASScan -ScanId 06f8c725-d9ed-4473-a063-be73b5ace9ca
