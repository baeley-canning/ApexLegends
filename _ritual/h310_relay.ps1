# h310 relay - loopback HTTP relay for the h310 probe: GET serves the payload dir, POST /log
# appends the probe's live feed to guest-h310.log. python -m http.server answers 501 to the POST
# and the probe swallows it, so a run on a plain file server leaves no readable feed at all.
# Bind is http://127.0.0.1:8080/ (the probe's $base) - start ELEVATED, else the prefix needs a urlacl.
$ErrorActionPreference = 'Continue'
$root  = 'C:\p37vm\payload'
$log   = 'C:\p37vm\guest-h310.log'
$stamp = 'C:\Users\Public\p37\h310_relay.txt'
function S([string]$m) { Add-Content -LiteralPath $stamp -Value ((Get-Date -f 'HH:mm:ss.fff') + ' ' + $m) }
S ('===== relay start pid=' + $PID + ' =====')
$l = New-Object System.Net.HttpListener
$l.Prefixes.Add('http://127.0.0.1:8080/')
try { $l.Start() } catch { S ('START ERR ' + $_.Exception.Message); exit 1 }
S ('listening=' + $l.IsListening)
while ($l.IsListening) {
    $c = $null
    try { $c = $l.GetContext() } catch { break }
    try {
        if ($c.Request.HttpMethod -eq 'POST') {
            $sr = New-Object System.IO.StreamReader($c.Request.InputStream)
            $body = $sr.ReadToEnd(); $sr.Close()
            Add-Content -LiteralPath $log -Value ('===== POST ' + (Get-Date -f 'HH:mm:ss') + ' ' + $c.Request.RawUrl + ' =====')
            Add-Content -LiteralPath $log -Value $body
            $b = [Text.Encoding]::UTF8.GetBytes('ok')
        } else {
            $name = [IO.Path]::GetFileName($c.Request.Url.LocalPath)
            $path = Join-Path $root $name
            if ($name -and (Test-Path -LiteralPath $path)) {
                $b = [IO.File]::ReadAllBytes($path)
                $c.Response.ContentType = 'application/octet-stream'
            } else {
                $c.Response.StatusCode = 404
                $b = [Text.Encoding]::UTF8.GetBytes('404')
            }
        }
        $c.Response.ContentLength64 = $b.Length
        $c.Response.OutputStream.Write($b, 0, $b.Length)
    } catch { Add-Content -LiteralPath $log -Value ('RELAY ERR ' + $_.Exception.Message) }
    finally { try { $c.Response.Close() } catch { } }
}
S 'listener closed'
