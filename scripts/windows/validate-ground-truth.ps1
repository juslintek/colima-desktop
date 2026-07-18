#!/usr/bin/env pwsh
# validate-ground-truth.ps1
# Validates exploration/windows/ground-truth.json for:
#   - Valid JSON (parseable)
#   - Required top-level keys present
#   - total_elements > 0  (no invented elements guard)
#   - ALL 13 surfaces have element_count > 0  (every nav surface must be captured)
#   - surfaces array non-empty
#   - capture_errors is empty  (zero errors required)
#
# Usage:  pwsh validate-ground-truth.ps1 <path-to-json>
# Exit:   0 = valid,  1 = invalid

param(
    [Parameter(Mandatory=$true)]
    [string]$JsonPath
)

$ErrorActionPreference = 'Stop'

Write-Host "[validate] Checking: $JsonPath"

if (-not (Test-Path $JsonPath)) {
    Write-Error "[validate] FAIL: File not found: $JsonPath"
    exit 1
}

# Parse JSON
try {
    $content = Get-Content $JsonPath -Raw
    $doc = $content | ConvertFrom-Json -Depth 50
} catch {
    Write-Error "[validate] FAIL: JSON parse error: $_"
    exit 1
}
Write-Host "[validate] JSON parsed OK"

# Required top-level fields
$required = @('platform','timestamp','total_elements','surfaces','surfaces_explored')
foreach ($key in $required) {
    if ($null -eq $doc.$key) {
        Write-Error "[validate] FAIL: Missing required key '$key'"
        exit 1
    }
}
Write-Host "[validate] Required keys present"

# Platform must be "Windows"
if ($doc.platform -ne 'Windows') {
    Write-Error "[validate] FAIL: platform='$($doc.platform)' expected 'Windows'"
    exit 1
}

# total_elements must be > 0
$total = [int]$doc.total_elements
Write-Host "[validate] total_elements = $total"
if ($total -le 0) {
    Write-Error "[validate] FAIL: total_elements=$total (must be > 0 — fabricated data guard)"
    exit 1
}

# surfaces must be a non-empty array
$surfaces = $doc.surfaces
if ($null -eq $surfaces -or $surfaces.Count -eq 0) {
    Write-Error "[validate] FAIL: surfaces array is empty"
    exit 1
}
Write-Host "[validate] surfaces count = $($surfaces.Count)"

# All 13 surfaces must have element_count > 0
$emptySurfaces = @($surfaces | Where-Object { [int]$_.element_count -eq 0 })
if ($emptySurfaces.Count -gt 0) {
    Write-Host "[validate] FAIL: $($emptySurfaces.Count) surface(s) have zero elements:"
    foreach ($s in $emptySurfaces) {
        $errMsgs = if ($s.errors) { $s.errors -join "; " } else { "(no error message)" }
        Write-Host "  - $($s.surface_label): $errMsgs"
    }
    Write-Error "[validate] FAIL: All 13 surfaces must have element_count > 0"
    exit 1
}
Write-Host "[validate] All $($surfaces.Count) surfaces have nonzero elements — OK"

# Zero capture errors required
$captureErrors = $doc.capture_errors
if ($captureErrors -and $captureErrors.Count -gt 0) {
    Write-Host "[validate] FAIL: $($captureErrors.Count) capture error(s):"
    foreach ($e in $captureErrors) { Write-Host "  - $e" }
    Write-Error "[validate] FAIL: capture_errors must be empty"
    exit 1
}
Write-Host "[validate] capture_errors = 0 — OK"

# Report per-surface summary
foreach ($s in $surfaces) {
    $errCount = if ($s.errors) { $s.errors.Count } else { 0 }
    $flag = if ([int]$s.element_count -gt 0) { "OK" } else { "EMPTY" }
    Write-Host "  [$flag] $($s.surface_label): $($s.element_count) elements, $errCount errors"
}

Write-Host "[validate] PASS: ground-truth.json is valid ($total elements across $($surfaces.Count)/13 surfaces, 0 capture errors)"
exit 0
