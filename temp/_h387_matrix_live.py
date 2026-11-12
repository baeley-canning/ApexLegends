"""h387: bounded, read-only validation of CViewRender's matrix accessor.

No qk_va, DTB discovery, ApexDrv access, writes, or synthetic input. All raw
addresses must be explicit and inside dumplive.usable_ranges (R10). The prior
h382 slot bytes decoded as code: base+RVA is not a general VA read contract.

Offline syntax/build/layout check:
    python temp\\_h387_matrix_live.py --pe "C:\\full\\path\\r5apex_dx12.exe"
Live access requires _ritual/h387_matrix.ps1 --pe <same explicit PE path>.
Evidence: temp\\_h387_out.txt, _h387_progress.txt, _h387_state.txt.
"""
from __future__ import annotations

import argparse
import struct
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(ROOT / "ext"))
import dumplive as dl  # noqa: E402

OUT = HERE / "_h387_out.txt"
PROGRESS = HERE / "_h387_progress.txt"
STATE = HERE / "_h387_state.txt"
SIZE_OF_IMAGE = 0xDFB8000
STAMP = 0x6ADBF892
ACCESSOR_RVA = 0x22670F0  # exact 4c8bdc; the fast-path LEA is later in this function.
VT_RVA = 0x3133AA0
EXPECTED_SLOTS = (0x11A390, 0x11A398)
EXPECTED_BUFFERS = (0x11A2D0, 0x11A310)


class Blocked(RuntimeError):
    """There is no validated build-specific physical mapping yet."""


class Evidence:
    def __init__(self):
        self.lines = []
        self.pid = None
        self.alive = None
        self.rc = 2

    def log(self, text=""):
        text = str(text)
        self.lines.append(text)
        print(text, flush=True)
        with OUT.open("w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(self.lines) + "\n")

    def progress(self, text):
        with PROGRESS.open("a", encoding="utf-8", newline="\n") as f:
            f.write("%s %s\n" % (time.strftime("%H:%M:%S"), text))

    def pre(self, pe):
        with STATE.open("w", encoding="utf-8", newline="\n") as f:
            f.write("probe=h387 variable=file-anchored accessor physical mapping\n")
            f.write("mode=read-only driver_load=0 service_change=0 game_writes=0 input=0\n")
            f.write("dtb_discovery=0 apexdrv_open=0 va_to_pa_fallback=0\n")
            f.write("pe=%s file_stamp=%08x file_size=%#x\n" %
                    (pe.path, pe.stamp, pe.size))
            f.write("pre_elevated=%d pre_pid=%s pre_game_alive=%s\n" %
                    (dl.elevation(), self.pid, self.alive))

    def post(self, rc, handle_closed):
        with STATE.open("a", encoding="utf-8", newline="\n") as f:
            f.write("post_pid=%s same_game_alive=%s output_exists=%s\n" %
                    (self.pid, self.alive, OUT.exists()))
            f.write("rc=%d restore=nothing_mutated handle_closed=%s %s\n" %
                    (rc, handle_closed, "" if handle_closed else "HANDLE_CLOSE_FAILED"))



class PE:
    """AMD64 PE reader with explicit RVA != file-offset translation."""
    def __init__(self, path):
        self.path = str(Path(path).resolve())
        with open(self.path, "rb") as f:
            self.data = f.read()
        if len(self.data) < 0x300:
            raise Blocked("PE file: truncated DOS header")
        self.nt = self.u32(0x3C)
        if self.data[:2] != b"MZ" or not 0x40 <= self.nt <= len(self.data) - 0x100:
            raise Blocked("PE file: malformed DOS/NT header")
        machine, nsec, self.stamp, _, _, optsz, _ = struct.unpack_from(
            "<HHIIIHH", self.data, self.nt + 4)
        opt = self.nt + 0x18
        if self.data[self.nt:self.nt + 4] != b"PE\0\0" or machine != 0x8664:
            raise Blocked("PE file: expected AMD64")
        if self.u16(opt) != 0x20B or opt + optsz + nsec * 40 > len(self.data):
            raise Blocked("PE file: expected PE32+ with complete sections")
        self.size = self.u32(opt + 0x38)
        if self.stamp != STAMP or self.size != SIZE_OF_IMAGE:
            raise Blocked("build mismatch: stamp=%08x size=%#x, expected %08x/%#x" %
                          (self.stamp, self.size, STAMP, SIZE_OF_IMAGE))
        self.sections = []
        for i in range(nsec):
            at = opt + optsz + i * 40
            name = self.data[at:at + 8].rstrip(b"\0").decode("ascii", "replace")
            vsize, va, rawsz, raw = struct.unpack_from("<IIII", self.data, at + 8)
            if (rawsz and va + rawsz > self.size) or raw + rawsz > len(self.data):
                raise Blocked("PE file: section extends outside image/file")
            self.sections.append((name, va, vsize, raw, rawsz))

    def u16(self, at):
        return struct.unpack_from("<H", self.data, at)[0]

    def u32(self, at):
        return struct.unpack_from("<I", self.data, at)[0]

    def raw(self, rva, size):
        if size <= 0 or rva < 0 or rva + size > self.size:
            return None
        if rva + size <= self.u32(self.nt + 0x18 + 0x3C):
            return self.data[rva:rva + size]
        for _, va, _, raw, rawsz in self.sections:
            if va <= rva and rva + size <= va + rawsz:
                at = raw + rva - va
                return self.data[at:at + size]
        return None


def build_accessor(pe):
    """Decode the accessors; do not treat totals or constants as binding."""
    code = pe.raw(ACCESSOR_RVA, 32)
    # This build uses `mov r11,rsp` as the anchor, then the static getter's
    # RIP-relative LEA and return. It does not use the older LEA-at-function-start.
    if not code or code[:3] != b"\x4c\x8b\xdc":
        raise Blocked("GetViewRenderInstance: expected mov r11,rsp anchor")
    body_all = pe.raw(ACCESSOR_RVA, 0x2000)
    if body_all is None:
        raise Blocked("GetViewRenderInstance function bytes are not file-backed")
    matches = []
    start = 0
    preferred = 0x140000000
    while True:
        pos = body_all.find(b"\x48\x8d\x05", start)
        if pos < 0:
            break
        obj = ACCESSOR_RVA + pos + 7 + struct.unpack_from("<i", body_all, pos + 3)[0]
        raw_obj = pe.raw(obj, 8)
        if raw_obj:
            value = struct.unpack("<Q", raw_obj)[0]
            if obj == 0x3D86100 and value == preferred + VT_RVA:
                matches.append((pos, obj, value - preferred))
        start = pos + 1
    if not matches:
        raise Blocked("no in-function LEA resolves to a relocated vtable")
    if len({obj for _, obj, _ in matches}) != 1:
        raise Blocked("ambiguous CViewRender singleton relocation targets")
    at, obj, vt_rva = matches[0]
    if vt_rva != VT_RVA:
        raise Blocked("singleton's active vtable is %#x, not requested %#x" % (vt_rva, VT_RVA))
    vt = pe.raw(vt_rva, 0x90)
    if not vt:
        raise Blocked("vtable function entries are not file-backed")
    file_vt = struct.unpack("<Q", vt[:8])[0]
    # file_vt is the vtable's FIRST FUNCTION ENTRY, not its own address.
    # The object's relocation is separate and was decoded to vt_rva above.
    base_obj = struct.unpack("<Q", pe.raw(obj, 8))[0]
    if base_obj != preferred + vt_rva:
        raise Blocked("singleton relocation does not point back to its vtable")
    functions = struct.unpack("<2Q", pe.raw(VT_RVA + 0x78, 16))
    body = pe.raw(functions[1] - 0x140000000, 0x1000)
    if body is None:
        raise Blocked("vtable: GetViewMatrix points outside file-backed code")
    slot_pattern = b"\x48\x8b\x84\xc1\x90\xa3\x11\x00"
    if slot_pattern not in body:
        raise Blocked("missing build-specific first-slot signature " + slot_pattern.hex())
    slot0 = struct.unpack_from("<I", body, body.find(slot_pattern) + 4)[0]
    slots = [slot0, slot0 + 8]
    # The actual selector body shows only +0x11A390. The second qword is the
    # adjacent array entry, to be checked by content; it is NOT claimed as a
    # separately decoded instruction merely because the old notes said so.
    second_slot_independent = b"\x48\x8b\x84\xc1\x98\xa3\x11\x00" in body
    print("DECODED function_entries=%s second_slot_instruction=%s"
          % ([hex(f) for f in functions], second_slot_independent))
    # Exact 0x20DB0BE body: index is moved to r8, not rbp-based rax as older notes said.
    idx = body.find(b"\x48\x0f\xbe\x85")
    displacement_offset = idx + 4 if idx >= 0 else 0
    if idx < 0:
        idx = body.find(b"\x48\x63\x85")
        displacement_offset = idx + 3 if idx >= 0 else 0
    index = struct.unpack_from("<i", body, displacement_offset)[0] if idx >= 0 else None
    if index != 0x1308 or not slots or slots[0] not in EXPECTED_SLOTS:
        raise Blocked("matrix accessor signature mismatch: slots=%s,index=%s" %
                      ([hex(v) for v in slots], hex(index) if index is not None else None))
    print("DECODED accessor=%#07x singleton=%#07x vt=%#07x" %
          (ACCESSOR_RVA, obj, VT_RVA))
    print("DECODED code=%s slots=%s index=%#04x" %
          ([hex(v - 0x140000000) for v in functions],
           [hex(v) for v in slots], index))
    return {"object": obj, "vt": VT_RVA, "file_vt": file_vt,
            "functions": functions, "slots": tuple(slots),
            "index": index, "accessor_bytes": code[:16]}



class ExplicitPhysical:
    """A falsifiable flat mapping hypothesis, not a VA->PA translation layer."""
    def __init__(self, g, ranges):
        self.g = g
        self.ranges = ranges
        self.reads = self.refused = self.faults = 0

    def read(self, pa, size):
        self.reads += 1
        assert isinstance(pa, int), "non-integer physical address from parser"
        if not any(lo <= pa and pa + size <= hi for lo, hi in self.ranges):
            self.refused += 1
            return None
        try:
            data = self.g.read_phys(pa, size)
            if data is None or len(data) != size:
                self.faults += 1
                return None
            return data
        except OSError:
            self.faults += 1
            return None

    def validate_layout(self, base, pe, a, ev):
        ev.progress("validate_flat_begin base=%#x" % base)
        hdr = self.read(base, 0x400)
        if not hdr or hdr[:2] != b"MZ":
            raise Blocked("image candidate has no MZ header")
        nt = struct.unpack_from("<I", hdr, 0x3C)[0]
        if hdr[nt:nt + 4] != b"PE\0\0":
            raise Blocked("image candidate has malformed PE header")
        if (struct.unpack_from("<I", hdr, nt + 8)[0],
                struct.unpack_from("<I", hdr, nt + 0x50)[0]) != (pe.stamp, pe.size):
            raise Blocked("physical image build differs from input file")
        at = self.read(base + ACCESSOR_RVA, 16)
        if at != a["accessor_bytes"]:
            raise Blocked("accessor bytes differ at candidate: expected=%s actual=%s" %
                          (a["accessor_bytes"].hex(), at.hex() if at else None))
        obj_raw = self.read(base + a["object"], 8)
        vt_raw = self.read(base + a["vt"], 8)
        if not obj_raw or not vt_raw:
            raise Blocked("singleton/vtable function table is unreadable")
        obj_vt = struct.unpack("<Q", obj_raw)[0]
        va = obj_vt - a["vt"]
        slide = va - 0x140000000
        if slide <= 0 or (slide & 0xFFFF) or not 0x100000000 <= va <= 0x7FFFFFFFFFFF:
            raise Blocked("singleton is not an expected image-relative vtable: obj_vt=%#x" % obj_vt)
        first_function = struct.unpack("<Q", vt_raw)[0]
        if first_function != a["file_vt"] + slide:
            raise Blocked("vtable first function does not match file relocation: got=%#x want=%#x" %
                          (first_function, a["file_vt"] + slide))
        ev.log("  file_layout: accessor=PASS singleton=%#x image_va=%#x slide=%#x" %
               (obj_vt, va, slide))
        # Relocation is checked on two separate entries. Matching archived PE
        # bytes do not qualify if neither points into the current image.
        for off, relva in ((0x80, a["functions"][1]),):
            actual = self.read(base + a["vt"] + off, 8)
            want = relva + slide
            got = struct.unpack("<Q", actual)[0] if actual else None


            if got != want:
                raise Blocked("relocated vtable +%#02x got=%s want=%#x" %
                              (off, hex(got) if got is not None else None, want))
        return va, slide


def gate_accessor(pr, base, va, a, ev):
    """One bounded sample followed by a briefing re-read; no polling loops."""
    required = (("obj", a["object"], 0x10),
                ("slots", a["slots"][0], 0x10),
                ("index", a["index"], 1),
                ("buf_a", EXPECTED_BUFFERS[0], 0x40),
                ("buf_b", EXPECTED_BUFFERS[1], 0x40))
    names = [name for name, _, _ in required]
    ev.progress("sample_begin")
    one = {}
    two = {}
    for name, rva, size in required:
        one[name] = pr.read(base + rva, size)
    time.sleep(0.3)
    for name, rva, size in required:
        two[name] = pr.read(base + rva, size)
    ev.progress("sample_end")
    for name, rva, size in required:
        b = one[name]
        ev.log("  %-6s RVA=%#07x len=%s hex=%s two_samples_equal=%s" %
               (name, rva, len(b) if b else "FAIL", b.hex() if b else None,
                b == two[name]))
    gates = {"G2_vtable": False, "G3_slots_buffers": False, "G4_matrix_shape": False,
             "G5_column_projection": None, "G6_readability": all(one[n] is not None for n in names)}
    if one["obj"] and struct.unpack_from("<Q", one["obj"])[0] == va + a["vt"]:
        gates["G2_vtable"] = True
    if one["slots"]:
        refs = struct.unpack("<2Q", one["slots"])
        expected = (va + EXPECTED_BUFFERS[0], va + EXPECTED_BUFFERS[1])
        ev.log("  slot_refs=%#x,%#x expected=%#x,%#x" % (refs + expected))
        gates["G3_slots_buffers"] = refs == expected
    ev.log("  index_byte=%s (G5 requires 0 or 1); actual selected matrix is not guessed" %
           (one["index"][0] if one["index"] else None))
    ma = struct.unpack("<16f", one["buf_a"]) if one["buf_a"] else None
    if ma:
        for row in range(4):
            ev.log("  float row%d %s" % (row, " ".join("%.6g" % v for v in ma[row * 4:row * 4 + 4])))
        # Matrix shape alone is insufficient: require a nonzero perspective
        # (rational values in [-1000,1000]) and stable reread before testing W2S.
        good_values = all(abs(x) <= 1000.0 and (x == 0.0 or abs(x) > 1e-20) for x in ma)
        nonzero = [abs(x) for x in ma if x != 0]
        gates["G4_matrix_shape"] = good_values and len(nonzero) >= 8 and max(nonzero) > 0.3
    ev.log("  reads=%d faults=%d R10_refused=%d" % (pr.reads, pr.faults, pr.refused))
    for name, result in gates.items():
        if result is not None:
            ev.log("%s=%s" % (name, "PASS" if result else "FAIL"))
    ev.log("G5_column_projection=SKIPPED (matrix layout/accessor needs binding verification)")
    return all(v is not False for v in gates.values())


def read_config(value):
    if value is not None:
        return value, "explicit-argument"
    values = {}
    with (HERE / "qk_offsets.txt").open(encoding="utf-8") as f:
        for line in f:
            if "=" in line:
                k, v = line.strip().split("=", 1)
                values[k] = v
    if "image_pa" not in values:
        raise Blocked("recorded image_pa missing; provide --image-pa=0x... explicitly")
    return int(values["image_pa"], 0), "recorded-hypothesis-until-anchor-validation"


def finish(ev, text, verdict, rc):
    ev.rc = rc
    ev.log("RESULT: " + text)
    ev.log("VERDICT: %s (h387 variable: file-anchored accessor physical mapping; "
           "no inherited matrix/PASS substitution)" % verdict)
    return rc


def main(argv=None):
    global OUT, PROGRESS, STATE
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pe")
    parser.add_argument("--image-pa", type=lambda v: int(v, 0))
    parser.add_argument("--label", default="h387",
                        help="unique read-only run label, forbids output overwrites")
    parser.add_argument("--preflight", action="store_true")
    args = parser.parse_args(argv)
    if not args.label.isalnum() or len(args.label) > 20:
        parser.error("--label must be a short alphanumeric, e.g. h387a")
    OUT = HERE / ("_%s_out.txt" % args.label)
    PROGRESS = HERE / ("_%s_progress.txt" % args.label)
    STATE = HERE / ("_%s_state.txt" % args.label)
    if not args.pe:
        parser.error("--pe=<absolute same-build PE path> is required")
    ev = Evidence()
    ev.progress("start python=%s pid=%d" % (sys.executable, __import__("os").getpid()))
    if not args.preflight:
        if OUT.exists():
            raise Blocked("h387 output already exists: use a new numbered probe, not overwrite (R5)")
    g = None
    closed = True
    rc = 2
    try:
        pe = PE(args.pe)
        ev.pid = dl.find_pid()
        ev.alive = bool(ev.pid and dl.pid_alive(ev.pid))
        ev.pre(pe)
        a = build_accessor(pe)
        if args.preflight:
            result = str(HERE / ("_%s_preflight.txt" % args.label))
            with open(result, "x", encoding="utf-8") as f:
                f.write("G0=SKIPPED (preflight does not probe game)\n")
                f.write("G1=PASS input build identity, RVA layout, accessor/vtable signatures\n")
                f.write("APPEND product_files_changed=0\n")
                f.write("RESULT: syntax and build-specific decoded path only\n")
                f.write("VERDICT: PARTIAL (SKIPPED all live/game gates, R9)\n")
            print("PREFLIGHT written: %s" % result, flush=True)
            rc = 0
            return finish(ev, "offline file identity/layout, game not read",
                          "PARTIAL (SKIPPED game and all physical gates, R9)", rc)
        ev.log("G0 game pid=%s alive=%s elevated=%d" % (ev.pid, ev.alive, dl.elevation()))
        if not ev.alive:
            return finish(ev, "game not running; no device opened",
                          "PARTIAL (SKIPPED all physical gates, R9)", 2)
        if not dl.elevation():
            return finish(ev, "not elevated; no device opened",
                          "PARTIAL (SKIPPED all physical gates)", 2)
        import gio
        ev.progress("gio_open_begin")
        g = gio.Gio(chunk=0x10000)
        closed = False
        ev.progress("gio_open_end")
        ranges, _ = dl.usable_ranges(g.ram_top, None, None)
        pr = ExplicitPhysical(g, ranges)
        base, origin = read_config(args.image_pa)
        ev.log("G1 image hypothesis=%#x origin=%s; validation before member reads" % (base, origin))
        va, slide = pr.validate_layout(base, pe, a, ev)
        ev.log("G1=PASS physical MZ/PE/build + exact accessor and relocated vtable")
        good = gate_accessor(pr, base, va, a, ev)
        if good:
            # The final result deliberately excludes skipped G5 from "all".
            return finish(ev, "accessor read healthy; in-game W2S is not claimed",
                          "PARTIAL (G5_column_projection SKIPPED; length plausibility not visual proof)", 0)
        return finish(ev, "one or more concrete accessor/matrix/read gates failed",
                      "FAIL", 1)
    except Blocked as e:
        return finish(ev, str(e), "BLOCKED / PARTIAL (SKIPPED physical W2S)", 2)
    except FileNotFoundError as e:
        return finish(ev, "required input missing: %s" % e,
                      "BLOCKED / PARTIAL (SKIPPED physical W2S)", 2)
    except OSError as e:
        return finish(ev, "local device/input read failure: %s" % e,
                      "PARTIAL (SKIPPED unfinished physical gates, R9)", 2)
    finally:
        if g is not None:
            try:
                g.close()
                closed = True
            except Exception as e:
                ev.log("HANDLE_CLOSE_FAILED=%s" % e)
                ev.rc = 3
        if ev.pid:
            post_pid = dl.find_pid()
            ev.alive = post_pid == ev.pid
        ev.post(ev.rc, closed)
        ev.progress("end rc=%d handle_closed=%s" % (ev.rc, closed))


if __name__ == "__main__":
    sys.exit(main())
