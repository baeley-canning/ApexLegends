import struct
p = r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe"
with open(p, "rb") as f:
    f.seek(0x3C)
    lf = struct.unpack("<I", f.read(4))[0]
    f.seek(lf + 4 + 2 + 2 + 4 + 4 + 4)          # skip sig, machine, nsec, ts, cksum, ptr
    opt_hdr_size = struct.unpack("<H", f.read(2))[0]
    f.seek(lf + 24 + 56)                        # optional header + SizeOfImage field
    size = struct.unpack("<I", f.read(4))[0]
with open(r"C:\Users\New User\OneDrive\Desktop\cheating\temp\r5_sizeofimage.txt", "w") as o:
    o.write("SizeOfImage=%#x (%.1f MB)\n" % (size, size / 1048576.0))
