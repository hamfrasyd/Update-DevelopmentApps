#requires -Version 7.0
<#
.SYNOPSIS
    Installs missing developer applications and updates installed applications.
.DESCRIPTION
    Uses WinGet with explicitly configured package IDs. Installs missing packages
    by default; -CheckOnly only reports changes. The application list is in
    $ApplicationDefinitions (or optional Applications.local.ps1). -Setup installs this script
    for the current Windows user and registers the update-devapps command.

    WinGet reports update availability from its own catalog, which can lag vendors.
    Certain vendor-managed applications are intentionally marked for manual review.
.EXAMPLE
    .\Update-DevelopmentApps.ps1 -Setup
.EXAMPLE
    update-devapps -CheckOnly
.EXAMPLE
    update-devapps
.EXAMPLE
    update-devapps -CheckOnly -Diagnostic
.EXAMPLE
    update-devapps -NoInstallMissing -SkipSourceUpdate
#>
[CmdletBinding()]
param(
    [switch]$Setup,
    [switch]$CheckOnly,
    [switch]$NoInstallMissing,
    [switch]$SkipSourceUpdate,
    [switch]$Diagnostic,
    [switch]$SkipSelfUpdate
)

$ErrorActionPreference = 'Stop'

# Self-update settings. Change only GitHubOwner when creating your repository.
$ScriptVersion = '1.0.0'
$GitHubOwner = 'hamfrasyd'
$GitHubRepository = 'Update-DevelopmentApps'

# ============================================================================
# APPLICATIONS: EDIT THIS LIST TO ADD OR REMOVE PROGRAMS
# ============================================================================
# To add an application:
#   1. Find its exact ID with: winget search "Application Name"
#   2. Add one row: @{ Name = 'Application Name'; PackageId = 'Publisher.Id' }
#   3. Run: update-devapps -CheckOnly
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
    @{ Name = 'PowerShell';                         PackageId = 'Microsoft.PowerShell' }
)

# Optional personal application list. This file is NOT replaced by GitHub updates.
# Create it only if you want different applications on your own computer.
$localApplicationsPath = Join-Path $env:LOCALAPPDATA 'Programs\DevAppUpdater\Applications.local.ps1'
if (Test-Path -LiteralPath $localApplicationsPath) {
    . $localApplicationsPath
}

# These values are intentionally small and are reset on each script invocation.
$script:ApplicationResults = [System.Collections.Generic.List[object]]::new()
$script:InstalledPackages = $null
$script:AvailableUpgrades = $null

function Install-UserCommand {
    # Use LOCALAPPDATA, not a hardcoded username and not Program Files.
    # This enables a standard user to install the command for their own account.
    $installationDirectory = Join-Path $env:LOCALAPPDATA 'Programs\DevAppUpdater'
    $commandsDirectory = Join-Path $installationDirectory 'bin'
    $destinationScriptPath = Join-Path $installationDirectory 'Update-DevelopmentApps.ps1'
    $launcherPath = Join-Path $commandsDirectory 'update-devapps.cmd'

    New-Item -ItemType Directory -Path $commandsDirectory -Force | Out-Null

    if (-not [string]::Equals($PSCommandPath, $destinationScriptPath, [StringComparison]::OrdinalIgnoreCase)) {
        Copy-Item -LiteralPath $PSCommandPath -Destination $destinationScriptPath -Force
    }

    # The downloaded file may carry the Windows Mark-of-the-Web flag.
    Unblock-File -LiteralPath $destinationScriptPath -ErrorAction Stop

    # The CMD launcher is intentionally simple and works from any directory.
    # %* forwards arguments such as -CheckOnly, -Diagnostic and -NoInstallMissing.
    $launcherContent = @'
@echo off
pwsh.exe -NoLogo -NoProfile -File "%~dp0..\Update-DevelopmentApps.ps1" %*
exit /b %ERRORLEVEL%
'@
    Set-Content -LiteralPath $launcherPath -Value $launcherContent -Encoding ascii

    $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
    $normalizedCommandDirectory = $commandsDirectory.TrimEnd('\')
    $alreadyInUserPath = @($userPath -split ';' | ForEach-Object { $_.Trim().TrimEnd('\') }) -contains $normalizedCommandDirectory

    if (-not $alreadyInUserPath) {
        $updatedUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
            $commandsDirectory
        }
        else {
            "$($userPath.TrimEnd(';'));$commandsDirectory"
        }
        [Environment]::SetEnvironmentVariable('Path', $updatedUserPath, 'User')
    }

    # Make the command usable in this terminal session immediately as well.
    $alreadyInProcessPath = @($env:Path -split ';' | ForEach-Object { $_.Trim().TrimEnd('\') }) -contains $normalizedCommandDirectory
    if (-not $alreadyInProcessPath) {
        $env:Path = "$($env:Path.TrimEnd(';'));$commandsDirectory"
    }

    Write-Host 'The update-devapps command has been installed for your Windows user.' -ForegroundColor Green
    Write-Host "Script:  $destinationScriptPath"
    Write-Host "Command: $launcherPath"
    Write-Host ''
    Write-Host 'Try these commands:' -ForegroundColor Cyan
    Write-Host '  update-devapps -CheckOnly (Checks for available updates and missing applications without making changes)'
    Write-Host '  update-devapps (Updates installed applications and installs missing applications)'
    Write-Host '  update-devapps -NoInstallMissing (Updates installed applications without installing missing ones)'
    Write-Host '  update-devapps -CheckOnly -Diagnostic (Checks for updates and displays detailed troubleshooting information without making changes)'
    Write-Host ''
    Write-Host 'Existing terminal windows may need to be reopened to inherit the updated user PATH.' -ForegroundColor DarkGray
    Write-Host 'For personal app changes, use Applications.local.ps1 beside the installed script.' -ForegroundColor DarkGray
}

function Invoke-SelfUpdate {
    # Only update the installed copy. -Setup is handled before this function runs.
    $installedScriptPath = Join-Path $env:LOCALAPPDATA 'Programs\DevAppUpdater\Update-DevelopmentApps.ps1'
    if ([string]::IsNullOrWhiteSpace($PSCommandPath) -or
        -not [string]::Equals($PSCommandPath, $installedScriptPath, [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }

    if ($GitHubOwner -eq 'REPLACE-WITH-YOUR-GITHUB-USERNAME') {
        Write-Warning 'Self-update is not configured. Set $GitHubOwner in the script.'
        return $false
    }

    $temporaryScriptPath = Join-Path (Split-Path $installedScriptPath -Parent) 'Update-DevelopmentApps.download.ps1'
    $backupScriptPath = Join-Path (Split-Path $installedScriptPath -Parent) 'Update-DevelopmentApps.previous.ps1'

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
            Where-Object { $_.name -eq 'Update-DevelopmentApps.ps1' } |
            Select-Object -First 1

        if ($null -eq $releaseAsset) {
            throw "Release $($release.tag_name) does not contain Update-DevelopmentApps.ps1 as an uploaded asset."
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
        if ($CheckOnly) {
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

    if ($CheckOnly) {
        Add-ApplicationResult -Name $Application.Name -Status 'INSTALL AVAILABLE' -Details "Not detected by WinGet; available version: $versionDescription"
        return
    }

    if ($NoInstallMissing -or ($Application.ContainsKey('InstallIfMissing') -and -not $Application.InstallIfMissing)) {
        Add-ApplicationResult -Name $Application.Name -Status 'NOT INSTALLED' -Details "Not detected by WinGet; automatic installation disabled. Available: $versionDescription"
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

    if ($CheckOnly) {
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

    if ($CheckOnly) {
        Write-Host "`nCheck-only mode: no applications were changed." -ForegroundColor Yellow
    }
    elseif ($NoInstallMissing) {
        Write-Host "`nFinished. Installation of missing packages was disabled." -ForegroundColor DarkGray
    }
    else {
        Write-Host "`nFinished. Applications may need to be closed, restarted or activated." -ForegroundColor DarkGray
    }
}

# ============================================================================
# MAIN
# ============================================================================
if ($Setup) {
    Install-UserCommand
    return
}

if (-not $SkipSelfUpdate) {
    $wasUpdated = Invoke-SelfUpdate
    if ($wasUpdated) {
        # Run the new version immediately, preserving the user's switches.
        $restartArguments = @('-NoLogo', '-NoProfile', '-File', $PSCommandPath, '-SkipSelfUpdate')
        foreach ($switchName in @('CheckOnly', 'NoInstallMissing', 'SkipSourceUpdate', 'Diagnostic')) {
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
