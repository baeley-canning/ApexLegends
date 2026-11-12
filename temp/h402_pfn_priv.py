import ctypes as C,os,sys,time
sys.path.insert(0,os.path.join(os.path.dirname(__file__),'..','ext'))
import gio,dumplive as dl,qk_gdrv_mapread,qk_pfn_read
r=os.path.dirname(__file__);out=os.path.join(r,'h402_pfn_priv.txt')
def say(s):
    print(s,flush=True)
    with open(out,'a',encoding='ascii') as f:f.write(s+'\n')
open(out,'w').close()
if not dl.elevation():sys.exit(dl.run_elevated('"%s"'%os.path.abspath(__file__)))
say('PFN local privilege control %s'%time.strftime('%F %T'))
say('enable profile status=%d'%qk_pfn_read.enable_page_query_privilege())
g=gio.Gio(chunk=0x1000);mr=qk_gdrv_mapread.install(g)
try:
    b=C.create_string_buffer(b'VALIDPFN-FRAME')
    status, triple=qk_pfn_read.translate(C.addressof(b))
    say('status=%#x triple=%s'%(status,[hex(x) for x in triple]))
finally:g.close()