r"""_whea.py -- decode the 0x124 WHEA records from the three minidumps, offline.

Reads each dump header, then finds the CPER (WHEA_ERROR_RECORD) block the kernel
attached and decodes: severity, section types, and for processor/memory sections the
bank + MCI_STATUS + physical address.  Files only -- cannot touch the live box.
"""
import glob
import os
import struct

DUMPS = [p for p in (
    r"C:\Windows\Minidump\110826-9828-01.dmp",   # 03:54 crash
    r"C:\Windows\Minidump\110826-10125-01.dmp",  # 03:50
    r"C:\Windows\Minidump\110826-10062-01.dmp",  # 03:46
) if os.path.exists(p)]
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "_whea.txt")
lines = []


def say(s):
    lines.append(str(s))
    print(s, flush=True)
    with open(OUT, "a") as f:
        f.write(str(s) + "\n")


def guid_at(b, off):
    d1, d2, d3 = struct.unpack_from("<IHH", b, off)
    d4 = b[off + 8:off + 16]
    return ("%08X-%04X-%04X-%s-%s"
            % (d1, d2, d3, d4[:2].hex().upper(), d4[2:].hex().upper()))


SECTION_NAMES = {
    "9876CCAD-47B4-4BDB-B65E-16F193C4F3DB": "processor-generic",
    "DC3EA0B0-A144-4797-B95B-53FA242B6E1D": "ia32/x64-processor",
    "A5BC1114-6F64-4EDE-B863-3E83ED7C83B1": "memory-error",
    "D995E954-BBC1-430F-AD91-B44DCB3C6F35": "pcie",
    "81212A96-09ED-4996-9471-8D729C8E69F7": "firmware",
}
SEVERITY = {0: "recoverable", 1: "FATAL", 2: "corrected", 3: "informational"}

with open(OUT, "w") as f:
    f.write("")

for path in DUMPS:
    say("=" * 78)
    say("dump %s (%d bytes)" % (os.path.basename(path), os.path.getsize(path)))
    with open(path, "rb") as f:
        data = f.read()
    if data[:4] != b"PAGE" or data[4:8] not in (b"DU64", b"DUMP"):
        say("  not a kernel dump header (%r %r)" % (data[:4], data[4:8]))
        continue
    dtb = struct.unpack_from("<Q", data, 0x10)[0]
    bug = struct.unpack_from("<I", data, 0x38)[0]
    p1, p2, p3, p4 = struct.unpack_from("<4Q", data, 0x40)
    say("  bugcheck=%#x dtb=%#x" % (bug, dtb))
    say("  params: %#x %#x %#x %#x" % (p1, p2, p3, p4))
    say("  expected MCI_STATUS = %#018x" % ((p4 << 32) | p3))

    # find every CPER record (WHEA_ERROR_RECORD) in the dump
    n = 0
    off = 0
    while True:
        off = data.find(b"CPER", off)
        if off < 0:
            break
        off += 1
        if off < 0x80:
            continue
        base = off - 4                                  # record start
        try:
            rev, sigend, seccount = struct.unpack_from("<HHH", data, base + 4)
            severity, validbits, rlen = struct.unpack_from("<III", data, base + 10)
        except struct.error:
            continue
        if sigend != 0x5347 or not (0x80 <= rlen <= 0x4000):  # 'SG' + sane length
            continue
        n += 1
        say("  CPER #%d at %#x: severity=%d(%s) sections=%d len=%#x"
            % (n, base, severity, SEVERITY.get(severity, "?"), seccount, rlen))
        # section descriptors at +0x80, 32 bytes each
        for i in range(min(seccount, 16)):
            so = base + 0x80 + i * 32
            if so + 32 > len(data):
                break
            sec_off, sec_len, srev, sflags = struct.unpack_from("<II", data, so) + (0, 0)
            sec_off, sec_len = struct.unpack_from("<II", data, so)
            sg = guid_at(data, so + 16)
            name = SECTION_NAMES.get(sg, "?")
            say("    section %d: %s off=%#x len=%#x" % (i, name, sec_off, sec_len))
            sec = base + sec_off
            if sec + 16 > len(data):
                continue
            blob = data[sec:sec + min(sec_len, 128)]
            say("      hex: " + blob[:64].hex())
            # MCI_STATUS hunt: any qword equal to (p4<<32)|p3
            want = (p4 << 32) | p3
            for k in range(0, max(0, len(blob) - 8), 8):
                q = struct.unpack_from("<Q", blob, k)[0]
                if q == want:
                    say("      field +%#x == MCI_STATUS (bank-ish fields precede)" % k)
                    if k >= 8:
                        say("      prev qword %#x  prev word %#x"
                            % (struct.unpack_from("<Q", blob, k - 8)[0],
                               struct.unpack_from("<H", blob, k - 2)[0]))
            if name == "memory-error" and len(blob) >= 24:
                vb, estatus, pa = struct.unpack_from("<3Q", blob, 0)
                say("      valid=%#x errstatus=%#x pa=%#x" % (vb, estatus, pa))
    if n == 0:
        # triage dumps can put the record elsewhere; show header tail offsets
        say("  no CPER; searching for 0x80113a pattern ...")
        pat = struct.pack("<I", p4 & 0xFFFFFFFF)
        pos = 0
        hits = 0
        while hits < 5:
            pos = data.find(pat, pos)
            if pos < 0:
                break
            say("    %#x: context %s" % (pos, data[max(0, pos - 8):pos + 24].hex()))
            pos += 1
            hits += 1

say("")
say("done: %d dumps" % len(DUMPS))
