# Run a command Rico wrote (only after you pressed Allow). Captures all output as text.
$code = [string]$A.command
try {
    $sb = [ScriptBlock]::Create($code)
    $text = & $sb 2>&1 | Out-String -Width 160
    Done @{ ok = $true; output = $text }
} catch {
    Done @{ ok = $false; output = $_.Exception.Message }
}
