#requires -Version 7.0
<#
.SYNOPSIS
    Installs missing developer applications and updates installed applications.
.DESCRIPTION
    Uses WinGet with explicitly configured package IDs. Installs missing packages
    by default; -Check only reports changes. The application list is in
    $ApplicationDefinitions (plus optional Local/Applications.local.json). -Setup installs this script
    for the current Windows user and registers the update-devapps command.
    -List, -Add, -Remove, -DisableInstall and -EnableInstall manage local settings.

    WinGet reports update availability from its own catalog, which can lag vendors.
    Certain vendor-managed applications are intentionally marked for manual review.
.EXAMPLE
    .\Update-DevelopmentApps.ps1 -Setup
.EXAMPLE
    update-devapps -Check
.EXAMPLE
    update-devapps
.EXAMPLE
    update-devapps -Check -Diagnostic
.EXAMPLE
    update-devapps -Update -SkipSourceUpdate
.EXAMPLE
    update-devapps -Add Discord
.EXAMPLE
    update-devapps -List
#>
[CmdletBinding()]
param(
    [switch]$Setup,
    [Alias('c')]
    [switch]$Check,
    [Alias('u')]
    [switch]$Update,
    [switch]$SkipSourceUpdate,
    [Alias('d')]
    [switch]$Diagnostic,
    [Alias('ssu')]
    [switch]$SkipSelfUpdate,
    [Alias('l')]
    [switch]$List,
    [Alias('a')]
    [string]$Add,
    [Alias('r')]
    [string]$Remove,
    [Alias('di')]
    [string]$DisableInstall,
    [Alias('ei')]
    [string]$EnableInstall,
    [string]$PackageId
)

$ErrorActionPreference = 'Stop'

# Release and installation constants. Keep the version as a literal: the release
# updater verifies that the script version matches the GitHub release tag.
$ScriptVersion = '2.0.0'
$script:GitHubOwner = 'hamfrasyd'
$script:GitHubRepository = 'Update-DevelopmentApps'
$script:ScriptFileName = 'Update-DevelopmentApps.ps1'
$script:LauncherFileName = 'update-devapps.cmd'
$script:LocalDirectoryName = 'Local'
$script:LocalConfigurationFileName = 'Applications.local.json'
$script:LocalConfigurationSchemaVersion = 1
$script:SearchResultLimit = 20
$script:PowerShellPackageId = 'Microsoft.PowerShell'
$script:InstallationDirectory = Join-Path $env:LOCALAPPDATA 'Programs\DevAppUpdater'
$script:CommandsDirectory = Join-Path $script:InstallationDirectory 'bin'
$script:LocalDirectory = Join-Path $script:InstallationDirectory $script:LocalDirectoryName
$script:InstalledScriptPath = Join-Path $script:InstallationDirectory $script:ScriptFileName
$script:LauncherPath = Join-Path $script:CommandsDirectory $script:LauncherFileName
$script:LocalConfigurationPath = Join-Path $script:LocalDirectory $script:LocalConfigurationFileName

# ============================================================================
# APPLICATIONS: EDIT THIS LIST TO ADD OR REMOVE PROGRAMS
# ============================================================================
# To add an application:
#   1. Find its exact ID with: winget search "Application Name"
#   2. Add one row: @{ Name = 'Application Name'; PackageId = 'Publisher.Id' }
#   3. Run: update-devapps -Check
#
# Optional properties:
#   VersionPrefix     Restrict upgrades AND fresh installs to a release series.
#                     Example: '8.0.' for MySQL Workbench 8.0.
#   ManagerPackageId  If this app manager is installed, leave the application
#                     to that manager instead of creating a duplicate install.
#   InstallIfMissing  Set to $false to update only (default is $true).
#   ManualInstructions  Mark an application as managed outside this script.
#
# Do not put passwords, tokens, or other secrets in this list.
# Can add "InstallIfMissing = $false" if you dont want to install something if you dont have it. Fx. "@{ Name = 'Git'; PackageId = 'Git.Git'; InstallIfMissing = $false }""
$ApplicationDefinitions = @(
    @{ Name = 'Obsidian';                           PackageId = 'Obsidian.Obsidian' }
    @{ Name = 'Notepad++';                          PackageId = 'Notepad++.Notepad++' }
    @{ Name = 'Postman';                            PackageId = 'Postman.Postman' }
    @{ Name = 'Wireshark';                          PackageId = 'WiresharkFoundation.Wireshark' }
    @{ Name = 'Visual Studio 2026 Enterprise';      PackageId = 'Microsoft.VisualStudio.Enterprise' }
    @{ Name = 'VS Code';                            PackageId = 'Microsoft.VisualStudioCode' }
    @{ Name = 'Cursor';                             PackageId = 'Anysphere.Cursor' }
    @{ Name = 'Docker Desktop';                     PackageId = 'Docker.DockerDesktop' }
    @{ Name = 'Ollama';                             PackageId = 'Ollama.Ollama' }
    @{ Name = 'SQL Server Management Studio 22';    PackageId = 'Microsoft.SQLServerManagementStudio.22' }
    @{ Name = 'MySQL Workbench';                    PackageId = 'Oracle.MySQLWorkbench' }
    @{ Name = 'Neo4j Desktop';                      PackageId = 'Neo4j.Neo4jDesktop' }
    @{ Name = 'MongoDB Compass';                    PackageId = 'MongoDB.Compass.Full'}
    @{ Name = 'MongoDB Shell';                      PackageId = 'MongoDB.Shell'}
    @{ Name = 'DataGrip';                           PackageId = 'JetBrains.DataGrip'; ManagerPackageId = 'JetBrains.Toolbox' }
    @{ Name = 'Git';                                PackageId = 'Git.Git' }
    @{ Name = 'Python 3.15';                        PackageId = 'Python.Python.3.15' }
    @{ Name = 'Java JDK 25 LTS';                    PackageId = 'EclipseAdoptium.Temurin.25.JDK' }
    @{ Name = '.NET 10 SDK';                        PackageId = 'Microsoft.DotNet.SDK.10' }
    @{ Name = '.NET 11 SDK';                        PackageId = 'Microsoft.DotNet.SDK.11' }

    # PowerShell is last because updating the running shell can interrupt the script.
    @{ Name = 'PowerShell';                         PackageId = $script:PowerShellPackageId }
)

# The standard application list is release-owned. Personal settings are stored
# as non-executable JSON below Local/ and loaded after CLI validation.
$script:DefaultApplications = @($ApplicationDefinitions)

# These values are intentionally small and are reset on each script invocation.
$script:ApplicationResults = [System.Collections.Generic.List[object]]::new()
$script:InstalledPackages = $null
$script:AvailableUpgrades = $null

function Install-UserCommand {
    # Use LOCALAPPDATA, not a hardcoded username and not Program Files.
    # This enables a standard user to install the command for their own account.
    New-Item -ItemType Directory -Path $script:CommandsDirectory -Force | Out-Null

    if (-not [string]::Equals($PSCommandPath, $script:InstalledScriptPath, [StringComparison]::OrdinalIgnoreCase)) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $script:InstalledScriptPath -Force
    }

    # The downloaded file may carry the Windows Mark-of-the-Web flag.
    Unblock-File -LiteralPath $script:InstalledScriptPath -ErrorAction Stop

    # The CMD launcher is intentionally simple and works from any directory.
    # %* forwards arguments such as -Check, -Diagnostic and -Update.
    $launcherContent = @"
@echo off
pwsh.exe -NoLogo -NoProfile -File "%~dp0..\$($script:ScriptFileName)" %*
exit /b %ERRORLEVEL%
"@
    Set-Content -LiteralPath $script:LauncherPath -Value $launcherContent -Encoding ascii

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $normalizedCommandDirectory = $script:CommandsDirectory.TrimEnd('\')
    $alreadyInUserPath = @($userPath -split ';' | ForEach-Object { $_.Trim().TrimEnd('\') }) -contains $normalizedCommandDirectory

    if (-not $alreadyInUserPath) {
        $updatedUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
            $script:CommandsDirectory
        }
        else {
            "$($userPath.TrimEnd(';'));$script:CommandsDirectory"
        }
        [Environment]::SetEnvironmentVariable('Path', $updatedUserPath, 'User')
    }

    # Make the command usable in this terminal session immediately as well.
    $alreadyInProcessPath = @($env:Path -split ';' | ForEach-Object { $_.Trim().TrimEnd('\') }) -contains $normalizedCommandDirectory
    if (-not $alreadyInProcessPath) {
        $env:Path = "$($env:Path.TrimEnd(';'));$script:CommandsDirectory"
    }

    Write-Host 'The update-devapps command has been installed for your Windows user.' -ForegroundColor Green
    Write-Host "Script:  $script:InstalledScriptPath"
    Write-Host "Command: $script:LauncherPath"
    Write-Host ''
    Write-Host 'Try these commands:' -ForegroundColor Cyan
    Write-Host '  update-devapps -Check (Checks for available updates and missing applications without making changes)'
    Write-Host '  update-devapps (Updates installed applications and installs missing applications)'
    Write-Host '  update-devapps -Update (Updates installed applications without installing missing ones)'
    Write-Host '  update-devapps -Check -Diagnostic (Checks for updates and displays detailed troubleshooting information without making changes)'
    Write-Host '  update-devapps -List (Shows your effective local configuration)'
    Write-Host '  update-devapps -Add Discord (Searches WinGet or restores a default application)'
    Write-Host '  update-devapps -Remove Obsidian (Excludes an application without uninstalling it)'
    Write-Host '  update-devapps -DisableInstall Git (Never installs Git if missing)'
    Write-Host ''
    Write-Host 'Existing terminal windows may need to be reopened to inherit the updated user PATH.' -ForegroundColor DarkGray
    Write-Host 'Use update-devapps -List to view and manage your personal application list.' -ForegroundColor DarkGray
}

function Invoke-SelfUpdate {
    # Only update the installed copy. -Setup is handled before this function runs.
    $installedScriptPath = $script:InstalledScriptPath
    if ([string]::IsNullOrWhiteSpace($PSCommandPath) -or
        -not [string]::Equals($PSCommandPath, $installedScriptPath, [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    if ([string]::IsNullOrWhiteSpace($script:GitHubOwner)) {
        Write-Warning 'Self-update is not configured. Set $GitHubOwner in the script.'
        return $false
    }

    $temporaryScriptPath = Join-Path $script:InstallationDirectory ([IO.Path]::GetFileNameWithoutExtension($script:ScriptFileName) + '.download.ps1')
    $backupScriptPath = Join-Path $script:InstallationDirectory ([IO.Path]::GetFileNameWithoutExtension($script:ScriptFileName) + '.previous.ps1')

    try {
        $releaseApiUrl = "https://api.github.com/repos/$GitHubOwner/$GitHubRepository/releases/latest"
        $release = Invoke-RestMethod -Uri $releaseApiUrl -Headers @{
            'Accept'               = 'application/vnd.github+json'
            'User-Agent'           = 'DevAppUpdater'
            'X-GitHub-Api-Version' = '2022-11-28'
        } -TimeoutSec 20

        if ($release.tag_name -match '^v(?<Version>\d+\.\d+\.\d+)$') {
            $releasedVersionText = $Matches.Version
        }
        else {
            throw "Release tag '$($release.tag_name)' must use vMAJOR.MINOR.PATCH, for example v1.0.1."
        }
        $releasedVersion = [version]$releasedVersionText
        $installedVersion = [version]$ScriptVersion

        if ($releasedVersion -le $installedVersion) {
            if ($Diagnostic) {
                Write-Host "DevAppUpdater: v$ScriptVersion is up to date." -ForegroundColor DarkGray
            }
            return $false
        }

        $releaseAsset = $release.assets |
            Where-Object { $_.name -eq $script:ScriptFileName } |
            Select-Object -First 1

        if ($null -eq $releaseAsset) {
            throw "Release $($release.tag_name) does not contain $($script:ScriptFileName) as an uploaded asset."
        }

        if ($releaseAsset.digest -match '^sha256:(?<Hash>[0-9a-fA-F]{64})$') {
            $expectedHash = $Matches.Hash
        }
        else {
            throw 'GitHub did not provide a SHA-256 digest for the release asset. Update skipped.'
        }
        $expectedUrlPrefix = "https://github.com/$GitHubOwner/$GitHubRepository/releases/download/"
        $assetUrl = [string]$releaseAsset.browser_download_url
        if (-not $assetUrl.StartsWith($expectedUrlPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'The release asset URL does not match the configured GitHub repository.'
        }

        Write-Host "DevAppUpdater update available: v$ScriptVersion -> $($release.tag_name)" -ForegroundColor Cyan
        if ($Check) {
            Write-Host 'Check-only mode: the script was not changed.' -ForegroundColor Yellow
            return $false
        }

        Write-Host 'Downloading the updated script from GitHub Releases...' -ForegroundColor Cyan
        Invoke-WebRequest -Uri $assetUrl -OutFile $temporaryScriptPath -TimeoutSec 60

        $downloadedHash = (Get-FileHash -LiteralPath $temporaryScriptPath -Algorithm SHA256).Hash
        if (-not [string]::Equals($downloadedHash, $expectedHash, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'SHA-256 verification failed. The installed script was not changed.'
        }

        $parseTokens = $null
        $parseErrors = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
            $temporaryScriptPath, [ref]$parseTokens, [ref]$parseErrors
        )
        if ($parseErrors.Count -gt 0) {
            throw "Downloaded PowerShell script has syntax errors: $($parseErrors[0].Message)"
        }

        # Prevent a release whose script version does not match its GitHub tag.
        $downloadedText = Get-Content -LiteralPath $temporaryScriptPath -Raw
        $versionMatch = [regex]::Match(
            $downloadedText,
            "(?m)^\s*\`$ScriptVersion\s*=\s*'(?<Version>\d+\.\d+\.\d+)'\s*$"
        )
        if (-not $versionMatch.Success -or $versionMatch.Groups['Version'].Value -ne $releasedVersionText) {
            throw "Downloaded script version must be '$releasedVersionText'."
        }

        Unblock-File -LiteralPath $temporaryScriptPath -ErrorAction Stop
        [System.IO.File]::Replace($temporaryScriptPath, $installedScriptPath, $backupScriptPath)
        Write-Host "DevAppUpdater updated to $($release.tag_name)." -ForegroundColor Green
        Write-Host "Previous script saved as: $backupScriptPath" -ForegroundColor DarkGray
        return $true
    }
    catch {
        Write-Warning "Self-update was skipped: $($_.Exception.Message)"
        Write-Host 'The installed version remains available; continuing with WinGet.' -ForegroundColor DarkGray
        return $false
    }
    finally {
        if (Test-Path -LiteralPath $temporaryScriptPath) {
            Remove-Item -LiteralPath $temporaryScriptPath -Force -ErrorAction SilentlyContinue
        }
    }
}

# ============================================================================
# LOCAL CONFIGURATION (DOMAIN + PERSISTENCE)
# ============================================================================
function New-LocalConfiguration {
    return [ordered]@{
        SchemaVersion = $script:LocalConfigurationSchemaVersion
        RemovedPackageIds = @()
        UpdateOnlyPackageIds = @()
        CustomApplications = @()
    }
}

function Assert-ValidPackageId {
    param([Parameter(Mandatory)][string]$Value)

    if ($Value.Length -gt 200 -or $Value -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
        throw "Invalid WinGet PackageId '$Value'. Use a valid catalog ID such as 'Discord.Discord'."
    }
}

function Assert-ValidLocalConfiguration {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Configuration)

    if (-not $Configuration.Contains('SchemaVersion') -or
        ($Configuration.SchemaVersion -isnot [int] -and $Configuration.SchemaVersion -isnot [long]) -or
        $Configuration.SchemaVersion -ne $script:LocalConfigurationSchemaVersion) {
        throw "SchemaVersion must be the number $($script:LocalConfigurationSchemaVersion)."
    }

    $propertyNames = @('RemovedPackageIds', 'UpdateOnlyPackageIds', 'CustomApplications')
    foreach ($propertyName in $propertyNames) {
        if (-not $Configuration.Contains($propertyName) -or $Configuration[$propertyName] -isnot [array]) {
            throw "$propertyName must be a JSON array, including when empty."
        }
    }

    foreach ($propertyName in @('RemovedPackageIds', 'UpdateOnlyPackageIds')) {
        $seenIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($packageId in $Configuration[$propertyName]) {
            if ($packageId -isnot [string] -or [string]::IsNullOrWhiteSpace($packageId)) {
                throw "$propertyName may only contain nonempty PackageId strings."
            }
            Assert-ValidPackageId -Value $packageId
            if (-not $seenIds.Add($packageId)) {
                throw "Duplicate PackageId '$packageId' in $propertyName."
            }
        }
    }

    $seenCustomIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($application in $Configuration.CustomApplications) {
        if ($application -isnot [System.Collections.IDictionary] -or
            -not $application.Contains('Name') -or
            -not $application.Contains('PackageId') -or
            $application.Name -isnot [string] -or
            $application.PackageId -isnot [string] -or
            [string]::IsNullOrWhiteSpace($application.Name) -or
            $application.Name.Length -gt 120) {
            throw 'Each CustomApplications entry must contain a nonempty Name and PackageId.'
        }
        Assert-ValidPackageId -Value $application.PackageId
        if (-not $seenCustomIds.Add($application.PackageId)) {
            throw "Duplicate custom PackageId '$($application.PackageId)'."
        }
    }
}

function Read-LocalConfiguration {
    if (-not (Test-Path -LiteralPath $script:LocalConfigurationPath -PathType Leaf)) {
        return (New-LocalConfiguration)
    }

    try {
        $rawJson = Get-Content -LiteralPath $script:LocalConfigurationPath -Raw -ErrorAction Stop
        $configuration = ConvertFrom-Json -InputObject $rawJson -AsHashtable -Depth 10 -ErrorAction Stop
        if ($configuration -isnot [System.Collections.IDictionary]) {
            throw 'The root JSON value must be an object.'
        }
        Assert-ValidLocalConfiguration -Configuration $configuration
        return $configuration
    }
    catch {
        throw "Cannot read local configuration '$($script:LocalConfigurationPath)'. Inspect and fix the JSON; the file has not been changed. Details: $($_.Exception.Message)"
    }
}

function Save-LocalConfiguration {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Configuration)

    Assert-ValidLocalConfiguration -Configuration $Configuration
    New-Item -ItemType Directory -Path $script:LocalDirectory -Force | Out-Null

    $temporaryPath = Join-Path $script:LocalDirectory ("$($script:LocalConfigurationFileName)." + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $serializableConfiguration = [ordered]@{
            SchemaVersion = $script:LocalConfigurationSchemaVersion
            RemovedPackageIds = @($Configuration.RemovedPackageIds)
            UpdateOnlyPackageIds = @($Configuration.UpdateOnlyPackageIds)
            CustomApplications = @($Configuration.CustomApplications | ForEach-Object {
                [ordered]@{ Name = $_.Name; PackageId = $_.PackageId }
            })
        }
        $json = ConvertTo-Json -InputObject $serializableConfiguration -Depth 10
        Set-Content -LiteralPath $temporaryPath -Value $json -Encoding utf8 -ErrorAction Stop
        if (Test-Path -LiteralPath $script:LocalConfigurationPath -PathType Leaf) {
            # PowerShell turns $null into an empty string here, which File.Replace rejects.
            [System.IO.File]::Replace($temporaryPath, $script:LocalConfigurationPath, [NullString]::Value)
        }
        else {
            [System.IO.File]::Move($temporaryPath, $script:LocalConfigurationPath)
        }
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-EffectiveApplications {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Configuration)

    $includedApplications = [System.Collections.Generic.List[hashtable]]::new()
    $seenIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    # PowerShell remains last: upgrading the running host can interrupt the script.
    $otherDefaults = @($script:DefaultApplications | Where-Object { $_.PackageId -ne $script:PowerShellPackageId })
    $powerShellDefault = @($script:DefaultApplications | Where-Object { $_.PackageId -eq $script:PowerShellPackageId })
    $defaultIds = @($script:DefaultApplications | ForEach-Object { $_.PackageId })
    $customApplications = @($Configuration.CustomApplications | Where-Object { $_.PackageId -notin $defaultIds })
    foreach ($application in $otherDefaults + $customApplications + $powerShellDefault) {
        if (-not $seenIds.Add([string]$application.PackageId)) {
            # A future default package could overlap a previously custom-added one.
            # Keep the default and avoid installing the same package twice.
            continue
        }
        if ($application.PackageId -in $Configuration.RemovedPackageIds) {
            continue
        }
        $effectiveApplication = @{}
        foreach ($key in $application.Keys) {
            $effectiveApplication[$key] = $application[$key]
        }
        if ($application.PackageId -in $Configuration.UpdateOnlyPackageIds) {
            $effectiveApplication['InstallIfMissing'] = $false
        }
        $includedApplications.Add($effectiveApplication)
    }
    return $includedApplications.ToArray()
}

function Resolve-ConfiguredApplication {
    param(
        [Parameter(Mandatory)][string]$NameOrId,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Configuration
    )

    $knownApplications = @($script:DefaultApplications) + @($Configuration.CustomApplications)
    $exactMatches = @($knownApplications | Where-Object {
        $_.Name -eq $NameOrId -or $_.PackageId -eq $NameOrId
    })
    $matches = $exactMatches
    if ($matches.Count -eq 0) {
        $matches = @($knownApplications | Where-Object {
            $_.Name.IndexOf($NameOrId, [StringComparison]::OrdinalIgnoreCase) -ge 0
        })
    }
    if ($matches.Count -eq 0) {
        throw "Application '$NameOrId' is not on your list. Use update-devapps -List or -Add '$NameOrId'."
    }
    if ($matches.Count -gt 1) {
        $names = @($matches | ForEach-Object { "$($_.Name) [$($_.PackageId)]" }) -join ', '
        throw "Application name '$NameOrId' is ambiguous: $names. Use the exact PackageId instead."
    }
    return $matches[0]
}

function Write-ConfiguredApplications {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Configuration)

    $records = [System.Collections.Generic.List[object]]::new()
    $customIds = @($Configuration.CustomApplications | ForEach-Object { $_.PackageId })
    $defaultIds = @($script:DefaultApplications | ForEach-Object { $_.PackageId })

    $seenIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($application in @($script:DefaultApplications) + @($Configuration.CustomApplications)) {
        if (-not $seenIds.Add([string]$application.PackageId)) {
            continue
        }
        $isCustom = $application.PackageId -in $customIds -and $application.PackageId -notin $defaultIds
        $isRemoved = $application.PackageId -in $Configuration.RemovedPackageIds
        $isUpdateOnly = $application.PackageId -in $Configuration.UpdateOnlyPackageIds -or
            ($application.ContainsKey('InstallIfMissing') -and $application.InstallIfMissing -eq $false)
        $status = if ($isRemoved) { 'Removed' } elseif ($isUpdateOnly) { 'Update Only' } elseif ($isCustom) { 'Custom Added' } else { 'Included' }
        $installMissing = if ($isRemoved) { '-' } elseif ($isUpdateOnly) { 'No' } else { 'Yes' }

        $records.Add([pscustomobject]@{
            Name = $application.Name
            Source = $(if ($isCustom) { 'Custom' } else { 'Default' })
            Status = $status
            InstallMissing = $installMissing
        })
    }

    $nameWidth = 30
    foreach ($record in $records) {
        $nameWidth = [Math]::Max($nameWidth, $record.Name.Length + 2)
    }
    $headerFormat = "{0,-$nameWidth} {1,-10} {2,-15} {3,-15}"
    Write-Host ''
    Write-Host ($headerFormat -f 'APPLICATION', 'SOURCE', 'STATUS', 'INSTALL MISSING') -ForegroundColor Cyan
    Write-Host ('-' * ($nameWidth + 44)) -ForegroundColor DarkGray
    foreach ($record in $records) {
        Write-Host ($record.Name.PadRight($nameWidth) + ' ' + $record.Source.PadRight(10) + ' ') -NoNewline
        $statusColor = switch ($record.Status) {
            'Removed'      { 'Red'; break }
            'Update Only'  { 'Yellow'; break }
            'Custom Added' { 'Cyan'; break }
            default        { 'Green' }
        }
        Write-Host ($record.Status.PadRight(15)) -ForegroundColor $statusColor -NoNewline
        Write-Host (' ' + $record.InstallMissing)
    }
    $removedCount = @($records | Where-Object { $_.Status -eq 'Removed' }).Count
    $updateOnlyCount = @($records | Where-Object { $_.Status -eq 'Update Only' }).Count
    $customCount = @($records | Where-Object { $_.Source -eq 'Custom' }).Count
    Write-Host "`nTotal: $($records.Count) | Removed: $removedCount | Update only: $updateOnlyCount | Custom: $customCount" -ForegroundColor DarkGray
    Write-Host "Local settings: $($script:LocalConfigurationPath)" -ForegroundColor DarkGray
}

# ============================================================================
# APPLICATION USE CASES (CLI COMMANDS)
# ============================================================================
function Find-WinGetCandidates {
    param([Parameter(Mandatory)][string]$SearchName)

    $result = Invoke-WinGet -Arguments @('search', '--query', $SearchName, '--source', 'winget', '--accept-source-agreements', '--disable-interactivity')
    if ($result.Output -match '(?i)no package found|no packages found|no results found|no matching package') {
        return @()
    }
    if ($result.ExitCode -ne 0) {
        throw "WinGet search failed for '$SearchName'. $($result.Output.Trim())"
    }

    # WinGet prints column-aligned text, not JSON. Use the Id and Version
    # positions from the header; never guess a package without validation.
    $searchLines = @($result.Output -split "`n")
    $headerIndex = -1
    $idStart = -1
    $versionStart = -1
    for ($index = 0; $index -lt $searchLines.Count; $index++) {
        $header = $searchLines[$index]
        $headerMatch = [regex]::Match($header, '(?i)^\s*\S.*?\s{2,}(?<Id>Id)\s{2,}(?<NextColumn>\S+)')
        if ($headerMatch.Success) {
            $headerIndex = $index
            $idStart = $headerMatch.Groups['Id'].Index
            $versionStart = $headerMatch.Groups['NextColumn'].Index
            break
        }
    }
    if ($headerIndex -lt 0) {
        throw "Cannot parse WinGet results for '$SearchName'. Run winget search --query '$SearchName' to inspect the catalog output."
    }

    $candidates = [System.Collections.Generic.List[object]]::new()
    $seenIds = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    for ($index = $headerIndex + 1; $index -lt $searchLines.Count; $index++) {
        $line = $searchLines[$index]
        if ($line.Length -lt $versionStart) {
            continue
        }
        $candidateName = $line.Substring(0, $idStart).Trim()
        $candidateId = $line.Substring($idStart, $versionStart - $idStart).Trim()
        if ([string]::IsNullOrWhiteSpace($candidateName) -or $candidateId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$') {
            continue
        }
        if ($seenIds.Add($candidateId)) {
            $candidates.Add([pscustomobject]@{ Name = $candidateName; PackageId = $candidateId })
        }
        if ($candidates.Count -ge $script:SearchResultLimit) {
            break
        }
    }
    return $candidates.ToArray()
}

function Add-ConfiguredApplication {
    param(
        [Parameter(Mandatory)][System.Collections.IDictionary]$Configuration,
        [Parameter(Mandatory)][string]$ApplicationName,
        [string]$ExplicitPackageId
    )

    if ([string]::IsNullOrWhiteSpace($ApplicationName)) {
        throw 'Provide an application name, for example: update-devapps -Add Discord.'
    }

    # Resolve release defaults before WinGet. This also permits -Add to include
    # a default application that was previously excluded by -Remove.
    $defaultMatches = @($script:DefaultApplications | Where-Object {
        $_.Name -eq $ApplicationName -or $_.PackageId -eq $ApplicationName -or
        (-not [string]::IsNullOrWhiteSpace($ExplicitPackageId) -and $_.PackageId -eq $ExplicitPackageId)
    })
    if ($defaultMatches.Count -gt 1) {
        throw "'$ApplicationName' matches more than one default application. Use the exact PackageId."
    }

    $knownApplications = @($script:DefaultApplications) + @($Configuration.CustomApplications)
    $selected = $null
    if ($defaultMatches.Count -eq 1) {
        $defaultApplication = $defaultMatches[0]
        if (-not [string]::IsNullOrWhiteSpace($ExplicitPackageId) -and
            $ExplicitPackageId -ne $defaultApplication.PackageId) {
            throw "The supplied PackageId '$ExplicitPackageId' does not match the default application $($defaultApplication.Name)."
        }
        $selected = [pscustomobject]@{ Name = $defaultApplication.Name; PackageId = $defaultApplication.PackageId }
    }
    elseif (-not [string]::IsNullOrWhiteSpace($ExplicitPackageId)) {
        Assert-ValidPackageId -Value $ExplicitPackageId
        $selected = [pscustomobject]@{ Name = $ApplicationName; PackageId = $ExplicitPackageId }
    }
    else {
        if (@($knownApplications | Where-Object { $_.Name -eq $ApplicationName -or $_.PackageId -eq $ApplicationName }).Count -gt 0) {
            throw "'$ApplicationName' already exists in the application list. Use -List to inspect it."
        }
        $candidates = @(Find-WinGetCandidates -SearchName $ApplicationName)
        if ($candidates.Count -eq 0) {
            throw "No application matching '$ApplicationName' was found in the WinGet catalog. No changes made."
        }
        if ($candidates.Count -eq 1) {
            $selected = $candidates[0]
            Write-Host "Found $($selected.Name) [$($selected.PackageId)]" -ForegroundColor Cyan
            $confirmation = Read-Host 'Add this application? (Y/N)'
            if ($confirmation -notin @('Y', 'y', 'Yes', 'yes')) {
                Write-Host 'Cancelled. No changes made.' -ForegroundColor Yellow
                return
            }
        }
        else {
            Write-Host "More than one WinGet package matched '$ApplicationName':" -ForegroundColor Cyan
            for ($index = 0; $index -lt $candidates.Count; $index++) {
                Write-Host ('{0,2}. {1} [{2}]' -f ($index + 1), $candidates[$index].Name, $candidates[$index].PackageId)
            }
            $choice = Read-Host 'Enter a number to add, or 0 to cancel'
            $choiceNumber = 0
            if (-not [int]::TryParse($choice, [ref]$choiceNumber) -or
                $choiceNumber -lt 1 -or $choiceNumber -gt $candidates.Count) {
                Write-Host 'Cancelled. No changes made.' -ForegroundColor Yellow
                return
            }
            $selected = $candidates[$choiceNumber - 1]
        }
    }

    # If WinGet resolved a different name for an existing default PackageId,
    # handle it as a default as well; never save a duplicate custom entry.
    $selectedDefault = @($script:DefaultApplications | Where-Object { $_.PackageId -eq $selected.PackageId })
    if ($selectedDefault.Count -gt 0) {
        $defaultApplication = $selectedDefault[0]
        if ($defaultApplication.PackageId -notin $Configuration.RemovedPackageIds) {
            Write-Host "$($defaultApplication.Name) is already included in the default application list." -ForegroundColor Yellow
            return
        }
        $Configuration.RemovedPackageIds = @($Configuration.RemovedPackageIds | Where-Object { $_ -ne $defaultApplication.PackageId })
        Save-LocalConfiguration -Configuration $Configuration
        Write-Host "Included default application $($defaultApplication.Name) [$($defaultApplication.PackageId)] in the updater list." -ForegroundColor Green
        return
    }

    if (@($knownApplications | Where-Object { $_.Name -eq $selected.Name -or $_.PackageId -eq $selected.PackageId }).Count -gt 0) {
        throw "Application '$($selected.Name)' [$($selected.PackageId)] is already configured. No duplicate was added."
    }

    # Validate the exact ID against the winget source, including explicit IDs.
    $packageInformation = Invoke-WinGet -Arguments @('show', '--id', $selected.PackageId, '--exact', '--source', 'winget', '--accept-source-agreements', '--disable-interactivity')
    if ($packageInformation.ExitCode -ne 0 -or
        $packageInformation.Output -notmatch [regex]::Escape("[$($selected.PackageId)]")) {
        throw "WinGet could not verify exact PackageId '$($selected.PackageId)'. Nothing was saved."
    }
    $Configuration.CustomApplications = @($Configuration.CustomApplications) + @(@{ Name = $selected.Name; PackageId = $selected.PackageId })
    Save-LocalConfiguration -Configuration $Configuration
    Write-Host "Added custom application $($selected.Name) [$($selected.PackageId)] to your local application list." -ForegroundColor Green
}
function Invoke-ConfigurationCommand {
    param(
        [Parameter(Mandatory)][string]$Command,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Configuration
    )

    if ($Command -eq 'List') {
        Write-ConfiguredApplications -Configuration $Configuration
        return
    }
    if ($Command -eq 'Add') {
        Add-ConfiguredApplication -Configuration $Configuration -ApplicationName $Add -ExplicitPackageId $PackageId
        return
    }

    $applicationName = switch ($Command) {
        'Remove'         { $Remove; break }
        'DisableInstall' { $DisableInstall; break }
        'EnableInstall'  { $EnableInstall; break }
        default          { throw "Unknown configuration command '$Command'." }
    }
    if ([string]::IsNullOrWhiteSpace($applicationName)) {
        throw "Provide an application name or PackageId for -$Command."
    }
    $application = Resolve-ConfiguredApplication -NameOrId $applicationName -Configuration $Configuration
    $packageId = $application.PackageId
    $isDefault = @($script:DefaultApplications | Where-Object { $_.PackageId -eq $packageId }).Count -gt 0
    $isRemoved = $packageId -in $Configuration.RemovedPackageIds
    $isInstallDisabled = $packageId -in $Configuration.UpdateOnlyPackageIds

    switch ($Command) {
        'Remove' {
            if ($isDefault) {
                if ($isRemoved) {
                    Write-Host "$($application.Name) is already excluded from the update list." -ForegroundColor Yellow
                    return
                }
                $Configuration.RemovedPackageIds = @($Configuration.RemovedPackageIds) + @($packageId)
                Save-LocalConfiguration -Configuration $Configuration
                Write-Host "Excluded default application $($application.Name) [$packageId] from the updater list (not uninstalled from Windows)." -ForegroundColor Green
            }
            else {
                $Configuration.CustomApplications = @($Configuration.CustomApplications | Where-Object { $_.PackageId -ne $packageId })
                $Configuration.RemovedPackageIds = @($Configuration.RemovedPackageIds | Where-Object { $_ -ne $packageId })
                $Configuration.UpdateOnlyPackageIds = @($Configuration.UpdateOnlyPackageIds | Where-Object { $_ -ne $packageId })
                Save-LocalConfiguration -Configuration $Configuration
                Write-Host "Deleted custom application $($application.Name) [$packageId] from local configuration (not uninstalled from Windows)." -ForegroundColor Green
            }
        }
        'DisableInstall' {
            if ($isRemoved) {
                throw "$($application.Name) is excluded from the updater list. Run update-devapps -Add '$($application.Name)' first."
            }
            if ($isInstallDisabled -or ($application.ContainsKey('InstallIfMissing') -and $application.InstallIfMissing -eq $false)) {
                Write-Host "Automatic installation is already disabled for $($application.Name)." -ForegroundColor Yellow
                return
            }
            $Configuration.UpdateOnlyPackageIds = @($Configuration.UpdateOnlyPackageIds) + @($packageId)
            Save-LocalConfiguration -Configuration $Configuration
            Write-Host "Automatic installation is now disabled for $($application.Name) [$packageId]. Installed versions can still be updated." -ForegroundColor Green
        }
        'EnableInstall' {
            if ($isRemoved) {
                throw "$($application.Name) is excluded from the updater list. Run update-devapps -Add '$($application.Name)' first."
            }
            if (-not $isInstallDisabled) {
                Write-Host "Automatic installation is already enabled for $($application.Name)." -ForegroundColor Yellow
                return
            }
            $Configuration.UpdateOnlyPackageIds = @($Configuration.UpdateOnlyPackageIds | Where-Object { $_ -ne $packageId })
            Save-LocalConfiguration -Configuration $Configuration
            Write-Host "Automatic installation is now enabled for $($application.Name) [$packageId]." -ForegroundColor Green
        }
    }
}

function Invoke-WinGet {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [switch]$ShowOutput
    )

    try {
        # A WinGet exit code is meaningful here: capture it rather than throwing.
        $PSNativeCommandUseErrorActionPreference = $false
        $outputLines = [System.Collections.Generic.List[string]]::new()

        & winget @Arguments 2>&1 | ForEach-Object {
            $rawLine = [string]$_
            $cleanLine = [regex]::Replace($rawLine, '\x1B\[[0-?]*[ -/]*[@-~]', '')
            $cleanLine = $cleanLine.Replace("`r", '')

            if ($ShowOutput -and -not [string]::IsNullOrWhiteSpace($cleanLine)) {
                Write-Host "    $cleanLine" -ForegroundColor DarkGray
            }

            # For install/update logs keep only recent lines: bounded memory use.
            if ($ShowOutput -and $outputLines.Count -ge 80) {
                $outputLines.RemoveAt(0)
            }
            $outputLines.Add($cleanLine)
        }

        return [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output   = $outputLines -join "`n"
        }
    }
    catch {
        return [pscustomobject]@{
            ExitCode = -1
            Output   = $_.Exception.Message
        }
    }
}

function Get-PackageRow {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$InventoryOutput,
        [Parameter(Mandatory)][string]$PackageId
    )

    # Retain the tolerant package-ID parser from v2, which worked on your system.
    # WinGet currently prints human-readable tables rather than stable JSON here.
    $escapedPackageId = [regex]::Escape($PackageId)
    $rowPattern = "(?i)(?<!\S)$escapedPackageId(?!\S)[^\S\r\n]+(?<Version>\S+)"

    foreach ($inventoryLine in ($InventoryOutput -split "`n")) {
        $match = [regex]::Match($inventoryLine, $rowPattern)
        if (-not $match.Success) {
            continue
        }

        return [pscustomobject]@{
            Version = $match.Groups['Version'].Value
            Line    = $inventoryLine.Trim()
        }
    }

    return $null
}

function Write-DiagnosticOutput {
    param(
        [string]$Description,
        [pscustomobject]$WinGetResult
    )

    if (-not $Diagnostic) {
        return
    }

    Write-Host "  DIAGNOSTIC: $Description (exit: $($WinGetResult.ExitCode))" -ForegroundColor DarkYellow
    if ([string]::IsNullOrWhiteSpace($WinGetResult.Output)) {
        Write-Host '  <empty output>' -ForegroundColor DarkGray
    }
    else {
        Write-Host $WinGetResult.Output -ForegroundColor DarkGray
    }
}

function Write-ColoredStatus {
    param([Parameter(Mandatory)][string]$Status)

    switch ($Status) {
        'NO update needed' { Write-Host $Status -ForegroundColor Green; return }
        'UPDATED'          { Write-Host $Status -ForegroundColor Green; return }
        'INSTALLED'        { Write-Host $Status -ForegroundColor Green; return }
        'UPDATE AVAILABLE' {
            Write-Host "$($PSStyle.Foreground.FromRgb(255, 165, 0))$Status$($PSStyle.Reset)"
            return
        }
        'INSTALL AVAILABLE' {
            Write-Host "$($PSStyle.Foreground.FromRgb(255, 165, 0))$Status$($PSStyle.Reset)"
            return
        }
        'NOT INSTALLED'    { Write-Host $Status -ForegroundColor Yellow; return }
        'MANUAL CHECK REQUIRED' { Write-Host $Status -ForegroundColor Red; return }
        'UPDATE FAILED'    { Write-Host $Status -ForegroundColor Red; return }
        'INSTALL FAILED'   { Write-Host $Status -ForegroundColor Red; return }
        'CHECK FAILED'     { Write-Host $Status -ForegroundColor Red; return }
        default            { Write-Host $Status -ForegroundColor Gray }
    }
}

function Add-ApplicationResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Status,
        [string]$Details = ''
    )

    $script:ApplicationResults.Add([pscustomobject]@{
        Application = $Name
        Status      = $Status
        Details     = $Details
    })

    # The app name is deliberately printed only once, above this result.
    Write-ColoredStatus -Status $Status
    if (-not [string]::IsNullOrWhiteSpace($Details)) {
        Write-Host "  $Details" -ForegroundColor DarkGray
    }
}

function Get-InstalledPackage {
    param([Parameter(Mandatory)][string]$PackageId)

    $versionPattern = '^\d+(?:\.\d+)+(?:[-+][0-9A-Za-z.-]+)?$'
    $cachedRow = Get-PackageRow -InventoryOutput $script:InstalledPackages.Output -PackageId $PackageId

    if ($cachedRow -and $cachedRow.Version -match $versionPattern) {
        return [pscustomobject]@{
            Detected = $true
            Row      = $cachedRow
            Reliable = $true
        }
    }

    # Retry if the package is missing or its cached version is invalid.
    $query = Invoke-WinGet -Arguments @(
        'list', '--id', $PackageId, '--exact', '--accept-source-agreements'
    )

    $freshRow = Get-PackageRow -InventoryOutput $query.Output -PackageId $PackageId
    $row = if ($freshRow) { $freshRow } else { $cachedRow }

    if ($row) {
        $reliable = $null -ne $freshRow -and $freshRow.Version -match $versionPattern

        if (-not $reliable) {
            Write-DiagnosticOutput -Description "winget list --id $PackageId" -WinGetResult $query
        }

        return [pscustomobject]@{
            Detected = $true
            Row      = $row
            Reliable = $reliable
        }
    }

    Write-DiagnosticOutput -Description "winget list --id $PackageId" -WinGetResult $query

    $notFound = $query.Output -match '(?i)no installed package found|no package found matching|no matching installed package'

    return [pscustomobject]@{
        Detected = $false
        Row      = $null
        Reliable = ($query.ExitCode -eq 0 -or $notFound)
    }
}

function Get-LatestVersionWithPrefix {
    param(
        [Parameter(Mandatory)][string]$PackageId,
        [Parameter(Mandatory)][string]$VersionPrefix
    )

    $versionQuery = Invoke-WinGet -Arguments @(
        'show', '--id', $PackageId, '--exact', '--source', 'winget',
        '--versions', '--accept-source-agreements'
    )

    if ($versionQuery.ExitCode -ne 0) {
        Write-DiagnosticOutput -Description "winget show --versions $PackageId" -WinGetResult $versionQuery
        return $null
    }

    $escapedVersionPrefix = [regex]::Escape($VersionPrefix)
    $versionPattern = "(?m)^\s*(?<Version>$escapedVersionPrefix\d+(?:\.\d+)*)\s*$"
    $matchingVersions = @(
        [regex]::Matches($versionQuery.Output, $versionPattern) |
            ForEach-Object { $_.Groups['Version'].Value } |
            Sort-Object -Unique
    )

    if ($matchingVersions.Count -eq 0) {
        Write-DiagnosticOutput -Description "winget show --versions $PackageId" -WinGetResult $versionQuery
        return $null
    }

    $latestVersion = $matchingVersions |
        Sort-Object { [version]$_ } -Descending |
        Select-Object -First 1
    return $latestVersion
}

function Get-LastWinGetMessage {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Output)

    $lastLines = @($Output -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 3)
    return ($lastLines -join ' | ')
}

function Install-MissingApplication {
    param(
        [Parameter(Mandatory)][hashtable]$Application,
        [string]$PinnedTargetVersion
    )

    $packageId = $Application.PackageId
    $availablePackage = Invoke-WinGet -Arguments @(
        'show', '--id', $packageId, '--exact', '--source', 'winget', '--accept-source-agreements'
    )

    if ($availablePackage.ExitCode -ne 0 -or $availablePackage.Output -notmatch [regex]::Escape("[$packageId]")) {
        Write-DiagnosticOutput -Description "winget show $packageId" -WinGetResult $availablePackage
        Add-ApplicationResult -Name $Application.Name -Status 'MANUAL CHECK REQUIRED' -Details "Exact package '$packageId' was not confirmed in the WinGet catalog. No installation attempted."
        return
    }

    $catalogVersionMatch = [regex]::Match($availablePackage.Output, '(?m)^Version:\s*(?<Version>\S+)')
    $catalogVersion = if ($catalogVersionMatch.Success) { $catalogVersionMatch.Groups['Version'].Value } else { 'unknown' }
    $versionDescription = if ($PinnedTargetVersion) { $PinnedTargetVersion } else { $catalogVersion }

    if ($Update -or ($Application.ContainsKey('InstallIfMissing') -and -not $Application.InstallIfMissing)) {
        Add-ApplicationResult -Name $Application.Name -Status 'NOT INSTALLED' -Details "Not detected by WinGet; automatic installation disabled. Available: $versionDescription"
        return
    }

    if ($Check) {
        Add-ApplicationResult -Name $Application.Name -Status 'INSTALL AVAILABLE' -Details "Not detected by WinGet; available version: $versionDescription"
        return
    }

    Write-Host "  Installing $packageId ($versionDescription)..." -ForegroundColor Yellow
    $installArguments = @(
        'install', '--id', $packageId, '--exact', '--source', 'winget',
        '--accept-package-agreements', '--accept-source-agreements'
    )
    if ($PinnedTargetVersion) {
        $installArguments += @('--version', $PinnedTargetVersion)
    }

    $installResult = Invoke-WinGet -Arguments $installArguments -ShowOutput
    Write-DiagnosticOutput -Description "winget install $packageId" -WinGetResult $installResult

    if ($installResult.ExitCode -eq 0) {
        Add-ApplicationResult -Name $Application.Name -Status 'INSTALLED' -Details "WinGet reported successful installation of $versionDescription."
    }
    else {
        Add-ApplicationResult -Name $Application.Name -Status 'INSTALL FAILED' -Details (Get-LastWinGetMessage -Output $installResult.Output)
    }
}

function Update-InstalledApplication {
    param(
        [Parameter(Mandatory)][hashtable]$Application,
        [Parameter(Mandatory)][string]$InstalledVersion,
        [string]$PinnedTargetVersion
    )

    $packageId = $Application.PackageId
    $updateAvailable = $false
    $updateDescription = ''

    if ($PinnedTargetVersion) {
        if ($InstalledVersion -notlike "$($Application.VersionPrefix)*") {
            Add-ApplicationResult -Name $Application.Name -Status 'MANUAL CHECK REQUIRED' -Details "Installed version $InstalledVersion does not match the configured release series '$($Application.VersionPrefix)'."
            return
        }

        try {
            $updateAvailable = [version]$PinnedTargetVersion -gt [version]$InstalledVersion
        }
        catch {
            Add-ApplicationResult -Name $Application.Name -Status 'MANUAL CHECK REQUIRED' -Details 'Cannot compare the installed version with the pinned release series.'
            return
        }
        $updateDescription = "Installed: $InstalledVersion; latest configured series: $PinnedTargetVersion"
    }
    else {
        $upgradeRow = Get-PackageRow -InventoryOutput $script:AvailableUpgrades.Output -PackageId $packageId
        $updateAvailable = $null -ne $upgradeRow
        $updateDescription = "Installed: $InstalledVersion; " + $(if ($updateAvailable) { 'WinGet reports an update' } else { 'no WinGet upgrade found' })
    }

    if (-not $updateAvailable) {
        Add-ApplicationResult -Name $Application.Name -Status 'NO update needed' -Details $updateDescription
        return
    }

    if ($Check) {
        Add-ApplicationResult -Name $Application.Name -Status 'UPDATE AVAILABLE' -Details $updateDescription
        return
    }

    Write-Host "  Upgrading $packageId..." -ForegroundColor Yellow
    $upgradeArguments = @(
        'upgrade', '--id', $packageId, '--exact', '--source', 'winget',
        '--accept-source-agreements', '--accept-package-agreements'
    )
    if ($PinnedTargetVersion) {
        $upgradeArguments += @('--version', $PinnedTargetVersion)
    }

    $upgradeResult = Invoke-WinGet -Arguments $upgradeArguments -ShowOutput
    Write-DiagnosticOutput -Description "winget upgrade $packageId" -WinGetResult $upgradeResult

    if ($upgradeResult.ExitCode -eq 0) {
        Add-ApplicationResult -Name $Application.Name -Status 'UPDATED' -Details "Previously installed: $InstalledVersion. WinGet reported success; restart the app if needed."
    }
    else {
        Add-ApplicationResult -Name $Application.Name -Status 'UPDATE FAILED' -Details (Get-LastWinGetMessage -Output $upgradeResult.Output)
    }
}

function Invoke-ApplicationCheck {
    param([Parameter(Mandatory)][hashtable]$Application)

    Write-Host "`nChecking $($Application.Name) ..." -ForegroundColor Cyan

    if ($Application.ContainsKey('ManualInstructions')) {
        Add-ApplicationResult -Name $Application.Name -Status 'MANUAL CHECK REQUIRED' -Details $Application.ManualInstructions
        return
    }

    if ($Application.ContainsKey('ManagerPackageId') -and $Application.ManagerPackageId) {
        $manager = Get-InstalledPackage -PackageId $Application.ManagerPackageId
        if ($manager.Detected) {
            Add-ApplicationResult -Name $Application.Name -Status 'MANUAL CHECK REQUIRED' -Details "Managed by '$($Application.ManagerPackageId)'. Update via that application to avoid duplicate installations."
            return
        }
        if (-not $manager.Reliable) {
            Add-ApplicationResult -Name $Application.Name -Status 'MANUAL CHECK REQUIRED' -Details 'Could not determine whether an external application manager controls this installation.'
            return
        }
    }

    $installedState = Get-InstalledPackage -PackageId $Application.PackageId
    if (-not $installedState.Reliable) {
        Add-ApplicationResult -Name $Application.Name -Status 'MANUAL CHECK REQUIRED' -Details "WinGet could not reliably detect '$($Application.PackageId)'. Use -Diagnostic."
        return
    }

    $targetVersion = $null
    if ($Application.ContainsKey('VersionPrefix') -and $Application.VersionPrefix) {
        $targetVersion = Get-LatestVersionWithPrefix -PackageId $Application.PackageId -VersionPrefix $Application.VersionPrefix
        if (-not $targetVersion) {
            Add-ApplicationResult -Name $Application.Name -Status 'MANUAL CHECK REQUIRED' -Details "Could not locate a WinGet release matching '$($Application.VersionPrefix)*'. No changes made."
            return
        }
    }

    if (-not $installedState.Detected) {
        Install-MissingApplication -Application $Application -PinnedTargetVersion $targetVersion
        return
    }

    $installedVersion = $installedState.Row.Version
    if ($installedVersion -in @('Unknown', '-', '')) {
        Add-ApplicationResult -Name $Application.Name -Status 'MANUAL CHECK REQUIRED' -Details 'The installed version is unknown to WinGet.'
        return
    }

    Update-InstalledApplication -Application $Application -InstalledVersion $installedVersion -PinnedTargetVersion $targetVersion
}

function Write-Summary {
    Write-Host "`n========== SUMMARY ==========" -ForegroundColor Cyan
    $statuses = @(
        'UPDATED', 'INSTALLED', 'NO update needed', 'UPDATE AVAILABLE',
        'INSTALL AVAILABLE', 'NOT INSTALLED', 'MANUAL CHECK REQUIRED',
        'UPDATE FAILED', 'INSTALL FAILED', 'CHECK FAILED'
    )

    foreach ($status in $statuses) {
        $matches = @($script:ApplicationResults | Where-Object { $_.Status -eq $status })
        if ($matches.Count -eq 0) {
            continue
        }
        Write-Host ("{0,2}  " -f $matches.Count) -NoNewline
        Write-ColoredStatus -Status $status
    }

    if ($Check) {
        Write-Host "`nCheck-only mode: no applications were changed." -ForegroundColor Yellow
    }
    elseif ($Update) {
        Write-Host "`nFinished. Installation of missing packages was disabled." -ForegroundColor DarkGray
    }
    else {
        Write-Host "`nFinished. Applications may need to be closed, restarted or activated." -ForegroundColor DarkGray
    }
}

# ============================================================================
# MAIN
# ============================================================================
# CLI operations intentionally bypass GitHub and WinGet updates. They only
# inspect or change Local/Applications.local.json (Add uses WinGet catalog search).
$configurationCommands = @('List', 'Add', 'Remove', 'DisableInstall', 'EnableInstall')
$selectedCommands = @($configurationCommands | Where-Object { $PSBoundParameters.ContainsKey($_) })
if ($selectedCommands.Count -gt 1) {
    throw 'Choose only one configuration command at a time.'
}
if ($PSBoundParameters.ContainsKey('PackageId') -and -not $PSBoundParameters.ContainsKey('Add')) {
    throw '-PackageId is only supported together with -Add.'
}
if ($selectedCommands.Count -gt 0 -and
    ($Setup -or $Check -or $Update -or $SkipSourceUpdate -or $Diagnostic -or $SkipSelfUpdate)) {
    throw 'Configuration commands cannot be combined with -Setup or updater options.'
}
if ($Setup -and $PSBoundParameters.ContainsKey('PackageId')) {
    throw '-PackageId cannot be combined with -Setup.'
}

if ($Setup) {
    Install-UserCommand
    return
}

if ($selectedCommands.Count -gt 0) {
    $localConfiguration = Read-LocalConfiguration
    Invoke-ConfigurationCommand -Command $selectedCommands[0] -Configuration $localConfiguration
    return
}

# Load local preferences only when running the updater. Invalid JSON stops the
# update before WinGet or GitHub can change installed applications.
$localConfiguration = Read-LocalConfiguration
$ApplicationDefinitions = @(Get-EffectiveApplications -Configuration $localConfiguration)

if (-not $SkipSelfUpdate) {
    $wasUpdated = Invoke-SelfUpdate
    if ($wasUpdated) {
        # Run the new version immediately, preserving the user's switches.
        $restartArguments = @('-NoLogo', '-NoProfile', '-File', $PSCommandPath, '-SkipSelfUpdate')
        foreach ($switchName in @('Check', 'Update', 'SkipSourceUpdate', 'Diagnostic')) {
            if ($PSBoundParameters.ContainsKey($switchName) -and $PSBoundParameters[$switchName]) {
                $restartArguments += "-$switchName"
            }
        }

        & pwsh.exe @restartArguments
        exit $LASTEXITCODE
    }
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    throw 'WinGet was not found. Install/repair Windows App Installer and retry.'
}

if (-not $SkipSourceUpdate) {
    Write-Host 'Refreshing the WinGet catalog...' -ForegroundColor Cyan
    $sourceUpdate = Invoke-WinGet -Arguments @('source', 'update', '--name', 'winget')
    if ($sourceUpdate.ExitCode -ne 0) {
        Write-Host 'WinGet catalog refresh failed. No changes made.' -ForegroundColor Red
        Write-DiagnosticOutput -Description 'winget source update' -WinGetResult $sourceUpdate
        return
    }
}

# Cache each inventory once. This avoids running winget list for every program.
$script:InstalledPackages = Invoke-WinGet -Arguments @('list', '--accept-source-agreements')
if ($script:InstalledPackages.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($script:InstalledPackages.Output)) {
    Write-Host 'Cannot read installed packages from WinGet. No changes made.' -ForegroundColor Red
    Write-DiagnosticOutput -Description 'winget list' -WinGetResult $script:InstalledPackages
    return
}

$script:AvailableUpgrades = Invoke-WinGet -Arguments @('list', '--upgrade-available', '--accept-source-agreements')
$expectedNoUpgrades = $script:AvailableUpgrades.Output -match '(?i)no available upgrade|no newer package|no applicable upgrade|no installed package found matching'
if ($script:AvailableUpgrades.ExitCode -ne 0 -and -not $expectedNoUpgrades) {
    Write-Host 'Cannot reliably read WinGet updates. No changes made.' -ForegroundColor Red
    Write-DiagnosticOutput -Description 'winget list --upgrade-available' -WinGetResult $script:AvailableUpgrades
    return
}

foreach ($application in $ApplicationDefinitions) {
    Invoke-ApplicationCheck -Application $application
}

Write-Summary
