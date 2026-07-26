<#
.SYNOPSIS
  Build a versioned, packaged Windows (WinUI 3) artifact for the release
  (R8 / tasks 13.1 + 13.3). Runs on the `windows-winui` CI runner (WinUI 3
  cannot build on the macOS verification host).

.DESCRIPTION
  Version is STAMPED at build time via MSBuild properties (no csproj edit):
    -p:Version -p:FileVersion -p:AssemblyVersion -p:InformationalVersion
  so the produced product version equals the git-tag version (single source of
  truth: scripts/version.sh, passed in as -Version by the workflow).

  Signing is CREDENTIAL-GATED and honest (task 13.3):
    * When WINDOWS_CERTIFICATE_PFX (+ WINDOWS_CERTIFICATE_PASSWORD) is present
      the launcher .exe (and the app's managed .dll) are Authenticode-signed
      with signtool (SHA-256, RFC-3161 timestamp) and the signature is VERIFIED
      (`signtool verify /pa`). signtool is DISCOVERED from the Windows SDK
      (it is not on PATH by default on the runner) rather than assumed on PATH.
    * When the credential is ABSENT the package is built UNSIGNED and labelled
      exactly "UNSIGNED - signing credential WINDOWS_CERTIFICATE_PFX absent" in
      the manifest sidecar, and the required credential names are reported.
  Nothing here fakes a signature or commits a key. The .zip container itself is
  not Authenticode-signable; its integrity is covered by the SHA-256 recorded
  in the sidecar + the aggregate SHA256SUMS.txt (scripts/release/checksums.sh).

.PARAMETER Version
  Marketing version (e.g. 1.0.0) from scripts/version.sh.

.PARAMETER DistDir
  Output directory for the packaged artifact + sidecar (default: dist).

.EXAMPLE
  pwsh scripts/windows/package-windows.ps1 -Version 1.0.0
#>
param(
  [Parameter(Mandatory = $true)][string]$Version,
  [string]$DistDir = "dist"
)
$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
$proj = Join-Path $repo "windows\ColimaDesktop.Windows.csproj"
$dist = if ([System.IO.Path]::IsPathRooted($DistDir)) { $DistDir } else { Join-Path $repo $DistDir }
New-Item -ItemType Directory -Force -Path $dist | Out-Null

# CFBundleVersion analogue: a 4-part FileVersion (Windows requires numeric parts).
$fileVersion = if ($Version -match '^\d+\.\d+\.\d+$') { "$Version.0" } else { "$Version" }

# ── Locate signtool.exe (NOT on PATH by default — it ships in the Windows SDK) ──
function Resolve-SignTool {
  # 1. Already on PATH?
  $cmd = Get-Command signtool.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  # 2. vswhere → VS/SDK install roots.
  $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
  # 3. Windows Kits 10 SDK bin (newest version, x64 preferred).
  $roots = @()
  if (${env:ProgramFiles(x86)}) { $roots += (Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\bin") }
  if ($env:ProgramFiles) { $roots += (Join-Path $env:ProgramFiles "Windows Kits\10\bin") }
  $arch = if ($env:PROCESSOR_ARCHITECTURE -eq "ARM64") { "arm64" } else { "x64" }
  $candidates = @()
  foreach ($root in $roots) {
    if (Test-Path $root) {
      # Versioned SDK dirs like 10.0.22621.0\<arch>\signtool.exe (newest first).
      Get-ChildItem $root -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | ForEach-Object {
          $candidates += (Join-Path $_.FullName "$arch\signtool.exe")
          $candidates += (Join-Path $_.FullName "x64\signtool.exe")
        }
      $candidates += (Join-Path $root "$arch\signtool.exe")
      $candidates += (Join-Path $root "x64\signtool.exe")
    }
  }
  # 4. App Certification Kit fallback.
  if (${env:ProgramFiles(x86)}) {
    $candidates += (Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\App Certification Kit\signtool.exe")
  }
  foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
  return $null
}

Write-Host "==> dotnet publish ColimaDesktop.Windows v$Version (win-x64)"
$publishDir = Join-Path $repo "windows\bin\x64\Release\publish"
dotnet publish $proj -c Release -r win-x64 --self-contained true `
  -p:Platform=x64 -p:PlatformTarget=x64 `
  -p:Version=$Version -p:FileVersion=$fileVersion -p:AssemblyVersion=$fileVersion `
  -p:InformationalVersion="$Version" `
  -p:PublishDir="$publishDir\"
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed ($LASTEXITCODE)" }

# ── Credential-gated Authenticode signing (+ discovery + verification) ──
$signed = $false
$signingStatus = "UNSIGNED - signing credential WINDOWS_CERTIFICATE_PFX absent"
$reqCreds = @("WINDOWS_CERTIFICATE_PFX", "WINDOWS_CERTIFICATE_PASSWORD")
$pfxB64 = $env:WINDOWS_CERTIFICATE_PFX
if ($pfxB64) {
  $signtool = Resolve-SignTool
  if (-not $signtool) {
    throw "WINDOWS_CERTIFICATE_PFX is set but signtool.exe was not found (install the Windows SDK on the runner)."
  }
  Write-Host "==> Authenticode signing with $signtool (WINDOWS_CERTIFICATE_PFX present)"
  $pfxPath = Join-Path $env:TEMP "cd-win-cert.pfx"
  [IO.File]::WriteAllBytes($pfxPath, [Convert]::FromBase64String($pfxB64))
  $ts = if ($env:WINDOWS_TIMESTAMP_URL) { $env:WINDOWS_TIMESTAMP_URL } else { "http://timestamp.digicert.com" }
  # Sign the launcher exe and (when present) the app's own managed dll — the
  # trust anchors SmartScreen evaluates. Runtime dependency dlls are covered by
  # the container checksum, not individually Authenticode-signed.
  $toSign = @()
  $exe = Join-Path $publishDir "ColimaDesktop.Windows.exe"
  if (Test-Path $exe) { $toSign += $exe }
  $appDll = Join-Path $publishDir "ColimaDesktop.Windows.dll"
  if (Test-Path $appDll) { $toSign += $appDll }
  if ($toSign.Count -eq 0) { throw "no signable artifact found under $publishDir" }
  foreach ($f in $toSign) {
    & $signtool sign /f $pfxPath /p $env:WINDOWS_CERTIFICATE_PASSWORD /fd SHA256 /tr $ts /td SHA256 $f
    if ($LASTEXITCODE -ne 0) { throw "signtool sign failed for $f ($LASTEXITCODE)" }
  }
  # Verify every signed file (proves the signature is valid, not just applied).
  foreach ($f in $toSign) {
    & $signtool verify /pa /v $f
    if ($LASTEXITCODE -ne 0) { throw "signtool verify failed for $f ($LASTEXITCODE)" }
  }
  Remove-Item $pfxPath -Force
  $signed = $true
  $signingStatus = "SIGNED (Authenticode SHA256, timestamped, verified)"
  $reqCreds = @()
} else {
  Write-Host "==> UNSIGNED build - signing credential WINDOWS_CERTIFICATE_PFX absent (ready to sign when set)"
}

# ── Package the publish folder into a versioned zip ──
$pkgName = "ColimaDesktop-$Version-windows-x64.zip"
$pkgPath = Join-Path $dist $pkgName
if (Test-Path $pkgPath) { Remove-Item $pkgPath -Force }
Compress-Archive -Path (Join-Path $publishDir "*") -DestinationPath $pkgPath
Write-Host "==> packaged $pkgName"

# ── SHA-256 (recorded in the sidecar; the canonical list is SHA256SUMS.txt) ──
$sha256 = (Get-FileHash -Algorithm SHA256 -Path $pkgPath).Hash.ToLower()
Write-Host "==> sha256 $sha256  $pkgName"

# ── Manifest sidecar consumed by scripts/release/checksums.sh ──
$meta = [ordered]@{
  component            = "windows"
  os                   = "windows"
  arch                 = "x64"
  version              = $Version
  signed               = $signed
  signing_status       = $signingStatus
  required_credentials = $reqCreds
  sha256               = $sha256
}
$meta | ConvertTo-Json -Depth 5 | Set-Content -Path "$pkgPath.meta.json" -Encoding utf8
Write-Host "==> $signingStatus"
