import pickle
C = pickle.load(open(r"C:\Users\New User\OneDrive\Desktop\cheating\temp\dm11_cache.pkl", "rb"))
lines = ["keys: %r" % (list(C.keys()),)]
for k, v in C.items():
    if k == "img":
        lines.append("img: %d entries" % len(v))
        continue
    try:
        lines.append("%s: %s len=%d" % (k, type(v).__name__, len(v)))
    except TypeError:
        lines.append("%s: %s %r" % (k, type(v).__name__, v))
open(r"C:\Users\New User\OneDrive\Desktop\cheating\temp\dm13_keys.txt", "w").write("\n".join(lines))
print("\n".join(lines))
