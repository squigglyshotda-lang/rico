# Rico's search server: stays running, reads one JSON request per line on stdin and
# answers with one JSON line on stdout. Uses the Windows Search index for files.
$ErrorActionPreference = 'SilentlyContinue'
$ProgressPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
[Console]::InputEncoding = [Text.Encoding]::UTF8
$conn = $null

function Open-Index {
    try {
        $script:conn = New-Object -ComObject ADODB.Connection
        $script:conn.Open("Provider=Search.CollatorDSO;Extended Properties='Application=Windows';")
    } catch { $script:conn = $null }
}

function Search-Files([string]$term, [int]$top) {
    if (-not $script:conn) { Open-Index }
    if (-not $script:conn) { return @() }
    $clean = ($term -replace "[`'%_\[\]]", ' ').Trim()
    if (-not $clean) { return @() }
    $words = @($clean -split '\s+' | Where-Object { $_ })
    $where = ($words | ForEach-Object { "System.ItemNameDisplay LIKE '%$_%'" }) -join ' AND '
    $sql = "SELECT TOP $top System.ItemPathDisplay, System.ItemNameDisplay, System.Size, System.DateModified, System.ItemType " +
           "FROM SYSTEMINDEX WHERE SCOPE='file:' AND $where AND System.ItemType <> '.lnk' ORDER BY System.DateModified DESC"
    $items = @()
    try {
        $rs = $script:conn.Execute($sql)
        while (-not $rs.EOF) {
            $f = $rs.Fields
            $size = $f.Item('System.Size').Value
            $date = $f.Item('System.DateModified').Value
            $type = [string]$f.Item('System.ItemType').Value
            $items += @{
                path = [string]$f.Item('System.ItemPathDisplay').Value
                name = [string]$f.Item('System.ItemNameDisplay').Value
                size = $(if ($size -is [DBNull] -or $null -eq $size) { -1 } else { [double]$size })
                modified = $(if ($date -is [DateTime]) { $date.ToString('yyyy-MM-dd HH:mm') } else { '' })
                folder = ($type -eq 'Directory' -or $type -eq 'Folder')
            }
            $rs.MoveNext()
        }
        $rs.Close()
    } catch { $script:conn = $null }
    return $items
}

while ($true) {
    $line = [Console]::In.ReadLine()
    if ($null -eq $line) { break }
    $q = $null
    try { $q = $line | ConvertFrom-Json } catch { continue }
    $out = @{ id = $q.id; op = $q.op }
    switch ($q.op) {
        'apps' {
            $out.items = @(Get-StartApps | ForEach-Object { @{ name = $_.Name; id = $_.AppID } })
        }
        'files' {
            $out.q = $q.q
            $out.items = @(Search-Files ([string]$q.q) 25)
        }
        'time' {
            try {
                $to = [TimeZoneInfo]::FindSystemTimeZoneById([string]$q.tz_to)
                if ([int]$q.hour -lt 0) {
                    $t = [TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $to)
                } else {
                    $from = [TimeZoneInfo]::Local
                    if ($q.tz_from) { $from = [TimeZoneInfo]::FindSystemTimeZoneById([string]$q.tz_from) }
                    $src = [DateTime]::SpecifyKind([DateTime]::Today.AddHours([int]$q.hour).AddMinutes([int]$q.minute), [DateTimeKind]::Unspecified)
                    $t = [TimeZoneInfo]::ConvertTime($src, $from, $to)
                }
                $out.time = $t.ToString('HH:mm')
                $out.day = $t.ToString('ddd d MMM')
            } catch { $out.error = $_.Exception.Message }
        }
        'ping' { $out.ok = $true }
    }
    [Console]::Out.WriteLine(($out | ConvertTo-Json -Depth 4 -Compress))
    [Console]::Out.Flush()
}
