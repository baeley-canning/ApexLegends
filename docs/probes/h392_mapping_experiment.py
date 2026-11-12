r"""h392 alt experiments — BLOCKED, evidence receipt, not a reader.

PFN query: STATUS_INFO_LENGTH_MISMATCH (0xC0000004), no marker round-trip or PE.
Ordinary user read: handle requesting PROCESS_VM_READ was refused.
Read temp/_h392_result.md, temp/_h392_mapping.txt, temp/_h392_access.txt.
This program deliberately does not expose unchecked PFN candidates.  It never
opens the driver or game and exits 1 to stop accidental use as a runtime module.
"""


def main():
    print("H392 alt experiments: BLOCKED, not a VA->PA method.")
    print("Read temp/_h392_result.md and the named evidence files.")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())