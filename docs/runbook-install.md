# Návod — Instalace a aktualizace (koncový uživatel)

## Instalace

### Nejjednodušší — instalační stránka

Otevři **<https://neo-hef.github.io/fenix-releases/>**, vyber modul + kanál a klikni **Instalovat**.
Stránka nabízí i fallback (stáhnout `.appinstaller` + dvojklik) a PowerShell příkaz.

### Varianta A — PowerShell (spolehlivá)

```powershell
Add-AppxPackage -AppInstallerFile "https://github.com/NEO-HEF/fenix-releases/releases/download/RZP-prod/RZP.appinstaller"
```

(Pro testovací/pilotní kanál nahraď `RZP-prod` za `RZP-beta` nebo `RZP-alpha`.)

### Varianta B — z prohlížeče

Otevři URL v prohlížeči:
```
https://github.com/NEO-HEF/fenix-releases/releases/download/RZP-prod/RZP.appinstaller
```

> ⚠️ GitHub servíruje soubor jako `application/octet-stream`, takže prohlížeč ho nejspíš **stáhne** místo přímého spuštění App Installeru. Po stažení na `.appinstaller` soubor **dvojklik** → otevře se Windows App Installer → **Instalovat**.

## Aktualizace

Aktualizace probíhá **automaticky**. Při spuštění aplikace App Installer zkontroluje feed; pokud je k dispozici novější verze, stáhne ji na pozadí a aplikace naběhne aktualizovaná (může to být až při druhém spuštění). Uživatel nemusí dělat nic.

## Kanály

| Kanál | Pro koho |
|-------|----------|
| **prod** | běžní uživatelé (ostrý provoz) |
| **beta** | pilotní uživatelé |
| **alpha** | testeři |

Přepnutí kanálu = reinstalace z jiné `.appinstaller` URL:
```powershell
Get-AppxPackage Asseco.Fenix.RZP | Remove-AppxPackage
Add-AppxPackage -AppInstallerFile "https://github.com/NEO-HEF/fenix-releases/releases/download/RZP-beta/RZP.appinstaller"
```

## Požadavky

- Windows 10 2004 (build 19041) nebo novější.
- .NET 10 Desktop Runtime (pokud build není self-contained).
- Aplikace je podepsaná veřejně-trusted EV certifikátem (Asseco Solutions a.s.) — žádné „neznámý vydavatel" varování.

## Když něco nejde

| Problém | Řešení |
|---------|--------|
| „This app package's publisher certificate could not be verified" | Nahlas IT — možná problém s cert chain / starý Windows. |
| Aplikace se neaktualizuje | Zkontroluj připojení k internetu; force update přes `Add-AppxPackage -AppInstallerFile <url>`. |
| Instalace selže | Nahlas IT s ActivityId z chybové hlášky (`Get-AppPackageLog`). |
