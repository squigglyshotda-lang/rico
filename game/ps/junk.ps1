# Junk files: $A.mode = 'scan' (sizes only) or 'clean' (delete chosen $A.categories).
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$la = $env:LOCALAPPDATA
$cats = [ordered]@{
    user_temp     = @{ label = 'Your temp files'; admin = $false; paths = @($env:TEMP) }
    browser_cache = @{ label = 'Browser caches (Chrome, Edge, Firefox)'; admin = $false; paths = @(
        "$la\Google\Chrome\User Data\*\Cache\Cache_Data", "$la\Google\Chrome\User Data\*\Code Cache",
        "$la\Microsoft\Edge\User Data\*\Cache\Cache_Data", "$la\Microsoft\Edge\User Data\*\Code Cache",
        "$la\Mozilla\Firefox\Profiles\*\cache2") }
    crash_dumps   = @{ label = 'Crash dumps'; admin = $false; paths = @("$la\CrashDumps", "$la\Microsoft\Windows\WER\ReportArchive", "$la\Microsoft\Windows\WER\ReportQueue") }
    shader_cache  = @{ label = 'GPU shader caches (rebuilt automatically)'; admin = $false; paths = @("$la\D3DSCache", "$la\NVIDIA\DXCache", "$la\NVIDIA\GLCache", "$la\AMD\DxCache", "$la\AMD\GLCache") }
    windows_temp  = @{ label = 'Windows temp files'; admin = $true; paths = @("$env:windir\Temp") }
    update_cache  = @{ label = 'Old Windows Update downloads'; admin = $true; paths = @("$env:windir\SoftwareDistribution\Download") }
}

function Get-Size($paths) {
    $total = 0
    foreach ($p in $paths) {
        foreach ($dir in @(Resolve-Path -Path $p -ErrorAction SilentlyContinue)) {
            $sum = (Get-ChildItem -LiteralPath $dir.Path -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            if ($sum) { $total += $sum }
        }
    }
    return $total
}

function Get-RecycleSize {
    $total = 0
    try {
        $shell = New-Object -ComObject Shell.Application
        foreach ($item in $shell.NameSpace(10).Items()) { $total += [double]$item.ExtendedProperty('Size') }
    } catch {}
    return $total
}

if ($A.mode -eq 'scan') {
    $out = @()
    foreach ($k in $cats.Keys) {
        $c = $cats[$k]
        $out += @{ id = $k; label = $c.label; needs_admin = $c.admin; mb = [math]::Round((Get-Size $c.paths) / 1MB) }
    }
    $out += @{ id = 'recycle_bin'; label = 'Recycle Bin'; needs_admin = $false; mb = [math]::Round((Get-RecycleSize) / 1MB) }
    Done @{ categories = $out; is_admin = $isAdmin }
    return
}

# clean
$report = @()
$cutoff = (Get-Date).AddHours(-24)
foreach ($k in @($A.categories)) {
    if ($k -eq 'recycle_bin') {
        $before = Get-RecycleSize
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        $report += @{ id = $k; freed_mb = [math]::Round(($before - (Get-RecycleSize)) / 1MB) }
        continue
    }
    if (-not $cats.Contains($k)) { continue }
    $c = $cats[$k]
    if ($c.admin -and -not $isAdmin) { $report += @{ id = $k; freed_mb = 0; note = 'needs admin' }; continue }
    $before = Get-Size $c.paths
    foreach ($p in $c.paths) {
        foreach ($dir in @(Resolve-Path -Path $p -ErrorAction SilentlyContinue)) {
            # files first (skipping anything touched in the last day, which is often still in use)
            Get-ChildItem -LiteralPath $dir.Path -Recurse -Force -File -ErrorAction SilentlyContinue |
                Where-Object { $k -ne 'user_temp' -and $k -ne 'windows_temp' -or $_.LastWriteTime -lt $cutoff } |
                Remove-Item -Force -ErrorAction SilentlyContinue
            Get-ChildItem -LiteralPath $dir.Path -Recurse -Force -Directory -ErrorAction SilentlyContinue |
                Sort-Object { $_.FullName.Length } -Descending |
                Where-Object { @(Get-ChildItem -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0 } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
    $report += @{ id = $k; freed_mb = [math]::Round(($before - (Get-Size $c.paths)) / 1MB) }
}
Done @{ cleaned = $report }
