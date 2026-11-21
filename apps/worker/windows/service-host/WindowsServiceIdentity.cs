using System.Runtime.InteropServices;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;
namespace EnterpriseIT.WorkerServiceHost;
internal static class WindowsServiceIdentity
{
    private const int TokenGroupsInformation = 2, ErrorInsufficientBuffer = 122;
    private const uint GroupEnabled = 0x4, GroupUseForDenyOnly = 0x10, TokenQuery = 0x8;
    private const int MaximumTokenBufferBytes = 1024 * 1024, MaximumTokenGroups = 4096;
    internal static SecurityIdentifier RequireEnabledServiceSid(string name) { using var identity = WindowsIdentity.GetCurrent(TokenAccessLevels.Query); return Validate(name, identity); }
    internal static SecurityIdentifier RequireEnabledServiceSid(string name, IntPtr processHandle)
    {
        if (!OperatingSystem.IsWindows() || processHandle == IntPtr.Zero) throw new PlatformNotSupportedException("A valid Windows process handle is required.");
        if (!OpenProcessToken(processHandle, TokenQuery, out var token)) throw new UnauthorizedAccessException("The Worker child process token could not be opened.");
        using (token) using (var identity = new WindowsIdentity(token.DangerousGetHandle())) return Validate(name, identity);
    }
    private static SecurityIdentifier Validate(string name, WindowsIdentity identity)
    {
        var account = new NTAccount("NT SERVICE", name);
        if (account.Translate(typeof(SecurityIdentifier)) is not SecurityIdentifier expected) throw new UnauthorizedAccessException("The Worker service SID could not be resolved.");
        var matches = new List<SecurityIdentifier>();
        if (identity.User is SecurityIdentifier user && expected.Equals(user)) matches.Add(user);
        var token = identity.AccessToken;
        var queried = GetTokenInformation(token.DangerousGetHandle(), TokenGroupsInformation, IntPtr.Zero, 0, out var bytes);
        var error = Marshal.GetLastWin32Error();
        var offset = Marshal.OffsetOf<TokenGroupsLayout>(nameof(TokenGroupsLayout.FirstGroup)).ToInt32();
        if (queried || error != ErrorInsufficientBuffer || bytes < offset || bytes > MaximumTokenBufferBytes) throw new UnauthorizedAccessException("The Worker service token could not be validated.");
        var buffer = Marshal.AllocHGlobal(bytes);
        try
        {
            if (!GetTokenInformation(token.DangerousGetHandle(), TokenGroupsInformation, buffer, bytes, out var returned) || returned < offset || returned > bytes) throw new UnauthorizedAccessException("The Worker service token could not be validated.");
            var count = Marshal.ReadInt32(buffer); var size = Marshal.SizeOf<SidAndAttributes>();
            if (count < 0 || count > MaximumTokenGroups || returned < offset + (long)count * size) throw new UnauthorizedAccessException("The Worker service token group table is invalid.");
            for (var i=0;i<count;i++) { var entry=Marshal.PtrToStructure<SidAndAttributes>(IntPtr.Add(buffer,offset+i*size)); if(entry.Sid==IntPtr.Zero||(entry.Attributes&GroupEnabled)==0||(entry.Attributes&GroupUseForDenyOnly)!=0) continue; var sid=new SecurityIdentifier(entry.Sid); if(expected.Equals(sid)) matches.Add(sid); }
        }
        finally { Marshal.FreeHGlobal(buffer); }
        if(matches.Count==0) throw new UnauthorizedAccessException("The process lacks the required enabled EnterpriseITWorker service SID.");
        return expected;
    }
    [StructLayout(LayoutKind.Sequential)] private struct SidAndAttributes { public IntPtr Sid; public uint Attributes; }
    [StructLayout(LayoutKind.Sequential)] private struct TokenGroupsLayout { public uint Count; public SidAndAttributes FirstGroup; }
    [DllImport("advapi32.dll",SetLastError=true)][return:MarshalAs(UnmanagedType.Bool)] private static extern bool OpenProcessToken(IntPtr process,uint access,out SafeAccessTokenHandle token);
    [DllImport("advapi32.dll",SetLastError=true)][return:MarshalAs(UnmanagedType.Bool)] private static extern bool GetTokenInformation(IntPtr token,int info,IntPtr buffer,int length,out int returned);
}