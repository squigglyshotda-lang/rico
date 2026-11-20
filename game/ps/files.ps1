# File jobs. $A.mode:
#   tidy_plan / tidy_apply  ($A.folder, $A.by = type|month)  -> moves top-level files into subfolders
#   rename_plan / rename_apply ($A.folder, $A.find, $A.replace, $A.prefix, $A.number, $A.ext)
#   undo ($A.log) -> reverses a tidy or rename using its log
#   find ($A.folder, $A.kind = big|duplicates, $A.min_mb, $A.limit)
#   delete ($A.paths) -> sends files to the Recycle Bin
function Resolve-Folder($f) {
    switch -Regex ([string]$f) {
        '^(downloads?)$' { return (New-Object -ComObject Shell.Application).NameSpace('shell:Downloads').Self.Path }
        '^desktop$'      { return [Environment]::GetFolderPath('Desktop') }
        '^documents$'    { return [Environment]::GetFolderPath('MyDocuments') }
        '^pictures$'     { return [Environment]::GetFolderPath('MyPictures') }
        '^videos$'       { return [Environment]::GetFolderPath('MyVideos') }
        '^music$'        { return [Environment]::GetFolderPath('MyMusic') }
        default          { return [Environment]::ExpandEnvironmentVariables($f) }
    }
}
function Get-FreeName($dir, $name) {
    $target = Join-Path $dir $name
    $i = 2
    $base = [IO.Path]::GetFileNameWithoutExtension($name)
    $ext = [IO.Path]::GetExtension($name)
    while (Test-Path -LiteralPath $target) { $target = Join-Path $dir ("$base ($i)$ext"); $i++ }
    return $target
}
$types = [ordered]@{
    'Images'     = 'jpg jpeg png gif webp bmp tif tiff svg heic psd kra clip ase aseprite ico'
    'Videos'     = 'mp4 mov mkv avi webm wmv m4v'
    'Audio'      = 'mp3 wav ogg flac m4a aac'
    'Documents'  = 'pdf doc docx txt md rtf odt xls xlsx csv ppt pptx key pages'
    'Archives'   = 'zip rar 7z tar gz tgz'
    'Installers' = 'exe msi msix appx'
    '3D'         = 'blend fbx obj glb gltf stl 3mf usd usdz dae'
    'Fonts'      = 'ttf otf woff woff2'
    'Code'       = 'gd cs py js ts json html css cpp c h lua tscn tres godot'
}
function Get-TypeFolder($ext) {
    $e = $ext.TrimStart('.').ToLower()
    foreach ($k in $types.Keys) { if ((' ' + $types[$k] + ' ').Contains(" $e ")) { return $k } }
    return 'Other'
}

$folder = Resolve-Folder $A.folder
$mode = [string]$A.mode

if ($mode -like 'tidy*') {
    if (-not (Test-Path -LiteralPath $folder)) { Done @{ error = "Folder not found: $folder" }; return }
    $plan = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $folder -File -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.Attributes.HasFlag([IO.FileAttributes]::Hidden) })) {
        if ($A.by -eq 'month') { $sub = $f.LastWriteTime.ToString('yyyy-MM') } else { $sub = Get-TypeFolder $f.Extension }
        $plan += [pscustomobject]@{ from = $f.FullName; folder = $sub; name = $f.Name }
    }
    $summary = @($plan | Group-Object folder | Sort-Object Count -Descending | ForEach-Object { [ordered]@{ folder = $_.Name; files = $_.Count } })
    if ($mode -eq 'tidy_plan') { Done @{ folder = $folder; total = $plan.Count; summary = $summary }; return }
    $log = @()
    foreach ($m in $plan) {
        $dir = Join-Path $folder $m.folder
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
        $to = Get-FreeName $dir $m.name
        try { Move-Item -LiteralPath $m.from -Destination $to -ErrorAction Stop; $log += [ordered]@{ from = $m.from; to = $to } } catch {}
    }
    Done @{ folder = $folder; moved = $log.Count; summary = $summary; log = $log }
    return
}

if ($mode -like 'rename*') {
    $files = @(Get-ChildItem -LiteralPath $folder -File -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($A.ext) { $files = @($files | Where-Object { $_.Extension.TrimStart('.') -ieq ([string]$A.ext).TrimStart('.') }) }
    $plan = @()
    $n = 1
    foreach ($f in $files) {
        $base = $f.BaseName
        if ($A.find) { $base = $base.Replace([string]$A.find, [string]$A.replace) }
        if ($A.prefix) { $base = [string]$A.prefix + $base }
        if ($A.number) { $base = $base + '_' + $n.ToString('000') }
        $new = $base + $f.Extension
        $n++
        if ($new -ne $f.Name) { $plan += [ordered]@{ from = $f.FullName; to = (Join-Path $folder $new) } }
    }
    if ($mode -eq 'rename_plan') { Done @{ folder = $folder; total = $plan.Count; preview = @($plan | Select-Object -First 12) }; return }
    $log = @()
    foreach ($m in $plan) {
        if (Test-Path -LiteralPath $m.to) { continue }
        try { Rename-Item -LiteralPath $m.from -NewName (Split-Path $m.to -Leaf) -ErrorAction Stop; $log += $m } catch {}
    }
    Done @{ folder = $folder; renamed = $log.Count; log = $log }
    return
}

if ($mode -eq 'undo') {
    $done = 0
    $entries = @($A.log)
    [array]::Reverse($entries)
    foreach ($m in $entries) {
        if ((Test-Path -LiteralPath $m.to) -and -not (Test-Path -LiteralPath $m.from)) {
            try { Move-Item -LiteralPath $m.to -Destination $m.from -ErrorAction Stop; $done++ } catch {}
        }
    }
    # remove folders the tidy created that are now empty
    foreach ($d in @($entries | ForEach-Object { Split-Path $_.to -Parent } | Select-Object -Unique)) {
        if ((Test-Path -LiteralPath $d) -and @(Get-ChildItem -LiteralPath $d -Force).Count -eq 0) { Remove-Item -LiteralPath $d -ErrorAction SilentlyContinue }
    }
    Done @{ restored = $done }
    return
}

if ($mode -eq 'find') {
    if (-not $folder) { $folder = [Environment]::GetFolderPath('UserProfile') }
    $min = 1MB
    if ($A.min_mb) { $min = [double]$A.min_mb * 1MB }
    $limit = 20
    if ($A.limit) { $limit = [int]$A.limit }
    $all = @(Get-ChildItem -LiteralPath $folder -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Length -ge $min })
    if ($A.kind -eq 'duplicates') {
        $groups = @()
        foreach ($g in @($all | Group-Object Length | Where-Object { $_.Count -gt 1 })) {
            foreach ($h in @($g.Group | ForEach-Object { [pscustomobject]@{ path = $_.FullName; hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm MD5 -ErrorAction SilentlyContinue).Hash; mb = [math]::Round($_.Length / 1MB, 1) } } | Where-Object { $_.hash } | Group-Object hash | Where-Object { $_.Count -gt 1 })) {
                $groups += [pscustomobject]@{ mb_each = $h.Group[0].mb; wasted_mb = [math]::Round($h.Group[0].mb * ($h.Count - 1), 1); paths = @($h.Group | ForEach-Object { $_.path }) }
            }
        }
        $groups = @($groups | Sort-Object { $_.wasted_mb } -Descending | Select-Object -First $limit)
        Done @{ folder = $folder; duplicate_groups = $groups; wasted_mb = [math]::Round(($groups | Measure-Object -Property wasted_mb -Sum).Sum, 1) }
        return
    }
    $big = @($all | Sort-Object Length -Descending | Select-Object -First $limit | ForEach-Object { [ordered]@{ path = $_.FullName; mb = [math]::Round($_.Length / 1MB, 1); modified = $_.LastWriteTime.ToString('yyyy-MM-dd') } })
    Done @{ folder = $folder; files = $big }
    return
}

if ($mode -eq 'delete') {
    Add-Type -AssemblyName Microsoft.VisualBasic
    $ok = 0
    $failed = @()
    foreach ($p in @($A.paths)) {
        try {
            if (Test-Path -LiteralPath $p -PathType Container) {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteDirectory($p, 'OnlyErrorDialogs', 'SendToRecycleBin')
            } else {
                [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($p, 'OnlyErrorDialogs', 'SendToRecycleBin')
            }
            $ok++
        } catch { $failed += $p }
    }
    Done @{ recycled = $ok; failed = $failed }
    return
}
Done @{ error = "Unknown mode $mode" }
