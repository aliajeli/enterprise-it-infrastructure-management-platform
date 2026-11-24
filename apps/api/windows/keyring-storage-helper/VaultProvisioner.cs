using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;

namespace CredentialVault.KeyringStorageHelper;

/// <summary>
/// Elevated provisioning and verify-only validation for the Credential Vault
/// directory and keyring.lock. This mode is invoked by the installer/orchestrator,
/// not by the runtime service. It never writes secrets and never uses the current
/// process token as the API service SID.
/// </summary>
internal static class VaultProvisioner
{
    private const string ProvisionFlag = "--provision-vault";
    private const string VerifyFlag = "--verify-vault";
    private const uint FileReadAttributes = 0x80;
    private const uint ReadControl = 0x20000;
    private const uint Synchronize = 0x100000;
    private const uint GenericRead = 0x80000000;
    private const uint GenericWrite = 0x40000000;
    private const uint DeleteAccess = 0x10000;
    private const uint FileAddFile = 0x2;
    private const uint FileAddSubdirectory = 0x4;
    private const uint FileDeleteChild = 0x40;
    private const uint ShareRead = 1;
    private const uint ShareWrite = 2;
    private const uint OpenExisting = 3;
    private const uint CreateNew = 2; // NT FILE_CREATE, not Win32 CREATE_NEW
    private const uint FileOpen = 1;
    private const uint BackupSemantics = 0x02000000;
    private const uint OpenReparsePoint = 0x00200000;
    private const uint DirectoryAttribute = 0x10;
    private const uint ReparseAttribute = 0x400;
    private const uint FileDirectoryFile = 1;
    private const uint FileNonDirectoryFile = 0x40;
    private const uint FileOpenReparsePoint = 0x00200000;
    private const uint FileSynchronousIoNonAlert = 0x20;
    private const uint ObjectCaseInsensitive = 0x40;
    private const uint OwnerSecurityInformation = 1;
    private const uint DaclSecurityInformation = 4;
    private const uint ProtectedDaclSecurityInformation = 0x80000000;
    private const int AttributeTagInfoClass = 9;
    private const int FileIdInfoClass = 18;
    private const int FileDispositionInformationClass = 13;
    private static readonly Regex ServiceSidPattern = new(
        @"^S-1-5-80-(?:\d+-){4}\d+$",
        RegexOptions.CultureInvariant | RegexOptions.Compiled);

    internal static bool IsProvisioningMode(string[] args) =>
        args.Any(a => string.Equals(a, ProvisionFlag, StringComparison.OrdinalIgnoreCase)
                   || string.Equals(a, VerifyFlag, StringComparison.OrdinalIgnoreCase));

    internal static int Execute(string[] args)
    {
        try
        {
            if (!OperatingSystem.IsWindows()) return 2;
            var options = ParseArgs(args);
            EnsureElevated();
            var serviceSid = ValidateServiceSid(options.ServiceSid);
            var programData = ResolveProgramData(options.ProgramDataRoot);
            using var chain = ProvisioningChain.Open(programData, serviceSid, options.VerifyOnly);
            chain.ProvisionOrVerify(options.VerifyOnly);
            Console.Out.Write("OK");
            return 0;
        }
        catch (ProvisioningException ex)
        {
            // Generic failure text only; never emit paths, SIDs, ACLs or secrets.
            Console.Error.Write(ex.Category);
            return ex.ExitCode;
        }
        catch
        {
            Console.Error.Write("provisioning-failed");
            return 1;
        }
    }

    private sealed record Options(string ServiceSid, bool VerifyOnly, string? ProgramDataRoot);

    private sealed class ProvisioningException : Exception
    {
        internal ProvisioningException(string category, int exitCode = 1) : base(category)
        {
            Category = category;
            ExitCode = exitCode;
        }
        internal string Category { get; }
        internal int ExitCode { get; }
    }

    private static Options ParseArgs(string[] args)
    {
        string? sid = null;
        string? programDataRoot = null;
        bool verifyOnly = false;
        bool provision = false;
        for (var i = 0; i < args.Length; i++)
        {
            var arg = args[i];
            if (string.Equals(arg, ProvisionFlag, StringComparison.OrdinalIgnoreCase)) { provision = true; continue; }
            if (string.Equals(arg, VerifyFlag, StringComparison.OrdinalIgnoreCase)) { verifyOnly = true; continue; }
            if (string.Equals(arg, "--service-sid", StringComparison.OrdinalIgnoreCase))
            {
                if (i + 1 >= args.Length) throw new ProvisioningException("invalid-arguments", 2);
                sid = args[++i];
                continue;
            }
            if (string.Equals(arg, "--program-data-root", StringComparison.OrdinalIgnoreCase))
            {
                if (i + 1 >= args.Length) throw new ProvisioningException("invalid-arguments", 2);
                programDataRoot = args[++i];
                continue;
            }
            throw new ProvisioningException("invalid-arguments", 2);
        }
        if (!provision && !verifyOnly) throw new ProvisioningException("invalid-arguments", 2);
        if (string.IsNullOrWhiteSpace(sid)) throw new ProvisioningException("invalid-arguments", 2);
        return new Options(sid, verifyOnly, programDataRoot);
    }

    private static void EnsureElevated()
    {
        using var identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);
        if (!principal.IsInRole(WindowsBuiltInRole.Administrator))
            throw new ProvisioningException("not-elevated", 3);
        if (!IsProcessElevated(identity))
            throw new ProvisioningException("not-elevated", 3);
    }

    private static bool IsProcessElevated(WindowsIdentity identity)
    {
        var token = identity.AccessToken.DangerousGetHandle();
        var size = Marshal.SizeOf<TokenElevation>();
        if (!GetTokenInformation(token, 20, out var elevation, size, out var returned) || returned != size)
            throw new ProvisioningException("not-elevated", 3);
        return elevation.TokenIsElevated != 0;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct TokenElevation { internal uint TokenIsElevated; }

    private static SecurityIdentifier ValidateServiceSid(string sidText)
    {
        if (!ServiceSidPattern.IsMatch(sidText))
            throw new ProvisioningException("invalid-service-sid", 2);
        try
        {
            return new SecurityIdentifier(sidText);
        }
        catch
        {
            throw new ProvisioningException("invalid-service-sid", 2);
        }
    }

    private static string ResolveProgramData(string? overrideRoot)
    {
        if (!string.IsNullOrWhiteSpace(overrideRoot))
        {
            var full = Path.GetFullPath(overrideRoot);
            if (!Path.IsPathRooted(full)) throw new ProvisioningException("invalid-arguments", 2);
            return full;
        }
        var known = Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData);
        if (string.IsNullOrWhiteSpace(known)) throw new ProvisioningException("programdata-unavailable");
        return Path.GetFullPath(known);
    }

    private sealed class ProvisioningChain : IDisposable
    {
        private readonly SafeFileHandle volumeRoot;
        private readonly SafeFileHandle programData;
        private readonly SafeFileHandle enterpriseRoot;
        private readonly SafeFileHandle vaultRoot;
        private readonly SecurityIdentifier serviceSid;
        private readonly string serviceSddl;
        private readonly bool createdEnterprise;
        private readonly bool createdVault;
        private readonly bool createdLock;
        private readonly DirectoryIdentity vaultIdentityAtCreation;
        private readonly VaultFileIdentity? lockIdentityAtCreation;
        private bool disposed;

        private ProvisioningChain(
            SafeFileHandle volumeRoot, SafeFileHandle programData,
            SafeFileHandle enterpriseRoot, SafeFileHandle vaultRoot,
            SecurityIdentifier serviceSid,
            bool createdEnterprise, bool createdVault, bool createdLock,
            DirectoryIdentity vaultIdentityAtCreation,
            VaultFileIdentity? lockIdentityAtCreation)
        {
            this.volumeRoot = volumeRoot;
            this.programData = programData;
            this.enterpriseRoot = enterpriseRoot;
            this.vaultRoot = vaultRoot;
            this.serviceSid = serviceSid;
            serviceSddl = $"O:{serviceSid.Value}D:P(A;;FA;;;{serviceSid.Value})(A;;FA;;;SY)";
            this.createdEnterprise = createdEnterprise;
            this.createdVault = createdVault;
            this.createdLock = createdLock;
            this.vaultIdentityAtCreation = vaultIdentityAtCreation;
            this.lockIdentityAtCreation = lockIdentityAtCreation;
        }

        internal static ProvisioningChain Open(string programDataPath, SecurityIdentifier serviceSid, bool verifyOnly)
        {
            var volumePath = Path.GetPathRoot(programDataPath);
            if (string.IsNullOrEmpty(volumePath) || volumePath.Length != 3 ||
                !char.IsAsciiLetter(volumePath[0]) || volumePath[1] != ':' ||
                (volumePath[2] != '\\' && volumePath[2] != '/'))
                throw new ProvisioningException("invalid-programdata-root");

            SafeFileHandle? volume = null, pd = null, enterprise = null, vault = null;
            bool createdEnterprise = false, createdVault = false, createdLock = false;
            // A fixed operation name and numeric OS error are safe diagnostics; never emit paths or ACLs.
            string stage = "open-volume";
            DirectoryIdentity vaultIdentity = default;
            VaultFileIdentity? lockIdentity = null;
            try
            {
                volume = OpenAbsoluteDirectory(volumePath);
                var volumeIdentity = ReadAndVerifyDirectory(volume, "programdata-root");
                stage = "open-programdata";
                pd = OpenAbsoluteDirectory(programDataPath, verifyOnly ? 0u : FileAddSubdirectory);
                var pdIdentity = ReadAndVerifyDirectory(pd, "programdata");
                if (pdIdentity.VolumeSerialNumber != volumeIdentity.VolumeSerialNumber)
                    throw new ProvisioningException("volume-mismatch");
                VerifyProgramDataAcl(pd);

                stage = "open-or-create-enterprise";
                (enterprise, createdEnterprise) = OpenOrCreateChildDirectory(
                    pd, "EnterpriseIT", volumeIdentity, verifyOnly, EnterpriseSddl(),
                    VerifyEnterpriseAcl, "enterprise-root");
                var enterpriseIdentity = ReadAndVerifyDirectory(enterprise, "enterprise-root");
                if (enterpriseIdentity.VolumeSerialNumber != volumeIdentity.VolumeSerialNumber)
                    throw new ProvisioningException("volume-mismatch");

                stage = "open-or-create-vault";
                (vault, createdVault) = OpenOrCreateChildDirectory(
                    enterprise, "CredentialVault", volumeIdentity, verifyOnly,
                    ServiceSddl(serviceSid), (h, _) => VerifyVaultAcl(h, serviceSid), "credential-vault");
                vaultIdentity = ReadAndVerifyDirectory(vault, "credential-vault");
                if (vaultIdentity.VolumeSerialNumber != volumeIdentity.VolumeSerialNumber)
                    throw new ProvisioningException("volume-mismatch");
                VerifyVaultAcl(vault, serviceSid);

                stage = "open-or-create-lock";
                (var lockHandle, createdLock) = OpenOrCreateLockFile(vault, serviceSid, verifyOnly);
                using (lockHandle)
                {
                    lockIdentity = ReadAndVerifyRegularFile(lockHandle, "keyring-lock");
                    VerifyVaultAcl(lockHandle, serviceSid);
                }

                var chain = new ProvisioningChain(volume, pd, enterprise, vault, serviceSid,
                    createdEnterprise, createdVault, createdLock, vaultIdentity, lockIdentity);
                volume = pd = enterprise = vault = null;
                return chain;
            }
            catch (Exception ex)
            {
                // Roll back only objects created by this exact invocation.
                try { Rollback(vault, enterprise, createdLock, createdVault, createdEnterprise, vaultIdentity, lockIdentity); }
                catch { /* fail closed: leave objects and report original failure */ }
                vault?.Dispose(); enterprise?.Dispose(); pd?.Dispose(); volume?.Dispose();
                if (ex is Win32Exception nativeError)
                    throw new ProvisioningException($"{stage}:win32-{nativeError.NativeErrorCode}");
                if (ex is not ProvisioningException)
                    throw new ProvisioningException($"{stage}:unexpected-error");
                throw;
            }
        }

        internal void ProvisionOrVerify(bool verifyOnly)
        {
            // Post-create/verify validation by handle.
            var vaultId = ReadAndVerifyDirectory(vaultRoot, "credential-vault");
            if (createdVault && vaultId != vaultIdentityAtCreation)
                throw new ProvisioningException("post-create-identity-mismatch");
            VerifyNotReparse(vaultRoot, "credential-vault");
            VerifyVaultAcl(vaultRoot, serviceSid);

            using var lockHandle = OpenRelativeFile(vaultRoot, "keyring.lock", GenericRead | ReadControl | Synchronize, ShareRead, FileOpen);
            var lockId = ReadAndVerifyRegularFile(lockHandle, "keyring-lock");
            if (createdLock && lockIdentityAtCreation.HasValue && lockId != lockIdentityAtCreation.Value)
                throw new ProvisioningException("post-create-identity-mismatch");
            VerifyNotReparse(lockHandle, "keyring-lock");
            VerifyVaultAcl(lockHandle, serviceSid);

            _ = ReadAndVerifyDirectory(enterpriseRoot, "enterprise-root");
            VerifyNotReparse(enterpriseRoot, "enterprise-root");
            VerifyEnterpriseAcl(enterpriseRoot, serviceSid);
            _ = ReadAndVerifyDirectory(programData, "programdata");
            VerifyNotReparse(programData, "programdata");
            VerifyProgramDataAcl(programData);
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            vaultRoot.Dispose();
            enterpriseRoot.Dispose();
            programData.Dispose();
            volumeRoot.Dispose();
        }
    }

    private static string ServiceSddl(SecurityIdentifier serviceSid) =>
        $"O:{serviceSid.Value}D:P(A;;FA;;;{serviceSid.Value})(A;;FA;;;SY)";

    private static string EnterpriseSddl() =>
        "O:BAG:SYD:P(A;OICI;FA;;;BA)(A;OICI;FA;;;SY)";

    private static void Rollback(
        SafeFileHandle? vault, SafeFileHandle? enterprise,
        bool createdLock, bool createdVault, bool createdEnterprise,
        DirectoryIdentity vaultIdentity, VaultFileIdentity? lockIdentity)
    {
        // Roll back in reverse order. Delete only exact objects created by this invocation.
        if (createdLock && vault is not null && !vault.IsInvalid && lockIdentity.HasValue)
        {
            try
            {
                using var h = OpenRelativeFile(vault, "keyring.lock", ReadControl | DeleteAccess | Synchronize, 0, FileOpen);
                var id = ReadAndVerifyRegularFile(h, "keyring-lock");
                if (id == lockIdentity.Value)
                    DeleteRelativeHandle(h);
            }
            catch { /* leave in place; fail closed by caller */ }
        }
        if (createdVault && enterprise is not null && !enterprise.IsInvalid)
        {
            try
            {
                using var h = OpenRelativeDirectory(enterprise, "CredentialVault", ReadControl | DeleteAccess | Synchronize, FileOpen);
                var id = ReadAndVerifyDirectory(h, "credential-vault");
                if (id == vaultIdentity)
                    DeleteRelativeHandle(h);
            }
            catch { /* leave in place; fail closed by caller */ }
        }
        // We do not roll back EnterpriseIT if we created it only when it is empty and we created it;
        // safer to leave it than risk deleting unexpected content. The caller fails closed.
        _ = createdEnterprise;
    }

    private static (SafeFileHandle handle, bool created) OpenOrCreateChildDirectory(
        SafeFileHandle parent, string name, DirectoryIdentity expectedVolume,
        bool verifyOnly, string sddl,
        Action<SafeFileHandle, SecurityIdentifier> verifyAcl, string label)
    {
        var access = FileReadAttributes | ReadControl | Synchronize | (verifyOnly ? 0u : (FileAddFile | FileAddSubdirectory | FileDeleteChild));
        try
        {
            var existing = OpenRelativeDirectory(parent, name, access, FileOpen);
            var id = ReadAndVerifyDirectory(existing, label);
            if (id.VolumeSerialNumber != expectedVolume.VolumeSerialNumber)
            { existing.Dispose(); throw new ProvisioningException("volume-mismatch"); }
            verifyAcl(existing, null!);
            return (existing, false);
        }
        catch (Win32Exception ex) when (ex.NativeErrorCode == 2)
        {
            if (verifyOnly) throw new ProvisioningException("missing-required-object");
            var sd = SddlToPtr(sddl);
            try
            {
                var created = OpenRelativeDirectory(parent, name, access, CreateNew, sd);
                var id = ReadAndVerifyDirectory(created, label);
                if (id.VolumeSerialNumber != expectedVolume.VolumeSerialNumber)
                { created.Dispose(); throw new ProvisioningException("volume-mismatch"); }
                verifyAcl(created, null!);
                return (created, true);
            }
            finally
            {
                if (sd != IntPtr.Zero) LocalFree(sd);
            }
        }
        catch (ProvisioningException) { throw; }
        catch { throw new ProvisioningException("path-validation-failed"); }
    }

    private static (SafeFileHandle handle, bool created) OpenOrCreateLockFile(
        SafeFileHandle vaultRoot, SecurityIdentifier serviceSid, bool verifyOnly)
    {
        try
        {
            var existing = OpenRelativeFile(vaultRoot, "keyring.lock", GenericRead | ReadControl | Synchronize, ShareRead, FileOpen);
            _ = ReadAndVerifyRegularFile(existing, "keyring-lock");
            VerifyVaultAcl(existing, serviceSid);
            return (existing, false);
        }
        catch (Win32Exception ex) when (ex.NativeErrorCode == 2)
        {
            if (verifyOnly) throw new ProvisioningException("missing-required-object");
            var sddl = ServiceSddl(serviceSid);
            var sd = SddlToPtr(sddl);
            try
            {
                var created = OpenRelativeFile(vaultRoot, "keyring.lock",
                    GenericRead | GenericWrite | ReadControl | Synchronize, 0, CreateNew, sd);
                _ = ReadAndVerifyRegularFile(created, "keyring-lock");
                VerifyVaultAcl(created, serviceSid);
                return (created, true);
            }
            finally
            {
                if (sd != IntPtr.Zero) LocalFree(sd);
            }
        }
        catch (ProvisioningException) { throw; }
        catch { throw new ProvisioningException("path-validation-failed"); }
    }

    private static IntPtr SddlToPtr(string sddl)
    {
        if (!ConvertStringSecurityDescriptorToSecurityDescriptorW(sddl, 1, out var sd, out _))
            throw new ProvisioningException("sddl-conversion-failed");
        return sd;
    }

    private static SafeFileHandle OpenAbsoluteDirectory(string path, uint additionalAccess = 0)
    {
        var handle = CreateFileW(path, FileReadAttributes | ReadControl | Synchronize | additionalAccess,
            ShareRead | ShareWrite, IntPtr.Zero, OpenExisting,
            BackupSemantics | OpenReparsePoint, IntPtr.Zero);
        if (handle.IsInvalid)
        {
            var error = Marshal.GetLastWin32Error();
            handle.Dispose();
            throw new Win32Exception(error);
        }
        return handle;
    }

    private static SafeFileHandle OpenRelativeDirectory(SafeFileHandle parent, string component,
        uint desiredAccess, uint disposition, IntPtr securityDescriptor = default)
    {
        return OpenRelativeObject(parent, component, desiredAccess, 0, disposition,
            FileDirectoryFile | FileOpenReparsePoint | FileSynchronousIoNonAlert, securityDescriptor);
    }

    private static SafeFileHandle OpenRelativeFile(SafeFileHandle parent, string component,
        uint desiredAccess, uint shareAccess, uint disposition, IntPtr securityDescriptor = default)
    {
        return OpenRelativeObject(parent, component, desiredAccess, shareAccess, disposition,
            FileNonDirectoryFile | FileOpenReparsePoint | FileSynchronousIoNonAlert, securityDescriptor, 0x80);
    }

    private static SafeFileHandle OpenRelativeObject(SafeFileHandle parent, string component,
        uint desiredAccess, uint shareAccess, uint disposition, uint createOptions,
        IntPtr securityDescriptor, uint fileAttributes = 0)
    {
        ValidateComponent(component);
        var nameBuffer = Marshal.StringToHGlobalUni(component);
        var unicodeNameBuffer = Marshal.AllocHGlobal(Marshal.SizeOf<UnicodeString>());
        SafeFileHandle? handle = null;
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
                Attributes = ObjectCaseInsensitive,
                SecurityDescriptor = securityDescriptor
            };
            var ioStatus = new IoStatusBlock();
            parent.DangerousAddRef(ref addedRef);
            var status = NtCreateFile(out handle, desiredAccess | Synchronize, ref attributes, ref ioStatus,
                IntPtr.Zero, fileAttributes, shareAccess, disposition, createOptions, IntPtr.Zero, 0);
            if (status < 0)
            {
                handle?.Dispose();
                handle = null;
                throw new Win32Exception(unchecked((int)RtlNtStatusToDosError(status)));
            }
            var result = handle;
            handle = null;
            return result;
        }
        finally
        {
            if (addedRef) parent.DangerousRelease();
            handle?.Dispose();
            Marshal.FreeHGlobal(unicodeNameBuffer);
            Marshal.FreeHGlobal(nameBuffer);
        }
    }

    private static void ValidateComponent(string component)
    {
        if (string.IsNullOrWhiteSpace(component) || component.Length > 128 || component is "." or ".." ||
            component.IndexOfAny(new[] { '/', '\\', ':', '*', '?', '"', '<', '>', '|', '\0' }) >= 0)
            throw new ProvisioningException("invalid-component");
    }

    private static void DeleteRelativeHandle(SafeFileHandle handle)
    {
        var info = Marshal.AllocHGlobal(1);
        try
        {
            Marshal.WriteByte(info, 0, 1);
            var ioStatus = new IoStatusBlock();
            var status = NtSetInformationFile(handle, ref ioStatus, info, 1, FileDispositionInformationClass);
            if (status < 0)
                throw new Win32Exception(unchecked((int)RtlNtStatusToDosError(status)));
        }
        finally
        {
            Marshal.FreeHGlobal(info);
        }
    }

    private static DirectoryIdentity ReadAndVerifyDirectory(SafeFileHandle handle, string label)
    {
        if (handle.IsInvalid || !GetFileInformationByHandleEx(handle, AttributeTagInfoClass, out FileAttributeTagInfo tag, Marshal.SizeOf<FileAttributeTagInfo>()))
            throw new ProvisioningException($"path-validation-failed:{label}");
        if ((tag.FileAttributes & DirectoryAttribute) == 0 || (tag.FileAttributes & ReparseAttribute) != 0)
            throw new ProvisioningException($"unexpected-object-type:{label}");
        if (!GetFileInformationByHandleEx(handle, FileIdInfoClass, out FileIdInfo id, Marshal.SizeOf<FileIdInfo>()))
            throw new ProvisioningException($"path-validation-failed:{label}");
        return new DirectoryIdentity(id.VolumeSerialNumber, id.FileIdLow, id.FileIdHigh);
    }

    private static VaultFileIdentity ReadAndVerifyRegularFile(SafeFileHandle handle, string label)
    {
        if (handle.IsInvalid || !GetFileInformationByHandleEx(handle, AttributeTagInfoClass, out FileAttributeTagInfo tag, Marshal.SizeOf<FileAttributeTagInfo>()))
            throw new ProvisioningException($"path-validation-failed:{label}");
        if ((tag.FileAttributes & DirectoryAttribute) != 0 || (tag.FileAttributes & ReparseAttribute) != 0)
            throw new ProvisioningException($"unexpected-object-type:{label}");
        if (!GetFileInformationByHandleEx(handle, FileIdInfoClass, out FileIdInfo id, Marshal.SizeOf<FileIdInfo>()))
            throw new ProvisioningException($"path-validation-failed:{label}");
        return new VaultFileIdentity(id.VolumeSerialNumber, id.FileIdLow, id.FileIdHigh);
    }

    private static void VerifyNotReparse(SafeFileHandle handle, string label)
    {
        if (!GetFileInformationByHandleEx(handle, AttributeTagInfoClass, out FileAttributeTagInfo tag, Marshal.SizeOf<FileAttributeTagInfo>()))
            throw new ProvisioningException($"path-validation-failed:{label}");
        if ((tag.FileAttributes & ReparseAttribute) != 0)
            throw new ProvisioningException($"reparse-point:{label}");
    }

    private static void VerifyVaultAcl(SafeFileHandle handle, SecurityIdentifier expectedServiceSid)
    {
        // Exact two-ACE policy matching runtime helper: owner=service SID, DACL protected,
        // exactly (A;;FA;;;serviceSID)(A;;FA;;;SY).
        var sd = ReadSecurityDescriptor(handle);
        if (sd.Owner is null || !expectedServiceSid.Equals(sd.Owner))
            throw new ProvisioningException("acl-owner-mismatch");
        if ((sd.ControlFlags & ControlFlags.DiscretionaryAclProtected) == 0 ||
            (sd.ControlFlags & ControlFlags.DiscretionaryAclPresent) == 0 ||
            sd.DiscretionaryAcl is null || sd.DiscretionaryAcl.Count != 2)
            throw new ProvisioningException("acl-dacl-mismatch");

        bool serviceAce = false, systemAce = false;
        var systemSid = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
        foreach (GenericAce ace in sd.DiscretionaryAcl)
        {
            if (ace is not CommonAce common ||
                common.AceQualifier != AceQualifier.AccessAllowed ||
                common.AceFlags != AceFlags.None ||
                common.IsCallback ||
                common.AccessMask != unchecked((int)0x001F01FF))
                throw new ProvisioningException("acl-dacl-mismatch");
            if (expectedServiceSid.Equals(common.SecurityIdentifier) && !serviceAce) serviceAce = true;
            else if (systemSid.Equals(common.SecurityIdentifier) && !systemAce) systemAce = true;
            else throw new ProvisioningException("acl-dacl-mismatch");
        }
        if (!serviceAce || !systemAce) throw new ProvisioningException("acl-dacl-mismatch");
    }

    private static void VerifyEnterpriseAcl(SafeFileHandle handle, SecurityIdentifier _)
    {
        // EnterpriseIT is an application-owned parent. Policy: owner is BUILTIN\Administrators
        // or LocalSystem, protected DACL, and no allow ACE grants write/modify rights to
        // non-admin non-system principals. We allow SYSTEM FA and Administrators FA.
        var sd = ReadSecurityDescriptor(handle);
        var admins = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
        var system = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
        if (sd.Owner is null || (!admins.Equals(sd.Owner) && !system.Equals(sd.Owner)))
            throw new ProvisioningException("parent-acl-owner-mismatch");
        if ((sd.ControlFlags & ControlFlags.DiscretionaryAclProtected) == 0 ||
            (sd.ControlFlags & ControlFlags.DiscretionaryAclPresent) == 0 ||
            sd.DiscretionaryAcl is null)
            throw new ProvisioningException("parent-acl-dacl-mismatch");

        bool hasAdminFa = false, hasSystemFa = false;
        foreach (GenericAce ace in sd.DiscretionaryAcl)
        {
            if (ace is not CommonAce common) throw new ProvisioningException("parent-acl-dacl-mismatch");
            if (common.AceQualifier != AceQualifier.AccessAllowed)
                throw new ProvisioningException("parent-acl-dacl-mismatch");
            if (common.IsCallback) throw new ProvisioningException("parent-acl-dacl-mismatch");
            var sid = common.SecurityIdentifier;
            var mask = unchecked((uint)common.AccessMask);
            bool isAdmin = admins.Equals(sid);
            bool isSystem = system.Equals(sid);
            if (isAdmin && mask == 0x001F01FF && common.AceFlags == (AceFlags.ObjectInherit | AceFlags.ContainerInherit))
                hasAdminFa = true;
            else if (isSystem && mask == 0x001F01FF && common.AceFlags == (AceFlags.ObjectInherit | AceFlags.ContainerInherit))
                hasSystemFa = true;
            else
                throw new ProvisioningException("parent-acl-dacl-mismatch");
        }
        if (!hasAdminFa || !hasSystemFa) throw new ProvisioningException("parent-acl-dacl-mismatch");
    }

    private static void VerifyProgramDataAcl(SafeFileHandle handle)
    {
        // ProgramData is OS-managed. We do not impose the Vault leaf policy. We reject
        // obviously unsafe conditions: reparse, non-directory handled elsewhere, and allow ACEs
        // granting write/modify to broad principals (Everyone, Authenticated Users, Users, Anonymous).
        var sd = ReadSecurityDescriptor(handle);
        if (sd.Owner is null) throw new ProvisioningException("programdata-acl-mismatch");
        if ((sd.ControlFlags & ControlFlags.DiscretionaryAclPresent) == 0 || sd.DiscretionaryAcl is null)
            throw new ProvisioningException("programdata-acl-mismatch");

        var broadWriteSids = new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "S-1-1-0",   // Everyone
            "S-1-5-7",   // Anonymous
            "S-1-5-11",  // Authenticated Users
            "S-1-5-32-545" // Users
        };
        const uint dangerousWriteMask =
            0x00000002 | // FILE_ADD_FILE / FILE_WRITE_DATA
            0x00000004 | // FILE_ADD_SUBDIRECTORY / FILE_APPEND_DATA
            0x00000040 | // DELETE
            0x00010000 | // DELETE access right
            0x00040000 | // WRITE_DAC
            0x00080000 | // WRITE_OWNER
            0x10000000 | // GENERIC_ALL
            0x40000000;  // GENERIC_WRITE
        foreach (GenericAce ace in sd.DiscretionaryAcl)
        {
            if (ace is not CommonAce common) continue;
            if (common.AceQualifier != AceQualifier.AccessAllowed) continue;
            if (!broadWriteSids.Contains(common.SecurityIdentifier.Value)) continue;
            var mask = unchecked((uint)common.AccessMask);
            if ((mask & dangerousWriteMask) != 0)
                throw new ProvisioningException("programdata-acl-unsafe");
        }
    }

    private static RawSecurityDescriptor ReadSecurityDescriptor(SafeFileHandle handle)
    {
        var status = GetSecurityInfo(handle, 1 /* SE_FILE_OBJECT */, OwnerSecurityInformation | DaclSecurityInformation,
            out _, out _, out _, out _, out var sdPtr);
        if (status != 0 || sdPtr == IntPtr.Zero)
            throw new ProvisioningException("acl-read-failed");
        try
        {
            var len = GetSecurityDescriptorLength(sdPtr);
            if (len == 0 || len > 65536) throw new ProvisioningException("acl-read-failed");
            var bytes = new byte[(int)len];
            Marshal.Copy(sdPtr, bytes, 0, bytes.Length);
            var sd = new RawSecurityDescriptor(bytes, 0);
            Array.Clear(bytes, 0, bytes.Length);
            return sd;
        }
        finally
        {
            LocalFree(sdPtr);
        }
    }

    private readonly record struct DirectoryIdentity(ulong VolumeSerialNumber, ulong FileIdLow, ulong FileIdHigh);
    private readonly record struct VaultFileIdentity(ulong VolumeSerialNumber, ulong FileIdLow, ulong FileIdHigh);

    [StructLayout(LayoutKind.Sequential)] private struct UnicodeString { public ushort Length, MaximumLength; public IntPtr Buffer; }
    [StructLayout(LayoutKind.Sequential)] private struct ObjectAttributes
    { public int Length; public IntPtr RootDirectory, ObjectName; public uint Attributes; public IntPtr SecurityDescriptor, SecurityQualityOfService; }
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

    [DllImport("ntdll.dll")]
    private static extern int NtSetInformationFile(SafeFileHandle fileHandle, ref IoStatusBlock ioStatusBlock,
        IntPtr fileInformation, uint length, int fileInformationClass);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern uint GetSecurityInfo(SafeFileHandle handle, uint objectType, uint securityInfo,
        out IntPtr sidOwner, out IntPtr sidGroup, out IntPtr dacl, out IntPtr sacl, out IntPtr securityDescriptor);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern uint GetSecurityDescriptorLength(IntPtr securityDescriptor);

    [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true, EntryPoint = "ConvertStringSecurityDescriptorToSecurityDescriptorW")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool ConvertStringSecurityDescriptorToSecurityDescriptorW(string stringSecurityDescriptor,
        uint stringSdRevision, out IntPtr securityDescriptor, out uint securityDescriptorSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr LocalFree(IntPtr hMem);

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetTokenInformation(IntPtr tokenHandle, int tokenInformationClass,
        out TokenElevation tokenInformation, int tokenInformationLength, out int returnLength);
}
