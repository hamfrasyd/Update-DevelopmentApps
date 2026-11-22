# Version calculation and release-asset substitution for Publish Release.
# The workflow calls these functions. They do not create commits or push to main.
# Tag lookup talks to GitHub; the version math and file substitution do not.

$script:SourceVersionPlaceholder = '0.0.0'
$script:ScriptFileName = 'Update-DevelopmentApps.ps1'

function ConvertTo-ReleaseVersion {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$VersionText
    )

    if ($VersionText -cnotmatch '^(?:v)?(?<Major>0|[1-9]\d*)\.(?<Minor>0|[1-9]\d*)\.(?<Patch>0|[1-9]\d*)$') {
        throw "Ugyldigt versionsnummer '$VersionText'. Brug formatet vMAJOR.MINOR.PATCH, for eksempel v1.0.0."
    }

    try {
        $major = [int]$Matches.Major
        $minor = [int]$Matches.Minor
        $patch = [int]$Matches.Patch
    }
    catch {
        throw "Ugyldigt versionsnummer '$VersionText'. Brug formatet vMAJOR.MINOR.PATCH, for eksempel v1.0.0."
    }

    $version = '{0}.{1}.{2}' -f $major, $minor, $patch
    return [pscustomobject]@{
        Major   = $major
        Minor   = $minor
        Patch   = $patch
        Version = $version
        TagName = "v$version"
    }
}

function Resolve-ReleaseBump {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Bump
    )

    $normalized = $Bump.Trim().ToLowerInvariant()
    if ($normalized -notin @('major', 'minor', 'patch')) {
        throw "Ugyldig versionsændring '$Bump'. Vælg major, minor eller patch."
    }

    return $normalized
}

function Get-NextReleaseVersion {
    param(
        [Parameter(Mandatory)]
        [string]$CurrentVersion,
        [Parameter(Mandatory)]
        [string]$Bump
    )

    $current = ConvertTo-ReleaseVersion -VersionText $CurrentVersion
    $resolvedBump = Resolve-ReleaseBump -Bump $Bump
    $major = $current.Major
    $minor = $current.Minor
    $patch = $current.Patch

    switch ($resolvedBump) {
        'major' {
            $major++
            $minor = 0
            $patch = 0
        }
        'minor' {
            $minor++
            $patch = 0
        }
        'patch' {
            $patch++
        }
    }

    return (ConvertTo-ReleaseVersion -VersionText ('{0}.{1}.{2}' -f $major, $minor, $patch))
}

function Assert-ReleaseTagIsAvailable {
    param(
        [Parameter(Mandatory)]
        [string]$TagName,
        [AllowEmptyCollection()]
        [string[]]$ExistingTags = @()
    )

    $normalized = ConvertTo-ReleaseVersion -VersionText $TagName
    foreach ($existing in @($ExistingTags)) {
        if ([string]::IsNullOrWhiteSpace($existing)) {
            continue
        }

        $candidate = $existing.Trim()
        $sameTag = [string]::Equals($candidate, $normalized.TagName, [StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($candidate, $normalized.Version, [StringComparison]::OrdinalIgnoreCase)
        if (-not $sameTag -and $candidate -cmatch '^(?:v)?(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$') {
            $existingVersion = ConvertTo-ReleaseVersion -VersionText $candidate
            $sameTag = [string]::Equals($existingVersion.TagName, $normalized.TagName, [StringComparison]::OrdinalIgnoreCase)
        }
        if ($sameTag) {
            throw "Tag '$($normalized.TagName)' findes allerede. En eksisterende release bliver ikke overskrevet."
        }
    }
}

function Set-ReleaseScriptVersion {
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,
        [Parameter(Mandatory)]
        [string]$DestinationPath,
        [Parameter(Mandatory)]
        [string]$Version
    )

    $releaseVersion = ConvertTo-ReleaseVersion -VersionText $Version
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "Kildefil blev ikke fundet: $SourcePath"
    }

    $sourceFullPath = [System.IO.Path]::GetFullPath($SourcePath)
    $destinationFullPath = [System.IO.Path]::GetFullPath($DestinationPath)
    if ([string]::Equals($sourceFullPath, $destinationFullPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Releasefilen må ikke overskrive kildefilen.'
    }

    $sourceBytes = [System.IO.File]::ReadAllBytes($sourceFullPath)
    $hasBom = $sourceBytes.Length -ge 3 -and $sourceBytes[0] -eq 0xEF -and $sourceBytes[1] -eq 0xBB -and $sourceBytes[2] -eq 0xBF
    $utf8 = New-Object System.Text.UTF8Encoding -ArgumentList @($false)
    $offset = 0
    if ($hasBom) {
        $offset = 3
    }
    $content = $utf8.GetString($sourceBytes, $offset, $sourceBytes.Length - $offset)

    # Same assignment shape the self-updater accepts. The line break stays outside the version group.
    $pattern = '(?m)^[ \t]*\$ScriptVersion\s*=\s*''(?<Version>\d+\.\d+\.\d+)''[ \t]*\r?$'
    $declarations = [regex]::Matches($content, $pattern)
    if ($declarations.Count -ne 1) {
        throw "Forventede præcis én `$ScriptVersion-deklaration i '$SourcePath', fandt $($declarations.Count)."
    }

    $versionGroup = $declarations[0].Groups['Version']
    if ($versionGroup.Value -ne $script:SourceVersionPlaceholder) {
        throw "Kildekoden skal indeholde `$ScriptVersion = '$($script:SourceVersionPlaceholder)'. Fandt '$($versionGroup.Value)'."
    }

    $updated = $content.Remove($versionGroup.Index, $versionGroup.Length).Insert($versionGroup.Index, $releaseVersion.Version)
    $destinationDirectory = Split-Path -Parent $destinationFullPath
    if (-not [string]::IsNullOrWhiteSpace($destinationDirectory)) {
        New-Item -ItemType Directory -Force -Path $destinationDirectory | Out-Null
    }

    $writeEncoding = New-Object System.Text.UTF8Encoding -ArgumentList @($hasBom)
    [System.IO.File]::WriteAllText($destinationFullPath, $updated, $writeEncoding)

    $parseTokens = $null
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($destinationFullPath, [ref]$parseTokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        throw "Den versionerede releasefil har syntaksfejl: $($parseErrors[0].Message)"
    }

    $writtenBytes = [System.IO.File]::ReadAllBytes($destinationFullPath)
    $writtenOffset = 0
    if ($hasBom) {
        $writtenOffset = 3
    }
    $written = $utf8.GetString($writtenBytes, $writtenOffset, $writtenBytes.Length - $writtenOffset)
    $writtenDeclarations = [regex]::Matches($written, $pattern)
    if ($writtenDeclarations.Count -ne 1 -or $writtenDeclarations[0].Groups['Version'].Value -ne $releaseVersion.Version) {
        throw "Releasefilen indeholder ikke `$ScriptVersion = '$($releaseVersion.Version)'."
    }

    $selfUpdatePattern = "(?m)^\s*\`$ScriptVersion\s*=\s*'(?<Version>\d+\.\d+\.\d+)'\s*$"
    $selfUpdateMatch = [regex]::Match($written, $selfUpdatePattern)
    if (-not $selfUpdateMatch.Success -or $selfUpdateMatch.Groups['Version'].Value -ne $releaseVersion.Version) {
        throw "Releasefilen matcher ikke selvopdateringens versionskrav '$($releaseVersion.Version)'."
    }
}

function Resolve-GitHubResourceExistence {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$HttpResponse,
        [Parameter(Mandatory)]
        [string]$ResourceName
    )

    $statuses = [regex]::Matches($HttpResponse, '(?m)^HTTP/\d+(?:\.\d+)?\s+(?<Status>\d{3})\b')
    if ($statuses.Count -eq 0) {
        $detail = ($HttpResponse -replace '\s+', ' ').Trim()
        if ($detail.Length -gt 300) {
            $detail = $detail.Substring(0, 300)
        }
        if ([string]::IsNullOrWhiteSpace($detail)) {
            $detail = 'intet svar'
        }
        throw "Kunne ikke kontrollere, om $ResourceName findes. GitHub-svaret indeholdt ingen HTTP-statuskode. $detail"
    }

    $status = [int]$statuses[$statuses.Count - 1].Groups['Status'].Value
    if ($status -eq 200) {
        return $true
    }
    if ($status -eq 404) {
        return $false
    }

    throw "Kunne ikke kontrollere, om $ResourceName findes. HTTP $status."
}

function Test-GitHubTagExists {
    param(
        [Parameter(Mandatory)]
        [string]$Repository,
        [Parameter(Mandatory)]
        [string]$TagName
    )

    $PSNativeCommandUseErrorActionPreference = $false
    $normalized = ConvertTo-ReleaseVersion -VersionText $TagName
    $response = gh api --include "repos/$Repository/git/ref/tags/$($normalized.TagName)" 2>&1 | Out-String
    return Resolve-GitHubResourceExistence -HttpResponse $response -ResourceName "tag '$($normalized.TagName)'"
}

function Test-GitHubReleaseExists {
    param(
        [Parameter(Mandatory)]
        [string]$Repository,
        [Parameter(Mandatory)]
        [string]$TagName
    )

    $PSNativeCommandUseErrorActionPreference = $false
    $normalized = ConvertTo-ReleaseVersion -VersionText $TagName
    $response = gh api --include "repos/$Repository/releases/tags/$($normalized.TagName)" 2>&1 | Out-String
    return Resolve-GitHubResourceExistence -HttpResponse $response -ResourceName "release '$($normalized.TagName)'"
}

function Get-ConflictingReleaseTags {
    param(
        [Parameter(Mandatory)]
        [string]$Repository,
        [Parameter(Mandatory)]
        [string]$TagName
    )

    $normalized = ConvertTo-ReleaseVersion -VersionText $TagName
    $conflicts = [System.Collections.Generic.List[string]]::new()
    if (Test-GitHubTagExists -Repository $Repository -TagName $normalized.TagName) {
        $conflicts.Add($normalized.TagName)
    }
    if (Test-GitHubReleaseExists -Repository $Repository -TagName $normalized.TagName) {
        if (-not $conflicts.Contains($normalized.TagName)) {
            $conflicts.Add($normalized.TagName)
        }
    }

    return @($conflicts)
}
