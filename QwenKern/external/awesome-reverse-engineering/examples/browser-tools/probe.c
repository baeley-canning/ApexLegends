/* Self-authored public-domain review fixture (CC0-1.0). */
#include <windows.h>

__declspec(dllexport) __attribute__((noinline)) int probe(int n) {
    return n < 0 ? -1 : n * 2 + 1;
}

void entry(void) {
    ExitProcess((UINT)probe(21));
}
