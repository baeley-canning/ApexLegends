// h278 control payload: the smallest thing a remote LoadLibraryW can be asked to
// load.  Deliberately has NO imports beyond what the linker forces, no CRT, no
// static initialisers and a DllMain that cannot fail - so "apxprobe.dll loads and
// apexcheat.dll does not" can only mean the payload, not the loader route.
//
// The export and the string exist so the image is not optimised down to nothing
// and so a GetProcAddress check has something to find.
__declspec(dllexport) int ApxprobeMarker(void) {
    return 0x4d;                                 // 'M'
}

const char kApxprobeTag[] = "apxprobe/h278";

__declspec(dllexport) const char* ApxprobeTag(void) {
    return kApxprobeTag;
}

#include <windows.h>

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID reserved) {
    (void)module;
    (void)reason;
    (void)reserved;
    return TRUE;
}
