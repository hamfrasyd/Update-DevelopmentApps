# Changelog

## v2.0.0

- Tilføjer `-List`, `-Add`, `-Remove`, `-DisableInstall` og `-EnableInstall` med korte parameternavne (`-l`, `-a`, `-r`, `-di`, `-ei`).
- `-Add` genaktiverer fjernede standardprogrammer; `-Remove` udelukker standardprogrammer eller sletter custom-programmer fra den lokale konfiguration.
- Understøtter også `-Check`/`-c`, `-Update`/`-u`, `-Diagnostic`/`-d` og `-SkipSelfUpdate`/`-ssu`.
- Lokal konfiguration i `%LOCALAPPDATA%\Programs\DevAppUpdater\Local\Applications.local.json`.
- Farvede statusser og bekræftelse af WinGet-ID ved tilføjelse.
- Bevarer lokal konfiguration ved GitHub-selvopdateringer.
- Centraliserer installationsstier og filnavne i scriptet.
- `-Check` respekterer også indstillinger fra `-DisableInstall`, når et program mangler.
- Tilføjer PowerShell-syntakskontrol og konfigurations-smoketests i GitHub Actions.

**Release:** Udskift ikke den gamle v1-release. Udgiv en ny `v2.0.0`, som indeholder `Update-DevelopmentApps.ps1` som vedhæftet asset.
