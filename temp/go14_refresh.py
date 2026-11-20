"""go14_refresh - keep the one-shot seed feed 'newborn' for the proof window.

`qk_live --from-feed` treats a record as stale (no boxes) when its `ts` is
older than 0.5 s (STALE_FEED), so a static seed ages out within one frame.
This mimics the real producer cadence: reload temp\\qk_feed.json, bump `ts`,
atomically rewrite (tmp + os.replace - the same contract as qk_va.py --emit),
every 0.25 s until the window closes.  Usage: go14_refresh.py <seconds>
"""
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
P = os.path.join(HERE, "qk_feed.json")
LOG = os.path.join(HERE, "go14_refresh_log.txt")


def main():
    end = time.time() + float(sys.argv[1] if len(sys.argv) > 1 else 65)
    n = 0
    errs = 0
    with open(LOG, "w") as log:
        while time.time() < end:
            try:
                with open(P, "r", encoding="utf-8") as f:
                    rec = json.load(f)
                rec["ts"] = time.time()
                tmp = P + ".tmp"
                with open(tmp, "w", encoding="utf-8") as f:
                    json.dump(rec, f, separators=(",", ":"))
                os.replace(tmp, P)
                n += 1
            except Exception as e:                     # noqa: BLE001 - log & go on
                errs += 1
                log.write("ERR %s: %s\n" % (type(e).__name__, str(e)[:100]))
                log.flush()
            time.sleep(0.25)
        log.write("DONE writes=%d errs=%d\n" % (n, errs))


if __name__ == "__main__":
    main()
