function F(){ return $true }
if(F()){ 'a1' } else { 'b1' }
if(F){ 'a2' } else { 'b2' }
$x = F()
$y = F
if((F()) -and $true){ 'a3' }
if((F) -and $true){ 'a4' }
$s2 = "v={0}" -f (F())
$s3 = "v={0}" -f (F)
