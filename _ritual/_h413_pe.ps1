# static PE section table, no process needed
$exe = 'C:\Program Files\EA Games\Apex\r5apex_dx12.exe'
$fs = [IO.File]::OpenRead($exe)
$br = New-Object IO.BinaryReader($fs)
$fs.Position = 0x3C
$lfanew = $br.ReadInt32()
$fs.Position = $lfanew
$sig = $br.ReadUInt32()
$machine = $br.ReadUInt16()
$nsec = $br.ReadUInt16()
$tds = $br.ReadUInt32()
$fs.Position = $lfanew + 20
$optsz = $br.ReadUInt16()
$chars = $br.ReadUInt16()
$fs.Position = $lfanew + 24
$opt = $br.ReadBytes($optsz)
$magic = [BitConverter]::ToUInt16($opt, 0)
$sizeOfImage = [BitConverter]::ToUInt32($opt, 56)
$secStart = $lfanew + 24 + $optsz
"file=$exe"
"lfanew=0x{0:x} sig=0x{1:x8} machine=0x{2:x4} nsec={3} optsz={4} magic=0x{5:x4} sizeOfImage=0x{6:x}" -f $lfanew, $sig, $machine, $nsec, $optsz, $magic, $sizeOfImage
"name          vsize       vaddr       rawsize     rawptr"
for ($i = 0; $i -lt $nsec; $i++) {
    $fs.Position = $secStart + ($i * 40)
    $nameBytes = $br.ReadBytes(8)
    $name = [Text.Encoding]::ASCII.GetString($nameBytes).Trim([char]0)
    $vsize = $br.ReadUInt32()
    $vaddr = $br.ReadUInt32()
    $rawsize = $br.ReadUInt32()
    $rawptr = $br.ReadUInt32()
    "{0,-13} 0x{1:x8}  0x{2:x8}  0x{3:x8}  0x{4:x8}" -f $name, $vsize, $vaddr, $rawsize, $rawptr
}
$br.Close(); $fs.Close()
