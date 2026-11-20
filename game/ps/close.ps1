# Close apps by process name. Asks windows to close politely first (so apps can
# prompt to save); only force-kills when $A.force is true.
$protected = @('Idle','System','Registry','smss','csrss','wininit','winlogon','services','lsass','svchost','dwm','explorer','fontdrvhost','sihost','ctfmon','Memory Compression','Secure System','LsaIso','spoolsv','audiodg','MsMpEng','SecurityHealthService','Rico','rico_helper')
$results = @()
foreach ($raw in @($A.names)) {
    $name = ([string]$raw) -replace '\.exe$', ''
    if ($protected -contains $name) { $results += @{ name = $name; status = 'protected, not touched' }; continue }
    $procs = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    if ($procs.Count -eq 0) { $results += @{ name = $name; status = 'not running' }; continue }
    $paths = @($procs | Where-Object { $_.Path } | Select-Object -ExpandProperty Path -Unique)
    foreach ($p in $procs) { if ($p.MainWindowHandle -ne 0) { [void]$p.CloseMainWindow() } }
    Start-Sleep -Milliseconds 2500
    $left = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    if ($left.Count -gt 0 -and $A.force) {
        $left | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        $left = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    }
    if ($left.Count -gt 0 -and -not $A.force -and @($left | Where-Object { $_.MainWindowHandle -ne 0 }).Count -eq 0) {
        # only background processes left (no windows): these never respond to a polite close
        $left | Stop-Process -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        $left = @(Get-Process -Name $name -ErrorAction SilentlyContinue)
    }
    $status = 'closed'
    if ($left.Count -gt 0) { $status = 'still open (it may be asking to save, or needs force)' }
    $results += @{ name = $name; status = $status; paths = $paths }
}
Done @{ results = $results }
