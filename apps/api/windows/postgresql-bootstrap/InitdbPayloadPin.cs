using System.Runtime.InteropServices;
using System.Security.AccessControl;
using Microsoft.Win32.SafeHandles;

namespace EnterpriseIT.PostgreSQLBootstrap;

/// <summary>
/// Pins initdb.exe for the whole duration of cluster initialization. The payload
/// is opened by handle with FILE_SHARE_READ|FILE_SHARE_WRITE and without
/// FILE_SHARE_DELETE, so the image cannot be renamed, replaced or deleted while
/// the version check and the initdb launch are running. File identity, reparse
/// state and the DACL are captured before the first launch and re-verified
/// through the retained handle after initialization completes. No path-based
/// existence check is used, and no exception text contains paths or ACL data.
/// </summary>
internal sealed class InitdbPayloadPin : IDisposable
{
    private const uint FileReadAttributes = 0x80;
    private const uint ReadControl = 0x20000;
    private const uint Synchronize = 0x100000;
    private const uint ShareRead = 1;
    private const uint ShareWrite = 2;
    private const uint OpenExisting = 3;
    private const uint OpenReparsePoint = 0x00200000;
    private const uint DirectoryAttribute = 0x10;
    private const uint ReparseAttribute = 0x400;
    private const int AttributeTagInfoClass = 9;
    private const int FileIdInfoClass = 18;
    private const uint OwnerSecurityInformation = 1;
    private const uint DaclSecurityInformation = 4;

    private readonly SafeFileHandle handle;
    private readonly FileIdentity identity;
    private readonly byte[] initialDescriptor;
    private bool disposed;

    private InitdbPayloadPin(SafeFileHandle handle, FileIdentity identity, byte[] initialDescriptor)
    {
        this.handle = handle;
        this.identity = identity;
        this.initialDescriptor = initialDescriptor;
    }

    internal static InitdbPayloadPin Open(string initdbPath)
    {
        var pinned = CreateFileW(initdbPath,
            FileReadAttributes | ReadControl | Synchronize,
            ShareRead | ShareWrite, // execute/read allowed; rename and delete blocked
            IntPtr.Zero, OpenExisting,
            OpenReparsePoint, // never follow; a reparse payload is rejected below
            IntPtr.Zero);
        if (pinned.IsInvalid)
        {
            var error = Marshal.GetLastWin32Error();
            pinned.Dispose();
            if (error is 2 or 3)
                throw new FileNotFoundException("PostgreSQL initdb payload is missing.");
            // Do not surface the native path or error text.
            throw new IOException("PostgreSQL initdb payload could not be pinned.");
        }
        try
        {
            var identity = ReadIdentity(pinned);
            if ((identity.Attributes & DirectoryAttribute) != 0 ||
                (identity.Attributes & ReparseAttribute) != 0)
                throw new InvalidDataException("PostgreSQL initdb payload is not a plain file.");
            var descriptor = ReadDescriptor(pinned);
            RejectUnsafeAcl(descriptor);
            return new InitdbPayloadPin(pinned,
                new FileIdentity(identity.VolumeSerialNumber, identity.FileIdLow, identity.FileIdHigh),
                descriptor);
        }
        catch
        {
            pinned.Dispose();
            throw;
        }
    }

    /// <summary>
    /// Re-verifies identity, reparse state and DACL through the retained pin
    /// handle after both initdb launches have completed.
    /// </summary>
    internal void VerifyUnchanged()
    {
        if (disposed) throw new ObjectDisposedException(nameof(InitdbPayloadPin));
        var current = ReadIdentity(handle);
        if ((current.Attributes & DirectoryAttribute) != 0 ||
            (current.Attributes & ReparseAttribute) != 0 ||
            current.VolumeSerialNumber != identity.VolumeSerialNumber ||
            current.FileIdLow != identity.FileIdLow ||
            current.FileIdHigh != identity.FileIdHigh)
            throw new InvalidDataException("PostgreSQL initdb payload identity changed during initialization.");
        var descriptor = ReadDescriptor(handle);
        if (!descriptor.AsSpan().SequenceEqual(initialDescriptor))
            throw new InvalidDataException("PostgreSQL initdb payload ACL changed during initialization.");
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        handle.Dispose();
    }

    private readonly record struct FileIdentity(
        ulong VolumeSerialNumber, ulong FileIdLow, ulong FileIdHigh, uint Attributes = 0)
    {
        // Attributes are captured alongside the identity for the reparse/type
        // check; they are not part of the before/after identity comparison.
        internal FileIdentity(ulong volume, ulong low, ulong high)
            : this(volume, low, high, 0) { }
    }

    private static FileIdentity ReadIdentity(SafeFileHandle pinned)
    {
        if (!GetFileInformationByHandleEx(pinned, AttributeTagInfoClass, out FileAttributeTagInfo tag, Marshal.SizeOf<FileAttributeTagInfo>()) ||
            !GetFileInformationByHandleEx(pinned, FileIdInfoClass, out FileIdInfo id, Marshal.SizeOf<FileIdInfo>()))
            throw new IOException("PostgreSQL initdb payload identity could not be verified.");
        return new FileIdentity(id.VolumeSerialNumber, id.FileIdLow, id.FileIdHigh, tag.FileAttributes);
    }

    private static byte[] ReadDescriptor(SafeFileHandle pinned)
    {
        var status = GetSecurityInfo(pinned, 1 /* SE_FILE_OBJECT */, OwnerSecurityInformation | DaclSecurityInformation,
            out _, out _, out _, out _, out var sdPtr);
        if (status != 0 || sdPtr == IntPtr.Zero)
            throw new IOException("PostgreSQL initdb payload ACL could not be read.");
        try
        {
            var len = GetSecurityDescriptorLength(sdPtr);
            if (len == 0 || len > 65536)
                throw new IOException("PostgreSQL initdb payload ACL could not be read.");
            var bytes = new byte[(int)len];
            Marshal.Copy(sdPtr, bytes, 0, bytes.Length);
            return bytes;
        }
        finally
        {
            LocalFree(sdPtr);
        }
    }

    private static void RejectUnsafeAcl(byte[] descriptor)
    {
        // The pinned payload must not be writable by broad principals. The
        // staged payload grants Full Control only to SYSTEM/Administrators and
        // read/execute to the bootstrap service SID; anything broader is a
        // tampered payload and fails closed before the first launch.
        var sd = new RawSecurityDescriptor(descriptor, 0);
        if (sd.DiscretionaryAcl is null) return;
        var broadWriteSids = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "S-1-1-0",    // Everyone
            "S-1-5-7",    // Anonymous
            "S-1-5-11",   // Authenticated Users
            "S-1-5-32-545" // Users
        };
        const uint dangerousWriteMask =
            0x00000002 | // FILE_WRITE_DATA
            0x00000004 | // FILE_APPEND_DATA
            0x00000040 | // DELETE_CHILD
            0x00010000 | // DELETE
            0x00040000 | // WRITE_DAC
            0x00080000 | // WRITE_OWNER
            0x10000000 | // GENERIC_ALL
            0x40000000;  // GENERIC_WRITE
        foreach (GenericAce ace in sd.DiscretionaryAcl)
        {
            if (ace is not QualifiedAce qualified) continue;
            if (qualified.AceQualifier != AceQualifier.AccessAllowed) continue;
            if (!broadWriteSids.Contains(qualified.SecurityIdentifier.Value)) continue;
            if ((unchecked((uint)qualified.AccessMask) & dangerousWriteMask) != 0)
                throw new InvalidDataException("PostgreSQL initdb payload ACL is unsafe.");
        }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct FileAttributeTagInfo { public uint FileAttributes, ReparseTag; }

    [StructLayout(LayoutKind.Sequential)]
    private struct FileIdInfo { public ulong VolumeSerialNumber, FileIdLow, FileIdHigh; }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CreateFileW")]
    private static extern SafeFileHandle CreateFileW(string fileName, uint desiredAccess, uint shareMode,
        IntPtr securityAttributes, uint creationDisposition, uint flagsAndAttributes, IntPtr templateFile);

    [DllImport("kernel32.dll", SetLastError = true, EntryPoint = "GetFileInformationByHandleEx")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandleEx(SafeFileHandle file, int infoClass,
        out FileAttributeTagInfo information, int bufferSize);

    [DllImport("kernel32.dll", SetLastError = true, EntryPoint = "GetFileInformationByHandleEx")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandleEx(SafeFileHandle file, int infoClass,
        out FileIdInfo information, int bufferSize);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern uint GetSecurityInfo(SafeFileHandle handle, uint objectType, uint securityInfo,
        out IntPtr sidOwner, out IntPtr sidGroup, out IntPtr dacl, out IntPtr sacl, out IntPtr securityDescriptor);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern uint GetSecurityDescriptorLength(IntPtr securityDescriptor);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LocalFree(IntPtr hMem);
}
