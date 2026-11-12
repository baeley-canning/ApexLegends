import os,sys,time
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,os.path.join(ROOT,"ext"))
import dumplive as dl
import gio
import qk_gdrv_mapread
import qk_rootbind
OUT=os.path.join(ROOT,"temp","h401_rootbind.txt")
def say(s):
    print(s,flush=True)
    with open(OUT,"a",encoding="ascii") as f:f.write(s+"\n")
open(OUT,"w").close()
if not dl.elevation():sys.exit(dl.run_elevated('"%s"'%os.path.abspath(__file__)))
say("h401 root bind %s"%time.strftime("%F %T"))
g=gio.Gio(chunk=0x1000)
try:
    qk_gdrv_mapread.install(g)
    result=qk_rootbind.locate(g,say)
    say("RESULT: %s"%(result,))
finally:g.close()