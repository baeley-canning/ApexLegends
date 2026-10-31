import os, struct, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import namehunt as nh

path = os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), "System32", "ntdll.dll")
data = open(path, "rb").read()
e = struct.unpack_from("<I", data, 0x3C)[0]
nt = e + 4
nsec = struct.unpack_from("<H", data, nt + 4)[0]
optsz = struct.unpack_from("<H", data, nt + 20)[0]
opt = nt + 24
magic = struct.unpack_from("<H", data, opt)[0]
secs, opt2 = nh._sections(data)
print("size", len(data), "e", hex(e), "nsec", nsec, "optsz", hex(optsz),
      "opt", hex(opt), "opt2", hex(opt2), "magic", hex(magic))
dd = opt + (0x70 if magic == 0x20B else 0x60)
print("ddoff", hex(dd), "edir_rva", hex(struct.unpack_from("<I", data, dd)[0]))
print("sections", [(hex(a), hex(s), hex(r)) for a, s, r in secs][:6])
print("eoff", hex(nh._off(secs, struct.unpack_from("<I", data, dd)[0]) or 0))
print("rva NtRVM", nh.disk_export_rva(path, "NtReadVirtualMemory"))
print("ssn", nh.disk_export(path, "NtReadVirtualMemory"))
