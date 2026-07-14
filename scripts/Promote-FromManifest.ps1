#requires -Version 7.0
<#
.SYNOPSIS
    Publikuje channel tagy podle release-manifest.json z immutable version tagů.

.DESCRIPTION
    Manifest-driven promote (multi-version, per Q6). Pro každou verzi Fenixu ×
    modul × kanál:
      1. VŽDY zajistí, že systémový channel release <Module>-<FenixVer>-<channel>
         existuje (vytvoří chybějící) a nastaví mu varovný popis "NEMAZAT".
      2. Pokud má kanál v manifestu 'version': stáhne <Module>.msix z immutable
         version tagu <Module>-v<version>, vygeneruje <Module>.appinstaller a nahraje
         oba assety (--clobber) → download URL stabilní napříč releasy.
      3. Prázdný kanál (bez 'version') = jen rezervovaný placeholder release bez assetů.

    Channel release jsou SYSTÉMOVÉ — drží stabilní install URL klientů. Smazání
    rozbije instalaci/aktualizaci. Proto se kontroluje jejich existence při každém
    promote a chybějící se doplní (self-healing po ručním smazání).

    Channel tag nese verzi Fenixu (RZP-10.1-alpha, RZP-10.11-alpha) — linie 10.1 a
    10.11 jsou tak fyzicky oddělené feedy s vlastní MSIX identitou. Version tag
    <Module>-v<version> je napříč liniemi unikátní (4-part verze), proto se nemění.

    NEPODEPISUJE nic — MSIX je už podepsaný ve version tagu (vznikl při build+sign
    na Asseco devcert). Proto tento script běží i na GitHub-hosted runneru bez
    přístupu k Asseco LAN.

    Spouští se z .github/workflows/promote.yml (push na release-manifest.json),
    nebo lokálně pro test/manuální promote / opravu smazaného channel release.

.PARAMETER Repo
    owner/repo (default 'NEO-HEF/fenix-releases').

.PARAMETER ManifestPath
    Cesta k release-manifest.json (default './release-manifest.json').

.PARAMETER FenixVersion
    Volitelný filtr — jen tato verze Fenixu (např. '10.1').

.PARAMETER Module
    Volitelný filtr — jen tento modul.

.PARAMETER Channel
    Volitelný filtr — jen tento kanál.

.PARAMETER WhatIf
    Jen vypiš co by se stalo, neprováděj gh příkazy.
#>

[CmdletBinding()]
param(
    [string]$Repo = 'NEO-HEF/fenix-releases',
    [string]$ManifestPath = './release-manifest.json',
    [string]$FenixVersion,
    [string]$Module,
    [string]$Channel,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ManifestPath)) { throw "Manifest nenalezen: $ManifestPath" }
$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json

# gh preflight
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "gh CLI nenalezen." }

# Varovný banner v popisu KAŽDÉHO systémového release (channel i version tag).
# Cíl: nikdo je omylem nesmaže — drží stabilní install URL / immutable artefakty.
$SYSTEM_RELEASE_WARNING = '⚠️ POZOR — NEMAZAT — SYSTÉMOVÁ RELEASE ⚠️'

function New-AppInstallerXml {
    param($IdName, $Publisher, $Arch, $Version, $SelfUrl, $MsixUrl)
    @"
<?xml version="1.0" encoding="utf-8"?>
<AppInstaller xmlns="http://schemas.microsoft.com/appx/appinstaller/2018"
              Version="$Version"
              Uri="$SelfUrl">
  <MainPackage Name="$IdName"
               Publisher="$Publisher"
               Version="$Version"
               Uri="$MsixUrl"
               ProcessorArchitecture="$Arch" />
  <UpdateSettings>
    <OnLaunch HoursBetweenUpdateChecks="0" />
    <AutomaticBackgroundTask />
  </UpdateSettings>
</AppInstaller>
"@
}

function Get-ChannelNotes {
    param([string]$Module, [string]$FenixVer, [string]$Channel, [string]$Version)
    $verLine = if ($Version) {
        "Aktuální verze: $Version."
    } else {
        "Kanál zatím bez publikované verze (rezervovaný placeholder)."
    }
    @"
$SYSTEM_RELEASE_WARNING

Kanálový feed $Module / Fenix $FenixVer / $Channel.
$verLine

Spravováno automaticky (release-manifest.json + promote workflow). Stabilní install
URL klientů míří na tento release — SMAZÁNÍ ROZBIJE INSTALACI A AUTOMATICKÉ
AKTUALIZACE u klientů. Neměnit ručně; verze se řídí výhradně přes release-manifest.json.
"@
}

# Zajistí existenci channel release + nastaví/obnoví warning popis (idempotentní).
function Set-ChannelRelease {
    param([string]$Tag, [string]$Title, [string]$Notes, [bool]$Prerelease, [string]$Repo, [switch]$WhatIf)
    & gh release view $Tag --repo $Repo 2>&1 | Out-Null
    $exists = ($LASTEXITCODE -eq 0)
    if ($WhatIf) {
        Write-Host "  [WhatIf] $(if ($exists) {'obnovit popis'} else {'VYTVOŘIT'}) systémový release $Tag" -ForegroundColor Yellow
        return
    }
    if (-not $exists) {
        $createArgs = @('release', 'create', $Tag, '--repo', $Repo, '--title', $Title, '--notes', $Notes)
        if ($Prerelease) { $createArgs += '--prerelease' }
        & gh @createArgs
        if ($LASTEXITCODE -ne 0) { throw "gh release create $Tag selhal" }
        Write-Host "  [+] doplněn chybějící systémový release $Tag" -ForegroundColor Green
    } else {
        & gh release edit $Tag --repo $Repo --title $Title --notes $Notes 2>&1 | Out-Null
    }
}

$promoted = @()

foreach ($fenixVer in $manifest.fenixVersions.PSObject.Properties.Name) {
    if ($FenixVersion -and $fenixVer -ne $FenixVersion) { continue }
    $line = $manifest.fenixVersions.$fenixVer

    foreach ($modName in $line.modules.PSObject.Properties.Name) {
        if ($Module -and $modName -ne $Module) { continue }
        $mod = $line.modules.$modName
        $idName = $mod.packageIdentityName
        $publisher = $mod.publisher
        $arch = if ($mod.architecture) { $mod.architecture } else { 'x64' }

        foreach ($chName in $mod.channels.PSObject.Properties.Name) {
            if ($Channel -and $chName -ne $Channel) { continue }
            $entry = $mod.channels.$chName
            $version = $entry.version
            $channelTag = "$modName-$fenixVer-$chName"      # RZP-10.1-alpha
            $isPrerelease = ($chName -ne 'prod')
            $relTitle = "$modName $fenixVer ($chName)"

            # Sanity: Major.Minor verze musí sedět na klíč linie Fenixu.
            if ($version) {
                $verMajorMinor = ($version -split '\.')[0..1] -join '.'
                if ($verMajorMinor -ne $fenixVer) {
                    throw "Verze '$version' ($modName/$chName) nesedí na linii Fenixu '$fenixVer' (Major.Minor=$verMajorMinor). Oprav manifest."
                }
            }

            # 1) VŽDY zajisti existenci systémového channel release + warning popis.
            $notes = Get-ChannelNotes -Module $modName -FenixVer $fenixVer -Channel $chName -Version $version
            Set-ChannelRelease -Tag $channelTag -Title $relTitle -Notes $notes -Prerelease $isPrerelease -Repo $Repo -WhatIf:$WhatIf

            # 2) Prázdný kanál = jen rezervovaný placeholder (žádné assety).
            if (-not $version) {
                Write-Host "[ensure] $fenixVer/$modName/$chName — placeholder bez verze (žádné assety)" -ForegroundColor DarkGray
                continue
            }

            $versionTag = "$modName-v$version"              # RZP-v10.1.6.0
            $downloadBase = "https://github.com/$Repo/releases/download/$channelTag"
            $appInstallerUrl = "$downloadBase/$modName.appinstaller"
            $msixUrl = "$downloadBase/$modName.msix"

            Write-Host "=== Promote $modName $version (Fenix $fenixVer) → $chName ===" -ForegroundColor Cyan
            Write-Host "  version tag: $versionTag  →  channel tag: $channelTag"

            if ($WhatIf) {
                Write-Host "  [WhatIf] download $modName.msix z $versionTag, regen appinstaller, upload na $channelTag" -ForegroundColor Yellow
                continue
            }

            $stageDir = New-Item -ItemType Directory -Force -Path (Join-Path ([System.IO.Path]::GetTempPath()) "promote-$(New-Guid)")
            try {
                # Stáhni MSIX z version tagu
                & gh release download $versionTag --repo $Repo --pattern "$modName.msix" --dir $stageDir --clobber
                if ($LASTEXITCODE -ne 0) {
                    throw "Nelze stáhnout $modName.msix z $versionTag. Existuje version tag s podepsaným MSIX? (vytváří Publish-FenixRelease.ps1)"
                }
                $stageMsix = Join-Path $stageDir "$modName.msix"

                # Vygeneruj appinstaller
                $xml = New-AppInstallerXml -IdName $idName -Publisher $publisher -Arch $arch `
                    -Version $version -SelfUrl $appInstallerUrl -MsixUrl $msixUrl
                $stageAppInstaller = Join-Path $stageDir "$modName.appinstaller"
                Set-Content -LiteralPath $stageAppInstaller -Value $xml -Encoding UTF8 -NoNewline

                # Nahraj assety na (už zajištěný) channel release
                & gh release upload $channelTag $stageMsix $stageAppInstaller --repo $Repo --clobber
                if ($LASTEXITCODE -ne 0) { throw "gh release upload na $channelTag selhal" }

                Write-Host "  [OK] $appInstallerUrl" -ForegroundColor Green
                $promoted += [PSCustomObject]@{ FenixVersion = $fenixVer; Module = $modName; Channel = $chName; Version = $version; Url = $appInstallerUrl }
            } finally {
                Remove-Item -Recurse -Force $stageDir -ErrorAction SilentlyContinue
            }
        }
    }
}

# ---------------------------------------------------------------------
# Instalátor (Asseco.Fenix.Installer) — společný hromadný instalátor.
# Instalátor NENÍ modul žádné linie Fenixu (viz 04-installer-design.md / Q7):
# žije v top-level bloku 'installer' vedle 'fenixVersions', je version-agnostic
# a má jediný kanál 'latest'. Distribuce: channel tag Installer-latest (NE
# prerelease — je to prod-like nástroj), immutable version tag Installer-v<version>,
# stabilní jména assetů Installer.msix / Installer.appinstaller. Znovupoužívá se
# Set-ChannelRelease (self-healing + NEMAZAT) a New-AppInstallerXml (žádná nová logika).
#
# Filtry: protože je instalátor version-agnostic, spouštíme jeho promote jen když
# NENÍ nastaven filtr -FenixVersion, NEBO byl explicitně předán -Module Installer
# (aby cílený promote konkrétní verze/modulu instalátor omylem nepřepsal). Zároveň
# ctíme -Module (jiný modul než 'Installer' → přeskočit) a -Channel (jiný kanál
# než 'latest' → přeskočit).
# ---------------------------------------------------------------------
if ($manifest.installer -and
    ((-not $FenixVersion) -or ($Module -eq 'Installer')) -and
    ((-not $Module) -or ($Module -eq 'Installer')) -and
    ((-not $Channel) -or ($Channel -eq 'latest'))) {

    $inst          = $manifest.installer
    $instIdName    = $inst.packageIdentityName
    $instPublisher = $inst.publisher
    $instArch      = if ($inst.architecture) { $inst.architecture } else { 'x64' }
    $instVersion   = $inst.channels.latest.version
    $instChannelTag = 'Installer-latest'
    $instTitle      = 'Fenix Instalátor (latest)'

    # 1) VŽDY zajisti existenci systémového channel release Installer-latest + warning popis.
    $instVerLine = if ($instVersion) {
        "Aktuální verze: $instVersion."
    } else {
        "Kanál zatím bez publikované verze (rezervovaný placeholder)."
    }
    $instNotes = @"
$SYSTEM_RELEASE_WARNING

Kanálový feed společného instalátoru (Asseco.Fenix.Installer) — nástroj NAD liniemi Fenixu.
$instVerLine

Spravováno automaticky (release-manifest.json + promote workflow). Stabilní install
URL klientů míří na tento release — SMAZÁNÍ ROZBIJE INSTALACI A AUTOMATICKÉ
AKTUALIZACE u klientů. Neměnit ručně; verze se řídí výhradně přes release-manifest.json.
"@
    # Instalátor je prod-like nástroj → NE prerelease.
    Set-ChannelRelease -Tag $instChannelTag -Title $instTitle -Notes $instNotes -Prerelease $false -Repo $Repo -WhatIf:$WhatIf

    if (-not $instVersion) {
        # Prázdný kanál = jen rezervovaný placeholder (žádné assety).
        Write-Host "[ensure] Installer/latest — placeholder bez verze (žádné assety)" -ForegroundColor DarkGray
    } else {
        $instVersionTag      = "Installer-v$instVersion"     # Installer-v1.0.0.0 (immutable version tag)
        $instDownloadBase    = "https://github.com/$Repo/releases/download/$instChannelTag"
        $instAppInstallerUrl = "$instDownloadBase/Installer.appinstaller"
        $instMsixUrl         = "$instDownloadBase/Installer.msix"

        Write-Host "=== Promote Instalátor $instVersion → latest ===" -ForegroundColor Cyan
        Write-Host "  version tag: $instVersionTag  →  channel tag: $instChannelTag"

        if ($WhatIf) {
            Write-Host "  [WhatIf] download Installer.msix z $instVersionTag, regen appinstaller, upload na $instChannelTag" -ForegroundColor Yellow
        } else {
            $instStageDir = New-Item -ItemType Directory -Force -Path (Join-Path ([System.IO.Path]::GetTempPath()) "promote-$(New-Guid)")
            try {
                # Stáhni MSIX z immutable version tagu
                & gh release download $instVersionTag --repo $Repo --pattern "Installer.msix" --dir $instStageDir --clobber
                if ($LASTEXITCODE -ne 0) {
                    throw "Nelze stáhnout Installer.msix z $instVersionTag. Existuje version tag s podepsaným MSIX? (vytváří Publish-FenixRelease.ps1)"
                }
                $instStageMsix = Join-Path $instStageDir 'Installer.msix'

                # Vygeneruj appinstaller (reuse New-AppInstallerXml — SelfUrl/MsixUrl míří na Installer-latest)
                $instXml = New-AppInstallerXml -IdName $instIdName -Publisher $instPublisher -Arch $instArch `
                    -Version $instVersion -SelfUrl $instAppInstallerUrl -MsixUrl $instMsixUrl
                $instStageAppInstaller = Join-Path $instStageDir 'Installer.appinstaller'
                Set-Content -LiteralPath $instStageAppInstaller -Value $instXml -Encoding UTF8 -NoNewline

                # Nahraj oba assety na (už zajištěný) channel release Installer-latest
                & gh release upload $instChannelTag $instStageMsix $instStageAppInstaller --repo $Repo --clobber
                if ($LASTEXITCODE -ne 0) { throw "gh release upload na $instChannelTag selhal" }

                Write-Host "  [OK] $instAppInstallerUrl" -ForegroundColor Green
                # Syntetický FenixVersion label 'installer' — instalátor nepatří do žádné linie.
                $promoted += [PSCustomObject]@{ FenixVersion = 'installer'; Module = 'Installer'; Channel = 'latest'; Version = $instVersion; Url = $instAppInstallerUrl }
            } finally {
                Remove-Item -Recurse -Force $instStageDir -ErrorAction SilentlyContinue
            }
        }
    }
}

Write-Host ""
Write-Host "=== Promote summary ===" -ForegroundColor Cyan
if ($promoted.Count -eq 0) {
    Write-Host "  (žádné assety nepublikovány — kanály jsou jen zajištěné/prázdné)"
} else {
    $promoted | Format-Table FenixVersion, Module, Channel, Version, Url -AutoSize
}
