# Build RS_VR_Unified.pk3  -- DRAFT, pending final layout from the design phase.
#
# Consolidates the three incompatible packers found across the five source repos:
#
#   RS_Reload      .NET ZipFile, entry-by-entry, forward slashes  -> .pk3   (correct, no verification)
#   RS_Holsters    7-Zip at a hardcoded absolute path             -> .zip   (external dep, leaks files)
#   RS_HardPoints  same 7-Zip script                              -> .zip   (external dep, leaks README)
#   RS_Hands       none at all -- pk3 committed with no script
#   Headshots      none at all -- zip committed with no script
#
# This takes RS_Reload's entry-by-entry .NET approach (no 7-Zip dependency, and
# zip entries must use forward slashes -- Compress-Archive and CreateFromDirectory
# both write backslashes on Windows PowerShell, which GZDoom tolerates and SLADE
# does not), plus ModelSwapper's post-build VERIFICATION, which was the only
# packer of the six that checked its own output.
#
# WHY AN ALLOWLIST, NOT A DENYLIST. RS_Holsters.zip currently ships
# .claude/settings.local.json, holsterideas.txt and README.md; RS_HardPoints.zip
# ships README.md. Both use '-x!' exclusion lists, and anything nobody thought to
# exclude gets shipped. A lump name IGNORES ITS EXTENSION, so a stray file in the
# tree can shadow a real lump -- a MODELDEF.bak in a pk3 root has silently
# replaced the real MODELDEF before. Naming what goes IN cannot fail that way.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$root = $PSScriptRoot
$out  = Join-Path $root 'RS_VR_Unified.pk3'

# Root lumps that must be present. A missing one is an error, not a warning:
# a merged project silently missing its MAPINFO registers no event handlers at
# all, which reads in-headset as "the whole mod does nothing."
$requiredLumps = @('zscript.txt', 'MAPINFO.txt', 'CVARINFO.txt', 'MENUDEF.txt', 'KEYCONF')
$optionalLumps = @('MODELDEF.txt', 'SNDINFO.txt', 'TEXTURES.txt', 'TRNSLATE.txt')
$contentDirs   = @('zscript', 'models', 'graphics', 'sprites', 'sounds')

$files = @()
foreach ($f in $requiredLumps) {
    $p = Join-Path $root $f
    if (-not (Test-Path $p)) { throw "REQUIRED lump missing: $f" }
    $files += Get-Item $p
}
foreach ($f in $optionalLumps) {
    $p = Join-Path $root $f
    if (Test-Path $p) { $files += Get-Item $p } else { Write-Warning "optional lump absent: $f" }
}
foreach ($d in $contentDirs) {
    $p = Join-Path $root $d
    if (Test-Path $p) { $files += Get-ChildItem $p -Recurse -File } else { Write-Warning "content dir absent: $d/" }
}

if (Test-Path $out) { Remove-Item $out -Force }

$fs  = [System.IO.File]::Open($out, 'Create')
$zip = New-Object System.IO.Compression.ZipArchive($fs, [System.IO.Compression.ZipArchiveMode]::Create)
foreach ($f in $files) {
    $rel = ($f.FullName.Substring($root.Length + 1)) -replace '\\', '/'
    $e   = $zip.CreateEntry($rel, [System.IO.Compression.CompressionLevel]::Optimal)
    $st  = $e.Open()
    $b   = [System.IO.File]::ReadAllBytes($f.FullName)
    $st.Write($b, 0, $b.Length)
    $st.Close()
}
$zip.Dispose()
$fs.Close()

# ---------------------------------------------------------------- verification
$z     = [System.IO.Compression.ZipFile]::OpenRead($out)
$names = @{}
$z.Entries | ForEach-Object { $names[$_.FullName.ToLower()] = $true }
$fail  = 0

# 1. Forward slashes only.
$bad = @($z.Entries | Where-Object { $_.FullName -match '\\' }).Count
if ($bad -gt 0) { Write-Warning "$bad entries contain backslashes"; $fail++ }

# 2. Nothing that isn't a lump. The allowlist should make this impossible --
#    it is here to catch the allowlist itself being widened carelessly later.
$stray = @($z.Entries | Where-Object { $_.FullName -match '(?i)(\.md$|\.ps1$|\.py$|\.json$|\.bak$|^\.claude/|^docs/|^tools/|^media/)' })
foreach ($s in $stray) { Write-Warning "stray non-lump packed: $($s.FullName)"; $fail++ }

# 3. Every #include in zscript.txt resolves to a packed entry. An unresolved
#    include is a hard load failure, and it is the single most likely thing to
#    break in a merge that reorganises directories.
$zsE  = $z.Entries | Where-Object { $_.FullName -eq 'zscript.txt' }
$sr   = New-Object System.IO.StreamReader($zsE.Open())
$zstxt = $sr.ReadToEnd(); $sr.Close()
$inc = 0; $incMiss = 0
foreach ($line in ($zstxt -split "`n")) {
    if ($line -match '^\s*#include\s+"([^"]+)"') {
        $inc++
        if (-not $names.ContainsKey($matches[1].ToLower())) {
            Write-Warning "unresolved #include: $($matches[1])"; $incMiss++; $fail++
        }
    }
}

# 4. Exactly one version line, and it is 5.0.0 -- the engine is UZDoom 5.0.0-rc.2.
$vers = @([regex]::Matches($zstxt, '(?m)^\s*version\s+"([^"]+)"'))
if ($vers.Count -ne 1) { Write-Warning "zscript.txt has $($vers.Count) version lines, expected exactly 1"; $fail++ }
elseif ($vers[0].Groups[1].Value -ne '5.0.0') { Write-Warning "version is $($vers[0].Groups[1].Value), expected 5.0.0"; $fail++ }

# 5. Every AddEventHandlers name in MAPINFO is a class that actually exists in
#    the packed zscript. A handler named but not defined is a load-blocking
#    error; a handler defined but never named is silence, which reads in-headset
#    as the feature simply not existing. Both have bitten this codebase.
$miE = $z.Entries | Where-Object { $_.FullName -eq 'MAPINFO.txt' }
$sr2 = New-Object System.IO.StreamReader($miE.Open())
$mitxt = $sr2.ReadToEnd(); $sr2.Close()

$allZs = ''
foreach ($e in ($z.Entries | Where-Object { $_.FullName -match '(?i)\.zs$' })) {
    $r = New-Object System.IO.StreamReader($e.Open())
    $allZs += $r.ReadToEnd(); $r.Close()
}
$declared = @([regex]::Matches($allZs, '(?im)^\s*class\s+([A-Za-z0-9_]+)') | ForEach-Object { $_.Groups[1].Value.ToLower() })

$handlers = @()
foreach ($m in [regex]::Matches($mitxt, '(?i)AddEventHandlers\s*=\s*([^\r\n}]+)')) {
    $handlers += ([regex]::Matches($m.Groups[1].Value, '"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
}
$hMiss = 0
foreach ($h in $handlers) {
    if ($declared -notcontains $h.ToLower()) { Write-Warning "MAPINFO registers undefined handler: $h"; $hMiss++; $fail++ }
}

# 6. No duplicate class name. Two classes of one name is a fatal compile error,
#    and it is the specific failure a stale entry in an incrementally-updated
#    archive produces -- the reason this script always deletes before writing.
$dupes = $declared | Group-Object | Where-Object { $_.Count -gt 1 }
foreach ($d in $dupes) { Write-Warning "duplicate class declaration: $($d.Name) x$($d.Count)"; $fail++ }

$n  = $z.Entries.Count
$kb = [math]::Round((Get-Item $out).Length / 1KB, 1)
$z.Dispose()

Write-Host ""
Write-Host "RS_VR_Unified.pk3  --  $n entries, $kb KB"
Write-Host "  backslash entries : $bad"
Write-Host "  stray files       : $($stray.Count)"
Write-Host "  #includes         : $inc checked, $incMiss unresolved"
Write-Host "  event handlers    : $($handlers.Count) registered, $hMiss undefined"
Write-Host "  classes           : $($declared.Count) declared, $($dupes.Count) duplicated"
if ($fail -gt 0) { throw "package verification failed ($fail problems)" }
Write-Host "  VERIFIED OK"
