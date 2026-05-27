# Runbook — Rollback

Rollback = vrácení kanálu na předchozí (funkční) verzi po zjištění regrese.

## Princip

Immutable version tagy (`<Module>-v<version>`) drží historické podepsané MSIX. Rollback = nastavit v manifestu `version` zpět na starší a nechat promote workflow přepublikovat channel tag z toho staršího version tagu.

## Postup

1. **Zjisti, na kterou verzi vrátit** — seznam dostupných version tagů:
   ```
   gh release list --repo NEO-HEF/fenix-releases | Select-String 'RZP-v'
   ```

2. **Edit `release-manifest.json`** — sniž `version` v postiženém kanálu:
   ```jsonc
   "prod": { "version": "10.1.1.0" }   // ← bylo 10.1.2.0, vracíme na .1.0
   ```

3. **PR + merge** (nebo manuálně `Promote-FromManifest.ps1`).

4. Promote workflow přepíše `RZP-prod` assety verzí 10.1.1.0.

## Co se stane u klienta

⚠️ **MSIX/AppInstaller standardně NEumí downgrade.** AppInstaller updatuje jen na **vyšší** verzi. Pokud klient už má 10.1.2.0 nainstalovanou, snížení feedu na 10.1.1.0 ho samo nevrátí.

Možnosti:
- **Forward-fix (preferováno):** místo rollbacku vydej **vyšší** verzi s opravou (10.1.3.0). Klienti se na ni updatují normálně.
- **Hard rollback (nouzově):** klient musí ručně odinstalovat + reinstalovat:
  ```powershell
  Get-AppxPackage Asseco.Fenix.RZP | Remove-AppxPackage
  Add-AppxPackage -AppInstallerFile https://github.com/NEO-HEF/fenix-releases/releases/download/RZP-prod/RZP.appinstaller
  ```

## Doporučení

Pro prod incidenty preferuj **forward-fix** (nová vyšší verze s opravou) před hard rollbackem — auto-update funguje jen dopředu. Hard rollback řeš jen když je nová verze nebezpečná a musí okamžitě zmizet.
