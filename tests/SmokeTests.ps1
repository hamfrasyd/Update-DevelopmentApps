# Configuration smoke tests. Windows runner + PowerShell 7 required.
# Each test is Arrange, Act, Assert and contains one assertion. Names follow
# Subject_WhenCondition_ShouldExpectedBehavior. Configuration state is not shared.
# WinGet installation and update behavior is covered by tests/WinGetTests.ps1.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

. (Join-Path $PSScriptRoot 'TestCommon.ps1')


try {
    # Parameter contract. These tests inspect the script and do not run it.
    Invoke-Test 'Check_WhenDeclared_ShouldExposeOnlyAliasC' {
        # Arrange
        $parameters = (Get-Command -Name $script:ScriptPath).Parameters

        # Act
        $aliases = @(Get-ParameterAliases -Parameters $parameters -Name 'Check')

        # Assert
        Assert-Result ($parameters.ContainsKey('Check') -and $aliases.Count -eq 1 -and $aliases[0] -eq 'c') 'Check must only use -c.'
    }

    Invoke-Test 'CheckOnly_WhenParametersAreInspected_ShouldNotBeDeclared' {
        # Arrange
        $parameters = (Get-Command -Name $script:ScriptPath).Parameters

        # Act
        $declared = $parameters.ContainsKey('CheckOnly')

        # Assert
        Assert-Result (-not $declared) 'CheckOnly is still a parameter.'
    }

    Invoke-Test 'Update_WhenDeclared_ShouldExposeOnlyAliasU' {
        # Arrange
        $parameters = (Get-Command -Name $script:ScriptPath).Parameters

        # Act
        $aliases = @(Get-ParameterAliases -Parameters $parameters -Name 'Update')

        # Assert
        Assert-Result ($parameters.ContainsKey('Update') -and $aliases.Count -eq 1 -and $aliases[0] -eq 'u') 'Update must only use -u.'
    }

    Invoke-Test 'UpdateInstalled_WhenParametersAreInspected_ShouldNotBeDeclared' {
        # Arrange
        $parameters = (Get-Command -Name $script:ScriptPath).Parameters

        # Act
        $declared = $parameters.ContainsKey('UpdateInstalled')

        # Assert
        Assert-Result (-not $declared) 'UpdateInstalled is still a parameter.'
    }

    Invoke-Test 'Remove_WhenDeclared_ShouldExposeOnlyAliasR' {
        # Arrange
        $parameters = (Get-Command -Name $script:ScriptPath).Parameters

        # Act
        $aliases = @(Get-ParameterAliases -Parameters $parameters -Name 'Remove')

        # Assert
        Assert-Result ($parameters.ContainsKey('Remove') -and $aliases.Count -eq 1 -and $aliases[0] -eq 'r') 'Remove must only use -r.'
    }

    Invoke-Test 'List_WhenProfileIsEmpty_ShouldShowObsidianAsIncluded' {
        $root = New-TestRoot
        try {
            # Arrange: empty local profile

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-l')

            # Assert
            Assert-Result ($result.Output -match '(?m)^Obsidian\s+Default\s+Included\b') (
                Get-FailureDetail -Result $result -Message '-List did not show Obsidian as Included.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'List_WhenProfileIsEmpty_ShouldNotCreateConfigurationFile' {
        $root = New-TestRoot
        try {
            # Arrange
            $configurationPath = Get-ConfigurationPath -Root $root

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-l')

            # Assert
            Assert-Result (-not (Test-Path -LiteralPath $configurationPath)) (
                Get-FailureDetail -Result $result -Message '-List unexpectedly created the config file.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Remove_WhenObsidianIsIncluded_ShouldExcludeObsidian' {
        $root = New-TestRoot
        try {
            # Arrange: empty local profile

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-r', 'Obsidian')

            # Assert
            $configuration = Read-TestConfiguration -Root $root
            Assert-Result (@($configuration.RemovedPackageIds) -contains 'Obsidian.Obsidian') (
                Get-FailureDetail -Result $result -Message 'Remove did not exclude default Obsidian.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'DisableInstall_WhenGitIsIncluded_ShouldRecordGitAsUpdateOnly' {
        $root = New-TestRoot
        try {
            # Arrange: empty local profile

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-di', 'Git')

            # Assert
            $configuration = Read-TestConfiguration -Root $root
            Assert-Result (@($configuration.UpdateOnlyPackageIds) -contains 'Git.Git') (
                Get-FailureDetail -Result $result -Message 'DisableInstall did not save Git.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Add_WhenPackageIdIsDiscordDiscord_ShouldSaveCustomDiscord' {
        $root = New-TestRoot
        try {
            # Arrange: empty local profile

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-a', 'Discord', '-PackageId', 'Discord.Discord')

            # Assert
            $configuration = Read-TestConfiguration -Root $root
            Assert-Result (@($configuration.CustomApplications | ForEach-Object { $_.PackageId }) -contains 'Discord.Discord') (
                Get-FailureDetail -Result $result -Message 'Add did not save Discord.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Add_WhenDiscordIsAlreadyConfigured_ShouldReportAlreadyConfigured' {
        $root = New-TestRoot
        try {
            # Arrange
            $null = Save-TestConfiguration -Root $root -CustomApplications @(@{ Name = 'Discord'; PackageId = 'Discord.Discord' })

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-a', 'Discord', '-PackageId', 'Discord.Discord')

            # Assert
            Assert-Result ($result.Output -match 'already configured') (
                Get-FailureDetail -Result $result -Message 'Duplicate Add did not report that Discord is already configured.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'List_WhenObsidianIsRemoved_ShouldShowObsidianAsRemoved' {
        $root = New-TestRoot
        try {
            # Arrange
            $null = Save-TestConfiguration -Root $root -RemovedPackageIds @('Obsidian.Obsidian')

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-L')

            # Assert
            Assert-Result ($result.Output -match '(?m)^Obsidian\s+Default\s+Removed\b') (
                Get-FailureDetail -Result $result -Message '-List did not report Removed for Obsidian.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'List_WhenGitIsUpdateOnly_ShouldShowGitAsUpdateOnly' {
        $root = New-TestRoot
        try {
            # Arrange
            $null = Save-TestConfiguration -Root $root -UpdateOnlyPackageIds @('Git.Git')

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-L')

            # Assert
            Assert-Result ($result.Output -match '(?m)^Git\s+Default\s+Update Only\b') (
                Get-FailureDetail -Result $result -Message '-List did not report Update Only for Git.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'List_WhenDiscordIsCustom_ShouldShowDiscordAsCustomAdded' {
        $root = New-TestRoot
        try {
            # Arrange
            $null = Save-TestConfiguration -Root $root -CustomApplications @(@{ Name = 'Discord'; PackageId = 'Discord.Discord' })

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-L')

            # Assert
            Assert-Result ($result.Output -match '(?m)^Discord\s+Custom\s+Custom Added\b') (
                Get-FailureDetail -Result $result -Message '-List did not report Custom Added for Discord.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'DisableInstall_WhenObsidianIsExcluded_ShouldReportThatObsidianMustBeAddedFirst' {
        $root = New-TestRoot
        try {
            # Arrange
            $null = Save-TestConfiguration -Root $root -RemovedPackageIds @('Obsidian.Obsidian')

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-DI', 'Obsidian')

            # Assert
            Assert-Result ($result.Output -match 'excluded from the updater list') (
                Get-FailureDetail -Result $result -Message 'DisableInstall did not report that Obsidian is excluded.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'EnableInstall_WhenGitIsUpdateOnly_ShouldClearUpdateOnlyPolicy' {
        $root = New-TestRoot
        try {
            # Arrange
            $null = Save-TestConfiguration -Root $root -UpdateOnlyPackageIds @('Git.Git')

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-EI', 'Git')

            # Assert
            $configuration = Read-TestConfiguration -Root $root
            Assert-Result (@($configuration.UpdateOnlyPackageIds) -notcontains 'Git.Git') (
                Get-FailureDetail -Result $result -Message 'EnableInstall did not reset Git.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Add_WhenObsidianIsExcluded_ShouldRestoreObsidian' {
        $root = New-TestRoot
        try {
            # Arrange
            $null = Save-TestConfiguration -Root $root -RemovedPackageIds @('Obsidian.Obsidian')

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-Add', 'Obsidian')

            # Assert
            $configuration = Read-TestConfiguration -Root $root
            Assert-Result (@($configuration.RemovedPackageIds) -notcontains 'Obsidian.Obsidian') (
                Get-FailureDetail -Result $result -Message 'Add did not restore excluded default Obsidian.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Remove_WhenDiscordIsCustom_ShouldDeleteCustomDiscord' {
        $root = New-TestRoot
        try {
            # Arrange
            $null = Save-TestConfiguration -Root $root -CustomApplications @(@{ Name = 'Discord'; PackageId = 'Discord.Discord' })

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-Remove', 'Discord')

            # Assert
            $configuration = Read-TestConfiguration -Root $root
            Assert-Result (@($configuration.CustomApplications | ForEach-Object { $_.PackageId }) -notcontains 'Discord.Discord') (
                Get-FailureDetail -Result $result -Message 'Remove did not delete custom Discord.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Remove_WhenCustomDiscordDisablesInstall_ShouldClearInstallPolicy' {
        $root = New-TestRoot
        try {
            # Arrange
            $null = Save-TestConfiguration -Root $root -UpdateOnlyPackageIds @('Discord.Discord') -CustomApplications @(@{ Name = 'Discord'; PackageId = 'Discord.Discord' })

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-r', 'Discord')

            # Assert
            $configuration = Read-TestConfiguration -Root $root
            Assert-Result (@($configuration.UpdateOnlyPackageIds) -notcontains 'Discord.Discord') (
                Get-FailureDetail -Result $result -Message 'Remove did not clear the install policy for custom Discord.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Add_WhenObsidianIsAlreadyIncluded_ShouldReportAlreadyIncluded' {
        $root = New-TestRoot
        try {
            # Arrange: Obsidian is a default and is not excluded
            $null = Save-TestConfiguration -Root $root

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-A', 'Obsidian')

            # Assert
            Assert-Result ($result.Output -match 'already included') (
                Get-FailureDetail -Result $result -Message 'Add should report an already included default.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Add_WhenObsidianIsAlreadyIncluded_ShouldLeaveConfigurationUnchanged' {
        $root = New-TestRoot
        try {
            # Arrange
            $configurationPath = Save-TestConfiguration -Root $root
            $before = Get-Content -LiteralPath $configurationPath -Raw

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-A', 'Obsidian')

            # Assert
            Assert-Result ($before -ceq (Get-Content -LiteralPath $configurationPath -Raw)) (
                Get-FailureDetail -Result $result -Message 'Duplicate Add modified JSON.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    $updaterOptions = @(
        @{ Option = '-c'; Condition = 'C' }
        @{ Option = '-Check'; Condition = 'Check' }
        @{ Option = '-u'; Condition = 'U' }
        @{ Option = '-Update'; Condition = 'Update' }
        @{ Option = '-d'; Condition = 'LowercaseD' }
        @{ Option = '-D'; Condition = 'UppercaseD' }
        @{ Option = '-ssu'; Condition = 'LowercaseSsu' }
        @{ Option = '-SSU'; Condition = 'UppercaseSsu' }
    )
    foreach ($updaterOption in $updaterOptions) {
        Invoke-Test "List_WhenCombinedWith$($updaterOption.Condition)_ShouldRejectUpdaterOption" {
            $root = New-TestRoot
            try {
                # Arrange
                $option = $updaterOption.Option

                # Act
                $result = Invoke-Updater -Root $root -Arguments @('-l', $option)

                # Assert
                Assert-Result ($result.Output -match 'Configuration commands cannot be combined') (
                    Get-FailureDetail -Result $result -Message "Alias $option did not bind to its updater option.")
            }
            finally {
                Remove-TestRoot $root
            }
        }
    }

    # -re is still a unique prefix of -Remove, so these are the names that must be rejected.
    foreach ($removedName in @('-CheckOnly', '-UpdateInstalled')) {
        Invoke-Test "$($removedName.TrimStart('-'))_WhenPassedOnCommandLine_ShouldBeRejected" {
            $root = New-TestRoot
            try {
                # Arrange
                $parameterName = $removedName

                # Act
                $result = Invoke-Updater -Root $root -Arguments @($parameterName)

                # Assert
                Assert-Result ($result.Output -match 'parameter cannot be found') (
                    Get-FailureDetail -Result $result -Message "Removed name $parameterName is still accepted.")
            }
            finally {
                Remove-TestRoot $root
            }
        }
    }

    Invoke-Test 'Remove_WhenConfigurationJsonIsInvalid_ShouldReportFileUnchanged' {
        $root = New-TestRoot
        try {
            # Arrange
            $configurationPath = Get-ConfigurationPath -Root $root
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $configurationPath) | Out-Null
            Set-Content -LiteralPath $configurationPath -Value '{invalid json' -Encoding utf8

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-r', 'Postman')

            # Assert
            Assert-Result ($result.Output -match 'has not been changed') (
                Get-FailureDetail -Result $result -Message 'Invalid JSON was not reported as unchanged.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Remove_WhenConfigurationJsonIsInvalid_ShouldLeaveFileUnchanged' {
        $root = New-TestRoot
        try {
            # Arrange
            $configurationPath = Get-ConfigurationPath -Root $root
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $configurationPath) | Out-Null
            Set-Content -LiteralPath $configurationPath -Value '{invalid json' -Encoding utf8
            $before = Get-Content -LiteralPath $configurationPath -Raw

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-r', 'Postman')

            # Assert
            Assert-Result ($before -ceq (Get-Content -LiteralPath $configurationPath -Raw)) (
                Get-FailureDetail -Result $result -Message 'Invalid JSON was modified.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Remove_WhenConfigurationJsonIsInvalid_ShouldExitWithCode1' {
        $root = New-TestRoot
        try {
            # Arrange
            $configurationPath = Get-ConfigurationPath -Root $root
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $configurationPath) | Out-Null
            Set-Content -LiteralPath $configurationPath -Value '{invalid json' -Encoding utf8

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-r', 'Postman')

            # Assert
            Assert-Result ($result.ExitCode -eq 1) (
                Get-FailureDetail -Result $result -Message 'Invalid JSON returned a success exit code.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Save_WhenConfigurationIsSavedThreeTimes_ShouldKeepSettingsAndRemoveTemporaryFiles' {
        $root = New-TestRoot
        try {
            # Arrange: no local file yet

            # Act
            $first = Invoke-Updater -Root $root -Arguments @('-r', 'Obsidian')
            $second = Invoke-Updater -Root $root -Arguments @('-di', 'Git')
            $third = Invoke-Updater -Root $root -Arguments @('-r', 'Notepad++')
            $configuration = Read-TestConfiguration -Root $root
            $removed = @($configuration.RemovedPackageIds)
            $updateOnly = @($configuration.UpdateOnlyPackageIds)
            $directory = Split-Path -Parent (Get-ConfigurationPath -Root $root)
            $leftovers = @(Get-ChildItem -LiteralPath $directory -Force | Where-Object { $_.Name -like '*.tmp' -or $_.Name -like '*.bak' })

            # Assert
            Assert-Result (
                $first.ExitCode -eq 0 -and $second.ExitCode -eq 0 -and $third.ExitCode -eq 0 -and
                ($removed -contains 'Obsidian.Obsidian') -and
                ($removed -contains 'Notepad++.Notepad++') -and
                ($updateOnly -contains 'Git.Git') -and
                $leftovers.Count -eq 0
            ) (Get-FailureDetail -Result $third -Message 'Repeated save did not keep every change or left temporary files.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Save_WhenDestinationIsReadOnly_ShouldLeaveExistingSettingsUnchanged' {
        $root = New-TestRoot
        $configurationPath = $null
        try {
            # Arrange
            $null = Invoke-Updater -Root $root -Arguments @('-r', 'Obsidian')
            $configurationPath = Get-ConfigurationPath -Root $root
            $before = Get-Content -LiteralPath $configurationPath -Raw
            (Get-Item -LiteralPath $configurationPath).IsReadOnly = $true

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-di', 'Git')
            $after = Get-Content -LiteralPath $configurationPath -Raw
            $directory = Split-Path -Parent $configurationPath
            $leftovers = @(Get-ChildItem -LiteralPath $directory -Force | Where-Object { $_.Name -like '*.tmp' -or $_.Name -like '*.bak' })

            # Assert
            Assert-Result (
                $before -ceq $after -and
                $result.ExitCode -eq 1 -and
                $result.Output -match 'left unchanged' -and
                $leftovers.Count -eq 0
            ) (Get-FailureDetail -Result $result -Message 'A failed save changed the existing configuration or left temporary files.')
        }
        finally {
            if ($configurationPath -and (Test-Path -LiteralPath $configurationPath)) {
                (Get-Item -LiteralPath $configurationPath).IsReadOnly = $false
            }
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Save_WhenOnePackageIsRemoved_ShouldKeepJsonArrays' {
        $root = New-TestRoot
        try {
            # Arrange: empty local profile

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-r', 'Obsidian')
            $raw = Get-Content -LiteralPath (Get-ConfigurationPath -Root $root) -Raw

            # Assert
            Assert-Result (
                $raw -match '"RemovedPackageIds"\s*:\s*\[\s*"Obsidian\.Obsidian"\s*\]' -and
                $raw -match '"UpdateOnlyPackageIds"\s*:\s*\[\s*\]' -and
                $raw -match '"CustomApplications"\s*:\s*\[\s*\]'
            ) (Get-FailureDetail -Result $result -Message 'Saved JSON did not keep array properties.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Add_WhenDiscordIsAlreadyConfigured_ShouldNotCreateAnotherEntry' {
        $root = New-TestRoot
        try {
            # Arrange
            $null = Save-TestConfiguration -Root $root -CustomApplications @(@{ Name = 'Discord'; PackageId = 'Discord.Discord' })

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-a', 'Discord', '-PackageId', 'Discord.Discord')
            $configuration = Read-TestConfiguration -Root $root

            # Assert
            Assert-Result (@($configuration.CustomApplications).Count -eq 1) (
                Get-FailureDetail -Result $result -Message 'Duplicate Add created another Discord entry.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Add_WhenPackageIdIsUnknown_ShouldSaveNothing' {
        $root = New-TestRoot
        try {
            # Arrange
            $configurationPath = Get-ConfigurationPath -Root $root

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-a', 'Missing', '-PackageId', 'Missing.Missing')

            # Assert
            Assert-Result (
                -not (Test-Path -LiteralPath $configurationPath) -and
                $result.ExitCode -eq 1 -and
                $result.Output -match 'Nothing was saved'
            ) (Get-FailureDetail -Result $result -Message 'Unknown PackageId was saved or reported as success.')
        }
        finally {
            Remove-TestRoot $root
        }
    }

    Invoke-Test 'Readme_WhenDescribingCheck_ShouldExplainThatTheCatalogMayBeUpdated' {
        # Arrange
        $readme = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\README.md') -Raw

        # Act
        $describesCheck = $readme -match 'uden at installere eller opdatere programmer' -and
            $readme -match 'WinGet-kataloget kan blive opdateret'

        # Assert
        Assert-Result $describesCheck 'README does not explain that -Check can refresh the WinGet catalog.'
    }

    Invoke-Test 'Setup_WhenRequested_ShouldWriteLauncherAndRestoreUserPath' {
        $root = New-TestRoot
        $originalUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        try {
            # Arrange: isolated LOCALAPPDATA, real user PATH restored before the assertion returns

            # Act
            $result = Invoke-Updater -Root $root -Arguments @('-Setup')
            $launcherPath = Join-Path $root 'Programs\DevAppUpdater\bin\update-devapps.cmd'
            $launcher = Get-Content -LiteralPath $launcherPath -Raw
            [Environment]::SetEnvironmentVariable('Path', $originalUserPath, 'User')
            $restoredUserPath = [Environment]::GetEnvironmentVariable('Path', 'User')

            # Assert
            Assert-Result (
                $result.ExitCode -eq 0 -and
                $launcher -match 'pwsh\.exe -NoLogo -NoProfile -File "%~dp0\.\.\\Update-DevelopmentApps\.ps1" %\*' -and
                $launcher -match 'exit /b %ERRORLEVEL%' -and
                $restoredUserPath -eq $originalUserPath
            ) (Get-FailureDetail -Result $result -Message 'Setup did not write the expected launcher.')
        }
        finally {
            [Environment]::SetEnvironmentVariable('Path', $originalUserPath, 'User')
            Remove-TestRoot $root
        }
    }

    Complete-TestRun -Name 'smoke'
}
finally {
    Clear-WinGetMockEnvironment
}
