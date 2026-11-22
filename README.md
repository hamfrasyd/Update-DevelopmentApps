# Update-DevelopmentApps

Et PowerShell-script til Windows, som bruger **WinGet** til at installere manglende udviklingsprogrammer og opdatere installerede programmer. Scriptet kan også **opdatere sig selv fra den seneste GitHub Release**.

> **Kræver:** Windows med [PowerShell 7](https://github.com/PowerShell/PowerShell/releases/latest) (`pwsh`) og WinGet (Windows App Installer).

## 1. Download

1. Åbn **[seneste GitHub Release](https://github.com/hamfrasyd/Update-DevelopmentApps/releases/latest)**.
2. Find **Assets** og klik på **`Update-DevelopmentApps.ps1`**. Vælg **ikke** `Source code (zip)` eller `Source code (tar.gz)`.
3. Gem filen i din **Downloads**-mappe:

   ```text
   C:\Users\<dinbruger>\Downloads\Update-DevelopmentApps.ps1
   ```

**[Download scriptet direkte fra seneste release](https://github.com/hamfrasyd/Update-DevelopmentApps/releases/latest/download/Update-DevelopmentApps.ps1)**

## 2. Engangsopsætning

1. Åbn **PowerShell 7**.
2. Kopiér og kør:

   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File "$HOME\Downloads\Update-DevelopmentApps.ps1" -Setup
   ```

3. Åbn en **ny PowerShell-terminal**. Du kan nu slette filen i Downloads.

> `-Setup` installerer kun selve kommandoen `update-devapps` for din Windows-bruger. Programmerne installeres først, når du kører `update-devapps`.

## 3. Brug kommandoerne

Kommandoerne kan køres fra **enhver mappe** i PowerShell.

| Formål | Kommando |
|---|---|
| Installér manglende programmer og opdatér installerede | `update-devapps` |
| Se tilgængelige installationer og opdateringer uden at ændre programmer | `update-devapps -CheckOnly` |
| Opdatér kun allerede installerede programmer | `update-devapps -NoInstallMissing` |
| Vis detaljer til fejlfinding uden at installere/opdatere programmer | `update-devapps -CheckOnly -Diagnostic` |
| Kør uden at kontrollere GitHub for en ny scriptversion | `update-devapps -SkipSelfUpdate` |

**Normalt bruger du:**

```powershell
update-devapps
```

### Automatisk selvopdatering

Når du kører `update-devapps`, kontrollerer scriptet, om der er en nyere **GitHub Release**. Hvis der er det, hentes den nye `.ps1`-fil, kontrolleres med SHA-256 og erstatter den installerede kopi, før programopdateringerne fortsætter.

`-CheckOnly` viser, om en nyere scriptversion findes, men installerer den ikke. Hvis GitHub ikke kan kontaktes, fortsætter WinGet-delen som normalt.

## 4. Ændr hvilke programmer der håndteres

Du skal **kun ændre** `Applications.local.ps1` for at tilpasse programmerne på din egen computer.

Filen bliver ikke overskrevet, når `update-devapps` henter en ny GitHub Release.

### 1. Åbn eller opret din lokale konfigurationsfil

Åbn PowerShell, og kør:

```
notepad "$env:LOCALAPPDATA\Programs\DevAppUpdater\Applications.local.ps1"
```

Hvis filen ikke findes, skal du vælge **Ja** for at oprette den.

### 2. Fjern programmer fra listen

Hvis du ikke ønsker, at scriptet skal installere eller opdatere eksempelvis **Obsidian** eller **Postman**:

```powershell
# REMOVE - Programmer der ikke skal håndteres
$ApplicationDefinitions = @($ApplicationDefinitions | Where-Object { $_.PackageId -ne 'Obsidian.Obsidian' })
$ApplicationDefinitions = @($ApplicationDefinitions | Where-Object { $_.PackageId -ne 'Postman.Postman' })
```

Dette fjerner kun programmerne fra opdateringslisten. De bliver ikke afinstalleret fra computeren.

### 3. Tilføj programmer til listen

Hvis du ønsker at tilføje eksempelvis **7-Zip** eller **VLC**:

```powershell
# ADD - Programmer der skal tilføjes
$ApplicationDefinitions += @{ Name = '7-Zip'; PackageId = '7zip.7zip' }
$ApplicationDefinitions += @{ Name = 'VLC';   PackageId = 'VideoLAN.VLC' }
```

Programmerne installeres, hvis de mangler, og opdateres, hvis de allerede findes.

### 4. Opdatér et program uden at installere det

Hvis du eksempelvis ønsker, at **Git** kun skal opdateres, hvis det allerede er installeret, skal du bruge:

```powershell
# UPDATE ONLY - Installér ikke programmet, hvis det mangler
$ApplicationDefinitions | Where-Object { $_.PackageId -eq 'Git.Git' } | ForEach-Object { $_['InstallIfMissing'] = $false }
```

Git forbliver på listen, men installeres ikke automatisk, hvis det mangler.

### 5. Gem dine ændringer

1. Tryk **Ctrl + S** i Notepad.
2. Luk Notepad.
3. Kør følgende for at se resultatet:

```
update-devapps -CheckOnly
```

Du behøver **ikke køre** `**-Setup**` **igen**.

---

### Eksempel på en komplet Applications.local.ps1

Du kan kombinere alle ændringer i den samme fil:

```powershell
# REMOVE - Programmer der ikke skal håndteres
$ApplicationDefinitions = @($ApplicationDefinitions | Where-Object { $_.PackageId -ne 'Obsidian.Obsidian' })
$ApplicationDefinitions = @($ApplicationDefinitions | Where-Object { $_.PackageId -ne 'Postman.Postman' })

# ADD - Programmer der skal tilføjes
$ApplicationDefinitions += @{ Name = '7-Zip'; PackageId = '7zip.7zip' }
$ApplicationDefinitions += @{ Name = 'VLC';   PackageId = 'VideoLAN.VLC' }

# UPDATE ONLY - Installér ikke programmet, hvis det mangler
$ApplicationDefinitions | Where-Object { $_.PackageId -eq 'Git.Git' } | ForEach-Object { $_['InstallIfMissing'] = $false }
```

**Find WinGet-ID for et nyt program:**

```powershell
winget search "Programnavn"
```

**Husk:** Slet eller udkommentér en linje med `#`, hvis du ikke længere ønsker den pågældende ændring.

Ændringer i `Applications.local.ps1` gælder kun din computer. Standardlisten i GitHub-releasen forbliver uændret.
## Programmer på standardlisten

| | | |
|---|---|---|
| Obsidian | Notepad++ | Postman |
| Wireshark | Visual Studio 2026 Enterprise | VS Code |
| Cursor | Docker Desktop | Ollama |
| SSMS 22 | MySQL Workbench | Neo4j Desktop |
| MongoDB Compass | MongoDB Shell | DataGrip |
| Git | Python 3.15 | Java JDK 25 LTS |
| .NET 10 SDK | .NET 11 SDK | PowerShell |

