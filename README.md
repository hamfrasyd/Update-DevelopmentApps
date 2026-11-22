# Update-DevelopmentApps

Et PowerShell-værktøj til Windows, der bruger **WinGet** til at installere manglende udviklingsprogrammer og opdatere allerede installerede. Værktøjet **opdaterer også sig selv fra den seneste GitHub Release**.

> **Krav:** Windows, [PowerShell 7](https://github.com/PowerShell/PowerShell/releases/latest) (`pwsh`) og [WinGet](https://github.com/microsoft/winget-cli) (Windows App Installer).

## 1. Download

1. Gå til **[seneste release](https://github.com/hamfrasyd/Update-DevelopmentApps/releases/latest)**.
2. Under **Assets**: Download **`Update-DevelopmentApps.ps1`**. Vælg **ikke** `Source code (zip)` eller `Source code (tar.gz)`.
3. Gem filen i **Downloads** (`C:\Users\<dinbruger>\Downloads`).

[Download `.ps1` direkte fra seneste release](https://github.com/hamfrasyd/Update-DevelopmentApps/releases/latest/download/Update-DevelopmentApps.ps1)

## 2. Engangsopsætning
1. Åbn **PowerShell 7**.
2. Kopiér og kør:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$HOME\Downloads\Update-DevelopmentApps.ps1" -Setup
```

Åbn derefter en **ny PowerShell-terminal**. Filen i Downloads kan slettes. Opsætningen installerer kommandoen for din Windows-bruger, **ikke alle programmerne**.

## 3. Kommandoer: Opdatér / Installér

Alle kommandoer kan køres fra enhver mappe i PowerShell 7. **Store og små bogstaver er ens** (`-c` og `-C` virker begge).

| Formål | Kommando | Andre navne |
| --- | --- | --- |
| Opdatér installerede programmer og installér manglende | `update-devapps` |   |
| Kontrollér tilgængelige opdateringer uden at installere eller opdatere programmer | `update-devapps -Check` | `-c` |
| Opdatér kun allerede installerede programmer i denne kørsel | `update-devapps -Update` | `-u` |
| Vis detaljer til fejlfinding (kombinér med `-Check`) | `update-devapps -Check -Diagnostic` | `-c -d` |
| Spring GitHub-selvopdateringen over | `update-devapps -SkipSelfUpdate` | `-ssu` |

`-Check` kontrollerer tilgængelige programopdateringer uden at installere eller opdatere programmer. WinGet-kataloget kan blive opdateret.

**Normalt bruger du:**

```powershell
update-devapps
```

## 4. Tilpas din programliste

Du kan ændre listen direkte med kommandoer, **uden at redigere scriptet eller bruge administratorrettigheder**. Ingen af kommandoerne nedenfor afinstallerer programmer fra Windows.

| Formål | Kommando | Kort form |
| --- | --- | --- |
| Vis alle standard- og custom-programmer | `update-devapps -List` | `-l` |
| Tilføj et nyt program, eller genaktivér et fjernet standardprogram | `update-devapps -Add Discord` | `-a Discord` |
| Tilføj med præcist WinGet-ID | `update-devapps -Add Discord -PackageId Discord.Discord` | `-a Discord -PackageId Discord.Discord` |
| Fjern et program fra opdateringslisten | `update-devapps -Remove Obsidian` | `-r Obsidian` |
| Slå automatisk installation fra for et program | `update-devapps -DisableInstall Git` | `-di Git` |
| Tillad automatisk installation igen | `update-devapps -EnableInstall Git` | `-ei Git` |

**Add og Remove tilpasser sig automatisk programtypen:**

- **Standardprogram:** `-Remove Obsidian` udelukker Obsidian fra opdateringslisten; `-Add Obsidian` inkluderer det igen. Standardlisten på GitHub ændres ikke.
- **Custom-program:** `-Add Discord` søger i WinGet og tilføjer Discord lokalt; `-Remove Discord` sletter registreringen fra den lokale JSON-konfiguration. Det afinstallerer ikke Discord fra Windows.
- **Begge typer:** `-DisableInstall Git` betyder, at Git stadig må opdateres, men ikke installeres, hvis det mangler. `-EnableInstall Git` tillader installation igen. Indstillingen gemmes lokalt.

**Eksempel:**

```powershell
update-devapps -r Obsidian
update-devapps -di Git
update-devapps -a Discord
update-devapps -l
update-devapps -a Obsidian
```

`-Add` søger i WinGet for nye custom-programmer; ved flere match vælger du programmet fra en nummereret liste. Ukendte WinGet-ID'er gemmes ikke. En allerede kendt standardapplikation genaktiveres uden WinGet-søgning.

Dine personlige valg gemmes automatisk i:

```text
%LOCALAPPDATA%\Programs\DevAppUpdater\Local\Applications.local.json
```

Filen oprettes først, når du ændrer noget. Du kan nulstille dine egne valg ved at slette JSON-filen. **`Local`-mappen bevares ved selvopdatering**, og `-List` kræver ikke netværksadgang. Hvis JSON-filen bliver ugyldig, stopper værktøjet med en fejl og beder dig undersøge filen i stedet for at overskrive den.

## Standardprogrammer
| Programmer                    |
| ----------------------------- |
| Obsidian                      |
| Notepad++                     |
| Postman                       |
| Wireshark                     |
| Visual Studio 2026 Enterprise |
| VS Code                       |
| Cursor                        |
| Docker Desktop                |
| Ollama                        |
| SSMS 22                       |
| MySQL Workbench               |
| Neo4j Desktop                 |
| MongoDB Compass               |
| MongoDB Shell                 |
| DataGrip                      |
| Git                           |
| Python 3.15                   |
| Java JDK 25 LTS               |
| .NET 10 SDK                   |
| .NET 11 SDK                   |
| PowerShell                    |

Programlisten omfatter databaseklienter, **ikke selve serverne** (SQL Server-, MySQL-, MongoDB- eller Neo4j-server).

Nogle programinstallationer kan kræve administratorgodkendelse.

## Udgiv en version

Nye versioner publiceres fra GitHub Actions. Du skal ikke ændre `$ScriptVersion`, oprette et tag eller uploade `.ps1`-filen selv. Release notes skrives af GitHub. `CHANGELOG.md` er ikke en del af publiceringen.

Kildekoden på `dev` og `main` har altid:

```powershell
$ScriptVersion = '0.0.0'
```

Den fil, der lægges på releasen, får det rigtige nummer. `v2.0.0` indeholder derfor `$ScriptVersion = '2.0.0'`.

1. Udvikl på `dev`, commit og push.
2. Opret en pull request fra `dev` til `main`. Actions validerer scriptet og kører tests.
3. Gennemgå og merge. Der pushes ikke direkte til `main`.
4. Åbn **Actions → Publish Release**, vælg branch **`main`**, og vælg versionsændring:
   - **patch** — `2.0.0` bliver `2.0.1` (standard)
   - **minor** — `2.0.0` bliver `2.1.0`
   - **major** — `1.0.0` bliver `2.0.0`
5. Start workflowet.

GitHub læser seneste stabile release, beregner næste nummer, bygger `Update-DevelopmentApps.ps1`, opretter tag og release og markerer den som seneste. Et eksisterende tag overskrives ikke. Starter du workflowet fra `dev`, stopper det med en fejl.

Kør scriptet fra repositorymappen, mens du udvikler. `-Setup` kopierer kildefilen med `0.0.0` til installationsmappen, og næste kørsel henter derfor seneste release.