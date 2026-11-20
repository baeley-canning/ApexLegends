Get-ChildItem -Path 'C:\Users\New User\OneDrive\Desktop\QwenKern\phase5_cpp_imgui' -Recurse |
  Where-Object { $_.PSIsContainer } |
  Select-Object FullName |
  Out-File -FilePath 'C:\Users\New User\OneDrive\Desktop\cheating\p5_dirs.txt' -Encoding ascii

Get-ChildItem -Path 'C:\Users\New User\OneDrive\Desktop\QwenKern\phase5_cpp_imgui' -Recurse -File |
  Select-Object FullName, Length |
  Out-File -FilePath 'C:\Users\New User\OneDrive\Desktop\cheating\p5_files.txt' -Encoding ascii
