# p25h.diag2.ps1 - UNELEVATED diagnostic: why did New-Cert2(...$true...) return nothing in p25g?
# Runs against Cert:\CurrentUser\My (no admin needed) and prints the EXACT exception per variant.
# No side effects on LocalMachine; all temp certs are removed at the end.
$o = Join-Path $PSScriptRoot 'p25h.diag2.txt'
Remove-Item -LiteralPath $o -ErrorAction SilentlyContinue
function W($t){ [void]([System.IO.File]::AppendAllText($o, [string]$t + "`r`n")) }

$store = 'Cert:\CurrentUser\My'
$MS2011 = 'CN=Microsoft Root Certificate Authority 2011, O=Microsoft Corporation, L=Redmond, S=Washington, C=US'
$made = @()
function Try-Make($tag,$sub,$useKU,$useTE,$kuVal){
  $p = @{ CertStoreLocation=$store; KeyExportPolicy='Exportable'; KeyAlgorithm='RSA'; KeyLength=2048
          HashAlgorithm='SHA256'; Subject=$sub; NotAfter=(Get-Date).AddYears(20); Type='Custom' }
  if($useTE){ $p.TextExtension = @('2.5.29.19={critical}{text}ca=1') }
  if($useKU){ $p.KeyUsage = $kuVal }
  $ev = $null
  try {
    $c = New-SelfSignedCertificate @p -ErrorVariable ev -ErrorAction Stop
    if($null -eq $c){
      W ("  {0}: RETURNED NOTHING (no throw). errvar=[{1}]" -f $tag, (($ev | ForEach-Object { $_.Exception.Message }) -join ' ; '))
    } else {
      $ku = '-'
      foreach($e in $c.Extensions){ if($e.Oid.Value -eq '2.5.29.15'){ $ku = $e.Format($false) } }
      W ("  {0}: OK thumb={1} subj='{2}' KU='{3}' notAfter={4}" -f $tag,$c.Thumbprint,$c.Subject,$ku,$c.NotAfter.ToString('yyyy-MM-dd'))
      $script:made += $c.Thumbprint
    }
  } catch {
    W ("  {0}: THREW -> {1} :: {2}" -f $tag,$_.Exception.GetType().Name,$_.Exception.Message)
  }
}

W ("=== p25h.diag2 {0} PS={1} ===" -f (Get-Date -f 'dd/MM/yyyy HH:mm:ss'),$PSVersionTable.PSVersion)

W '-- A: is $var::Static supported in this PS host? --'
$KU = [System.Security.Cryptography.X509Certificates.X509KeyUsageFlags]
try { $v = $KU::KeyCertSign; W ("   \$KU::KeyCertSign = {0} (type {1})" -f $v,$v.GetType().FullName) } catch { W ("   \$KU::KeyCertSign THREW -> " + $_.Exception.Message) }
try { $b = ($KU::KeyCertSign -bor $KU::CrlSign); W ("   KeyCertSign|CrlSign = {0} (int {1})" -f $b,[int]$b) } catch { W ("   -bor expression THREW -> " + $_.Exception.Message) }

W '-- B: parameter matrix (the p25g root call + isolates) --'
Try-Make 'V1-exact-p25g'      $MS2011                       $true  $true  $(try{ ($KU::KeyCertSign -bor $KU::CrlSign) }catch{ $null })
Try-Make 'V2-bare-custom'     $MS2011                       $false $false $null
Try-Make 'V3-ca1-only'        $MS2011                       $false $true  $null
Try-Make 'V4-ku-strings'      $MS2011                       $true  $true  @('CertSign','CRLSign')
Try-Make 'V5-short-subject'   'CN=S10plain (QwenKern)'      $true  $true  $(try{ ($KU::KeyCertSign -bor $KU::CrlSign) }catch{ $null })
Try-Make 'V6-no-S-token'      'CN=Microsoft Root Certificate Authority 2011, O=Microsoft Corporation, C=US' $true $true @('CertSign','CRLSign')
Try-Make 'V7-ou-copyright'    'CN=Microsoft Root Authority, OU=Microsoft Corporation, OU=Copyright (c) 1997 Microsoft Corp.' $true $true @('CertSign','CRLSign')

W '-- C: extra subject-token isolates (find the offending RDN) --'
Try-Make 'V8-ooo-order'       'C=US, S=Washington, L=Redmond, O=Microsoft Corporation, CN=Microsoft Root Certificate Authority 2011' $false $true $null
Try-Make 'V9-just-S'          'CN=S11s (QwenKern), S=Washington' $false $true $null
Try-Make 'V10-just-L'         'CN=S11l (QwenKern), L=Redmond'    $false $true $null

W '-- D: cleanup --'
foreach($t in $script:made){ try { Remove-Item -LiteralPath ($store + '\' + $t) -Force -ErrorAction Stop; W ("   removed {0}" -f $t) } catch { W ("   remove FAILED {0}: {1}" -f $t,$_.Exception.Message) } }
W '-- done --'
