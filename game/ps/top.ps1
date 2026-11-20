# What's using the PC right now. Samples CPU over one second, groups processes by name.
$protected = @('Idle','System','Registry','smss','csrss','wininit','winlogon','services','lsass','svchost','dwm','explorer','fontdrvhost','sihost','ctfmon','Memory Compression','Secure System','LsaIso','spoolsv','audiodg','WmiPrvSE','RuntimeBroker','SearchHost','StartMenuExperienceHost','ShellExperienceHost','TextInputHost','conhost','powershell','Rico','rico_helper','MsMpEng','SecurityHealthService','NisSrv','wlanext','dllhost','taskhostw')
$cores = [Environment]::ProcessorCount
$before = @{}
foreach ($p in Get-Process) { $before[$p.Id] = $p.TotalProcessorTime.TotalMilliseconds }
$t0 = Get-Date
Start-Sleep -Milliseconds 1000
$elapsed = ((Get-Date) - $t0).TotalMilliseconds
$gpu = @{}
try {
    $samples = (Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop).CounterSamples
    foreach ($s in $samples) {
        if ($s.InstanceName -match 'pid_(\d+)_') {
            $id = [int]$Matches[1]
            $gpu[$id] = [double]$gpu[$id] + $s.CookedValue
        }
    }
} catch {}
$groups = @{}
foreach ($p in Get-Process) {
    $cpu = 0.0
    if ($before.ContainsKey($p.Id)) {
        $cpu = ($p.TotalProcessorTime.TotalMilliseconds - $before[$p.Id]) / $elapsed * 100.0 / $cores
    }
    $n = $p.ProcessName
    if (-not $groups.ContainsKey($n)) {
        $groups[$n] = [ordered]@{ name = $n; title = ''; cpu = 0.0; mem_mb = 0.0; gpu = 0.0; count = 0; has_window = $false; protected = ($protected -contains $n) }
    }
    $g = $groups[$n]
    $g.cpu += [math]::Max(0, $cpu)
    $g.mem_mb += $p.WorkingSet64 / 1MB
    $g.gpu += [double]$gpu[$p.Id]
    $g.count += 1
    if ($p.MainWindowHandle -ne 0) { $g.has_window = $true; if ($p.MainWindowTitle) { $g.title = $p.MainWindowTitle } }
}
$sortKey = 'cpu'
if ($A.sort -eq 'memory') { $sortKey = 'mem_mb' } elseif ($A.sort -eq 'gpu') { $sortKey = 'gpu' }
$count = 10
if ($A.count) { $count = [int]$A.count }
$list = @($groups.Values | ForEach-Object {
    $_.cpu = [math]::Round($_.cpu, 1); $_.mem_mb = [math]::Round($_.mem_mb); $_.gpu = [math]::Round([math]::Min($_.gpu, 100), 1); [pscustomobject]$_
} | Sort-Object -Property $sortKey -Descending | Select-Object -First $count)
$os = Get-CimInstance Win32_OperatingSystem
$cpuLoad = (Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average
Done @{
    processes = $list
    total_cpu_percent = $cpuLoad
    ram_used_percent = [math]::Round((1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100)
    ram_total_gb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
}
