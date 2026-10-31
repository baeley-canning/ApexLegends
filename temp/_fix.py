import io

p = "temp/scan_offsets.py"
txt = open(p, "r", newline="").read()
ls = txt.split("\r\n")
block = ls[195:229]          # misplaced apexdream signature block (comment .. last report)
del ls[193:230]              # remove it from inside find_all()
while ls and ls[-1] == "":
    ls.pop()
ls += ["", ""] + block
open(p, "w", newline="").write("\r\n".join(ls) + "\r\n")
print("moved %d lines" % len(block))
