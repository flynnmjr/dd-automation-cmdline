# DefectDojo Automation CLI

## Overview
This PowerShell-based **headless CLI tool** automates the export and import of security findings between various tools and DefectDojo. It is designed to be run as a scheduled task or cron job.

Supported Integrations:
- **Tenable WAS** → Defect Dojo
- **SonarQube** → Defect Dojo (API-based reimport)
- **GitHub Advanced Security** → Defect Dojo
    - CodeQL SARIF reports
    - Secret Scanning JSON
    - Dependabot JSON
- **BurpSuite** → Defect Dojo (XML report parsing)
- **Webhooks** → Notification support (Slack/Teams integration)

## Prerequisites
- Windows 10/11 or Windows Server (capable of running PowerShell Core)
- **PowerShell 7.2** or later
- Network access to APIs (Defect Dojo, Tenable WAS, GitHub, etc.)
- Environment variables set for API keys and credentials
- **Pester 5+** (Required for running tests in `Tests/`)

## Continuous Integration

This project uses **GitHub Actions** to automatically run all Pester tests on every pull request.

**What happens on PRs**:
- All tests in `Tests/` are executed automatically
- Test results appear in the PR "Checks" tab
- PRs with failing tests are blocked from merging (if branch protection is enabled)

**For Contributors**:
- Create applicable tests for all new code
- Run new and existing tests locally before pushing: `Invoke-Pester .\Tests\`
- Ensure all tests pass before creating a PR

## Installation
1. Clone this repository to your local machine or server.
2. Ensure you have set the required environment variables (see below).
3. Create a custom configuration file by copying the example:
   `Copy-Item config\config.psd1.example config\config.psd1`
4. Update `config\config.psd1` with your specific URLs, paths, and tool preferences.

## Configuration

### Environment Variables
| Variable            | Description|
|---------------------|--------------------------------|
| `DOJO_API_KEY`      | API key for Defect Dojo |
| `TENWAS_ACCESS_KEY` | API access key for Tenable WAS |
| `TENWAS_SECRET_KEY` | API secret key for Tenable WAS |
| `GITHUB_PAT`        | API Key for GitHub (must have access to configured orgs) |

### Config File
The configuration file (`config\config.psd1`) controls which tools run and how they behave.

#### Enabling Tools
Toggle tools on or off in the `Tools` block:
```powershell
Tools = @{
    TenableWAS = $true
    SonarQube  = $false
    BurpSuite  = $false
    DefectDojo = $true
    GitHub = @{
        CodeQL         = $true
        SecretScanning = $false
        Dependabot     = $false
    }
}
```

#### Webhook Notifications
Configure notifications for automation results (e.g., Slack or Teams webhooks):
```powershell
Webhooks = @{
    Enabled       = $true
    Url           = 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'
    ReportSuccess = $true # Set to $false to only report Failures/Errors
}
```

#### API Base URLs
Set the base URLs for your instances:
```powershell
ApiBaseUrls = @{
    TenableWAS = 'https://fedcloud.tenable.com/'
    SonarQube  = 'https://sonarqube.internal.example.com'
    DefectDojo = 'https://defect-dojo.internal.example.com/api/v2'
    GitHub     = 'https://api.github.com'
}
```

## Usage

The tool is executed via the `Run-Automation.ps1` script. It runs in a headless mode, performing all enabled tasks sequentially.

### Standard Run
Uses the default config file at `config\config.psd1`:
```powershell
.\Run-Automation.ps1
```

### Custom Config Path
Specify a different configuration file (useful for managing multiple pipelines):
```powershell
.\Run-Automation.ps1 -ConfigPath "C:\Configs\project-a.psd1"
```

### Logging
- Console output provides real-time status.
- Detailed logs are written to `logs\Run-Automation.log`.
- Log files are rotated/overwritten on each run.

## Integrations Detail

### Tenable WAS
Exports completed scans from Tenable WAS and uploads them to DefectDojo.
- **Trigger**: Enabled via `Tools.TenableWAS = $true`
- **Config**: Requires `TenableWASScanId` in config and `TENWAS_` env vars.
- **Workflow**: Initiates report generation -> Downloads CSV -> Uploads to DD.

### SonarQube
Triggers DefectDojo's API-based import for SonarQube.
- **Trigger**: Enabled via `Tools.SonarQube = $true`
- **Config**: Requires `DefectDojo.APIScanConfigId` and `SonarQubeTestId`.
- **Workflow**: Sends a re-import request to DefectDojo to fetch findings directly from SonarQube.

### GitHub Integration
Scans all repositories in configured GitHub organizations.
- **Trigger**: Enabled via `Tools.GitHub` sub-keys.
- **Config**: Define orgs in `GitHub.Orgs` array.
- **Filters**: Use `IncludeRepos` and `ExcludeRepos` to control scope.
- **Workflow**:
    - **CodeQL**: Downloads latest SARIF.
    - **Secret Scanning**: Downloads open alerts (JSON).
    - **Dependabot**: Downloads open alerts (JSON).

### BurpSuite
Uploads a local XML report to DefectDojo.
- **Trigger**: Enabled via `Tools.BurpSuite = $true`
- **Config**: `Paths.BurpSuiteXmlFolder` must point to the folder containing the XML report.
- **Workflow**: Finds XML file in folder -> Uploads to configured `BurpSuiteTestId`.

## Modules Structure
| Module | Description |
|--------|-------------|
| `Run-Automation.ps1` | **Entry Point**. Orchestrates the workflow. |
| `AutomationWorkflow` | Contains the high-level logic for invoking each tool's workflow. |
| `Config` | Loads and validates configuration files. |
| `Logging` | centralized logging capability. |
| `Webhooks` | Handles sending status notifications to external services. |
| `EnvValidator` | Checks for required environment variables. |
| `Uploader` | Helper for generic DefectDojo uploads. |
| `TenableWAS`, `SonarQube`, `BurpSuite`, `GitHub` | Tool-specific implementation logic. |
