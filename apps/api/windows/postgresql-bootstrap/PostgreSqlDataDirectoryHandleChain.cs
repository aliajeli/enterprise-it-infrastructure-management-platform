using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace EnterpriseIT.PostgreSQLBootstrap;

/// <summary>
/// Pins the fixed ProgramData PostgreSQL directory chain without FILE_SHARE_DELETE.
/// Every component is opened relative to its retained parent handle with
/// FILE_OPEN_REPARSE_POINT, then checked for directory type, reparse status,
/// volume serial and 128-bit file ID. Reopening the chain detects replacement.
/// </summary>
internal sealed class PostgreSqlDataDirectoryHandleChain : IDisposable
{
    private const uint FileReadAttributes = 0x80, ReadControl = 0x20000, Synchronize = 0x100000;
    private const uint ShareRead = 1, ShareWrite = 2, OpenExisting = 3;
    private const uint BackupSemantics = 0x02000000, OpenReparsePoint = 0x00200000;
    private const uint DirectoryAttribute = 0x10, ReparseAttribute = 0x400;
    private const uint ObjectCaseInsensitive = 0x40, FileDirectoryFile = 1;
    private const uint FileOpenReparsePoint = 0x00200000, FileSynchronousIoNonAlert = 0x20;
    private const uint FileOpen = 1;
    private const uint FileWriteData = 0x2;
    private const uint PointerEnd = 2; // FILE_END for SetFilePointerEx
    private const int FileAttributeTagInfoClass = 9, FileIdInfoClass = 18;

    private readonly string _displayPath;
    private readonly SafeFileHandle _volume;
    private readonly SafeFileHandle[] _components;
    private readonly Identity[] _identities;
    private bool _disposed;

    private PostgreSqlDataDirectoryHandleChain(string displayPath, SafeFileHandle volume,
        SafeFileHandle[] components, Identity[] identities)
    {
        _displayPath = displayPath;
        _volume = volume;
        _components = components;
        _identities = identities;
    }

    internal string DisplayPath { get { ThrowIfDisposed(); return _displayPath; } }

    internal static PostgreSqlDataDirectoryHandleChain OpenKnownDataRoot()
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException();
        var known = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
        if (string.IsNullOrWhiteSpace(known)) throw new UnauthorizedAccessException("ProgramData is unavailable.");
        var full = Path.GetFullPath(known).TrimEnd(Path.DirectorySeparatorChar);
        var volumePath = Path.GetPathRoot(full);
        if (string.IsNullOrEmpty(volumePath) || volumePath.Length != 3 ||
            !char.IsAsciiLetter(volumePath[0]) || volumePath[1] != ':' ||
            !string.Equals(Path.GetRelativePath(volumePath, full), "ProgramData", StringComparison.OrdinalIgnoreCase))
            throw new UnauthorizedAccessException("ProgramData must be the fixed local volume directory.");

        SafeFileHandle? volume = null;
        var opened = new List<SafeFileHandle>();
        try
        {
            volume = OpenAbsoluteDirectory(volumePath);
            var volumeIdentity = ReadDirectoryIdentity(volume);
            var parent = volume;
            foreach (var component in new[] { "ProgramData", "EnterpriseIT", "PostgreSQL", "18", "data" })
            {
                var child = OpenChildDirectory(parent, component);
                var identity = ReadDirectoryIdentity(child);
                if (identity.VolumeSerial != volumeIdentity.VolumeSerial)
                {
                    child.Dispose();
                    throw new UnauthorizedAccessException("PostgreSQL data path crossed a volume boundary.");
                }
                opened.Add(child);
                parent = child;
            }
            var ids = opened.Select(ReadDirectoryIdentity).ToArray();
            var result = new PostgreSqlDataDirectoryHandleChain(
                Path.Combine(full, "EnterpriseIT", "PostgreSQL", "18", "data"), volume,
                opened.ToArray(), ids);
            volume = null;
            opened.Clear();
            return result;
        }
        finally
        {
            for (var i = opened.Count - 1; i >= 0; i--) opened[i].Dispose();
            volume?.Dispose();
        }
    }

    /// <summary>Reopens each fixed component from the volume root and compares all IDs.</summary>
    internal void VerifyStillBound()
    {
        ThrowIfDisposed();
        using var current = OpenKnownDataRoot();
        if (_identities.Length != current._identities.Length)
            throw new UnauthorizedAccessException("PostgreSQL data path identity changed.");
        for (var i = 0; i < _identities.Length; i++)
            if (_identities[i] != current._identities[i])
                throw new UnauthorizedAccessException("PostgreSQL data path was replaced during initialization.");
    }

    /// <summary>Opens a fixed leaf relative to the pinned data directory and rejects reparse points.</summary>
    internal SafeFileHandle OpenDataFileForRead(string name)
    {
        ThrowIfDisposed();
        if (name is not ("PG_VERSION" or "pg_hba.conf" or "postgresql.conf"))
            throw new ArgumentException("Unexpected PostgreSQL verification file.", nameof(name));
        var parent = _components[^1];
        var nameBuffer = Marshal.StringToHGlobalUni(name);
        var unicodeBuffer = Marshal.AllocHGlobal(Marshal.SizeOf<UnicodeString>());
        SafeFileHandle? file = null;
        var parentRef = false;
        try
        {
            Marshal.StructureToPtr(new UnicodeString
            {
                Length = checked((ushort)(name.Length * sizeof(char))),
                MaximumLength = checked((ushort)((name.Length + 1) * sizeof(char))),
                Buffer = nameBuffer
            }, unicodeBuffer, false);
            var attributes = new ObjectAttributes
            {
                Length = Marshal.SizeOf<ObjectAttributes>(),
                RootDirectory = parent.DangerousGetHandle(),
                ObjectName = unicodeBuffer,
                Attributes = ObjectCaseInsensitive
            };
            var io = new IoStatusBlock();
            parent.DangerousAddRef(ref parentRef);
            var status = NtCreateFile(out file, 0x80000000u | FileReadAttributes | ReadControl | Synchronize,
                ref attributes, ref io, IntPtr.Zero, 0, ShareRead, FileOpen,
                FileOpenReparsePoint | FileSynchronousIoNonAlert, IntPtr.Zero, 0);
            if (status < 0)
                throw new Win32Exception(unchecked((int)RtlNtStatusToDosError(status)));
            if (!TryGetFileInformationByHandleEx(file, FileAttributeTagInfoClass, out FileAttributeTagInfo tag) ||
                (tag.FileAttributes & (DirectoryAttribute | ReparseAttribute)) != 0)
                throw new UnauthorizedAccessException("PostgreSQL verification file is a directory or reparse point.");
            if (!TryGetFileInformationByHandleEx(file, FileIdInfoClass, out FileIdInfo fileId) ||
                fileId.VolumeSerial != _identities[^1].VolumeSerial)
                throw new UnauthorizedAccessException("PostgreSQL verification file identity is invalid.");
            var result = file;
            file = null;
            return result;
        }
        finally
        {
            if (parentRef) parent.DangerousRelease();
            file?.Dispose();
            Marshal.FreeHGlobal(unicodeBuffer);
            Marshal.FreeHGlobal(nameBuffer);
        }
    }

    /// <summary>Appends UTF-8 text to a fixed configuration leaf relative to the
    /// pinned data directory. The leaf must already exist as a plain file on the
    /// pinned volume; no create, rename or path-based write is possible.</summary>
    internal void AppendDataFileText(string name, string text)
    {
        ThrowIfDisposed();
        if (name is not ("postgresql.conf" or "pg_hba.conf"))
            throw new ArgumentException("Unexpected PostgreSQL configuration file.", nameof(name));
        var bytes = new UTF8Encoding(false).GetBytes(text);
        var parent = _components[^1];
        var nameBuffer = Marshal.StringToHGlobalUni(name);
        var unicodeBuffer = Marshal.AllocHGlobal(Marshal.SizeOf<UnicodeString>());
        SafeFileHandle? file = null;
        var parentRef = false;
        try
        {
            Marshal.StructureToPtr(new UnicodeString
            {
                Length = checked((ushort)(name.Length * sizeof(char))),
                MaximumLength = checked((ushort)((name.Length + 1) * sizeof(char))),
                Buffer = nameBuffer
            }, unicodeBuffer, false);
            var attributes = new ObjectAttributes
            {
                Length = Marshal.SizeOf<ObjectAttributes>(),
                RootDirectory = parent.DangerousGetHandle(),
                ObjectName = unicodeBuffer,
                Attributes = ObjectCaseInsensitive
            };
            var io = new IoStatusBlock();
            parent.DangerousAddRef(ref parentRef);
            var status = NtCreateFile(out file, FileWriteData | FileReadAttributes | ReadControl | Synchronize,
                ref attributes, ref io, IntPtr.Zero, 0, ShareRead, FileOpen,
                FileOpenReparsePoint | FileSynchronousIoNonAlert, IntPtr.Zero, 0);
            if (status < 0)
                throw new Win32Exception(unchecked((int)RtlNtStatusToDosError(status)));
            if (!TryGetFileInformationByHandleEx(file, FileAttributeTagInfoClass, out FileAttributeTagInfo tag) ||
                (tag.FileAttributes & (DirectoryAttribute | ReparseAttribute)) != 0)
                throw new UnauthorizedAccessException("PostgreSQL configuration file is a directory or reparse point.");
            if (!TryGetFileInformationByHandleEx(file, FileIdInfoClass, out FileIdInfo fileId) ||
                fileId.VolumeSerial != _identities[^1].VolumeSerial)
                throw new UnauthorizedAccessException("PostgreSQL configuration file identity is invalid.");
            if (!SetFilePointerEx(file, 0, out _, PointerEnd))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            if (!WriteFile(file, bytes, checked((uint)bytes.Length), out var written, IntPtr.Zero) ||
                written != (uint)bytes.Length)
                throw new Win32Exception(Marshal.GetLastWin32Error());
        }
        finally
        {
            if (parentRef) parent.DangerousRelease();
            file?.Dispose();
            Marshal.FreeHGlobal(unicodeBuffer);
            Marshal.FreeHGlobal(nameBuffer);
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
        _ = ReadDirectoryIdentity(handle);
        return handle;
    }

    private static SafeFileHandle OpenChildDirectory(SafeFileHandle parent, string component)
    {
        var nameBuffer = Marshal.StringToHGlobalUni(component);
        var unicodeBuffer = Marshal.AllocHGlobal(Marshal.SizeOf<UnicodeString>());
        SafeFileHandle? child = null;
        var parentRef = false;
        try
        {
            Marshal.StructureToPtr(new UnicodeString
            {
                Length = checked((ushort)(component.Length * sizeof(char))),
                MaximumLength = checked((ushort)((component.Length + 1) * sizeof(char))),
                Buffer = nameBuffer
            }, unicodeBuffer, false);
            var attributes = new ObjectAttributes
            {
                Length = Marshal.SizeOf<ObjectAttributes>(),
                RootDirectory = parent.DangerousGetHandle(),
                ObjectName = unicodeBuffer,
                Attributes = ObjectCaseInsensitive
            };
            var io = new IoStatusBlock();
            parent.DangerousAddRef(ref parentRef);
            var status = NtCreateFile(out child, FileReadAttributes | ReadControl | Synchronize,
                ref attributes, ref io, IntPtr.Zero, 0, ShareRead | ShareWrite,
                FileOpen, FileDirectoryFile | FileOpenReparsePoint | FileSynchronousIoNonAlert,
                IntPtr.Zero, 0);
            if (status < 0)
                throw new Win32Exception(unchecked((int)RtlNtStatusToDosError(status)));
            _ = ReadDirectoryIdentity(child);
            var result = child;
            child = null;
            return result;
        }
        finally
        {
            if (parentRef) parent.DangerousRelease();
            child?.Dispose();
            Marshal.FreeHGlobal(unicodeBuffer);
            Marshal.FreeHGlobal(nameBuffer);
        }
    }

    private static Identity ReadDirectoryIdentity(SafeFileHandle handle)
    {
        if (handle.IsInvalid ||
            !TryGetFileInformationByHandleEx(handle, FileAttributeTagInfoClass, out FileAttributeTagInfo tag))
            throw new Win32Exception(Marshal.GetLastWin32Error());
        if ((tag.FileAttributes & DirectoryAttribute) == 0 ||
            (tag.FileAttributes & ReparseAttribute) != 0)
            throw new UnauthorizedAccessException("A PostgreSQL path component is not a plain directory.");
        if (!TryGetFileInformationByHandleEx(handle, FileIdInfoClass, out FileIdInfo id))
            throw new Win32Exception(Marshal.GetLastWin32Error());
        return new Identity(id.VolumeSerial, id.FileIdLow, id.FileIdHigh);
    }

    private void ThrowIfDisposed() => ObjectDisposedException.ThrowIf(_disposed, this);

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        for (var i = _components.Length - 1; i >= 0; i--) _components[i].Dispose();
        _volume.Dispose();
    }

    private readonly record struct Identity(ulong VolumeSerial, ulong FileIdLow, ulong FileIdHigh);
    [StructLayout(LayoutKind.Sequential)] private struct UnicodeString { public ushort Length, MaximumLength; public IntPtr Buffer; }
    [StructLayout(LayoutKind.Sequential)] private struct ObjectAttributes
    {
        public int Length; public IntPtr RootDirectory, ObjectName; public uint Attributes;
        public IntPtr SecurityDescriptor, SecurityQualityOfService;
    }
    [StructLayout(LayoutKind.Sequential)] private struct IoStatusBlock { public IntPtr Status; public UIntPtr Information; }
    [StructLayout(LayoutKind.Sequential)] private struct FileAttributeTagInfo { public uint FileAttributes, ReparseTag; }
    [StructLayout(LayoutKind.Sequential)] private struct FileIdInfo { public ulong VolumeSerial, FileIdLow, FileIdHigh; }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "CreateFileW")]
    private static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security,
        uint disposition, uint flags, IntPtr template);

    private static bool TryGetFileInformationByHandleEx<T>(
        SafeFileHandle handle, int infoClass, out T info) where T : struct
    {
        var size = Marshal.SizeOf<T>();
        var buffer = Marshal.AllocHGlobal(size);
        try
        {
            if (!GetFileInformationByHandleEx(handle, infoClass, buffer, checked((uint)size)))
            {
                info = default;
                return false;
            }
            info = Marshal.PtrToStructure<T>(buffer);
            return true;
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    [DllImport("kernel32.dll", SetLastError = true, EntryPoint = "GetFileInformationByHandleEx")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandleEx(
        SafeFileHandle handle, int infoClass, IntPtr info, uint size);

    [DllImport("ntdll.dll")]
    private static extern int NtCreateFile(out SafeFileHandle handle, uint access,
        ref ObjectAttributes attributes, ref IoStatusBlock io, IntPtr allocationSize,
        uint fileAttributes, uint shareAccess, uint disposition, uint options, IntPtr ea, uint eaLength);

    [DllImport("ntdll.dll")]
    private static extern uint RtlNtStatusToDosError(int status);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetFilePointerEx(SafeFileHandle hFile, long distanceToMove,
        out long lpDistanceToMoveHigh, uint dwMoveMethod);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool WriteFile(SafeFileHandle hFile, byte[] lpBuffer, uint nNumberOfBytesToWrite,
        out uint lpNumberOfBytesWritten, IntPtr lpOverlapped);
}
