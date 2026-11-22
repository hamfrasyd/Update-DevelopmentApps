Write-Host 'ARGS:'
[Environment]::GetCommandLineArgs() | ForEach-Object { Write-Host "ARG=$_" }
Write-Host "PSCommandPath=$PSCommandPath"
exit 7
