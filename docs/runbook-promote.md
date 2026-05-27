# Runbook — Promote verze mezi kanály

Promote = posun verze modulu z nižšího kanálu do vyššího (alpha → beta → prod), nebo nasazení nové verze do alpha.

## Předpoklad

Verze, kterou promotuješ, MUSÍ existovat jako **immutable version tag** `<Module>-v<version>` s podepsaným MSIX. Ten vzniká při build+sign procesu (s `-CreateVersionTag`). Ověř:

```
gh release view RZP-v10.1.1.0 --repo NEO-HEF/fenix-releases
```

## Postup (PR-based, doporučeno)

1. **Edit `release-manifest.json`** — nastav `version` v cílovém kanálu:

   ```jsonc
   "RZP": {
     "channels": {
       "alpha": { "version": "10.1.2.0" },
       "beta":  { "version": "10.1.1.0" },   // ← promote: alpha verze, co byla otestovaná
       "prod":  {}
     }
   }
   ```

2. **Otevři PR** proti `main`. (CI ověří manifest proti schématu.)

3. **Merge.** GitHub Actions (`promote.yml`) se spustí automaticky:
   - stáhne `RZP.msix` z `RZP-v10.1.1.0`
   - vygeneruje `RZP.appinstaller` s beta URL
   - nahraje oba na `RZP-beta` channel tag (`--clobber`)

4. **Ověř:**
   ```
   curl -sL https://github.com/NEO-HEF/fenix-releases/releases/download/RZP-beta/RZP.appinstaller
   ```
   Verze v XML musí odpovídat manifestu.

## Manuální promote (bez PR, nouzově)

```powershell
gh repo clone NEO-HEF/fenix-releases
cd fenix-releases
# edit release-manifest.json
./scripts/Promote-FromManifest.ps1 -Repo NEO-HEF/fenix-releases -Module RZP -Channel beta
```

(Lokálně vyžaduje `gh auth login`.)

## Co se stane u klienta

Klient nainstalovaný z daného kanálu při příštím spuštění aplikace (OnLaunch polling) detekuje vyšší verzi a auto-updatuje. Žádná akce uživatele.

## Pozn.

- **Nová verze do alpha** = stejný postup, jen edituješ `channels.alpha.version`. Vyžaduje, aby version tag s tou verzí už existoval (z build+sign).
- Promote **nepodepisuje** — pracuje s už podepsaným MSIX z version tagu. Proto běží i v GitHub cloudu bez Asseco LAN.
