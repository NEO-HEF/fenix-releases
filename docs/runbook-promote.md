# Runbook — Promote verze mezi kanály

Promote = posun verze modulu z nižšího kanálu do vyššího (alpha → beta → prod), nebo nasazení nové verze do alpha.

## Předpoklad

Verze, kterou promotuješ, MUSÍ existovat jako **immutable version tag** `<Module>-v<version>` s podepsaným MSIX. Ten vzniká při build+sign procesu (s `-CreateVersionTag`). Ověř:

```
gh release view RZP-v10.1.1.0 --repo NEO-HEF/fenix-releases
```

## Postup (PR-based, doporučeno)

1. **Edit `release-manifest.json`** — nastav `version` v cílovém kanálu **uvnitř příslušné verze Fenixu** (`fenixVersions.<verze>.modules.<modul>.channels`):

   ```jsonc
   "fenixVersions": {
     "10.1": {
       "status": "active",
       "modules": {
         "RZP": {
           "packageIdentityName": "Asseco.Fenix.RZP.v10-1",
           "channels": {
             "alpha": { "version": "10.1.2.0" },
             "beta":  { "version": "10.1.1.0" },   // ← promote: alpha verze, co byla otestovaná
             "prod":  {}
           }
         }
       }
     }
   }
   ```

2. **Otevři PR** proti `main`. (CI ověří manifest proti schématu.)

3. **Merge.** GitHub Actions (`promote.yml`) se spustí automaticky:
   - stáhne `RZP.msix` z `RZP-v10.1.1.0` (version tag je napříč liniemi unikátní)
   - vygeneruje `RZP.appinstaller` s beta URL linie 10.1
   - nahraje oba na `RZP-10.1-beta` channel tag (`--clobber`)

4. **Ověř:**
   ```
   curl -sL https://github.com/NEO-HEF/fenix-releases/releases/download/RZP-10.1-beta/RZP.appinstaller
   ```
   Verze v XML musí odpovídat manifestu; `MainPackage Name` musí být `Asseco.Fenix.RZP.v10-1`.

## Manuální promote (bez PR, nouzově)

```powershell
gh repo clone NEO-HEF/fenix-releases
cd fenix-releases
# edit release-manifest.json
./scripts/Promote-FromManifest.ps1 -Repo NEO-HEF/fenix-releases -FenixVersion 10.1 -Module RZP -Channel beta
```

(Lokálně vyžaduje `gh auth login`. Filtry `-FenixVersion` / `-Module` / `-Channel` jsou volitelné — bez nich promotuje vše z manifestu.)

## Co se stane u klienta

Klient nainstalovaný z daného kanálu při příštím spuštění aplikace (OnLaunch polling) detekuje vyšší verzi a auto-updatuje. Žádná akce uživatele.

## Pozn.

- **Nová verze do alpha** = stejný postup, jen edituješ `channels.alpha.version`. Vyžaduje, aby version tag s tou verzí už existoval (z build+sign).
- Promote **nepodepisuje** — pracuje s už podepsaným MSIX z version tagu. Proto běží i v GitHub cloudu bez Asseco LAN.
- **Multi-version (Q6):** každá verze Fenixu je samostatná oblast s vlastní MSIX identitou (`Asseco.Fenix.RZP.v10-1` vs `.v10-11`) a vlastními channel tagy (`RZP-10.1-<kanál>` vs `RZP-10.11-<kanál>`). Klient se mezi verzemi **neupgraduje automaticky** (jiná identita). `Major.Minor` verze v `channels.*.version` musí sedět na klíč nadřazené linie — promote to kontroluje.
- **Identita uvnitř MSIX musí odpovídat `packageIdentityName`** v manifestu. První publikace linie pod novou identitou (`.v10-1`) proto vyžaduje MSIX zbuilděný z aktuálního `Package.appxmanifest` — starší version tagy se starou identitou nelze promotovat pod novou identitu.
