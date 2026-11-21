using System.Runtime.InteropServices;
using System.Security.Principal;
using Microsoft.Win32.SafeHandles;

namespace EnterpriseIT.ApiServiceHost;

internal static class WindowsServiceIdentity
{
    private const int TokenGroupsInformation = 2;
    private const int ErrorInsufficientBuffer = 122;
    private const uint GroupEnabled = 0x00000004;
    private const uint GroupUseForDenyOnly = 0x00000010;
    private const uint TokenQuery = 0x0008;
    private const int MaximumTokenBufferBytes = 1024 * 1024;
    private const int MaximumTokenGroups = 4096;

    public static SecurityIdentifier RequireEnabledServiceSid(string serviceName)
    {
        using var identity = WindowsIdentity.GetCurrent(TokenAccessLevels.Query);
        return ValidateIdentity(serviceName, identity);
    }

    public static SecurityIdentifier RequireEnabledServiceSid(string serviceName, IntPtr processHandle)
    {
        if (!OperatingSystem.IsWindows())
            throw new PlatformNotSupportedException("The API service host requires Windows service-token validation.");
        if (processHandle == IntPtr.Zero)
            throw new ArgumentException("A valid process handle is required.", nameof(processHandle));
        if (!OpenProcessToken(processHandle, TokenQuery, out var token))
            throw new UnauthorizedAccessException("The API child process token could not be opened.");

        using (token)
        using (var identity = new WindowsIdentity(token.DangerousGetHandle()))
            return ValidateIdentity(serviceName, identity);
    }

    private static SecurityIdentifier ValidateIdentity(string serviceName, WindowsIdentity identity)
    {
        if (!OperatingSystem.IsWindows())
            throw new PlatformNotSupportedException("The API service host requires Windows service-token validation.");
        if (string.IsNullOrWhiteSpace(serviceName))
            throw new ArgumentException("A service name is required.", nameof(serviceName));

        var account = new NTAccount("NT SERVICE", serviceName);
        if (account.Translate(typeof(SecurityIdentifier)) is not SecurityIdentifier expectedSid)
            throw new UnauthorizedAccessException("The configured Windows service identity could not be resolved.");

        var candidates = new List<SecurityIdentifier>();
        if (identity.User is SecurityIdentifier user && expectedSid.Equals(user))
            candidates.Add(user);

        var token = identity.AccessToken;
        var sizeQuerySucceeded = GetTokenInformation(
            token.DangerousGetHandle(), TokenGroupsInformation,
            IntPtr.Zero, 0, out var requiredBytes);
        var sizeQueryError = Marshal.GetLastWin32Error();
        var firstGroupOffset = Marshal.OffsetOf<TokenGroupsLayout>(
            nameof(TokenGroupsLayout.FirstGroup)).ToInt32();
        if (sizeQuerySucceeded || sizeQueryError != ErrorInsufficientBuffer ||
            requiredBytes < firstGroupOffset || requiredBytes > MaximumTokenBufferBytes)
            throw new UnauthorizedAccessException("The Windows service token could not be validated.");

        var buffer = Marshal.AllocHGlobal(requiredBytes);
        try
        {
            if (!GetTokenInformation(token.DangerousGetHandle(), TokenGroupsInformation,
                    buffer, requiredBytes, out var returnedBytes) ||
                returnedBytes < firstGroupOffset || returnedBytes > requiredBytes)
                throw new UnauthorizedAccessException("The Windows service token could not be validated.");

            var groupCount = Marshal.ReadInt32(buffer);
            var entrySize = Marshal.SizeOf<SidAndAttributes>();
            if (groupCount < 0 || groupCount > MaximumTokenGroups ||
                returnedBytes < firstGroupOffset + (long)groupCount * entrySize)
                throw new UnauthorizedAccessException("The Windows service token contains an invalid group table.");

            for (var index = 0; index < groupCount; index++)
            {
                var entry = Marshal.PtrToStructure<SidAndAttributes>(
                    IntPtr.Add(buffer, firstGroupOffset + index * entrySize));
                if (entry.Sid == IntPtr.Zero ||
                    (entry.Attributes & GroupEnabled) == 0 ||
                    (entry.Attributes & GroupUseForDenyOnly) != 0)
                    continue;
                var groupSid = new SecurityIdentifier(entry.Sid);
                if (expectedSid.Equals(groupSid))
                    candidates.Add(groupSid);
            }
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }

        var matched = candidates.GroupBy(candidate => candidate.Value, StringComparer.Ordinal)
            .Select(group => group.First()).ToArray();
        if (matched.Length != 1)
            throw new UnauthorizedAccessException(
                "The process is not running with the required enabled Windows service SID.");
        return expectedSid;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct SidAndAttributes
    {
        public IntPtr Sid;
        public uint Attributes;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct TokenGroupsLayout
    {
        public uint GroupCount;
        public SidAndAttributes FirstGroup;
    }

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool OpenProcessToken(
        IntPtr processHandle, uint desiredAccess, out SafeAccessTokenHandle tokenHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetTokenInformation(
        IntPtr token, int informationClass, IntPtr information,
        int informationLength, out int returnLength);
}
