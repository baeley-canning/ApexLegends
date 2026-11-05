import importlib.util
import inspect

spec = importlib.util.spec_from_file_location(
    "dl", r"c:\Users\New User\OneDrive\Desktop\cheating\ext\dumplive.py")
dl = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dl)
src = inspect.getsource(dl.probe_dtb)
print(src)
print("file:", dl.__file__)
print("has 4k loop:", "0x1000" in src)
