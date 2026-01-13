# Pester tests for Logging module

Describe 'Initialize-Log' {
    BeforeAll {
        $testDirectory = Split-Path -Parent $PSCommandPath
        $repoRoot = Split-Path -Parent $testDirectory
        $modulePath = Join-Path $repoRoot 'modules/Logging.ps1'
        . $modulePath
    }

    It 'Creates log file with header' {
        $logDirectory = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        Initialize-Log -LogDirectory $logDirectory -LogFileName 'testlog.txt' -Overwrite

        $logFile = Join-Path $logDirectory 'testlog.txt'
        Test-Path $logFile | Should -BeTrue
        $content = Get-Content -Path $logFile -Raw
        $content | Should -Match '===== Log started at '
    }
}

Describe 'Write-Log' {
    BeforeAll {
        $testDirectory = Split-Path -Parent $PSCommandPath
        $repoRoot = Split-Path -Parent $testDirectory
        $modulePath = Join-Path $repoRoot 'modules/Logging.ps1'
        . $modulePath
    }

    Context 'Log initialized' {
        BeforeEach {
            $script:logDirectory = Join-Path $TestDrive ([guid]::NewGuid().ToString())
            Initialize-Log -LogDirectory $script:logDirectory -LogFileName 'testlog2.txt' -Overwrite
            $script:logFile = Join-Path $script:logDirectory 'testlog2.txt'
        }

        AfterEach {
            Remove-Variable -Scope Script -Name LogFilePath -ErrorAction SilentlyContinue
        }

        It 'Appends INFO log entry to file' {
            Write-Log -Message 'Hello World' -Level 'INFO'
            $lines = Get-Content $script:logFile
            $lastLine = $lines[-1]
            $lastLine | Should -Match 'INFO'
            $lastLine | Should -Match 'Hello World'
        }
    }

    Context 'Log not initialized' {
        BeforeEach {
            Remove-Variable -Scope Script -Name LogFilePath -ErrorAction SilentlyContinue
            Mock Write-Host {}
        }

        It 'Throws and notifies the user when log is not initialized' {
            { Write-Log -Message 'Test' } | Should -Throw
            Assert-MockCalled Write-Host -Times 1 -ParameterFilter { $Object -match 'Log file not initialized' }
        }
    }
}

Describe 'Cleanup-Logs' {
    BeforeAll {
        $testDirectory = Split-Path -Parent $PSCommandPath
        $repoRoot = Split-Path -Parent $testDirectory
        $modulePath = Join-Path $repoRoot 'modules/Logging.ps1'
        . $modulePath
    }

    It 'Deletes logs older than retention period' {
        $logDir = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -Path $logDir -ItemType Directory | Out-Null
        
        $retentionDays = 7
        
        # Create old file (8 days old)
        $oldFile = Join-Path $logDir 'old.log'
        New-Item -Path $oldFile -ItemType File | Out-Null
        (Get-Item $oldFile).LastWriteTime = (Get-Date).AddDays(-($retentionDays + 1))
        
        # Create new file (today)
        $newFile = Join-Path $logDir 'new.log'
        New-Item -Path $newFile -ItemType File | Out-Null
        
        Cleanup-Logs -LogDirectory $logDir -RetentionDays $retentionDays
        
        Test-Path $oldFile | Should -BeFalse
        Test-Path $newFile | Should -BeTrue
    }

    It 'Does nothing if directory does not exist' {
        $logDir = Join-Path $TestDrive "NonExistentDir"
        { Cleanup-Logs -LogDirectory $logDir -RetentionDays 7 } | Should -Not -Throw
    }
}

