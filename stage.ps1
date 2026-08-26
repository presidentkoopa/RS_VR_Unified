# Re-stage RS_VR_Unified from the CURRENT state of the source repos.
#
# The unified package is a TEST VEHICLE, not the merge. The merge is paused --
# each mod is being fixed in its own repo first -- but a single pk3 is the only
# way to see the mods behave together, and cross-mod behaviour is exactly what
# the grip arbiter exists to fix. So this restages on demand rather than being
# hand-maintained.
#
# ALWAYS RUN THIS BEFORE TESTING. The first unified build was staged on
# 2026-08-25 from the pre-fix sources; loading a stale one means testing code
# that no longer exists in any repo.
#
# Assets are UNIONED and never deduplicated by deletion. Model filenames are
# hardcoded as A_ChangeModel string literals in several places while appearing
# in MODELDEF only inside comments, which is what led two independent design
# passes to conclude they were dead. A missing model in GZDoom is a log line and
# an invisible actor, not an error -- the hardest regression class to notice.
param(
    [switch]$NoArbiter   # stage without RS_GripArbiter, to isolate its effect
)

$ErrorActionPreference = 'Stop'
$U = $PSScriptRoot

# ---- sources, in dependency order -----------------------------------------
# hands first: RS_Basis is the foundation every other package reads from.
$mods = [ordered]@{
    'hands'      = 'E:\RS_Hands'
    'holsters'   = 'E:\RS_Holsters'
    'hardpoints' = 'E:\RS_HardPoints'
    'reload'     = 'E:\RS_Reload'
    'headshots'  = 'E:\RS_Headshots'
}
if (-not $NoArbiter) { $mods['arbiter'] = 'E:\RS_GripArbiter' }

foreach ($k in $mods.Keys) {
    if (-not (Test-Path $mods[$k])) { throw "source missing: $($mods[$k])" }
    $b = git -C $mods[$k] rev-parse --abbrev-ref HEAD 2>$null
    $h = git -C $mods[$k] log -1 --format='%h %s' 2>$null
    Write-Host ("  {0,-11} {1,-28} [{2}] {3}" -f $k, (Split-Path $mods[$k] -Leaf), $b, $h)
}
Write-Host ""

# ---- clear the staged tree, keep the repo's own files ----------------------
foreach ($d in @('zscript','models','graphics','sprites','sounds')) {
    $p = Join-Path $U $d
    if (Test-Path $p) { Remove-Item $p -Recurse -Force }
}

foreach ($k in $mods.Keys) {
    $src = $mods[$k]
    $dst = Join-Path $U "zscript\$k"
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    # Flatten each mod's zscript tree into one namespaced directory. Every
    # include path in the merged zscript.txt is written against this layout,
    # so a source repo reorganising its own subdirectories does not matter.
    Get-ChildItem (Join-Path $src 'zscript') -Recurse -File -Filter '*.zs' |
        ForEach-Object { Copy-Item $_.FullName (Join-Path $dst $_.Name) -Force }
}

# ---- assets: union, with byte-level collision reporting --------------------
$seen = @{}
$collisions = @()
foreach ($k in $mods.Keys) {
    foreach ($sub in @('models','graphics','sprites','sounds')) {
        $base = Join-Path $mods[$k] $sub
        if (-not (Test-Path $base)) { continue }
        foreach ($f in (Get-ChildItem $base -Recurse -File)) {
            $rel = $f.FullName.Substring($mods[$k].Length + 1)
            $h = (Get-FileHash $f.FullName -Algorithm SHA256).Hash
            if ($seen.ContainsKey($rel)) {
                $collisions += [pscustomobject]@{ path=$rel; a=$seen[$rel].Mod; b=$k; same=($seen[$rel].Hash -eq $h) }
                if ($seen[$rel].Hash -eq $h) { continue }
                Write-Warning "DIFFERING files at one path: $rel ($($seen[$rel].Mod) vs $k) -- second one wins, investigate"
            } else { $seen[$rel] = [pscustomobject]@{ Mod=$k; Hash=$h } }
            $d = Join-Path $U $rel
            New-Item -ItemType Directory -Force -Path (Split-Path $d -Parent) | Out-Null
            Copy-Item $f.FullName $d -Force
        }
    }
}

Write-Host ("zscript files : {0}" -f (Get-ChildItem (Join-Path $U 'zscript') -Recurse -File).Count)
Write-Host ("asset files   : {0}" -f (Get-ChildItem $U -Recurse -File | Where-Object { $_.FullName -notmatch '\\zscript\\' -and $_.Extension -notin @('.txt','.md','.ps1','.pk3') }).Count)
Write-Host ("collisions    : {0} ({1} byte-identical)" -f $collisions.Count, @($collisions | Where-Object { $_.same }).Count)
foreach ($c in $collisions) { Write-Host ("    {0}  [{1} vs {2}]  identical={3}" -f $c.path, $c.a, $c.b, $c.same) }
Write-Host ""
Write-Host "Staged. zscript.txt / MAPINFO.txt / KEYCONF and the concatenated lumps are"
Write-Host "hand-maintained in this repo -- re-check them if a source repo added a class"
Write-Host "or an event handler. Then run .\build.ps1"
