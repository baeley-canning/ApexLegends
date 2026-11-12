import os,sys,time
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,os.path.join(ROOT,"ext"))
import gio,dumplive as dl,qk_gdrv_mapread,qk_bridge,qk_live_bridge
OUT=os.path.join(ROOT,"temp","h402_bridge.txt")
def say(s):
    print(s,flush=True)
    with open(OUT,"a",encoding="ascii") as f:f.write(s+"\n")
open(OUT,"w").close()
if not dl.elevation():sys.exit(dl.run_elevated('"%s"'%os.path.abspath(__file__)))
say("h402 Proc-without-NUL locator %s"%time.strftime("%F %T"))
pids=qk_bridge.find_pid()
if not pids:
    say("VERDICT: SKIPPED no current game process");sys.exit(2)
g=gio.Gio(chunk=0x1000)
try:
    qk_gdrv_mapread.install(g)
    result=qk_live_bridge.bind_current(g,pids[0],say)
    say("RESULT: %s"%(result,))
    say("VERDICT: %s"%("PASS" if result else "BLOCKED"))
finally:g.close()