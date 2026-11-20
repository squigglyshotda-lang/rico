# System health check. $A.updates = also search Windows Update (slow), $A.lhm = path to LibreHardwareMonitorLib.dll
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$os = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$drives = @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' | ForEach-Object {
    [ordered]@{ drive = $_.DeviceID; free_gb = [math]::Round($_.FreeSpace / 1GB, 1); size_gb = [math]::Round($_.Size / 1GB); free_percent = [math]::Round($_.FreeSpace / [math]::Max($_.Size, 1) * 100) }
})
$gpus = @(Get-CimInstance Win32_VideoController | ForEach-Object {
    $date = ''
    if ($_.DriverDate) { $date = $_.DriverDate.ToString('yyyy-MM-dd') }
    [ordered]@{ name = $_.Name; driver = $_.DriverVersion; driver_date = $date }
})
$uptime = (Get-Date) - $os.LastBootUpTime
$reboot = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')
$lastUpdate = ''
$hf = Get-HotFix -ErrorAction SilentlyContinue | Where-Object { $_.InstalledOn } | Sort-Object InstalledOn -Descending | Select-Object -First 1
if ($hf) { $lastUpdate = $hf.InstalledOn.ToString('yyyy-MM-dd') }
$pending = $null
if ($A.updates) {
    try {
        $searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $pending = $searcher.Search("IsInstalled=0 and IsHidden=0 and Type='Software'").Updates.Count
    } catch { $pending = $null }
}
$startupOn = 0
foreach ($k in @('HKCU:\Software\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')) {
    $p = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
    if ($p) { $startupOn += @($p.PSObject.Properties | Where-Object { @('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider') -notcontains $_.Name }).Count }
}

# Temperatures via LibreHardwareMonitor (GPU usually works without admin; CPU needs admin + the PawnIO driver)
$temps = @()
$tempNote = ''
if ($A.lhm -and (Test-Path -LiteralPath $A.lhm)) {
    try {
        $libDir = Split-Path $A.lhm -Parent
        [AppDomain]::CurrentDomain.add_AssemblyResolve({
            param($s, $e)
            $f = Join-Path $libDir (($e.Name -split ',')[0] + '.dll')
            if (Test-Path -LiteralPath $f) { return [Reflection.Assembly]::LoadFrom($f) }
            return $null
        })
        Add-Type -Path $A.lhm
        $c = New-Object LibreHardwareMonitor.Hardware.Computer
        $c.IsCpuEnabled = $true
        $c.IsGpuEnabled = $true
        $c.IsMotherboardEnabled = $true
        $c.IsStorageEnabled = $true
        $c.Open()
        foreach ($hw in $c.Hardware) {
            $hw.Update()
            $all = @($hw.Sensors) + @($hw.SubHardware | ForEach-Object { $_.Update(); $_.Sensors })
            foreach ($s in $all) {
                if ($s.SensorType -eq [LibreHardwareMonitor.Hardware.SensorType]::Temperature -and $null -ne $s.Value -and $s.Value -gt 0) {
                    $temps += [pscustomobject]@{ device = $hw.Name; sensor = $s.Name; celsius = [math]::Round([double]$s.Value) }
                }
            }
        }
        $c.Close()
    } catch { $tempNote = "Temperature library failed: $($_.Exception.Message)" }
    if (-not $isAdmin) { $tempNote = ($tempNote + ' CPU temperatures need admin rights (ask to check temps with admin).').Trim() }
    elseif (-not ($temps | Where-Object { $_.device -eq $cpu.Name.Trim() })) { $tempNote = ($tempNote + ' No CPU temperature: install the free PawnIO driver (pawnio.eu) for CPU sensors.').Trim() }
}
# keep the list short: hottest reading per device plus CPU package/core max
$tempSummary = @($temps | Group-Object device | ForEach-Object {
    $hot = $_.Group | Sort-Object { $_.celsius } -Descending | Select-Object -First 1
    [ordered]@{ device = $_.Name; hottest_sensor = $hot.sensor; celsius = $hot.celsius }
})

Done ([ordered]@{
    computer = $env:COMPUTERNAME
    windows = $os.Caption + ' ' + $os.DisplayVersion
    cpu = $cpu.Name.Trim()
    cpu_load_percent = $cpu.LoadPercentage
    ram_total_gb = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
    ram_used_percent = [math]::Round((1 - $os.FreePhysicalMemory / $os.TotalVisibleMemorySize) * 100)
    drives = $drives
    gpus = $gpus
    uptime_days = [math]::Round($uptime.TotalDays, 1)
    reboot_pending = $reboot
    last_update_installed = $lastUpdate
    pending_updates = $pending
    startup_entries = $startupOn
    temperatures = $tempSummary
    temperature_note = $tempNote
    is_admin = $isAdmin
})
