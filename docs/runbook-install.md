# Návod — Instalace a aktualizace (koncový uživatel)

## Instalace

### ⭐ Doporučeno — hromadný instalátor

Nejjednodušší cesta pro **novou stanici**: otevři **<https://neo-hef.github.io/fenix-releases/>** a hned nahoře klikni na **Instalovat hromadný instalátor** (nebo **Stáhnout .appinstaller**, pokud tlačítko *Instalovat* nereaguje — viz *povolení protokolu* níže).

Hromadný instalátor je jedna aplikace, která:

- sama najde **dostupné moduly** podle zvolené **verze Fenixu** a **kanálu**,
- umožní nainstalovat **jeden**, **vybrané** nebo **všechny moduly najednou**,
- nainstalované moduly si pak dál drží **vlastní automatickou aktualizaci** (jako při ruční instalaci).

Samotný instalátor se drží aktualizovaný přes feed **`Installer-latest`** (`https://github.com/NEO-HEF/fenix-releases/releases/download/Installer-latest/Installer.appinstaller`), takže máš vždy nejnovější verzi.

Ruční instalace jednotlivých modulů níže (`.appinstaller` per modul, PowerShell) zůstává jako **pokročilá / záložní** varianta.

### Nejjednodušší (ruční) — instalační stránka

Otevři **<https://neo-hef.github.io/fenix-releases/>**, vyber **verzi Fenixu** (záložka, např. *Fenix 10.01*), pak **kanál** + modul a klikni **Instalovat**.
Stránka nabízí i fallback (stáhnout `.appinstaller` + dvojklik) a PowerShell příkaz.

### Varianta A — PowerShell (spolehlivá)

```powershell
Add-AppxPackage -AppInstallerFile "https://github.com/NEO-HEF/fenix-releases/releases/download/RZP-10.1-prod/RZP.appinstaller"
```

URL nese **verzi Fenixu i kanál**: `RZP-<verze>-<kanál>`. Pro pilotní/testovací kanál nahraď `prod` za `beta`/`alpha`; pro jinou verzi Fenixu nahraď `10.1` za `10.11`.

### Varianta B — z prohlížeče

Otevři URL v prohlížeči:
```
https://github.com/NEO-HEF/fenix-releases/releases/download/RZP-10.1-prod/RZP.appinstaller
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

Kanály patří **vždy do jedné verze Fenixu** (10.01, 10.11, …). Přepnutí kanálu v rámci téže verze = reinstalace z jiné `.appinstaller` URL:
```powershell
Get-AppxPackage Asseco.Fenix.RZP.v10-1 | Remove-AppxPackage
Add-AppxPackage -AppInstallerFile "https://github.com/NEO-HEF/fenix-releases/releases/download/RZP-10.1-beta/RZP.appinstaller"
```

> **Přechod mezi verzemi Fenixu** (10.01 → 10.11) **není automatický** — různé verze mají odlišnou identitu (`.v10-1` vs `.v10-11`), takže se aplikace sama neupgraduje. Vyžaduje **migraci databázového schématu a reinstalaci všech modulů** podle pokynů dodavatele.

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
