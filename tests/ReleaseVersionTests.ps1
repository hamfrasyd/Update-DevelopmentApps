# Tests for release version calculation and asset substitution.
# Each test is Arrange, Act, Assert and contains one assertion.
$ErrorActionPreference = 'Stop'

$script:RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $script:RepositoryRoot '.github\scripts\ReleaseVersion.ps1')

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
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ('DevAppUpdaterRelease-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    return $root
}

function Remove-TestRoot {
    param([string]$Root)

    if ($Root -and (Test-Path -LiteralPath $Root)) {
        Remove-Item -LiteralPath $Root -Recurse -Force
    }
}

function Write-Fixture {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )

    $encoding = New-Object System.Text.UTF8Encoding -ArgumentList @($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

Invoke-Test 'NextReleaseVersion_WhenMajorFromOne_ShouldResetMinorAndPatch' {
    $next = Get-NextReleaseVersion -CurrentVersion '1.0.0' -Bump 'major'

    Assert-Result ($next.Version -eq '2.0.0' -and $next.TagName -eq 'v2.0.0') "Expected v2.0.0, got $($next.TagName)."
}

Invoke-Test 'NextReleaseVersion_WhenMinorFromTwo_ShouldIncrementMinor' {
    $next = Get-NextReleaseVersion -CurrentVersion '2.0.0' -Bump 'minor'

    Assert-Result ($next.Version -eq '2.1.0' -and $next.TagName -eq 'v2.1.0') "Expected v2.1.0, got $($next.TagName)."
}

Invoke-Test 'NextReleaseVersion_WhenPatchFromTwo_ShouldIncrementPatch' {
    $next = Get-NextReleaseVersion -CurrentVersion '2.0.0' -Bump 'patch'

    Assert-Result ($next.Version -eq '2.0.1' -and $next.TagName -eq 'v2.0.1') "Expected v2.0.1, got $($next.TagName)."
}

Invoke-Test 'NextReleaseVersion_WhenMajorHasMinorAndPatch_ShouldResetBoth' {
    $next = Get-NextReleaseVersion -CurrentVersion 'v1.4.7' -Bump 'major'

    Assert-Result ($next.Version -eq '2.0.0') "Expected 2.0.0, got $($next.Version)."
}

Invoke-Test 'NextReleaseVersion_WhenMinorHasPatch_ShouldResetPatch' {
    $next = Get-NextReleaseVersion -CurrentVersion 'v2.3.9' -Bump 'minor'

    Assert-Result ($next.Version -eq '2.4.0') "Expected 2.4.0, got $($next.Version)."
}

Invoke-Test 'NextReleaseVersion_WhenPatchCrossesTen_ShouldKeepDecimalValue' {
    $next = Get-NextReleaseVersion -CurrentVersion '2.1.9' -Bump 'patch'

    Assert-Result ($next.Version -eq '2.1.10' -and $next.TagName -eq 'v2.1.10') "Expected v2.1.10, got $($next.TagName)."
}

Invoke-Test 'NextReleaseVersion_WhenBumpHasDifferentCase_ShouldAcceptIt' {
    $next = Get-NextReleaseVersion -CurrentVersion 'v1.2.3' -Bump ' PATCH '

    Assert-Result ($next.TagName -eq 'v1.2.4') "Expected v1.2.4, got $($next.TagName)."
}

Invoke-Test 'ReleaseVersion_WhenFormatIsInvalid_ShouldFailClearly' {
    $samples = @('1.0', '01.2.3', 'v1.2.3-beta', 'v1.2.3.4', 'latest', '', 'V1.0.0', 'v1.00.0')
    $accepted = [System.Collections.Generic.List[string]]::new()
    foreach ($sample in $samples) {
        try {
            ConvertTo-ReleaseVersion -VersionText $sample | Out-Null
            $accepted.Add($sample)
        }
        catch {
            if ($_.Exception.Message -notmatch 'Ugyldigt versionsnummer') {
                $accepted.Add("$sample ($($_.Exception.Message))")
            }
        }
    }

    Assert-Result ($accepted.Count -eq 0) ("Invalid versions were accepted: " + ($accepted -join ', '))
}

Invoke-Test 'ReleaseBump_WhenChoiceIsUnknown_ShouldFail' {
    $message = ''
    try {
        Resolve-ReleaseBump -Bump 'build' | Out-Null
    }
    catch {
        $message = $_.Exception.Message
    }

    Assert-Result ($message -match 'Ugyldig versionsændring') 'Unknown bump was accepted.'
}

Invoke-Test 'ReleaseTag_WhenTagAlreadyExists_ShouldRefuseOverwrite' {
    $message = ''
    try {
        Assert-ReleaseTagIsAvailable -TagName 'v2.0.0' -ExistingTags @('v1.0.0', 'v2.0.0')
    }
    catch {
        $message = $_.Exception.Message
    }

    Assert-Result ($message -match 'findes allerede' -and $message -match 'ikke overskrevet') 'Existing tag was not rejected.'
}

Invoke-Test 'ReleaseTag_WhenOnlyOtherTagsExist_ShouldAllowTheNewTag' {
    $threw = $false
    try {
        Assert-ReleaseTagIsAvailable -TagName 'v2.0.0' -ExistingTags @('v1.0.0', 'v1.1.0')
    }
    catch {
        $threw = $true
    }

    Assert-Result (-not $threw) 'A new tag was treated as an existing release.'
}

Invoke-Test 'ReleaseTag_WhenExistingTagDiffersOnlyByCase_ShouldRefuseIt' {
    $threw = $false
    try {
        Assert-ReleaseTagIsAvailable -TagName 'v2.0.0' -ExistingTags @('V2.0.0')
    }
    catch {
        $threw = $true
    }

    Assert-Result $threw 'A case-variant of an existing tag was allowed.'
}

Invoke-Test 'ReleaseScript_WhenVersionIsInserted_ShouldChangeOnlyThePlaceholder' {
    $root = New-TestRoot
    try {
        $source = Join-Path $root 'Update-DevelopmentApps.ps1'
        $destination = Join-Path $root 'dist\Update-DevelopmentApps.ps1'
        $fixture = "# before`r`n`$ScriptVersion = '0.0.0'`r`nWrite-Host `"v`$ScriptVersion`"`r`n"
        Write-Fixture -Path $source -Content $fixture

        Set-ReleaseScriptVersion -SourcePath $source -DestinationPath $destination -Version '10.11.12'

        $written = [System.IO.File]::ReadAllText($destination)
        $expected = "# before`r`n`$ScriptVersion = '10.11.12'`r`nWrite-Host `"v`$ScriptVersion`"`r`n"
        Assert-Result ($written -ceq $expected) 'The release asset changed more than the version literal.'
    }
    finally {
        Remove-TestRoot $root
    }
}

Invoke-Test 'ReleaseScript_WhenBuiltFromRepository_ShouldKeepEveryOtherByte' {
    $root = New-TestRoot
    try {
        $source = Join-Path $script:RepositoryRoot 'Update-DevelopmentApps.ps1'
        $destination = Join-Path $root 'dist\Update-DevelopmentApps.ps1'
        Set-ReleaseScriptVersion -SourcePath $source -DestinationPath $destination -Version '2.0.0'

        $before = [System.IO.File]::ReadAllText($source)
        $after = [System.IO.File]::ReadAllText($destination)
        $placeholder = "`$ScriptVersion = '0.0.0'"
        $declarationCount = ([regex]::Matches($before, [regex]::Escape($placeholder))).Count
        $expected = $before.Replace($placeholder, "`$ScriptVersion = '2.0.0'")
        Assert-Result (($declarationCount -eq 1) -and ($after -ceq $expected)) 'The repository release asset was not a single version substitution.'
    }
    finally {
        Remove-TestRoot $root
    }
}

Invoke-Test 'ReleaseScript_WhenBuilt_ShouldMatchTheSelfUpdateContract' {
    $root = New-TestRoot
    try {
        $source = Join-Path $script:RepositoryRoot 'Update-DevelopmentApps.ps1'
        $destination = Join-Path $root 'dist\Update-DevelopmentApps.ps1'
        Set-ReleaseScriptVersion -SourcePath $source -DestinationPath $destination -Version 'v2.0.0'

        $written = [System.IO.File]::ReadAllText($destination)
        $match = [regex]::Match($written, "(?m)^\s*\`$ScriptVersion\s*=\s*'(?<Version>\d+\.\d+\.\d+)'\s*$")
        Assert-Result ($match.Success -and $match.Groups['Version'].Value -eq '2.0.0') 'The release asset version does not match v2.0.0.'
    }
    finally {
        Remove-TestRoot $root
    }
}

Invoke-Test 'ReleaseScript_WhenDeclarationIsMissing_ShouldFail' {
    $root = New-TestRoot
    try {
        $source = Join-Path $root 'Update-DevelopmentApps.ps1'
        $destination = Join-Path $root 'dist\Update-DevelopmentApps.ps1'
        Write-Fixture -Path $source -Content "Write-Host 'no version'`r`n"
        $message = ''
        try {
            Set-ReleaseScriptVersion -SourcePath $source -DestinationPath $destination -Version '2.0.0'
        }
        catch {
            $message = $_.Exception.Message
        }

        Assert-Result ($message -match 'præcis én' -and -not (Test-Path -LiteralPath $destination)) 'A missing version declaration was accepted.'
    }
    finally {
        Remove-TestRoot $root
    }
}

Invoke-Test 'ReleaseScript_WhenDeclarationIsRepeated_ShouldFail' {
    $root = New-TestRoot
    try {
        $source = Join-Path $root 'Update-DevelopmentApps.ps1'
        $destination = Join-Path $root 'dist\Update-DevelopmentApps.ps1'
        Write-Fixture -Path $source -Content "`$ScriptVersion = '0.0.0'`r`n`$ScriptVersion = '0.0.0'`r`n"
        $message = ''
        try {
            Set-ReleaseScriptVersion -SourcePath $source -DestinationPath $destination -Version '2.0.0'
        }
        catch {
            $message = $_.Exception.Message
        }

        Assert-Result ($message -match 'fandt 2') 'Repeated version declarations were accepted.'
    }
    finally {
        Remove-TestRoot $root
    }
}

Invoke-Test 'ReleaseScript_WhenPlaceholderIsNotZero_ShouldFail' {
    $root = New-TestRoot
    try {
        $source = Join-Path $root 'Update-DevelopmentApps.ps1'
        $destination = Join-Path $root 'dist\Update-DevelopmentApps.ps1'
        Write-Fixture -Path $source -Content "`$ScriptVersion = '1.2.3'`r`n"
        $message = ''
        try {
            Set-ReleaseScriptVersion -SourcePath $source -DestinationPath $destination -Version '2.0.0'
        }
        catch {
            $message = $_.Exception.Message
        }

        Assert-Result ($message -match "0\.0\.0") 'A non-placeholder source version was accepted.'
    }
    finally {
        Remove-TestRoot $root
    }
}

Invoke-Test 'ReleaseScript_WhenDestinationIsTheSource_ShouldFail' {
    $root = New-TestRoot
    try {
        $source = Join-Path $root 'Update-DevelopmentApps.ps1'
        Write-Fixture -Path $source -Content "`$ScriptVersion = '0.0.0'`r`n"
        $message = ''
        try {
            Set-ReleaseScriptVersion -SourcePath $source -DestinationPath $source -Version '2.0.0'
        }
        catch {
            $message = $_.Exception.Message
        }

        $stillPlaceholder = [System.IO.File]::ReadAllText($source) -eq "`$ScriptVersion = '0.0.0'`r`n"
        Assert-Result ($message -match 'ikke overskrive' -and $stillPlaceholder) 'The source file was overwritten.'
    }
    finally {
        Remove-TestRoot $root
    }
}

Invoke-Test 'PublishWorkflow_WhenInspected_ShouldNotPushAndShouldPublishFromMain' {
    $workflow = [System.IO.File]::ReadAllText((Join-Path $script:RepositoryRoot '.github\workflows\release.yml'))
    $problems = [System.Collections.Generic.List[string]]::new()
    $required = @(
        '(?m)^name:\s*Publish Release\s*$',
        'workflow_dispatch:',
        'default:\s*patch',
        'contents:\s*write',
        'cancel-in-progress:\s*false',
        'runs-on:\s*windows-latest',
        'refs/heads/main',
        'persist-credentials:\s*false',
        'gh release create',
        '--generate-notes',
        '--draft',
        'gh release edit',
        '--draft=false',
        '--latest',
        '--target'
    )
    foreach ($pattern in $required) {
        if ($workflow -notmatch $pattern) {
            $problems.Add("missing $pattern")
        }
    }
    foreach ($choice in @('patch', 'minor', 'major')) {
        if ($workflow -notmatch "(?m)^\s*- $choice\s*$") {
            $problems.Add("missing choice $choice")
        }
    }
    if ($workflow -match '(?m)^\s*git\s+push\b' -or $workflow -match '(?m)^\s*git\s+commit\b' -or $workflow -match '(?m)^\s*git\s+tag\b') {
        $problems.Add('git write command')
    }
    if ($workflow -match '(?m)^\s*push:') {
        $problems.Add('push trigger')
    }
    if ($workflow -match '--force' -or $workflow -match 'release delete') {
        $problems.Add('overwrite flag')
    }

    Assert-Result ($problems.Count -eq 0) ("Publish Release workflow contract failed: " + ($problems -join '; '))
}

Invoke-Test 'PublishWorkflow_WhenInspected_ShouldVerifyTheDraftBeforePublishing' {
    $workflow = [System.IO.File]::ReadAllText((Join-Path $script:RepositoryRoot '.github\workflows\release.yml'))
    $create = $workflow.IndexOf('gh release create')
    $verify = $workflow.IndexOf('Verify the draft release')
    $publish = $workflow.IndexOf('gh release edit')
    $ordered = $create -ge 0 -and $verify -gt $create -and $publish -gt $verify
    $createSection = $workflow.Substring($create, $verify - $create)
    $verifySection = $workflow.Substring($verify, $publish - $verify)
    $publishSection = $workflow.Substring($publish)
    $createIsDraft = $createSection -match '(?m)^\s*--draft\s*`\s*$' -and $createSection -notmatch '--latest'
    $verifyChecksAsset = $verifySection -match 'SHA256' -and $verifySection -match 'ScriptVersion' -and $verifySection -match 'GITHUB_SHA' -and $verifySection -notmatch '--latest' -and $verifySection -notmatch 'gh release edit'
    $publishesAfterSuccess = $publishSection -match '--draft=false' -and $publishSection -match '--latest' -and $workflow -match '(?m)^[ \t]*- name: Publish the verified release[ \t]*\r?\n[ \t]*if: success\(\)[ \t]*$'

    Assert-Result ($ordered -and $createIsDraft -and $verifyChecksAsset -and $publishesAfterSuccess) 'The draft is not verified before it is published.'
}

Invoke-Test 'GitHubExistence_WhenStatusIs200_ShouldReportThatTheResourceExists' {
    $response = "HTTP/2.0 200 OK`r`n`r`n{`"message`":`"Not Found`"}"
    $exists = Resolve-GitHubResourceExistence -HttpResponse $response -ResourceName "tag 'v2.0.0'"

    Assert-Result ($exists -eq $true) 'HTTP 200 was not treated as an existing resource.'
}

Invoke-Test 'GitHubExistence_WhenStatusIs404_ShouldReportThatTheResourceIsMissing' {
    $exists = Resolve-GitHubResourceExistence -HttpResponse "HTTP/2.0 404 Not Found`r`n" -ResourceName "tag 'v2.0.0'"

    Assert-Result ($exists -eq $false) 'HTTP 404 was not treated as a missing resource.'
}

Invoke-Test 'GitHubExistence_WhenRedirectEndsIn404_ShouldUseTheFinalStatus' {
    $response = "HTTP/1.1 302 Found`nHTTP/2.0 404 Not Found`n"
    $exists = Resolve-GitHubResourceExistence -HttpResponse $response -ResourceName "release 'v2.0.0'"

    Assert-Result ($exists -eq $false) 'A redirect was used instead of the final HTTP status.'
}

Invoke-Test 'GitHubExistence_WhenStatusIsAnError_ShouldFail' {
    $samples = @(401, 403, 500, 502)
    $accepted = [System.Collections.Generic.List[string]]::new()
    foreach ($status in $samples) {
        try {
            $result = Resolve-GitHubResourceExistence -HttpResponse "HTTP/2.0 $status Error`r`n{`"message`":`"Not Found 404`"}" -ResourceName "tag 'v2.0.0'"
            $accepted.Add("$status returned $result")
        }
        catch {
            if ($_.Exception.Message -notmatch "HTTP $status") {
                $accepted.Add("$status ($($_.Exception.Message))")
            }
        }
    }

    Assert-Result ($accepted.Count -eq 0) ("GitHub errors were treated as a missing tag: " + ($accepted -join ', '))
}

Invoke-Test 'GitHubExistence_WhenOnlyCliErrorTextIsPresent_ShouldFail' {
    $message = ''
    try {
        Resolve-GitHubResourceExistence -HttpResponse 'gh: Not Found (HTTP 404)' -ResourceName "tag 'v2.0.0'" | Out-Null
    }
    catch {
        $message = $_.Exception.Message
    }

    Assert-Result ($message -match 'ingen HTTP-statuskode') 'CLI error text was treated as a missing tag.'
}

Invoke-Test 'GitHubLookup_WhenInspected_ShouldRequestHttpStatusForTagAndRelease' {
    $source = [System.IO.File]::ReadAllText((Join-Path $script:RepositoryRoot '.github\scripts\ReleaseVersion.ps1'))
    $tagLookup = [regex]::Match($source, '(?s)function Test-GitHubTagExists \{.*?\r?\n\}')
    $releaseLookup = [regex]::Match($source, '(?s)function Test-GitHubReleaseExists \{.*?\r?\n\}')
    $tagUsesStatus = $tagLookup.Success -and $tagLookup.Value -match 'gh api --include "repos/\$Repository/git/ref/tags/' -and $tagLookup.Value -match 'Resolve-GitHubResourceExistence'
    $releaseUsesStatus = $releaseLookup.Success -and $releaseLookup.Value -match 'gh api --include "repos/\$Repository/releases/tags/' -and $releaseLookup.Value -match 'Resolve-GitHubResourceExistence'
    $avoidsErrorText = $source -notmatch 'release not found'

    Assert-Result ($tagUsesStatus -and $releaseUsesStatus -and $avoidsErrorText) 'GitHub lookups still depend on CLI error text.'
}

if ($script:FailedCases.Count -gt 0) {
    Write-Host ''
    Write-Host 'Failed release version tests:' -ForegroundColor Red
    foreach ($failedCase in $script:FailedCases) {
        Write-Host "  $failedCase" -ForegroundColor Red
    }
    throw "$($script:FailedCases.Count) release version test(s) failed."
}

Write-Host "All release version tests passed ($($script:PassedCount))." -ForegroundColor Green
