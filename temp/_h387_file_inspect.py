"""Read the exact h387 file anchors; never opens the game or Gio."""
from pathlib import Path
import _h387_matrix_live as h

P = Path(r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe")
OUT = Path(__file__).with_name("_h387_file_inspect.txt")
pe = h.PE(P)
lines = ["file=%s" % pe.path, "idents stamp=%#x size=%#x raw_len=%#x" % (pe.stamp, pe.size, len(pe.data))]
for section in pe.sections:
    if section[1] <= h.ACCESSOR_RVA < section[1] + section[2]:
        lines.append("accessor_section=%s va=%#x vsize=%#x raw=%#x rawsz=%#x" % section)
    lines.append("section=%s va=%#x vsize=%#x raw=%#x rawsz=%#x" % section)
raw = pe.raw(h.ACCESSOR_RVA, 32)
lines.append("accessor=%#x raw=%s" % (h.ACCESSOR_RVA, raw.hex() if raw else None))
lines.append("at_vt=%#x bytes=%s" % (h.VT_RVA, pe.raw(h.VT_RVA, 16).hex()))
for va, section in ((0x20DA270, "trampoline"), (0x20DB0BE, "body"), (0x3D86100, "object")):
    b = pe.raw(va, 32)
    lines.append("%s=%#x bytes=%s" % (section, va, b.hex() if b else None))
if OUT.exists():
    raise RuntimeError("refusing overwrite: " + str(OUT))
OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
print(OUT)
