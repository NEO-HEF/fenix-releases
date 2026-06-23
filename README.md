# fenix-releases

MSIX distribuční feed pro migrované moduly **NEO_HEF** (Fenix .NET). Distribuce přes **GitHub Releases** + Windows **AppInstaller** auto-update.

> **📦 Instalační stránka pro uživatele: <https://neo-hef.github.io/fenix-releases/>**

> Tohle repo je **čistě distribuční feed** — žádný zdrojový kód NEO_HEF. Zdroj je v Azure DevOps. Sem patří jen `release-manifest.json`, promote workflow, runbooky a release assety (`.msix` + `.appinstaller`, visí na releasech, ne v gitu).

## Jak to funguje

```
Build + Sign (Asseco devcert, AzDevOps self-hosted agent / lokálně)
   │  publikuje podepsaný MSIX jako immutable version tag:
   ▼          <Module>-v<version>   (např. RZP-v10.1.1.0)
┌─────────────────────────────────────────────────────────┐
│ release-manifest.json   (source of truth: co je v kanálu)│
│   version-first: fenixVersions.<verze>.modules.<m>.chan. │
│   edit + PR + merge na main                              │
└─────────────────────────────────────────────────────────┘
   │  .github/workflows/promote.yml (GitHub Actions, BEZ signing)
   ▼  kopíruje MSIX z version tagu na channel tag + regen .appinstaller
mutable channel tagy:   <Module>-<FenixVer>-alpha / -beta / -prod   (RZP-10.1-alpha)
   │  stabilní URL (assety přepisované --clobber)
   ▼
Klient:  Add-AppxPackage -AppInstallerFile https://github.com/NEO-HEF/fenix-releases/releases/download/<Module>-<FenixVer>-<channel>/<Module>.appinstaller
         → auto-update jen UVNITŘ verze Fenixu (jiná verze = jiná identita, žádný cross-version upgrade)
```

> **Multi-version (Q6):** nejvyšší dimenzí je **verze Fenixu** (10.1, 10.11, …) — souběžně podporované linie, každá s vlastní MSIX identitou (`Asseco.Fenix.RZP.v10-1` / `.v10-11`) a vlastními channel tagy. Přechod klienta mezi verzemi **není automatický** (vyžaduje migraci DB schématu + reinstalaci). Instalační stránka generuje verzní záložky přímo z klíčů `fenixVersions` v manifestu.

## Kanály

| Kanál | Účel | Tag | Prerelease flag |
|-------|------|-----|-----------------|
| alpha | testování | `<Module>-<FenixVer>-alpha` | ano |
| beta  | pilot | `<Module>-<FenixVer>-beta` | ano |
| prod  | ostrý provoz | `<Module>-<FenixVer>-prod` | ne |

## Stabilní install URL

```
https://github.com/NEO-HEF/fenix-releases/releases/download/RZP-10.1-alpha/RZP.appinstaller
https://github.com/NEO-HEF/fenix-releases/releases/download/RZP-10.1-beta/RZP.appinstaller
https://github.com/NEO-HEF/fenix-releases/releases/download/RZP-10.1-prod/RZP.appinstaller
```

URL je stabilní napříč buildy téže linie — promote přepisuje assety (`--clobber`), tag jméno se nemění. Verze Fenixu je součástí tagu (`RZP-10.1-…` vs `RZP-10.11-…`), takže linie mají oddělené, stabilní feedy.

## Soubory

| Soubor | Účel |
|--------|------|
| [`release-manifest.json`](./release-manifest.json) | Source of truth — který modul / verze v jakém kanálu |
| [`schema/release-manifest.schema.json`](./schema/release-manifest.schema.json) | JSON Schema (IDE + CI validace) |
| [`scripts/Promote-FromManifest.ps1`](./scripts/Promote-FromManifest.ps1) | Promote logika (běží v Actions + lokálně) |
| [`.github/workflows/promote.yml`](./.github/workflows/promote.yml) | Auto-promote při změně manifestu |
| [`docs/runbook-promote.md`](./docs/runbook-promote.md) | Jak promotovat verzi mezi kanály |
| [`docs/runbook-rollback.md`](./docs/runbook-rollback.md) | Jak vrátit starší verzi |
| [`docs/runbook-install.md`](./docs/runbook-install.md) | Návod pro koncové uživatele |

## Role: Release Manager

Promote verze = edit `release-manifest.json` → PR → merge. Workflow zbytek zařídí. Viz [runbook-promote](./docs/runbook-promote.md).
