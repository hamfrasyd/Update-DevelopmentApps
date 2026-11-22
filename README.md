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

**Brug en separat lokal fil**, så dine personlige ændringer ikke overskrives af næste GitHub Release.

1. Åbn eller opret den lokale fil:

   ```powershell
   notepad "$env:LOCALAPPDATA\Programs\DevAppUpdater\Applications.local.ps1"
   ```

2. Indsæt for eksempel dette for at **fjerne Obsidian** fra din lokale liste:

   ```powershell
   $ApplicationDefinitions = @(
       $ApplicationDefinitions | Where-Object {
           $_.PackageId -ne 'Obsidian.Obsidian'
       }
   )
   ```

3. Hvis du også vil **tilføje 7-Zip**, indsæt dette nedenunder:

   ```powershell
   $ApplicationDefinitions += @{
       Name = '7-Zip'
       PackageId = '7zip.7zip'
   }
   ```

4. Gem med **Ctrl + S**. Ændringerne bruges næste gang, du kører `update-devapps`. Du behøver ikke køre `-Setup` igen.

**Find det korrekte WinGet-ID:**

```powershell
winget search "Programnavn"
```

**Opdatér kun et program, hvis det allerede er installeret:**

```powershell
@{ Name = 'Git'; PackageId = 'Git.Git'; InstallIfMissing = $false }
```

Denne linje er et eksempel på en post i ` $ApplicationDefinitions `. Hvis du ønsker at ændre **standardlisten for alle brugere**, skal du ændre scriptet på `dev`, oprette en pull request til release-branchen og udgive en ny release.

> **Vigtigt:** Redigér normalt ikke den installerede `Update-DevelopmentApps.ps1` direkte. Selvopdatering erstatter filen, så lokale ændringer dér går tabt.

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

> Listen omfatter **administrationsprogrammer**, ikke selve SQL Server-, MySQL-, MongoDB- eller Neo4j-databaseserverne. DataGrip overlades til JetBrains Toolbox, hvis den er installeret.
