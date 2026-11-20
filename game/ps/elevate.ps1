# Launcher: re-runs a job script with admin rights (Windows shows its UAC prompt).
param([string]$Script, [string]$Out)
try {
    $argList = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $Script + '" -Out "' + $Out + '"'
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -WindowStyle Hidden -ArgumentList $argList -ErrorAction Stop
} catch {
    '{"error":"Admin permission was declined."}' | Out-File -Encoding utf8 -FilePath $Out
}
