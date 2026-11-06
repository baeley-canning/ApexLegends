# h280 side check: prove the ApexdrvStampStub byte layout on the host, before a guest rung spends
# itself on it. v6 got this wrong twice over (absolute offsets as RIP disps, read-back at the
# stub base) and h278 paid for it. This builds the byte image EXACTLY as the driver does, runs it
# against a recording routine, and reads the data slots back.
#   expect: magic 0x4870 at +38, the argument we passed at +46, and the routine's own record of
#   what RCX held. Any other magic/offset means the arithmetic in apexdrv.c is still wrong.
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class StubTest {
    [DllImport("kernel32", SetLastError=true)] public static extern IntPtr VirtualAlloc(IntPtr a, UIntPtr s, uint t, uint p);
    [DllImport("kernel32")] public static extern bool VirtualFree(IntPtr a, UIntPtr s, uint t);
    public const uint COMMIT = 0x1000, RESERVE = 0x2000, RWX = 0x40, RELEASE = 0x8000;
    public const int CODE = 38, DATA = 16, TOTAL = CODE + DATA;
    public static ulong SeenRcx; public static int Calls;
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    public delegate void Proto(IntPtr arg);

    public static byte[] Image(IntPtr routine, bool ex) {
        byte[] s = new byte[TOTAL];
        s[0] = 0x48; s[1] = 0xC7; s[2] = 0x05;
        BitConverter.GetBytes((uint)(CODE - 11)).CopyTo(s, 3);   // same expression as the driver
        BitConverter.GetBytes((uint)0x4870).CopyTo(s, 7);
        s[11] = 0x48; s[12] = 0x89; s[13] = 0x0D;
        BitConverter.GetBytes((uint)(CODE + 8 - 18)).CopyTo(s, 14);
        if (ex) { s[18]=0x31; s[19]=0xD2; s[20]=0x41; s[21]=0xB8; BitConverter.GetBytes((uint)8).CopyTo(s,22); }
        else { for (int i = 18; i < 26; i++) s[i] = 0x90; }
        s[26] = 0x48; s[27] = 0xB8;
        BitConverter.GetBytes((long)routine).CopyTo(s, 28);
        s[36] = 0xFF; s[37] = 0xE0;
        return s;
    }

    public static string Run(bool ex) {
        Proto rec = delegate(IntPtr arg) { SeenRcx = (ulong)arg; Calls++; };
        IntPtr fn = Marshal.GetFunctionPointerForDelegate(rec);
        IntPtr page = VirtualAlloc(IntPtr.Zero, (UIntPtr)0x1000, COMMIT | RESERVE, RWX);
        if (page == IntPtr.Zero) return "VirtualAlloc failed";
        byte[] img = Image(fn, ex);
        Marshal.Copy(img, 0, page, img.Length);
        try {
            Proto entry = (Proto)Marshal.GetDelegateForFunctionPointer(page, typeof(Proto));
            IntPtr arg = (IntPtr)0x1122334455667788UL;
            entry(arg);
            ulong magic = (ulong)Marshal.ReadInt64(page, CODE);
            ulong got   = (ulong)Marshal.ReadInt64(page, CODE + 8);
            string[] words = new string[TOTAL];
            for (int i = 0; i < TOTAL; i++) words[i] = Marshal.ReadByte(page, i).ToString("X2");
            // Calls is static and survives the first run, so assert "it ran at all", not "==1"
            string verdict = (magic == 0x4870 && got == (ulong)arg && SeenRcx == (ulong)arg && Calls >= 1)
                ? "OK" : "BAD";
            return string.Format("ex={0} verdict={1} magic=0x{2:X} slot_rcx=0x{3:X} routine_saw=0x{4:X} calls={5}\r\nbytes: {6}",
                                 ex, verdict, magic, got, SeenRcx, Calls, string.Join(" ", words));
        } finally { VirtualFree(page, (UIntPtr)0, RELEASE); GC.KeepAlive(rec); }
    }
}
'@
[StubTest]::Run($false) | Write-Output
[StubTest]::Run($true) | Write-Output
