@echo off
setlocal EnableExtensions
rem Test double for winget. Behavior is selected with DEVAPP_WINGET_* variables.
if defined DEVAPP_WINGET_LOG >>"%DEVAPP_WINGET_LOG%" echo %*

set "COMMAND=%~1"
set "PACKAGE="
set "UPGRADE="
set "VERSIONS="

:parse
if "%~1"=="" goto dispatch
if /I "%~1"=="--id" goto take_id
if /I "%~1"=="--upgrade-available" goto mark_upgrade
if /I "%~1"=="--versions" goto mark_versions
shift
goto parse

:take_id
shift
set "PACKAGE=%~1"
shift
goto parse

:mark_upgrade
set "UPGRADE=1"
shift
goto parse

:mark_versions
set "VERSIONS=1"
shift
goto parse

:dispatch
if /I "%DEVAPP_WINGET_MODE%"=="updater" goto updater
if /I "%COMMAND%"=="search" goto default_search
if /I "%COMMAND%"=="show" goto default_show
echo Mock winget does not support this command 1>&2
exit /b 2

:default_search
echo Name                    Id                    Version   Source
echo ---------------------------------------------------------------
echo Discord                 Discord.Discord       1.0.99    winget
exit /b 0

:default_show
if "%PACKAGE%"=="Discord.Discord" (
    echo Found Discord [Discord.Discord]
    echo Version: 3.0.99
    exit /b 0
)
echo No package found matching input criteria.
exit /b 1

:updater
if /I "%COMMAND%"=="source" goto updater_source
if /I "%COMMAND%"=="list" goto updater_list
if /I "%COMMAND%"=="show" goto updater_show
if /I "%COMMAND%"=="install" goto updater_install
if /I "%COMMAND%"=="upgrade" goto updater_upgrade
echo Mock winget does not support this command 1>&2
exit /b 2

:updater_source
if "%DEVAPP_SOURCE_EXIT%"=="1" (
    echo catalog unavailable
    exit /b 1
)
echo Done
exit /b 0

:updater_list
if "%DEVAPP_LIST_EXIT%"=="1" (
    echo cannot read inventory
    exit /b 1
)
if defined UPGRADE goto updater_list_upgrade
if not "%PACKAGE%"=="" goto updater_list_one
goto updater_list_all

:updater_list_all
echo Name Id Version Source
call :write_records "%DEVAPP_INSTALLED%"
exit /b 0

:updater_list_upgrade
if "%DEVAPP_UPGRADES%"=="" (
    echo No applicable upgrade found.
    exit /b 0
)
call :write_records "%DEVAPP_UPGRADES%"
exit /b 0

:updater_list_one
call :find_version "%DEVAPP_INSTALLED%" "%PACKAGE%"
if defined FOUND_VERSION (
    echo %PACKAGE% %FOUND_VERSION%
    exit /b 0
)
echo No installed package found matching input criteria.
exit /b 0

:updater_show
if defined VERSIONS goto updater_versions
echo Found %PACKAGE% [%PACKAGE%]
echo Version: 9.9.9
exit /b 0

:updater_versions
if defined DEVAPP_BAD_VERSION_ID if /I "%PACKAGE%"=="%DEVAPP_BAD_VERSION_ID%" (
    echo 1.2.3.4.5
    exit /b 0
)
echo 9.9.9
exit /b 0

:updater_install
if "%DEVAPP_INSTALL_EXIT%"=="1" (
    echo Installer failed
    exit /b 1
)
echo Successfully installed
exit /b 0

:updater_upgrade
if "%DEVAPP_UPGRADE_EXIT%"=="1" (
    echo Upgrade failed
    exit /b 1
)
echo Successfully upgraded
exit /b 0

:write_records
set "RECORDS=%~1"
if "%RECORDS%"=="" exit /b 0
for %%A in ("%RECORDS:;=" "%") do (
    for /f "tokens=1,* delims==" %%B in ("%%~A") do (
        if not "%%B"=="" echo %%B %%C
    )
)
exit /b 0

:find_version
set "FOUND_VERSION="
set "RECORDS=%~1"
set "WANTED=%~2"
if "%RECORDS%"=="" exit /b 0
for %%A in ("%RECORDS:;=" "%") do (
    for /f "tokens=1,* delims==" %%B in ("%%~A") do (
        if /I "%%B"=="%WANTED%" set "FOUND_VERSION=%%C"
    )
)
exit /b 0
