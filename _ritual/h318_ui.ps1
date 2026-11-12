# h318_ui.ps1 - list the real controls of a window via UI Automation (names + rectangles), so clicks
# can be aimed instead of guessed. Read-only.
param([Parameter(Mandatory = $true)][string]$ProcName)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$p = @(Get-Process $ProcName -EA 0 | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
if (-not $p) { 'no window'; exit 1 }
$root = [System.Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
"window=[" + $root.Current.Name + "] class=" + $root.Current.ClassName
$cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)
$btns = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
"buttons=" + $btns.Count
foreach ($b in $btns) {
    $r = $b.Current.BoundingRectangle
    ('  btn [' + $b.Current.Name + '] @ ' + [int]($r.X + $r.Width / 2) + ',' + [int]($r.Y + $r.Height / 2) + ' enabled=' + $b.Current.IsEnabled)
}
$tcond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Text)
$txt = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $tcond)
$i = 0
foreach ($t in $txt) { if ($t.Current.Name -and $i -lt 12) { '  txt [' + $t.Current.Name + ']'; $i++ } }
