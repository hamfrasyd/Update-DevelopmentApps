# Smoke tests for local configuration. Windows runner + PowerShell 7 required.
# Each test is Arrange, Act, Assert and contains one assertion. Names follow
# Subject_WhenCondition_ShouldExpectedBehavior. Configuration state is not shared.
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$script:ScriptPath = (Resolve-Path (Join-Path $PSScriptRoot '..\Update-DevelopmentApps.ps1')).Path
$script:AssertionCount = 0
$script:PassedCount = 0
$script:FailedCases = [System.Collections.Generic.List[string]]::new()

function Invoke-Test {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Case
    )

    $script:AssertionCount = 0
    try {
        & $Case
        if ($script:AssertionCount -ne 1) {
            throw 'A test must contain exactly one assertion.'
        }
        $script:PassedCount++
        Write-Host "PASS  $Name" -ForegroundColor DarkGray
    }
    catch {
        $script:FailedCases.Add("${Name}: $($_.Exception.Message)")
        Write-Host "FAIL  $Name" -ForegroundColor Red
        Write-Host "      $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Assert-Result {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Message
    )

    $script:AssertionCount++
    if ($script:AssertionCount -gt 1) {
        throw 'A test may contain only one assertion.'
    }
    if (-not $Condition) {
        throw $Message
    }
}

function New-TestRoot {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('DevAppUpdaterTests-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    return $root
}

function Remove-TestRoot {
    param([string]$Root)

    if ($Root -and (Test-Path -LiteralPath $Root)) {
        Remove-Item -LiteralPath $Root -Recurse -Force
    }
}

function Get-ConfigurationPath {
    param([Parameter(Mandatory)][string]$Root)

    return (Join-Path $Root 'Programs\DevAppUpdater\Local\Applications.local.json')
}

function Format-JsonString {
    param([Parameter(Mandatory)][string]$Value)

    return '"' + ($Value -replace '\\', '\\' -replace '"', '\"') + '"'
}

function Save-TestConfiguration {
    param(
        [Parameter(Mandatory)][string]$Root,
        [string[]]$RemovedPackageIds = @(),
        [string[]]$UpdateOnlyPackageIds = @(),
        [hashtable[]]$CustomApplications = @()
    )

    $path = Get-ConfigurationPath -Root $Root
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null

    $removed = (@($RemovedPackageIds) | ForEach-Object { Format-JsonString $_ }) -join ','
    $updateOnly = (@($UpdateOnlyPackageIds) | ForEach-Object { Format-JsonString $_ }) -join ','
    $custom = (@($CustomApplications) | ForEach-Object {
        '{ "Name": ' + (Format-JsonString $_.Name) + ', "PackageId": ' + (Format-JsonString $_.PackageId) + ' }'
    }) -join ','
    $json = '{"SchemaVersion":1,"RemovedPackageIds":[' + $removed + '],"UpdateOnlyPackageIds":[' + $updateOnly + '],"CustomApplications":[' + $custom + ']}'
    Set-Content -LiteralPath $path -Value $json -Encoding utf8
    return $path
}

function Read-TestConfiguration {
    param([Parameter(Mandatory)][string]$Root)

    return (Get-Content -LiteralPath (Get-ConfigurationPath -Root $Root) -Raw | ConvertFrom-Json -Depth 10)
}

function Invoke-Updater {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    $previousLocalAppData = $env:LOCALAPPDATA
    $previousPath = $env:PATH
    try {
        $env:LOCALAPPDATA = $Root
        $env:PATH = $script:PathWithMock
        $nativeOutput = & pwsh -NoProfile -File $script:ScriptPath @Arguments *>&1
        $exitCode = $LASTEXITCODE
        return [pscustomobject]@{
            ExitCode = $exitCode
            Output   = ($nativeOutput | Out-String)
        }
    }
    finally {
        $env:LOCALAPPDATA = $previousLocalAppData
        $env:PATH = $previousPath
    }
}

function Get-FailureDetail {
    param(
        [string]$Message,
        $Result
    )

    if (-not $Result) {
        return $Message
    }
    $excerpt = (($Result.Output -replace '\s+', ' ').Trim())
    if ($excerpt.Length -gt 300) {
        $excerpt = $excerpt.Substring(0, 300)
    }
    return "$Message Exit code $($Result.ExitCode). $excerpt"
}

function Get-ParameterAliases {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Parameters,
        [Parameter(Mandatory)][string]$Name
    )

    if (-not $Parameters.ContainsKey($Name)) {
        return @()
    }
    return @($Parameters[$Name].Aliases)
}

$mockDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('DevAppUpdaterMock-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $mockDirectory | Out-Null
Set-Content -LiteralPath (Join-Path $mockDirectory 'winget.cmd') -Encoding ascii -Value @'
@echo off
if /I "%~1"=="show" (
 echo Found Discord [Discord.Discord]
 echo Version: 3.0.99
 exit /b 0
)
if /I "%~1"=="search" (
 echo Name                    Id                    Version   Source
 echo ---------------------------------------------------------------
 echo Discord                 Discord.Discord       1.0.99    winget
 exit /b 0
)
exit /b 2
'@
$script:PathWithMock = "$mockDirectory;$env:PATH"

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

    if ($script:FailedCases.Count -gt 0) {
        Write-Host ''
        Write-Host 'Failed smoke tests:' -ForegroundColor Red
        foreach ($failedCase in $script:FailedCases) {
            Write-Host "  $failedCase" -ForegroundColor Red
        }
        throw "$($script:FailedCases.Count) smoke test(s) failed."
    }

    Write-Host "All smoke tests passed ($($script:PassedCount))." -ForegroundColor Green
}
finally {
    if (Test-Path -LiteralPath $mockDirectory) {
        Remove-Item -LiteralPath $mockDirectory -Recurse -Force
    }
}
