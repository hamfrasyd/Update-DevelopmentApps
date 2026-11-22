# Shared harness for the local updater tests. Dot-source this file.
$script:AssertionCount = 0
$script:PassedCount = 0
$script:FailedCases = [System.Collections.Generic.List[string]]::new()
$script:TestDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:ScriptPath = (Resolve-Path (Join-Path $script:TestDirectory '..\Update-DevelopmentApps.ps1')).Path
$script:MockDirectory = Join-Path $script:TestDirectory 'mocks'
$script:PathWithMock = "$($script:MockDirectory);$env:PATH"

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
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Arguments
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
    if ($excerpt.Length -gt 500) {
        $excerpt = $excerpt.Substring(0, 500)
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

function Reset-WinGetMock {
    param(
        [ValidateSet('default', 'updater')]
        [string]$Mode = 'default',
        [string]$LogPath,
        [string]$Installed = '',
        [string]$Upgrades = '',
        [string]$InstallExit = '0',
        [string]$UpgradeExit = '0',
        [string]$SourceExit = '0',
        [string]$ListExit = '0',
        [string]$BadVersionId = ''
    )

    $env:DEVAPP_WINGET_MODE = $Mode
    $env:DEVAPP_INSTALLED = $Installed
    $env:DEVAPP_UPGRADES = $Upgrades
    $env:DEVAPP_INSTALL_EXIT = $InstallExit
    $env:DEVAPP_UPGRADE_EXIT = $UpgradeExit
    $env:DEVAPP_SOURCE_EXIT = $SourceExit
    $env:DEVAPP_LIST_EXIT = $ListExit
    $env:DEVAPP_BAD_VERSION_ID = $BadVersionId

    if ($LogPath) {
        $env:DEVAPP_WINGET_LOG = $LogPath
        Set-Content -LiteralPath $LogPath -Value '' -Encoding ascii
    }
    else {
        Remove-Item Env:\DEVAPP_WINGET_LOG -ErrorAction SilentlyContinue
    }
}

function Clear-WinGetMockEnvironment {
    foreach ($name in @(
            'DEVAPP_WINGET_MODE', 'DEVAPP_WINGET_LOG', 'DEVAPP_INSTALLED', 'DEVAPP_UPGRADES',
            'DEVAPP_INSTALL_EXIT', 'DEVAPP_UPGRADE_EXIT', 'DEVAPP_SOURCE_EXIT', 'DEVAPP_LIST_EXIT',
            'DEVAPP_BAD_VERSION_ID'
        )) {
        Remove-Item "Env:\$name" -ErrorAction SilentlyContinue
    }
}

function Get-WinGetLogLines {
    param([Parameter(Mandatory)][string]$LogPath)

    if (-not (Test-Path -LiteralPath $LogPath)) {
        return @()
    }
    return @(Get-Content -LiteralPath $LogPath | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Complete-TestRun {
    param([Parameter(Mandatory)][string]$Name)

    if ($script:FailedCases.Count -gt 0) {
        Write-Host ''
        Write-Host "Failed $Name tests:" -ForegroundColor Red
        foreach ($failedCase in $script:FailedCases) {
            Write-Host "  $failedCase" -ForegroundColor Red
        }
        throw "$($script:FailedCases.Count) $Name test(s) failed."
    }

    Write-Host "All $Name tests passed ($($script:PassedCount))." -ForegroundColor Green
}

Reset-WinGetMock -Mode default
