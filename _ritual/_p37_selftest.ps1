$ErrorActionPreference = 'Stop'
Add-Type -Path (Join-Path $PSScriptRoot 'p37_prov.cs')
'compiled OK'
[P37Prov]::SetBadRanges('0-200000,200000-400000')
[P37Prov]::SetRamRanges('1000-9e000,9f000-a0000,100000-31f52000', 0x800000000)
function T([string]$n, $v) { '{0,-34} = {1}' -f $n, $v }
T 'bulk span 0x1000/1M cross-end (want False)' ([P37Prov]::InRamSpan([uint64]0x1000, 0x100000))
T 'probe 0x1000/32 in-range (want True)' ([P37Prov]::InRamSpanNoBad([uint64]0x1000, 32))
T 'bulk 0x200000/64K in blacklist (want False)' ([P37Prov]::InRamSpan([uint64]0x200000, 0x10000))
T 'probe 0x200000/64K bypass (want True)' ([P37Prov]::InRamSpanNoBad([uint64]0x200000, 0x10000))
T 'bulk 0x400000/64K clean (want True)' ([P37Prov]::InRamSpan([uint64]0x400000, 0x10000))
T 'bulk 0x3ff000/64K straddles bad end (want False)' ([P37Prov]::InRamSpan([uint64]0x3FF000, 0x10000))
T 'InRam 0x1000 blacklisted (want False)' ([P37Prov]::InRam([uint64]0x1000))
$sw = New-Object System.IO.StringWriter
[P37Prov]::Notify = [P37Prov+Note] { param([string]$s) $sw.WriteLine($s) }
foreach ($pa in @(0x400000L, 0x401000L, 0x600000L)) {
    try { $null = [P37Prov]::GdrvProbe([IntPtr]::Zero, [uint64]$pa, 64) } catch { }
}
'--- notify records (expect 2: 0x400000 then 0x600000, same block deduped):'
$sw.ToString()

# --- regression: a hand-edit slip must never shrink the blacklist silently ----
[P37Prov]::SetBadRanges('127c00000-14000000')          # dropped trailing zero on purpose
T 'inverted pair kept (want 1)' ([P37Prov]::BadStarts.Length)
T 'start as written 0x127c00000' ('{0:x}' -f [P37Prov]::BadStarts[0])
T 'end rebuilt to 0x140000000' ('{0:x}' -f [P37Prov]::BadEnds[0])
T 'repaired count (want 1)' ([P37Prov]::BadRepaired)
T 'IsBad 0x128000000/64K (want True)' ([P37Prov]::IsBad([uint64]0x128000000, 0x10000))
T 'IsBad last page 0x13ffff000/4K (want True)' ([P37Prov]::IsBad([uint64]0x13FFFF000, 0x1000))
T 'IsBad at end 0x140000000/4K (want False)' ([P37Prov]::IsBad([uint64]0x140000000, 0x1000))
T 'bytes of repaired span (want 406847488)' ([P37Prov]::BlacklistedBytes())
[P37Prov]::SetBadRanges('500000-600000,junk,700000-700000,900000-800000')
T 'rejected (junk + degenerate; want 2)' ([P37Prov]::BadRejected)
T 'sorted first start 0x500000' ('{0:x}' -f [P37Prov]::BadStarts[0])
T 'sorted second start 0x800000' ('{0:x}' -f [P37Prov]::BadStarts[1])
T 'bytes 0x500000-0x900000 2x1M (want 2097152)' ([P37Prov]::BlacklistedBytes())
