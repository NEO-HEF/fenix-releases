#requires -Version 7.0
<#
.SYNOPSIS
    Publikuje channel tagy podle release-manifest.json z immutable version tagů.

.DESCRIPTION
    Manifest-driven promote. Pro každý modul × kanál s vyplněnou 'version':
      1. Stáhne <Module>.msix z immutable version tagu <Module>-v<version>.
      2. Vygeneruje <Module>.appinstaller (z manifest metadat + channel URL).
      3. Vytvoří/aktualizuje channel release <Module>-<channel> a nahraje assety
         (--clobber) → download URL stabilní napříč releasy.

    NEPODEPISUJE nic — MSIX je už podepsaný ve version tagu (vznikl při build+sign
    na Asseco devcert). Proto tento script běží i na GitHub-hosted runneru bez
    přístupu k Asseco LAN.

    Spouští se z .github/workflows/promote.yml (push na release-manifest.json),
    nebo lokálně pro test/manuální promote.

.PARAMETER Repo
    owner/repo (default 'NEO-HEF/fenix-releases').

.PARAMETER ManifestPath
    Cesta k release-manifest.json (default './release-manifest.json').

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
    [string]$Module,
    [string]$Channel,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $ManifestPath)) { throw "Manifest nenalezen: $ManifestPath" }
$manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json

# gh preflight
if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw "gh CLI nenalezen." }

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

$promoted = @()

foreach ($modName in $manifest.modules.PSObject.Properties.Name) {
    if ($Module -and $modName -ne $Module) { continue }
    $mod = $manifest.modules.$modName
    $idName = $mod.packageIdentityName
    $publisher = $mod.publisher
    $arch = if ($mod.architecture) { $mod.architecture } else { 'x64' }

    foreach ($chName in $mod.channels.PSObject.Properties.Name) {
        if ($Channel -and $chName -ne $Channel) { continue }
        $entry = $mod.channels.$chName
        $version = $entry.version
        if (-not $version) {
            Write-Host "[skip] $modName/$chName — prázdný kanál (žádná version)" -ForegroundColor DarkGray
            continue
        }

        $channelTag = "$modName-$chName"
        $versionTag = "$modName-v$version"
        $downloadBase = "https://github.com/$Repo/releases/download/$channelTag"
        $appInstallerUrl = "$downloadBase/$modName.appinstaller"
        $msixUrl = "$downloadBase/$modName.msix"

        Write-Host "=== Promote $modName $version → $chName ===" -ForegroundColor Cyan
        Write-Host "  version tag: $versionTag  →  channel tag: $channelTag"

        if ($WhatIf) {
            Write-Host "  [WhatIf] download $modName.msix z $versionTag, regen appinstaller, upload na $channelTag" -ForegroundColor Yellow
            continue
        }

        $stageDir = New-Item -ItemType Directory -Force -Path (Join-Path ([System.IO.Path]::GetTempPath()) "promote-$(New-Guid)")
        try {
            # 1. Stáhni MSIX z version tagu
            & gh release download $versionTag --repo $Repo --pattern "$modName.msix" --dir $stageDir --clobber
            if ($LASTEXITCODE -ne 0) {
                throw "Nelze stáhnout $modName.msix z $versionTag. Existuje version tag s podepsaným MSIX? (vytváří Build+Publish s -CreateVersionTag)"
            }
            $stageMsix = Join-Path $stageDir "$modName.msix"

            # 2. Vygeneruj appinstaller
            $xml = New-AppInstallerXml -IdName $idName -Publisher $publisher -Arch $arch `
                -Version $version -SelfUrl $appInstallerUrl -MsixUrl $msixUrl
            $stageAppInstaller = Join-Path $stageDir "$modName.appinstaller"
            Set-Content -LiteralPath $stageAppInstaller -Value $xml -Encoding UTF8 -NoNewline

            # 3. Channel release create/update
            $isPrerelease = ($chName -ne 'prod')
            & gh release view $channelTag --repo $Repo 2>&1 | Out-Null
            if ($LASTEXITCODE -ne 0) {
                $createArgs = @('release', 'create', $channelTag, '--repo', $Repo,
                                '--title', "$modName ($chName)",
                                '--notes', "Channel feed $modName / $chName. Aktuální verze: $version.")
                if ($isPrerelease) { $createArgs += '--prerelease' }
                & gh @createArgs
                if ($LASTEXITCODE -ne 0) { throw "gh release create $channelTag selhal" }
            } else {
                & gh release edit $channelTag --repo $Repo --notes "Channel feed $modName / $chName. Aktuální verze: $version." 2>&1 | Out-Null
            }

            & gh release upload $channelTag $stageMsix $stageAppInstaller --repo $Repo --clobber
            if ($LASTEXITCODE -ne 0) { throw "gh release upload na $channelTag selhal" }

            Write-Host "  [OK] $appInstallerUrl" -ForegroundColor Green
            $promoted += [PSCustomObject]@{ Module = $modName; Channel = $chName; Version = $version; Url = $appInstallerUrl }
        } finally {
            Remove-Item -Recurse -Force $stageDir -ErrorAction SilentlyContinue
        }
    }
}

Write-Host ""
Write-Host "=== Promote summary ===" -ForegroundColor Cyan
if ($promoted.Count -eq 0) {
    Write-Host "  (nic nepublikováno)"
} else {
    $promoted | Format-Table Module, Channel, Version, Url -AutoSize
}
