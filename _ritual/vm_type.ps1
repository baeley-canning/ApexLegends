param([string[]]$Seq = @())
# vm_type.ps1 - type into the VM console via VBoxManage keyboardputscancode.
# Works on a headless VM with NO guest additions.  -Seq is a list of tokens: any
# token matching a special name sends that key, any other token is typed literally.
#   specials: space enter tab esc winr win cad alty alt ctrl shift del
$VB  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'
$VM  = 'Win11-Test2'
$log = 'C:\Users\New User\OneDrive\Desktop\cheating\_ritual\vm_type.txt'
function Say($t) { $t | Out-File -FilePath $log -Encoding ascii -Append }

$tbl = @'
a 1e
b 30
c 2e
d 20
e 12
f 21
g 22
h 23
i 17
j 24
k 25
l 26
m 32
n 31
o 18
p 19
q 10
r 13
s 1f
t 14
u 16
v 2f
w 11
x 2d
y 15
z 2c
1 02
2 03
3 04
4 05
5 06
6 07
7 08
8 09
9 0a
0 0b
minus 0c
equals 0d
lbracket 1a
rbracket 1b
semi 27
quote 28
grave 29
bslash 2b
comma 33
dot 34
fslash 35
space 39
'@
$mk = @{}
foreach ($line in ($tbl -split "`n")) {
    $p = ($line.Trim() -split '\s+')
    if ($p.Count -eq 2) { $mk[$p[0]] = $p[1] }
}
# char -> key name (unshifted)
$cmap = @{
    ' ' = 'space'; '\' = 'bslash'; '/' = 'fslash'; '.' = 'dot'; ',' = 'comma'; '-' = 'minus'
    '=' = 'equals'; '[' = 'lbracket'; ']' = 'rbracket'; ';' = 'semi'; "'" = 'quote'; '`' = 'grave'
}
# char -> key name that needs SHIFT, and char -> key name that needs SHIFT with a mapped symbol
$smap = @{
    ':' = 'semi'; '_' = 'minus'; '+' = 'equals'; '{' = 'lbracket'; '}' = 'rbracket'; '"' = 'quote'
    '~' = 'grave'; '|' = 'bslash'; '<' = 'comma'; '>' = 'dot'; '?' = 'fslash'; '(' = '9'; ')' = '0'
    '!' = '1'; '@' = '2'; '#' = '3'; '$' = '4'; '%' = '5'; '^' = '6'; '&' = '7'; '*' = '8'
}
$specials = @{
    'space' = @('39', 'b9'); 'enter' = @('1c', '9c'); 'tab' = @('0f', '8f'); 'esc' = @('01', '81')
    'winr'  = @('e0', '5b', 'e0', 'db', '13', '93')
    'win'   = @('e0', '5b', 'e0', 'db')
    'cad'   = @('1d', '38', '53', 'd3', 'b8', '9d')
    'alty'  = @('38', '15', '95', 'b8')
    'alt'   = @('38', 'b8'); 'ctrl' = @('1d', '9d'); 'shift' = @('2a', 'aa'); 'del' = @('e0', '53', 'e0', 'd3')
}

function SendCodes([string[]]$codes) {
    if ($codes.Count -eq 0) { return }
    $r = (& $VB controlvm $VM keyboardputscancode @codes 2>&1)
    Say ("  send {0} {1}" -f ($codes -join ' '), ($(if ($r) { 'ERR:' + ($r -join ' ') } else { 'ok' })))
}

function SendText([string]$text) {
    foreach ($ch in $text.ToCharArray()) {
        $s = [string]$ch
        $shift = $false
        if ($s -cmatch '^[A-Z]$') { $key = $s.ToLower(); $shift = $true }
        elseif ($cmap.ContainsKey($s)) { $key = $cmap[$s] }
        elseif ($smap.ContainsKey($s)) { $key = $smap[$s]; $shift = $true }
        elseif ($mk.ContainsKey($s)) { $key = $s }
        else { Say ("  ?? unknown char '" + $s + "'"); continue }
        $make = $mk[$key]
        if (-not $make) { Say ("  ?? no scancode for key $key"); continue }
        $brk = '{0:x2}' -f ([Convert]::ToInt32($make, 16) -bor 0x80)
        $codes = New-Object System.Collections.ArrayList
        if ($shift) { [void]$codes.Add('2a') }
        [void]$codes.Add($make); [void]$codes.Add($brk)
        if ($shift) { [void]$codes.Add('aa') }
        SendCodes $codes.ToArray()
        Start-Sleep -Milliseconds 40
    }
}

Say ("== vm_type {0}  seq=[{1}]" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'), ($Seq -join ' | '))
foreach ($tok in $Seq) {
    if ($specials.ContainsKey($tok)) {
        Say ("  token '{0}' = special" -f $tok)
        SendCodes $specials[$tok]
        Start-Sleep -Milliseconds 150
    } else {
        Say ("  token '{0}' = text" -f $tok)
        SendText $tok
    }
}
Say '== done'
