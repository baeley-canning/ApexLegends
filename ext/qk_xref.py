r"""qk_xref.py -- offline PE retargeting (PLAN 19/11 item 2, offline half).

WHY: the boot-vintage offset records disagree and each was taken from a
DIFFERENT boot of the binary.  Before the next `--find-array` splash shot,
the on-disk PE is the one artefact every vintage shares: parse ITS section
map, drop each candidate RVA into .text / .data-initialised /
.data-zero-tail / out-of-image, and reconcile against temp\qk_offsets.txt.

Candidates cross-checked:
  vp_rva(qk_offsets)  0xB88BCB0     (temp\qk_offsets.txt)
  vp_static(handoff)  0xDB5BC40     (HANDOFF 08/11 static note)
  view_ini(ini)       0x11A350      (v3.0.2.23 ini; FACTS: .text rva -> instr bytes)
Positive control: the parsed section map must reproduce the 18/11 measured
shape (9 sections, SizeOfImage 0xDFB8000, .text 0x1000/0x2CA2B7C,
.data 0x334C000 vsize 0xAB23AAC) else the installed binary changed and every
historic RVA is suspect (verdict says so).

Zero kernel calls, zero elevation, game-independent.  Out: temp\qk_xref_out.txt.
"""
import os
import struct
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TMP = os.path.join(ROOT, "temp")
OUT = os.path.join(TMP, "qk_xref_out.txt")

_POS_CTRL = {"sections": 9, "sizeofimage": 0xDFB8000,
             "text": (0x1000, 0x2CA2B7C),
             "data": (0x334C000, 0xAB23AAC)}

_PE_SEARCH = [
    r"C:\Program Files\EA Games\Apex\r5apex_dx12.exe",
    r"C:\Program Files (x86)\Steam\steamapps\common\Apex Legends\r5apex_dx12.exe",
    r"C:\Program Files\EA Games\Apex Legends\r5apex_dx12.exe",
    r"C:\Program Files\Electronic Arts\Apex Legends\r5apex_dx12.exe",
    r"C:\Program Files (x86)\Origin Games\Apex Legends\r5apex_dx12.exe",
]

_lines = []


def out(s):
    _lines.append(str(s))


def read_offsets_vp():
    try:
        with open(os.path.join(TMP, "qk_offsets.txt"), encoding="utf-8") as f:
            for ln in f:
                if ln.strip().startswith("vp_rva="):
                    return int(ln.strip().split("=", 1)[1], 16)
    except (OSError, ValueError):
        pass
    return None


def find_pe():
    """Installed game binary; filesystem probing only."""
    roots = []
    pf86 = os.environ.get("ProgramFiles(x86)")
    pf = os.environ.get("ProgramFiles")
    if pf86:
        roots.append(os.path.join(pf86, "Steam", "steamapps", "common"))
    if pf:
        roots.append(os.path.join(pf, "EA Games"))
        roots.append(os.path.join(pf, "EA"))
        roots.append(os.path.join(pf, "Electronic Arts"))
    hits = list(_PE_SEARCH)
    for r in roots:
        if os.path.isdir(r):
            base = os.path.join(r, "Apex Legends")
            if os.path.isdir(base):
                hits.append(os.path.join(base, "r5apex_dx12.exe"))
    for h in hits:
        if h and os.path.isfile(h):
            return h
    return None


def parse_pe(path):
    with open(path, "rb") as f:
        dos = f.read(0x40)
        if dos[:2] != b"MZ":
            raise ValueError("no MZ (first bytes %s)" % dos[:16].hex())
        e_lfanew = struct.unpack_from("<I", dos, 0x3C)[0]
        f.seek(e_lfanew)
        pe = f.read(24)                       # sig + COFF header
        if pe[:4] != b"PE\x00\x00":
            raise ValueError("no PE sig at e_lfanew=%#x (bytes %s)"
                             % (e_lfanew, pe[:16].hex()))
        machine, nsec = struct.unpack_from("<HH", pe, 4)
        optsz = struct.unpack_from("<H", pe, 20)[0]   # measured pe+20 (direct byte dump 20/11)
        rest = f.read(optsz + 40 * nsec)      # optional header + section table, contiguous
        opt = rest[:optsz]
        sect_raw = rest[optsz:]
        magic = struct.unpack_from("<H", opt, 0)[0] if len(opt) >= 2 else 0
        if magic != 0x20B:
            raise ValueError(
                "not PE32+ (magic=%#x optsz=%#x coff=%s)" %
                (magic, optsz, pe[4:24].hex()))
        size_of_image = struct.unpack_from("<I", opt, 56)[0]
        sect_tab = []
        for i in range(nsec):
            name = sect_raw[i * 40:i * 40 + 8].rstrip(b"\x00").decode("latin1")
            vsize, vaddr, rawsz, rawptr = struct.unpack_from("<IIII", sect_raw, i * 40 + 8)
            sect_tab.append({"name": name, "vaddr": vaddr, "vsize": vsize,
                             "rawsz": rawsz, "rawptr": rawptr})
        return machine, size_of_image, sect_tab, nsec


def classify(sect, rva, sizeofimg):
    for s in sect:
        if s["vaddr"] <= rva < s["vaddr"] + s["vsize"]:
            if s["name"].startswith(".data"):
                file_end = s["vaddr"] + s["rawsz"]
                zone = ("initialised(file-backed)" if rva < file_end
                        else "zero-tail(uninitialised)")
                return ".data/%s" % zone
            return s["name"]
    if 0 <= rva < sizeofimg:
        return "in-image(section-gap)"
    return "OUT-OF-IMAGE"


def main():
    out("=== qk_xref v1 (offline on-disk PE retarget; %s) ==="
        % time.strftime("%Y-%m-%d %H:%M:%S"))
    rc = 0
    try:
        pe = find_pe()
        if not pe:
            out("Searched default Steam/EA/Origin locations; none held the binary.")
            out("RESULT: no-pe-found")
            out("VERDICT: XREF_V1 BLOCKED_NO_BINARY")
            rc = 2
            return rc
        out("pe=%s" % pe)
        try:
            machine, sizeofimg, sect, nsec = parse_pe(pe)
        except (OSError, ValueError) as e:
            out("RESULT: parse-failed (%s)" % e)
            out("VERDICT: XREF_V1 PARSE_FAIL")
            rc = 5
            return rc
        out("machine=%#06x sections=%d sizeofimage=%#x" % (machine, nsec, sizeofimg))
        for s in sect:
            out("  %-8s vaddr=%#010x vsize=%#010x rawsz=%#010x"
                % (s["name"], s["vaddr"], s["vsize"], s["rawsz"]))
        txt = next((s for s in sect if s["name"].startswith(".text")), None)
        dat = next((s for s in sect if s["name"].startswith(".data")), None)
        ctrl_ok = (nsec == _POS_CTRL["sections"]
                   and sizeofimg == _POS_CTRL["sizeofimage"]
                   and txt is not None and (txt["vaddr"], txt["vsize"]) == _POS_CTRL["text"]
                   and dat is not None and (dat["vaddr"], dat["vsize"]) == _POS_CTRL["data"])
        out("PC_SECTIONSHAPE_MATCH=%s (18/11 positive control)" % ctrl_ok)
        cands = [("vp_static_handoff", 0xDB5BC40, "HANDOFF 08/11"),
                 ("view_ini_text", 0x11A350, "ini v3.0.2.23")]
        vpr = read_offsets_vp()
        if vpr is not None:
            cands.insert(0, ("vp_rva_qk_offsets", vpr, "temp\\qk_offsets.txt"))
        recon = {}
        for key, rva, origin in cands:
            cls = classify(sect, rva, sizeofimg)
            recon[key] = cls
            out("  %-18s rva=%#010x (%s) -> %s" % (key, rva, origin, cls))
        v_new = recon.get("vp_rva_qk_offsets")
        v_old = recon.get("vp_static_handoff")
        differ = (v_new is not None and v_old is not None and v_new != v_old)
        out("RECON vp offsets land in different zones across vintages: %s" % differ)
        if not ctrl_ok:
            out("RESULT: section-shape drift vs 18/11 control")
            out("VERDICT: XREF_V1 TABLE_DRIFT_BINARY_CHANGED")
            rc = 4
        elif differ:
            out("RESULT: reconciled table above; --find-array arbitrates on splash")
            out("VERDICT: XREF_V1 RECON_REQUIRED")
            rc = 3
        else:
            out("RESULT: candidates classified; no vintage drift detected")
            out("VERDICT: XREF_V1 CLEAN")
        return rc
    finally:
        with open(OUT, "w", encoding="utf-8") as f:
            f.write("\n".join(_lines) + "\n")
        for ln in _lines:
            print(ln)


if __name__ == "__main__":
    sys.exit(main())
