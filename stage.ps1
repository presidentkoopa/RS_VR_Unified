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
#
# Each value is the package ROOT -- the directory whose layout matches what a
# pk3 root looks like. For five of these that is also the repo root. It is NOT
# for the wheel: E:\RS_WeaponWheel is a repo that CONTAINS its package in a
# subdirectory of the same name (alongside RS_WeaponWheel_dev, a separate debug
# pk3 that must never be staged -- it ships its own zscript.zs and an
# AddPlayerClasses that is global and permanent). Pointing the lane at the inner
# directory is what keeps the dev package out and makes sounds\ line up with
# every other lane's.
$mods = [ordered]@{
    'hands'      = 'E:\RS_Hands'
    'holsters'   = 'E:\RS_Holsters'
    'hardpoints' = 'E:\RS_HardPoints'
    'reload'     = 'E:\RS_Reload'
    'headshots'  = 'E:\RS_Headshots'
    'wheel'      = 'E:\RS_WeaponWheel\RS_WeaponWheel'
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

# Lines the merged package owns and an individual .zs must therefore NOT carry.
# See the long note below the loop for why each one is fatal here.
$preambleRe = '(?m)^[ \t]*(?:version|#include)[ \t]+"[^"]*"[ \t]*\r?\n'
$stripped   = @()

foreach ($k in $mods.Keys) {
    $src = $mods[$k]
    $dst = Join-Path $U "zscript\$k"
    New-Item -ItemType Directory -Force -Path $dst | Out-Null

    # Five packages keep their .zs under <root>\zscript. The wheel keeps its
    # eighteen at the package root, next to its lumps, because its root script
    # IS one of them. Fall back to the root rather than special-casing a lane
    # name, and never recurse above the package root.
    $zsSrc = Join-Path $src 'zscript'
    if (-not (Test-Path $zsSrc)) { $zsSrc = $src }

    # Flatten each mod's zscript tree into one namespaced directory. Every
    # include path in the merged zscript.txt is written against this layout,
    # so a source repo reorganising its own subdirectories does not matter.
    Get-ChildItem $zsSrc -Recurse -File -Filter '*.zs' | ForEach-Object {
        $to = Join-Path $dst $_.Name
        Copy-Item $_.FullName $to -Force

        # THE MERGED zscript.txt OWNS THE VERSION LINE AND THE INCLUDE GRAPH.
        #
        # Both of these are fatal, not cosmetic, in a file that is #included
        # rather than being the base lump:
        #
        #   version "x"  is read by ParseOneScript BEFORE the grammar ever
        #                runs, and only for the base lump. There is no
        #                top-level `version` production in the grammar
        #                (zcc-parse.lemon has VERSION only as a class/struct/
        #                member flag, with parens), so the same line inside an
        #                included file is a bare token the parser rejects.
        #
        #   #include     resolves against the ARCHIVE ROOT, not against the
        #                including file, unless the path begins './' or '../'
        #                (ResolveIncludePath in zcc_parser.cpp). A wheel file
        #                asking for "wr_gunhud.zs" after being staged to
        #                zscript/wheel/ therefore looks at the pk3 root, finds
        #                nothing, and errors -- or, worse, finds the copy in a
        #                still-loaded RS_WeaponWheel.pk3 and declares every
        #                class twice. The './' form has no precedent anywhere
        #                in E:\UZDXREMA\wadsrc\static\zscript or in any RS_*
        #                package, so it is not used here either.
        #
        # This is a no-op for all five original lanes -- none of their .zs has
        # ever carried either line. Anything it removes is REPORTED below,
        # because a silently dropped #include is precisely the failure this
        # package has already been taken down by once.
        $txt = [System.IO.File]::ReadAllText($to)
        $hits = [regex]::Matches($txt, $preambleRe)
        if ($hits.Count -gt 0) {
            foreach ($h in $hits) { $stripped += [pscustomobject]@{ lane=$k; file=$_.Name; line=$h.Value.Trim() } }
            $clean = [regex]::Replace($txt, $preambleRe, '')
            [System.IO.File]::WriteAllText($to, $clean, (New-Object System.Text.UTF8Encoding($false)))
        }
    }
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

# Every line the staging step removed. Each '#include' printed here MUST have a
# matching entry in the merged zscript.txt or its file's classes will not exist.
Write-Host ("preamble lines stripped : {0}" -f $stripped.Count)
foreach ($s in $stripped) { Write-Host ("    {0}/{1}  {2}" -f $s.lane, $s.file, $s.line) }

Write-Host ""
Write-Host "Staged. zscript.txt / MAPINFO.txt / KEYCONF and the concatenated lumps are"
Write-Host "hand-maintained in this repo -- re-check them if a source repo added a class"
Write-Host "or an event handler. Then run .\build.ps1"
