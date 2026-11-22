# WinGet behavior tests. Windows runner + PowerShell 7 required.
# WinGet is replaced by tests/mocks/winget.cmd. Each case is independent.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

. (Join-Path $PSScriptRoot 'TestCommon.ps1')

function Test-LogHasCommand {
    param(
        [Parameter(Mandatory)][string[]]$Lines,
        [Parameter(Mandatory)][string]$Command
    )

    return @($Lines | Where-Object { $_ -match "^(?i)$([regex]::Escape($Command))\b" }).Count -gt 0
}

try {
    Invoke-Test 'Check_WhenUpdatesAreAvailable_ShouldNotInstallOrUpgrade' {
        $root = New-TestRoot
        $logPath = Join-Path $root 'winget.log'
        try {
            # Arrange
            Reset-WinGetMock -Mode updater -LogPath $logPath -Installed 'Git.Git=2.47.0' -Upgrades 'Git.Git=2.48.0'

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-Check')
            $lines = @(Get-WinGetLogLines -LogPath $logPath)

            # Assert
            Assert-Result (
                $result.ExitCode -eq 0 -and
                -not (Test-LogHasCommand -Lines $lines -Command 'install') -and
                -not (Test-LogHasCommand -Lines $lines -Command 'upgrade') -and
                $result.Output -match 'UPDATE AVAILABLE' -and
                $result.Output -match 'INSTALL AVAILABLE'
            ) (Get-FailureDetail -Result $result -Message '-Check installed or upgraded an application.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Check_WhenManagerControlsApplication_ShouldReportManualCheck' {
        $root = New-TestRoot
        $logPath = Join-Path $root 'winget.log'
        try {
            # Arrange: DataGrip is left to JetBrains Toolbox when that manager is installed
            Reset-WinGetMock -Mode updater -LogPath $logPath -Installed 'JetBrains.Toolbox=2.1.0'

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-Check')

            # Assert
            Assert-Result ($result.ExitCode -eq 0 -and $result.Output -match 'MANUAL CHECK REQUIRED') (
                Get-FailureDetail -Result $result -Message '-Check did not report an expected manual check.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Update_WhenSomeApplicationsAreMissing_ShouldUpgradeWithoutInstalling' {
        $root = New-TestRoot
        $logPath = Join-Path $root 'winget.log'
        try {
            # Arrange
            Reset-WinGetMock -Mode updater -LogPath $logPath -Installed 'Git.Git=2.47.0' -Upgrades 'Git.Git=2.48.0'

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-Update')
            $lines = @(Get-WinGetLogLines -LogPath $logPath)
            $upgradedGit = @($lines | Where-Object { $_ -match '(?i)^upgrade\b' -and $_ -match '(?i)\bGit\.Git\b' }).Count -gt 0

            # Assert
            Assert-Result (
                $result.ExitCode -eq 0 -and
                $upgradedGit -and
                -not (Test-LogHasCommand -Lines $lines -Command 'install') -and
                $result.Output -match 'UPDATED' -and
                $result.Output -match 'NOT INSTALLED'
            ) (Get-FailureDetail -Result $result -Message '-Update installed a missing application or skipped the upgrade.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Run_WhenApplicationsNeedChanges_ShouldInstallMissingAndUpgradeInstalled' {
        $root = New-TestRoot
        $logPath = Join-Path $root 'winget.log'
        try {
            # Arrange
            Reset-WinGetMock -Mode updater -LogPath $logPath -Installed 'Git.Git=2.47.0' -Upgrades 'Git.Git=2.48.0'

            # Act
            $result = Invoke-Updater -Root $root -Arguments @()
            $lines = @(Get-WinGetLogLines -LogPath $logPath)
            $installedObsidian = @($lines | Where-Object { $_ -match '(?i)^install\b' -and $_ -match '(?i)\bObsidian\.Obsidian\b' }).Count -gt 0
            $upgradedGit = @($lines | Where-Object { $_ -match '(?i)^upgrade\b' -and $_ -match '(?i)\bGit\.Git\b' }).Count -gt 0

            # Assert
            Assert-Result (
                $result.ExitCode -eq 0 -and
                $installedObsidian -and
                $upgradedGit -and
                $result.Output -match 'INSTALLED' -and
                $result.Output -match 'UPDATED'
            ) (Get-FailureDetail -Result $result -Message 'The normal run did not install Obsidian and upgrade Git.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Run_WhenInstallFails_ShouldContinueAndExitWithCode1' {
        $root = New-TestRoot
        $logPath = Join-Path $root 'winget.log'
        try {
            # Arrange
            Reset-WinGetMock -Mode updater -LogPath $logPath -InstallExit '1'

            # Act
            $result = Invoke-Updater -Root $root -Arguments @()

            # Assert
            Assert-Result (
                $result.ExitCode -eq 1 -and
                $result.Output -match '(?s)Checking Obsidian \.\.\..*INSTALL FAILED.*Checking Notepad\+\+ \.\.\..*INSTALL FAILED'
            ) (Get-FailureDetail -Result $result -Message 'An installation failure stopped the run or returned success.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Update_WhenUpgradeFails_ShouldExitWithCode1' {
        $root = New-TestRoot
        $logPath = Join-Path $root 'winget.log'
        try {
            # Arrange
            Reset-WinGetMock -Mode updater -LogPath $logPath -Installed 'Git.Git=2.47.0' -Upgrades 'Git.Git=2.48.0' -UpgradeExit '1'

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-Update')

            # Assert
            Assert-Result ($result.ExitCode -eq 1 -and $result.Output -match 'UPDATE FAILED') (
                Get-FailureDetail -Result $result -Message 'A failed upgrade returned success.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Run_WhenCatalogCannotBeRead_ShouldExitWithCode1' {
        $root = New-TestRoot
        $logPath = Join-Path $root 'winget.log'
        try {
            # Arrange
            Reset-WinGetMock -Mode updater -LogPath $logPath -SourceExit '1'

            # Act
            $result = Invoke-Updater -Root $root -Arguments @()
            $lines = @(Get-WinGetLogLines -LogPath $logPath)

            # Assert
            Assert-Result (
                $result.ExitCode -eq 1 -and
                $result.Output -match 'catalog refresh failed' -and
                -not (Test-LogHasCommand -Lines $lines -Command 'install') -and
                -not (Test-LogHasCommand -Lines $lines -Command 'list')
            ) (Get-FailureDetail -Result $result -Message 'A catalog failure continued or returned success.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Run_WhenInventoryCannotBeRead_ShouldExitWithCode1' {
        $root = New-TestRoot
        $logPath = Join-Path $root 'winget.log'
        try {
            # Arrange
            Reset-WinGetMock -Mode updater -LogPath $logPath -ListExit '1'

            # Act
            $result = Invoke-Updater -Root $root -Arguments @()
            $lines = @(Get-WinGetLogLines -LogPath $logPath)

            # Assert
            Assert-Result (
                $result.ExitCode -eq 1 -and
                $result.Output -match 'Cannot read installed packages' -and
                -not (Test-LogHasCommand -Lines $lines -Command 'install')
            ) (Get-FailureDetail -Result $result -Message 'An inventory failure continued or returned success.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Check_WhenOneApplicationThrows_ShouldContinueAndExitWithCode1' {
        $root = New-TestRoot
        $logPath = Join-Path $root 'winget.log'
        try {
            # Arrange: a custom release series whose WinGet version cannot be parsed
            $configurationPath = Get-ConfigurationPath -Root $root
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $configurationPath) | Out-Null
            Set-Content -LiteralPath $configurationPath -Encoding utf8 -Value '{"SchemaVersion":1,"RemovedPackageIds":[],"UpdateOnlyPackageIds":[],"CustomApplications":[{"Name":"Broken Tool","PackageId":"Example.Broken","VersionPrefix":"1."}]}'
            Reset-WinGetMock -Mode updater -LogPath $logPath -BadVersionId 'Example.Broken'

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-Check')

            # Assert
            Assert-Result (
                $result.ExitCode -eq 1 -and
                $result.Output -match 'Broken Tool' -and
                $result.Output -match 'CHECK FAILED' -and
                $result.Output -match 'Checking PowerShell'
            ) (Get-FailureDetail -Result $result -Message 'One application exception stopped the remaining applications or returned success.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Complete-TestRun -Name 'WinGet'
}
finally {
    Clear-WinGetMockEnvironment
}
