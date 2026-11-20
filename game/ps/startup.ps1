# Startup apps: $A.mode = 'list' or 'set' ($A.name, $A.scope, $A.enabled).
# Uses the same StartupApproved switches as Task Manager, so nothing is deleted.
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$approvedBase = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
$sources = @(
    @{ scope = 'user';        hive = 'HKCU:'; key = 'Software\Microsoft\Windows\CurrentVersion\Run';             approved = 'Run';           admin = $false },
    @{ scope = 'machine';     hive = 'HKLM:'; key = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run';             approved = 'Run';           admin = $true },
    @{ scope = 'machine32';   hive = 'HKLM:'; key = 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; approved = 'Run32';         admin = $true }
)

function Get-Enabled($hive, $approved, $name) {
    $v = (Get-ItemProperty -Path "$hive\$approvedBase\$approved" -Name $name -ErrorAction SilentlyContinue).$name
    if ($null -eq $v) { return $true }
    return (($v[0] -band 1) -eq 0)
}

function Set-Enabled($hive, $approved, $name, $on) {
    $path = "$hive\$approvedBase\$approved"
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    $bytes = [byte[]](0,0,0,0,0,0,0,0,0,0,0,0)
    if ($on) { $bytes[0] = 2 } else {
        $bytes[0] = 3
        $ft = [BitConverter]::GetBytes((Get-Date).ToFileTime())
        [Array]::Copy($ft, 0, $bytes, 4, 8)
    }
    Set-ItemProperty -Path $path -Name $name -Value $bytes -Type Binary
}

$items = @()
foreach ($s in $sources) {
    $props = Get-ItemProperty -Path "$($s.hive)\$($s.key)" -ErrorAction SilentlyContinue
    if (-not $props) { continue }
    foreach ($p in $props.PSObject.Properties) {
        if (@('PSPath','PSParentPath','PSChildName','PSDrive','PSProvider') -contains $p.Name) { continue }
        $items += [ordered]@{ name = $p.Name; command = [string]$p.Value; scope = $s.scope; needs_admin = $s.admin; enabled = (Get-Enabled $s.hive $s.approved $p.Name); hive = $s.hive; approved = $s.approved }
    }
}
$folders = @(
    @{ scope = 'user_folder';   dir = [Environment]::GetFolderPath('Startup');       hive = 'HKCU:'; admin = $false },
    @{ scope = 'common_folder'; dir = [Environment]::GetFolderPath('CommonStartup'); hive = 'HKLM:'; admin = $true }
)
foreach ($f in $folders) {
    foreach ($file in @(Get-ChildItem -LiteralPath $f.dir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) {
        $items += [ordered]@{ name = $file.Name; command = $file.FullName; scope = $f.scope; needs_admin = $f.admin; enabled = (Get-Enabled $f.hive 'StartupFolder' $file.Name); hive = $f.hive; approved = 'StartupFolder' }
    }
}

if ($A.mode -eq 'set') {
    $target = @($items | Where-Object { $_.name -eq $A.name -and (-not $A.scope -or $_.scope -eq $A.scope) })
    if ($target.Count -eq 0) {
        $target = @($items | Where-Object { $_.name -like "*$($A.name)*" })
    }
    if ($target.Count -eq 0) { Done @{ error = "No startup item called '$($A.name)'." }; return }
    $t = $target[0]
    if ($t.needs_admin -and -not $isAdmin) { Done @{ error = 'needs admin'; needs_admin = $true }; return }
    Set-Enabled $t.hive $t.approved $t.name ([bool]$A.enabled)
    Done @{ name = $t.name; enabled = [bool]$A.enabled }
    return
}
Done @{ items = @($items | ForEach-Object { [ordered]@{ name = $_.name; command = $_.command; scope = $_.scope; needs_admin = $_.needs_admin; enabled = $_.enabled } }) }
