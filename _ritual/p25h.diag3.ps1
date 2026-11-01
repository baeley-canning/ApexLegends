# p25h.diag3.ps1 - UNELEVATED: prove the EXACT -KeyUsage spelling that binds.
# facts: diag2 V1 (X509KeyUsageFlags value) THREW ; V4/V6/V7 (@('CertSign','CRLSign')) OK ;
#        p25h.ps1 used the JOINED STRING 'CertSign,CRLSign' -> THREW.
# hypothesis: KeyUsage param is an ARRAY (KeyUsage[]), each element must be one valid enum name;
#             a comma-joined string is ONE element and the enum has no [Flags] -> parse fails.
$o = Join-Path $PSScriptRoot 'p25h.diag3.txt'
Remove-Item -LiteralPath $o -ErrorAction SilentlyContinue
function W($t){ [void]([System.IO.File]::AppendAllText($o, [string]$t + "`r`n")) }
$store = 'Cert:\CurrentUser\My'
$made = @()
$base = @{ CertStoreLocation=$store; KeyExportPolicy='Exportable'; KeyAlgorithm='RSA'; KeyLength=2048
           HashAlgorithm='SHA256'; Subject='CN=p25h diag3 X (QwenKern)'; NotAfter=(Get-Date).AddYears(20)
           Type='Custom'; TextExtension=@('2.5.29.19={critical}{text}ca=1') }
function Try-Form($tag,$direct,$ku){
  $ev = $null; $c = $null
  try {
    $b = @{}; foreach($k in $base.Keys){ $b[$k] = $base[$k] }
    if($direct){ $c = New-SelfSignedCertificate @b -KeyUsage $ku -ErrorVariable ev -ErrorAction Stop }
    else { $b.KeyUsage = $ku; $c = New-SelfSignedCertificate @b -ErrorVariable ev -ErrorAction Stop }
  } catch {
    W ("  {0,-26} {1} THREW -> {2}" -f $tag,$(if($direct){'direct'}else{'splat '}),($_.Exception.Message -replace '\s+',' ')); return
  }
  if($null -eq $c){ W ("  {0,-26} {1} RETURNED NULL errvar=[{2}]" -f $tag,$(if($direct){'direct'}else{'splat '}),(($ev|ForEach-Object{$_.Exception.Message}) -join '; ')); return }
  $ku = '-'; foreach($e in $c.Extensions){ if($e.Oid.Value -eq '2.5.29.15'){ $ku = [BitConverter]::ToString($e.RawData) } }
  W ("  {0,-26} {1} OK KU={2} thumb={3}" -f $tag,$(if($direct){'direct'}else{'splat '}),$ku,$c.Thumbprint)
  $script:made += $c.Thumbprint
}
function Cleanup { foreach($t in $script:made){ Remove-Item -LiteralPath ($store + '\' + $t) -Force -ErrorAction SilentlyContinue } }

W ("=== p25h.diag3 {0} PS={1} ===" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'),$PSVersionTable.PSVersion)

W '-- A: parameter type metadata --'
$pt = $null
try { $pt = (Get-Command New-SelfSignedCertificate).Parameters['KeyUsage'].ParameterType } catch { W ('   lookup THREW -> ' + $_.Exception.Message) }
if($pt){
  W ("   KeyUsage ParameterType   = {0}" -f $pt.FullName)
  W ("   isArray={0}  isEnum={1}  hasFlagsAttr={2}" -f $pt.IsArray,$pt.IsEnum,[bool]($pt.GetCustomAttributes([FlagsAttribute],$false).Count))
  $et = if($pt.IsArray){ $pt.GetElementType() } else { $pt }
  W ("   elementType={0} elementIsEnum={1}" -f $et.FullName,$et.IsEnum)
  W ("   enumNames=[{0}]" -f ([System.Enum]::GetNames($et) -join ','))
  W ("   Enum.Parse('CertSign,CRLSign') -> {0}" -f $(try{ [System.Enum]::Parse($et,'CertSign,CRLSign'); 'OK' }catch{ 'THREW ' + $_.Exception.Message.Substring(0,[Math]::Min(90,$_.Exception.Message.Length)) }))
}

W '-- B: spelling matrix (the SAME string p25h.ps1 used, plus every neighbour) --'
Try-Form 'T1 joined-string'      $false 'CertSign,CRLSign'
Try-Form 'T2 array-strings'      $false @('CertSign','CRLSign')
Try-Form 'T3 array-lowercase'    $false @('certsign','crlsign')
Try-Form 'T4 array-wrongcase'    $false @('CertSign','CrlSign')
Try-Form 'T5 single CertSign'    $false 'CertSign'
Try-Form 'T6 single CRLSign'     $false 'CRLSign'
Try-Form 'T7 array-3elem'        $false @('CertSign','CRLSign','DigitalSignature')
Try-Form 'T8 direct-joinedstr'   $true  'CertSign,CRLSign'
Try-Form 'T9 direct-array'       $true  @('CertSign','CRLSign')
Try-Form 'T10 enum-int'          $false 6

W '-- C: leaf spelling control (DigitalSignature, ca=0) --'
W ("   leaf KU param form that p25h.ps1 uses = 'DigitalSignature' (single name, no comma)")
Try-Form 'T11 leaf singlesign'   $false 'DigitalSignature'

W '-- D: cleanup --'
Cleanup
W '-- done --'
