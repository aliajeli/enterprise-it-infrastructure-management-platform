using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace CredentialVault.KeyringStorageHelper;

/// <summary>
/// Acquires the fixed ProgramData -> EnterpriseIT -> CredentialVault directory
/// chain using retained handles. Not wired into storage until Windows acceptance
/// tests cover the native interop and adversarial namespace behavior.
/// </summary>
internal sealed class WindowsDirectoryHandleChain : IDisposable
{
    private const uint FileReadAttributes = 0x80, ReadControl = 0x20000, Synchronize = 0x100000;
    private const uint ShareRead = 1, ShareWrite = 2, OpenExisting = 3;
    private const uint BackupSemantics = 0x02000000, OpenReparsePoint = 0x00200000;
    private const uint DirectoryAttribute = 0x10, ReparseAttribute = 0x400;
    private const int AttributeTagInfoClass = 9, FileIdInfoClass = 18;
    private const uint ObjectCaseInsensitive = 0x40, FileDirectoryFile = 1;
    private const uint FileSynchronousIoNonAlert = 0x20, FileOpenReparsePoint = 0x00200000;
    private const uint FileOpen = 1;

    private readonly SafeFileHandle volumeRoot, programData, enterpriseRoot, vaultRoot;
    private bool disposed;

    private WindowsDirectoryHandleChain(SafeFileHandle volumeRoot, SafeFileHandle programData,
        SafeFileHandle enterpriseRoot, SafeFileHandle vaultRoot)
    {
        this.volumeRoot = volumeRoot;
        this.programData = programData;
        this.enterpriseRoot = enterpriseRoot;
        this.vaultRoot = vaultRoot;
    }

    internal SafeFileHandle VaultHandle
    {
        get { ObjectDisposedException.ThrowIf(disposed, this); return vaultRoot; }
    }

    internal static WindowsDirectoryHandleChain OpenKnownProgramData()
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
        var knownPath = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
        if (string.IsNullOrWhiteSpace(knownPath)) throw new UnauthorizedAccessException();

        var fullPath = Path.GetFullPath(knownPath);
        var volumePath = Path.GetPathRoot(fullPath);
        if (string.IsNullOrEmpty(volumePath) || volumePath.Length != 3 ||
            !char.IsAsciiLetter(volumePath[0]) || volumePath[1] != ':' ||
            volumePath[2] != Path.DirectorySeparatorChar ||
            !string.Equals(Path.GetRelativePath(volumePath, fullPath), "ProgramData",
                StringComparison.OrdinalIgnoreCase))
            throw new UnauthorizedAccessException();

        SafeFileHandle? volume = null, data = null, enterprise = null, vault = null;
        try
        {
            volume = OpenAbsoluteDirectory(volumePath);
            var volumeIdentity = ReadAndVerifyDirectory(volume);
            data = OpenChildDirectory(volume, "ProgramData", volumeIdentity);
            _ = ReadAndVerifyDirectory(data);
            enterprise = OpenChildDirectory(data, "EnterpriseIT", volumeIdentity);
            _ = ReadAndVerifyDirectory(enterprise);
            vault = OpenChildDirectory(enterprise, "CredentialVault", volumeIdentity);
            _ = ReadAndVerifyDirectory(vault);

            var chain = new WindowsDirectoryHandleChain(volume, data, enterprise, vault);
            volume = data = enterprise = vault = null;
            return chain;
        }
        finally
        {
            vault?.Dispose(); enterprise?.Dispose(); data?.Dispose(); volume?.Dispose();
        }
    }

    private static SafeFileHandle OpenAbsoluteDirectory(string path)
    {
        var handle = CreateFileW(path, FileReadAttributes | ReadControl | Synchronize,
            ShareRead | ShareWrite, IntPtr.Zero, OpenExisting,
            BackupSemantics | OpenReparsePoint, IntPtr.Zero);
        if (handle.IsInvalid)
        {
            var error = Marshal.GetLastWin32Error();
            handle.Dispose();
            throw new Win32Exception(error);
        }
        _ = ReadAndVerifyDirectory(handle);
        return handle;
    }

    private static SafeFileHandle OpenChildDirectory(SafeFileHandle parent, string component,
        DirectoryIdentity expectedVolume)
    {
        if (component.Length is < 1 or > 64 || component is "." or ".." ||
            component.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not '-' and not '_' and not '.'))
            throw new ArgumentException("Invalid fixed directory component.", nameof(component));

        var nameBuffer = Marshal.StringToHGlobalUni(component);
        var unicodeNameBuffer = Marshal.AllocHGlobal(Marshal.SizeOf<UnicodeString>());
        SafeFileHandle? child = null;
        var addedRef = false;
        try
        {
            var unicodeName = new UnicodeString
            {
                Length = checked((ushort)(component.Length * sizeof(char))),
                MaximumLength = checked((ushort)((component.Length + 1) * sizeof(char))),
                Buffer = nameBuffer
            };
            Marshal.StructureToPtr(unicodeName, unicodeNameBuffer, false);
            var attributes = new ObjectAttributes
            {
                Length = Marshal.SizeOf<ObjectAttributes>(),
                RootDirectory = parent.DangerousGetHandle(),
                ObjectName = unicodeNameBuffer,
                Attributes = ObjectCaseInsensitive
            };
            var ioStatus = new IoStatusBlock();
            parent.DangerousAddRef(ref addedRef);
            var status = NtCreateFile(out child,
                FileReadAttributes | ReadControl | Synchronize | 0x1,
                ref attributes, ref ioStatus, IntPtr.Zero, 0, ShareRead | ShareWrite,
                FileOpen, FileDirectoryFile | FileOpenReparsePoint | FileSynchronousIoNonAlert,
                IntPtr.Zero, 0);

            if (status < 0)
            {
                child?.Dispose();
                child = null;
                throw new Win32Exception(unchecked((int)RtlNtStatusToDosError(status)));
            }

            var actual = ReadAndVerifyDirectory(child);
            if (actual.VolumeSerialNumber != expectedVolume.VolumeSerialNumber)
                throw new UnauthorizedAccessException("Credential vault path crossed a volume boundary.");

            var result = child;
            child = null;
            return result;
        }
        finally
        {
            if (addedRef) parent.DangerousRelease();
            child?.Dispose();
            Marshal.FreeHGlobal(unicodeNameBuffer);
            Marshal.FreeHGlobal(nameBuffer);
        }
    }

    private static DirectoryIdentity ReadAndVerifyDirectory(SafeFileHandle handle)
    {
        if (handle.IsInvalid || !GetFileInformationByHandleEx(handle, AttributeTagInfoClass,
                out var attributes, Marshal.SizeOf<FileAttributeTagInfo>()))
            throw new Win32Exception(Marshal.GetLastWin32Error());
        if ((attributes.FileAttributes & DirectoryAttribute) == 0 ||
            (attributes.FileAttributes & ReparseAttribute) != 0)
            throw new UnauthorizedAccessException("A keyring path component is not a plain directory.");

        if (!GetFileInformationByHandleEx(handle, FileIdInfoClass,
                out var identity, Marshal.SizeOf<FileIdInfo>()))
            throw new Win32Exception(Marshal.GetLastWin32Error());
        return new DirectoryIdentity(identity.VolumeSerialNumber, identity.FileIdLow, identity.FileIdHigh);
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        vaultRoot.Dispose(); enterpriseRoot.Dispose(); programData.Dispose(); volumeRoot.Dispose();
    }

    private readonly record struct DirectoryIdentity(ulong VolumeSerialNumber, ulong FileIdLow, ulong FileIdHigh);
    [StructLayout(LayoutKind.Sequential)] private struct UnicodeString { public ushort Length, MaximumLength; public IntPtr Buffer; }
    [StructLayout(LayoutKind.Sequential)] private struct ObjectAttributes
    {
        public int Length; public IntPtr RootDirectory, ObjectName; public uint Attributes;
        public IntPtr SecurityDescriptor, SecurityQualityOfService;
    }
    [StructLayout(LayoutKind.Sequential)] private struct IoStatusBlock { public IntPtr Status; public UIntPtr Information; }
    [StructLayout(LayoutKind.Sequential)] private struct FileAttributeTagInfo { public uint FileAttributes, ReparseTag; }
    [StructLayout(LayoutKind.Sequential)] private struct FileIdInfo { public ulong VolumeSerialNumber, FileIdLow, FileIdHigh; }

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

    [DllImport("ntdll.dll")]
    private static extern int NtCreateFile(out SafeFileHandle fileHandle, uint desiredAccess,
        ref ObjectAttributes objectAttributes, ref IoStatusBlock ioStatusBlock, IntPtr allocationSize,
        uint fileAttributes, uint shareAccess, uint createDisposition, uint createOptions,
        IntPtr eaBuffer, uint eaLength);

    [DllImport("ntdll.dll")]
    private static extern uint RtlNtStatusToDosError(int status);
}
