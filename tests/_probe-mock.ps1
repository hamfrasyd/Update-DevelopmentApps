$ErrorActionPreference = 'Stop'
$log = Join-Path $env:TEMP 'winget-mock-log.txt'
$env:DEVAPP_WINGET_LOG = $log
$env:DEVAPP_WINGET_MODE = 'default'
$env:DEVAPP_INSTALLED = 'Git.Git=2.47.0;JetBrains.Toolbox=2.1.0'
$env:DEVAPP_UPGRADES = 'Git.Git=2.48.0'
$env:DEVAPP_BAD_VERSION_ID = 'Example.Broken'
$env:DEVAPP_SOURCE_EXIT = '0'
$env:DEVAPP_LIST_EXIT = '0'
$env:DEVAPP_INSTALL_EXIT = '0'
$env:DEVAPP_UPGRADE_EXIT = '0'
Set-Content -LiteralPath $log -Value '' -Encoding ascii
$mock = Join-Path $PSScriptRoot 'mocks\winget.cmd'

function Invoke-Mock {
    param([Parameter(Mandatory)][string[]]$MockArguments)
    $output = & $mock @MockArguments
    Write-Host "EXIT $LASTEXITCODE :: $($MockArguments -join ' ')"
    $output | ForEach-Object { Write-Host "  $_" }
}

Invoke-Mock -MockArguments @('show', '--id', 'Discord.Discord', '--exact')
Invoke-Mock -MockArguments @('show', '--id', 'Missing.Missing', '--exact')
$env:DEVAPP_WINGET_MODE = 'updater'
Invoke-Mock -MockArguments @('list', '--accept-source-agreements')
Invoke-Mock -MockArguments @('list', '--id', 'Git.Git', '--exact')
Invoke-Mock -MockArguments @('list', '--id', 'Obsidian.Obsidian', '--exact')
Invoke-Mock -MockArguments @('list', '--upgrade-available', '--accept-source-agreements')
Invoke-Mock -MockArguments @('show', '--id', 'Example.Broken', '--exact', '--versions')
Invoke-Mock -MockArguments @('show', '--id', 'Git.Git', '--exact')
Invoke-Mock -MockArguments @('install', '--id', 'Obsidian.Obsidian', '--exact')
$env:DEVAPP_SOURCE_EXIT = '1'
Invoke-Mock -MockArguments @('source', 'update', '--name', 'winget')
Write-Host '--- LOG ---'
Get-Content -LiteralPath $log
