# h392 PFN/user-read A/B — blocked

The PFN-query alternative returned `0xC0000004` on each tried request shape,
failed its local marker control, and yielded no complete Apex PE. Its output is
in `temp/_h392_mapping.txt`. The candidate decoder is deliberately NOT retained
as executable library code, because it could read a plausible wrong physical
address. See `_h392_pfn_experiment.py.txt` for the evidence note. The similarly
failed normal user-read permission probe is in `temp/_h392_access.py`.