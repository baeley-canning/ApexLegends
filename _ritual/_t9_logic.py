import sys
sys.path.insert(0, r"C:\Users\New User\OneDrive\Desktop\cheating\ext")
import qk_va as Q
for argv in (["x"], ["x","--driver"], ["x","--no-driver"], ["x","--driver","--no-driver"], ["x","--apexdrv"]):
    sys.argv = argv
    print(argv[1:] or ["default"], "->", "no-driver =", Q.flag("no-driver"),
          "| driver(residual) =", Q.flag("driver"))
assert not hasattr(Q, "use_driver"), "use_driver must stay retired"
