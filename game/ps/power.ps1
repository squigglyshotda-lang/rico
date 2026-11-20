# Power plans: $A.mode = 'list' or 'set' ($A.plan = balanced|high|ultimate|saver or a GUID).
$known = @{
    balanced = '381b4222-f694-41f0-9685-ff5bb260df2e'
    high     = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    saver    = 'a1841308-3541-4fab-bc81-f71556f20b4a'
    ultimate = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
}
function Get-Plans {
    $plans = @()
    foreach ($line in (powercfg /list)) {
        if ($line -match '([0-9a-fA-F\-]{36})\s+\((.+?)\)(\s*\*)?') {
            $plans += [ordered]@{ guid = $Matches[1].ToLower(); name = $Matches[2]; active = [bool]$Matches[3] }
        }
    }
    return $plans
}
$plans = @(Get-Plans)
$active = @($plans | Where-Object { $_.active } | Select-Object -First 1)
if ($A.mode -eq 'set') {
    $want = [string]$A.plan
    $guid = $want
    if ($known.ContainsKey($want)) { $guid = $known[$want] }
    $match = @($plans | Where-Object { $_.guid -eq $guid -or $_.name -like "*$want*" } | Select-Object -First 1)
    if ($match.Count -eq 0 -and ($want -eq 'high' -or $want -eq 'ultimate')) {
        # Hidden on many PCs: make a copy of the built-in scheme
        $created = powercfg -duplicatescheme $known[$want]
        $plans = @(Get-Plans)
        if (($created -join " ") -match '([0-9a-fA-F\-]{36})') { $match = @($plans | Where-Object { $_.guid -eq $Matches[1].ToLower() }) }
    }
    if ($match.Count -eq 0) { Done @{ error = "No power plan matching '$want'."; plans = $plans }; return }
    powercfg /setactive $match[0].guid
    Done @{ previous = $active[0].guid; previous_name = $active[0].name; now = $match[0].name; guid = $match[0].guid }
    return
}
Done @{ plans = $plans }
