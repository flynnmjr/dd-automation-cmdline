<#
.SYNOPSIS
    Functions to send webhook notifications for automation results.
.DESCRIPTION
    Sends JSON payloads to a configured webhook URL (e.g., Slack, Teams, Discord).
    Supports partial reporting based on configuration (Success/Failure toggles).
#>

function Send-WebhookNotification {
    param(
        [Parameter(Mandatory)]
        [array]$Results,

        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    if (-not $Config.Webhooks.Enabled) {
        Write-Log -Message "Webhook notifications disabled in config." -Level 'INFO'
        return
    }

    if (-not $Config.Webhooks.Url) {
        Write-Log -Message "Webhook enabled but no URL configured." -Level 'WARNING'
        return
    }

    # Filter results based on reporting preferences
    $reportSuccess = $true
    if ($Config.Webhooks.ContainsKey('ReportSuccess')) {
        $reportSuccess = [bool]$Config.Webhooks.ReportSuccess
    }

    $filteredResults = @()
    foreach ($res in $Results) {
        if ($res.Status -eq 'Success' -and -not $reportSuccess) {
            continue
        }
        $filteredResults += $res
    }

    if ($filteredResults.Count -eq 0) {
        Write-Log -Message "No results to report via webhook (based on ReportSuccess settings)." -Level 'INFO'
        return
    }

    # Construct Payload
    # Using a generic Card/Attachment style that works reasonably well with connectors like Teams/Slack
    # For better Teams specific support, we might need Adaptive Cards, but let's stick to a rich JSON structure.
    
    $overallStatus = "Success"
    if ($filteredResults.Status -contains 'Error') {
        $overallStatus = "Failure"
    } elseif ($filteredResults.Status -contains 'Warning') {
        $overallStatus = "Warning"
    }

    $color = switch($overallStatus) {
        "Success" { "00FF00" } # Green
        "Warning" { "FFA500" } # Orange
        "Failure" { "FF0000" } # Red
    }

    $fields = @()
    foreach ($res in $filteredResults) {
        $icon = switch($res.Status) {
            'Success' { '✅' }
            'Warning' { '⚠️' }
            'Error'   { '❌' }
        }
        $fields += @{
            name = "$icon $($res.Tool)"
            value = $res.Message
            inline = $false
        }
    }

    $payload = @{
        title = "DefectDojo Automation Report"
        text = "Automation run completed with status: **$overallStatus**"
        themeColor = $color # Teams specific
        sections = @(
            @{
                activityTitle = "Summary"
                activitySubtitle = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
                facts = $fields | ForEach-Object {
                    @{
                        name = $_.name
                        value = $_.value
                    }
                }
            }
        )
        # Slack compatibility fallback (simplified)
        attachments = @(
            @{
                color = "#$color"
                title = "DefectDojo Automation Report"
                fields = $fields
                footer = "DD Automation CLI"
                ts = [int][double]::Parse((Get-Date -UFormat %s))
            }
        )
    }

    $jsonPayload = $payload | ConvertTo-Json -Depth 10 -Compress

    Write-Log -Message "Sending webhook notification to $($Config.Webhooks.Url)..." -Level 'INFO'
    try {
        $response = Invoke-RestMethod -Uri $Config.Webhooks.Url -Method Post -Body $jsonPayload -ContentType 'application/json' -ErrorAction Stop
        Write-Log -Message "Webhook sent successfully." -Level 'INFO'
    } catch {
        Write-Log -Message "Failed to send webhook: $_" -Level 'ERROR'
        if ($_.Exception.Response) {
             # Try to read response stream for more details
             $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
             $details = $reader.ReadToEnd()
             Write-Log -Message "Webhook Response Details: $details" -Level 'ERROR'
        }
    }
}
