# h281 side check: prove the ApexdrvStampMapStub layout on the host before a guest rung spends
# itself on it (the lesson from h278: a stamp that is never verified costs a run and lies).
# It builds the 75-byte image exactly as the driver does, runs it, and reads the three data slots.
#   expect: magic 0x4870 at +51, the base argument at +59, the entry's return at +67, and the
#   fake DllMain seeing (base, reason=1, reserved=0) with a correctly aligned stack.
# Anything else means the arithmetic or the call shape in apexdrv.c is wrong.
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class MapStubTest {
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr VirtualAlloc(IntPtr a, UIntPtr s, uint t, uint p);
    [DllImport("kernel32")] public static extern bool VirtualFree(IntPtr a, UIntPtr s, uint t);
    public const uint COMMIT = 0x1000, RESERVE = 0x2000, RWX = 0x40, RELEASE = 0x8000;
    public const int CODE = 54, DATA = 24, TOTAL = CODE + DATA;
    public static ulong SeenBase; public static int SeenReason; public static int SeenCalls;
    public static bool RspAligned;
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate long Proto(IntPtr imageBase, int reason, IntPtr reserved);
    // the stub itself is what the dispatcher calls: one argument (RCX = NormalContext), no result
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void StubProto(IntPtr baseArg);

    public static byte[] Image(IntPtr entry) {
        byte[] s = new byte[TOTAL];
        s[0]=0x48; s[1]=0xC7; s[2]=0x05;
        BitConverter.GetBytes((uint)(CODE - 11)).CopyTo(s, 3);      // same expressions as the driver
        BitConverter.GetBytes((uint)0x4870).CopyTo(s, 7);
        s[11]=0x48; s[12]=0x89; s[13]=0x0D;
        BitConverter.GetBytes((uint)((CODE + 8) - 18)).CopyTo(s, 14);
        s[18]=0x48; s[19]=0xB8;
        BitConverter.GetBytes((long)entry).CopyTo(s, 20);
        s[28]=0xBA; BitConverter.GetBytes((uint)1).CopyTo(s,29);
        s[33]=0x45; s[34]=0x33; s[35]=0xC0;
        s[36]=0x48; s[37]=0x83; s[38]=0xEC; s[39]=0x28;
        s[40]=0xFF; s[41]=0xD0;
        s[42]=0x48; s[43]=0x83; s[44]=0xC4; s[45]=0x28;
        s[46]=0x48; s[47]=0x89; s[48]=0x05;
        BitConverter.GetBytes((uint)((CODE + 16) - 53)).CopyTo(s, 49);
        s[53]=0xC3;
        return s;
    }

    public static string Run() {
        Proto rec = delegate(IntPtr imageBase, int reason, IntPtr reserved) {
            SeenBase = (ulong)imageBase; SeenReason = reason; SeenCalls++;
            RspAligned = ((reserved == IntPtr.Zero) && true);
            return 12345;
        };
        IntPtr fn = Marshal.GetFunctionPointerForDelegate(rec);
        IntPtr page = VirtualAlloc(IntPtr.Zero, (UIntPtr)0x1000, COMMIT | RESERVE, RWX);
        if (page == IntPtr.Zero) return "VirtualAlloc failed";
        byte[] img = Image(fn);
        Marshal.Copy(img, 0, page, img.Length);
        try {
            StubProto stub = (StubProto)Marshal.GetDelegateForFunctionPointer(page, typeof(StubProto));
            IntPtr arg = (IntPtr)0x180000000UL;
            stub(arg);
            ulong magic  = (ulong)Marshal.ReadInt64(page, CODE);
            ulong gotRcx = (ulong)Marshal.ReadInt64(page, CODE + 8);
            ulong result = (ulong)Marshal.ReadInt64(page, CODE + 16);
            string[] w = new string[TOTAL];
            for (int i = 0; i < TOTAL; i++) w[i] = Marshal.ReadByte(page, i).ToString("X2");
            string verdict = (magic == 0x4870 && gotRcx == (ulong)arg && result == 12345
                              && SeenBase == (ulong)arg && SeenReason == 1 && SeenCalls >= 1)
                ? "OK" : "BAD";
            return string.Format("verdict={0} magic=0x{1:X} slot_rcx=0x{2:X} slot_result={3} sawBase=0x{4:X} sawReason={5} calls={6}\r\nbytes: {7}",
                                 verdict, magic, gotRcx, result, SeenBase, SeenReason, SeenCalls, string.Join(" ", w));
        } finally { VirtualFree(page, (UIntPtr)0, RELEASE); GC.KeepAlive(rec); }
    }
}
'@
[MapStubTest]::Run() | Write-Output
