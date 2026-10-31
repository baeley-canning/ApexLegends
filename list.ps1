$ErrorActionPreference = 'Continue'
$out = @()
foreach ($d in 'C:\Users\New User\OneDrive\Desktop\QwenKern\phase5_cpp_imgui', 'C:\Users\New User\OneDrive\Desktop\QwenKern\imgui_repo') {
    if (Test-Path $d) {
        Get-ChildItem -Path $d -Recurse -File | ForEach-Object { $out += $_.FullName }
    } else {
        $out += "MISSING: $d"
    }
}
$out | Out-File -FilePath 'C:\Users\New User\OneDrive\Desktop\cheating\tree.txt' -Encoding ascii
