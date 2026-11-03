# ea_uia - drive the EA sign-in form through UI Automation instead of pixel clicks.
# The Qt surface ignores synthetic clicks without focusing; UIA SetFocus + Invoke is reliable.
# Stage 1 = email + NEXT, stage 2 = password + Sign in. Geometry-free.
param([int]$Stage = 1)
$rit = $PSScriptRoot
$o   = Join-Path $rit 'ea_uia.txt'
function W($t){ $t | Add-Content -LiteralPath $o; $t }
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

$email = 'kern30120@fldubai.com'
$pass  = '7sp0OTh5RBydZQ64j1vX!Q7z'

$ea = @(Get-Process EADesktop -EA SilentlyContinue)
if(-not $ea.Count){ 'EA not running'; exit 1 }
$pids = @($ea | ForEach-Object { $_.Id })
$cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $pids[0])
$root = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
if(-not $root){ 'EA automation root not found'; exit 1 }
$root.SetFocus()

function FindBy([string]$type, [string]$name){
  $c1 = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::$type)
  if($name){ $c2 = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $name); $c = New-Object System.Windows.Automation.AndCondition($c1, $c2) } else { $c = $c1 }
  return $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $c)
}
function Esc([string]$s){
  $sb = New-Object System.Text.StringBuilder
  foreach($ch in $s.ToCharArray()){ if('!+^%~(){}[]'.Contains($ch)){ [void]$sb.Append('{').Append($ch).Append('}') } else { [void]$sb.Append($ch) } }
  $sb.ToString()
}
function TypeInto($el, [string]$text){
  $el.SetFocus(); Start-Sleep -Milliseconds 350
  [System.Windows.Forms.SendKeys]::SendWait((Esc $text)); Start-Sleep -Milliseconds 350
}

W ("=== ea_uia stage $Stage " + (Get-Date -f 'HH:mm:ss') + ' ===')
$edits = @($root.FindAll([System.Windows.Automation.TreeScope]::Descendants,
  (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit))))
W ('edits found: ' + $edits.Count + ' (' + (($edits | ForEach-Object { $_.Current.Name }) -join ' | ') + ')')

if($Stage -eq 1){
  if($edits.Count -lt 1){ 'no edit control'; exit 1 }
  TypeInto $edits[0] $email
  $next = FindBy 'Button' 'NEXT'
  if(-not $next){ $next = FindBy 'Button' 'Next' }
  if($next){ $next.Invoke(); W 'invoked NEXT' } else { W 'NEXT not found' }
  Start-Sleep -Seconds 2
}
if($Stage -eq 2){
  $pw = $edits | Where-Object { $_.Current.Name -match 'password' } | Select-Object -First 1
  if(-not $pw){ $pw = $edits | Select-Object -Last 1 }
  TypeInto $pw $pass
  $go = FindBy 'Button' 'Sign in'
  if(-not $go){ $go = FindBy 'Button' 'SIGN IN' }
  if($go){ $go.Invoke(); W 'invoked Sign in' } else { [System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); W 'ENTER sent' }
  Start-Sleep -Seconds 4
}
W ('edits now: ' + (($edits | ForEach-Object { $_.Current.Name + '=' + $(try { $_.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value } catch { '?' }) }) -join ' | '))
& (Join-Path $rit 'small_shot.ps1') -Scale 0.5