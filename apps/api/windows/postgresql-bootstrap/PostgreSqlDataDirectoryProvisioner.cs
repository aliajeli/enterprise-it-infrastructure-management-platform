using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;

namespace EnterpriseIT.PostgreSQLBootstrap;

/// <summary>
/// Elevated provisioning and verify-only validation for the fixed PostgreSQL
/// data directory chain under ProgramData: EnterpriseIT (shared application
/// root, inherited policy), PostgreSQL (traversal parent), the versioned
/// directory (traversal parent) and data (writable leaf). Creation uses
/// NtCreateFile with FILE_CREATE and an explicit SECURITY_DESCRIPTOR; every
/// component is opened relative to retained parent handles with reparse-point,
/// volume-serial and file-ID checks. No path-based create, ACL, existence or
/// content operation is performed on the data chain. Invoked by the elevated
/// provisioning script, not by the runtime service; it never writes secrets.
/// </summary>
internal static class PostgreSqlDataDirectoryProvisioner
{
    private const string ProvisionFlag = "--provision-data";
    private const string VerifyFlag = "--verify-data";
    private const string EnterpriseDirectoryName = "EnterpriseIT";
    private const string PostgreSQLDirectoryName = "PostgreSQL";
    private const string DataDirectoryName = "data";

    private const uint FileReadAttributes = 0x80;
    private const uint ReadControl = 0x20000;
    private const uint Synchronize = 0x100000;
    private const uint DeleteAccess = 0x10000;
    private const uint FileAddSubdirectory = 0x4;
    private const uint ShareRead = 1;
    private const uint ShareWrite = 2;
    private const uint CreateNew = 2; // NT FILE_CREATE, not Win32 CREATE_NEW
    private const uint FileOpen = 1;
    private const uint OpenExisting = 3;
    private const uint BackupSemantics = 0x02000000;
    private const uint OpenReparsePoint = 0x00200000;
    private const uint DirectoryAttribute = 0x10;
    private const uint ReparseAttribute = 0x400;
    private const uint FileDirectoryFile = 1;
    private const uint FileOpenReparsePoint = 0x00200000;
    private const uint FileSynchronousIoNonAlert = 0x20;
    private const uint ObjectCaseInsensitive = 0x40;
    private const uint OwnerSecurityInformation = 1;
    private const uint DaclSecurityInformation = 4;
    private const int AttributeTagInfoClass = 9;
    private const int FileIdInfoClass = 18;
    private const int FileDispositionInformationClass = 13;

    // Exact data-directory ACE masks: parent directories grant traversal/read
    // (icacls RX semantics) while the data leaf grants modify-minus-owner-rights.
    private const uint FullControlMask = 0x001F01FF;
    private const uint ParentDirectoryMask = 0x001200A9; // RX
    private const uint DataLeafMask = 0x001301FF;        // Modify without WRITE_DAC/WRITE_OWNER

    private static readonly Regex ServiceSidPattern = new(
        @"^S-1-5-80-(?:[0-9]+-){4}[0-9]+$",
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
            var bootstrapSid = ValidateServiceSid(options.BootstrapSid);
            var postgresSid = ValidateServiceSid(options.PostgresSid);
            if (bootstrapSid.Equals(postgresSid))
                throw new ProvisioningException("invalid-arguments", 2);
            var pgVersion = ValidatePgVersion(options.PgVersion);
            var programData = ResolveProgramData(options.ProgramDataRoot);
            using var chain = ProvisioningChain.Open(
                programData, bootstrapSid, postgresSid, pgVersion, options.VerifyOnly);
            try
            {
                chain.ProvisionOrVerify(options.VerifyOnly);
#if POSTGRES_TEST_FAULTS
                InjectTestFault("after-final-verification");
#endif
            }
            catch
            {
                // Post-creation validation failures must not leave objects that
                // can be proven to have been created by this invocation.
                chain.RollbackCreated();
                throw;
            }
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

    private sealed record Options(
        string BootstrapSid, string PostgresSid, string PgVersion, bool VerifyOnly, string? ProgramDataRoot);

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
        string? bootstrapSid = null, postgresSid = null, pgVersion = null, programDataRoot = null;
        bool verifyOnly = false, provision = false;
        for (var i = 0; i < args.Length; i++)
        {
            var arg = args[i];
            if (string.Equals(arg, ProvisionFlag, StringComparison.OrdinalIgnoreCase)) { provision = true; continue; }
            if (string.Equals(arg, VerifyFlag, StringComparison.OrdinalIgnoreCase)) { verifyOnly = true; continue; }
            if (string.Equals(arg, "--bootstrap-sid", StringComparison.OrdinalIgnoreCase))
            {
                if (i + 1 >= args.Length) throw new ProvisioningException("invalid-arguments", 2);
                bootstrapSid = args[++i];
                continue;
            }
            if (string.Equals(arg, "--postgres-sid", StringComparison.OrdinalIgnoreCase))
            {
                if (i + 1 >= args.Length) throw new ProvisioningException("invalid-arguments", 2);
                postgresSid = args[++i];
                continue;
            }
            if (string.Equals(arg, "--pg-version", StringComparison.OrdinalIgnoreCase))
            {
                if (i + 1 >= args.Length) throw new ProvisioningException("invalid-arguments", 2);
                pgVersion = args[++i];
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
        if (string.IsNullOrWhiteSpace(bootstrapSid) ||
            string.IsNullOrWhiteSpace(postgresSid) ||
            string.IsNullOrWhiteSpace(pgVersion))
            throw new ProvisioningException("invalid-arguments", 2);
        return new Options(bootstrapSid, postgresSid, pgVersion, verifyOnly, programDataRoot);
    }

    private static SecurityIdentifier ValidateServiceSid(string sidText)
    {
        if (!ServiceSidPattern.IsMatch(sidText) ||
            sidText["S-1-5-80-".Length..].Split('-').Any(part =>
                !uint.TryParse(part, System.Globalization.NumberStyles.None,
                    System.Globalization.CultureInfo.InvariantCulture, out _)))
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

    private static string ValidatePgVersion(string pgVersion)
    {
        if (pgVersion.Length is < 1 or > 3 || !pgVersion.All(char.IsAsciiDigit))
            throw new ProvisioningException("invalid-arguments", 2);
        return pgVersion;
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
        var resolved = Path.GetFullPath(known);
        var volume = Path.GetPathRoot(resolved);
        // Match the runtime helper's fixed-path contract; do not provision a
        // redirected location that the service will subsequently refuse to use.
        if (string.IsNullOrEmpty(volume) ||
            !string.Equals(Path.GetRelativePath(volume, resolved), "ProgramData", StringComparison.OrdinalIgnoreCase))
            throw new ProvisioningException("invalid-programdata-root");
        return resolved;
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

    private sealed class ProvisioningChain : IDisposable
    {
        private readonly SafeFileHandle volumeRoot;
        private readonly SafeFileHandle programData;
        private readonly List<SafeFileHandle> programDataAncestors;
        private readonly SafeFileHandle enterpriseRoot;
        private readonly SafeFileHandle postgreSqlRoot;
        private readonly SafeFileHandle versionRoot;
        private readonly SafeFileHandle dataRoot;
        private readonly SecurityIdentifier bootstrapSid;
        private readonly SecurityIdentifier postgresSid;
        private readonly bool createdEnterprise;
        private readonly bool createdPostgreSql;
        private readonly bool createdVersion;
        private readonly bool createdData;
        private readonly DirectoryIdentity postgreSqlIdentityAtCreation;
        private readonly DirectoryIdentity versionIdentityAtCreation;
        private readonly DirectoryIdentity dataIdentityAtCreation;
        private bool disposed;

        private ProvisioningChain(
            SafeFileHandle volumeRoot, SafeFileHandle programData, List<SafeFileHandle> programDataAncestors,
            SafeFileHandle enterpriseRoot, SafeFileHandle postgreSqlRoot, SafeFileHandle versionRoot,
            SafeFileHandle dataRoot, SecurityIdentifier bootstrapSid, SecurityIdentifier postgresSid,
            bool createdEnterprise, bool createdPostgreSql, bool createdVersion, bool createdData,
            DirectoryIdentity postgreSqlIdentityAtCreation, DirectoryIdentity versionIdentityAtCreation,
            DirectoryIdentity dataIdentityAtCreation)
        {
            this.volumeRoot = volumeRoot;
            this.programData = programData;
            this.programDataAncestors = programDataAncestors;
            this.enterpriseRoot = enterpriseRoot;
            this.postgreSqlRoot = postgreSqlRoot;
            this.versionRoot = versionRoot;
            this.dataRoot = dataRoot;
            this.bootstrapSid = bootstrapSid;
            this.postgresSid = postgresSid;
            this.createdEnterprise = createdEnterprise;
            this.createdPostgreSql = createdPostgreSql;
            this.createdVersion = createdVersion;
            this.createdData = createdData;
            this.postgreSqlIdentityAtCreation = postgreSqlIdentityAtCreation;
            this.versionIdentityAtCreation = versionIdentityAtCreation;
            this.dataIdentityAtCreation = dataIdentityAtCreation;
        }

        internal static ProvisioningChain Open(
            string programDataPath, SecurityIdentifier bootstrapSid, SecurityIdentifier postgresSid,
            string pgVersion, bool verifyOnly)
        {
            var volumePath = Path.GetPathRoot(programDataPath);
            if (string.IsNullOrEmpty(volumePath) || volumePath.Length != 3 ||
                !char.IsAsciiLetter(volumePath[0]) || volumePath[1] != ':' ||
                (volumePath[2] != '\\' && volumePath[2] != '/'))
                throw new ProvisioningException("invalid-programdata-root");

            SafeFileHandle? volume = null, pd = null, enterprise = null;
            SafeFileHandle? postgreSql = null, versionDir = null, data = null;
            var ancestors = new List<SafeFileHandle>();
            bool createdEnterprise = false, createdPostgreSql = false, createdVersion = false, createdData = false;
            // A fixed operation name and numeric OS error are safe diagnostics; never emit paths or ACLs.
            string stage = "open-volume";
            DirectoryIdentity? postgreSqlIdentity = null, versionIdentity = null, dataIdentity = null;
            try
            {
                volume = OpenAbsoluteDirectory(volumePath);
                var volumeIdentity = ReadAndVerifyDirectory(volume, "programdata-root");
                stage = "open-programdata";
                var relative = Path.GetRelativePath(volumePath, programDataPath);
                var components = relative.Split(new[] { '\\', '/' }, StringSplitOptions.None);
                if (components.Length == 0) throw new ProvisioningException("invalid-programdata-root");
                SafeFileHandle parent = volume;
                for (var i = 0; i < components.Length; i++)
                {
                    var isLast = i == components.Length - 1;
                    var access = FileReadAttributes | ReadControl | Synchronize |
                        (isLast && !verifyOnly ? FileAddSubdirectory : 0u);
                    var next = OpenRelativeObject(parent, components[i], access, ShareRead | ShareWrite,
                        FileOpen, FileDirectoryFile | FileOpenReparsePoint | FileSynchronousIoNonAlert,
                        IntPtr.Zero);
                    // Retain each handle until the operation ends; check every path component
                    // before opening its child so intermediate junctions cannot be traversed.
                    if (isLast) pd = next; else ancestors.Add(next);
                    var identity = ReadAndVerifyDirectory(next, isLast ? "programdata" : "programdata-ancestor");
                    if (identity.VolumeSerialNumber != volumeIdentity.VolumeSerialNumber)
                        throw new ProvisioningException("volume-mismatch");
                    // Every existing ancestor is part of the trust boundary. A safe
                    // ProgramData leaf is insufficient if a parent can be replaced or
                    // redirected by a broad principal before child creation.
                    if (!isLast) VerifyProgramDataAcl(next);
                    parent = next;
                }
                if (pd is null) throw new ProvisioningException("invalid-programdata-root");
                VerifyProgramDataAcl(pd);

                // EnterpriseIT is the shared application root owned by the Vault
                // provisioner's policy. This provisioner never adds, removes or
                // rewrites an EnterpriseIT ACE: an existing root is opened and
                // validated as a plain directory on this volume, and a missing
                // root is created with a NULL descriptor so it inherits the
                // OS-managed ProgramData ACL exactly as before. Vault ACL
                // verification therefore remains unaffected either way.
                stage = "open-or-create-enterprise";
                (enterprise, createdEnterprise) = OpenOrCreateInheritedDirectory(
                    pd, EnterpriseDirectoryName, verifyOnly);
                var enterpriseIdentity = ReadAndVerifyDirectory(enterprise, "enterprise-root");
                if (enterpriseIdentity.VolumeSerialNumber != volumeIdentity.VolumeSerialNumber)
                    throw new ProvisioningException("volume-mismatch");

                stage = "open-or-create-postgresql";
                (postgreSql, createdPostgreSql) = OpenOrCreateChildDirectory(
                    enterprise, PostgreSQLDirectoryName, verifyOnly,
                    ParentSddl(bootstrapSid, postgresSid), deleteOnCreate: true, "postgresql-root");
                postgreSqlIdentity = ReadAndVerifyDirectory(postgreSql, "postgresql-root");
                if (postgreSqlIdentity.Value.VolumeSerialNumber != volumeIdentity.VolumeSerialNumber)
                    throw new ProvisioningException("volume-mismatch");
                VerifyDataAcl(postgreSql, bootstrapSid, postgresSid, leaf: false, "postgresql-root");
#if POSTGRES_TEST_FAULTS
                InjectTestFault("after-create-postgresql");
#endif

                stage = "open-or-create-version";
                (versionDir, createdVersion) = OpenOrCreateChildDirectory(
                    postgreSql, pgVersion, verifyOnly,
                    ParentSddl(bootstrapSid, postgresSid), deleteOnCreate: true, "version-root");
                versionIdentity = ReadAndVerifyDirectory(versionDir, "version-root");
                if (versionIdentity.Value.VolumeSerialNumber != volumeIdentity.VolumeSerialNumber)
                    throw new ProvisioningException("volume-mismatch");
                VerifyDataAcl(versionDir, bootstrapSid, postgresSid, leaf: false, "version-root");
#if POSTGRES_TEST_FAULTS
                InjectTestFault("after-create-version");
#endif

                stage = "open-or-create-data";
                (data, createdData) = OpenOrCreateChildDirectory(
                    versionDir, DataDirectoryName, verifyOnly,
                    LeafSddl(bootstrapSid, postgresSid), deleteOnCreate: true, "data-leaf");
                dataIdentity = ReadAndVerifyDirectory(data, "data-leaf");
                if (dataIdentity.Value.VolumeSerialNumber != volumeIdentity.VolumeSerialNumber)
                    throw new ProvisioningException("volume-mismatch");
                VerifyDataAcl(data, bootstrapSid, postgresSid, leaf: true, "data-leaf");
#if POSTGRES_TEST_FAULTS
                InjectTestFault("after-create-data");
#endif

                var chain = new ProvisioningChain(volume, pd, ancestors, enterprise, postgreSql, versionDir,
                    data, bootstrapSid, postgresSid, createdEnterprise, createdPostgreSql, createdVersion,
                    createdData, postgreSqlIdentity.Value, versionIdentity.Value, dataIdentity.Value);
                ancestors = new List<SafeFileHandle>();
                volume = pd = enterprise = postgreSql = versionDir = data = null;
                return chain;
            }
            catch (Exception ex)
            {
                // Roll back only objects created by this exact invocation.
                try
                {
                    Rollback(data, versionDir, postgreSql, createdData, createdVersion, createdPostgreSql,
                        dataIdentity, versionIdentity, postgreSqlIdentity);
                }
                catch { /* fail closed: leave objects and report original failure */ }
                data?.Dispose(); versionDir?.Dispose(); postgreSql?.Dispose();
                enterprise?.Dispose(); pd?.Dispose();
                for (var i = ancestors.Count - 1; i >= 0; i--) ancestors[i].Dispose();
                volume?.Dispose();
                if (ex is Win32Exception nativeError)
                    throw new ProvisioningException($"{stage}:win32-{nativeError.NativeErrorCode}");
                if (ex is not ProvisioningException)
                    throw new ProvisioningException($"{stage}:unexpected-error");
                throw;
            }
        }

        internal void ProvisionOrVerify(bool verifyOnly)
        {
            // Post-create/verify validation by retained handle: identity, type,
            // reparse state and exact ACL are re-checked without any path op.
            var enterpriseId = ReadAndVerifyDirectory(enterpriseRoot, "enterprise-root");
            VerifyNotReparse(enterpriseRoot, "enterprise-root");

            var postgreSqlId = ReadAndVerifyDirectory(postgreSqlRoot, "postgresql-root");
            if (createdPostgreSql && postgreSqlId != postgreSqlIdentityAtCreation)
                throw new ProvisioningException("post-create-identity-mismatch");
            VerifyNotReparse(postgreSqlRoot, "postgresql-root");
            VerifyDataAcl(postgreSqlRoot, bootstrapSid, postgresSid, leaf: false, "postgresql-root");

            var versionId = ReadAndVerifyDirectory(versionRoot, "version-root");
            if (createdVersion && versionId != versionIdentityAtCreation)
                throw new ProvisioningException("post-create-identity-mismatch");
            VerifyNotReparse(versionRoot, "version-root");
            VerifyDataAcl(versionRoot, bootstrapSid, postgresSid, leaf: false, "version-root");

            var dataId = ReadAndVerifyDirectory(dataRoot, "data-leaf");
            if (createdData && dataId != dataIdentityAtCreation)
                throw new ProvisioningException("post-create-identity-mismatch");
            VerifyNotReparse(dataRoot, "data-leaf");
            VerifyDataAcl(dataRoot, bootstrapSid, postgresSid, leaf: true, "data-leaf");

            _ = ReadAndVerifyDirectory(programData, "programdata");
            VerifyNotReparse(programData, "programdata");
            VerifyProgramDataAcl(programData);
            _ = verifyOnly;
        }

        internal void RollbackCreated()
        {
            // EnterpriseIT is the shared application root and is never rolled
            // back even when this invocation created it.
            _ = createdEnterprise;
            // Rollback is best-effort and identity-checked; it never removes an
            // object whose identity cannot be proven. Preserve the original error.
            try
            {
                Rollback(dataRoot, versionRoot, postgreSqlRoot, createdData, createdVersion, createdPostgreSql,
                    dataIdentityAtCreation, versionIdentityAtCreation, postgreSqlIdentityAtCreation);
            }
            catch { /* leave the object for administrator inspection */ }
        }

        public void Dispose()
        {
            if (disposed) return;
            disposed = true;
            // Dispose in child-to-parent order so delete-on-close from rollback
            // always observes empty directories.
            dataRoot.Dispose();
            versionRoot.Dispose();
            postgreSqlRoot.Dispose();
            enterpriseRoot.Dispose();
            programData.Dispose();
            for (var i = programDataAncestors.Count - 1; i >= 0; i--) programDataAncestors[i].Dispose();
            volumeRoot.Dispose();
        }
    }

    private static void Rollback(
        SafeFileHandle? data, SafeFileHandle? versionDir, SafeFileHandle? postgreSql,
        bool createdData, bool createdVersion, bool createdPostgreSql,
        DirectoryIdentity? dataIdentity, DirectoryIdentity? versionIdentity, DirectoryIdentity? postgreSqlIdentity)
    {
        // Reverse order, created-only, identity-checked. EnterpriseIT is the
        // shared application root and is deliberately never removed.
        if (createdData && data is not null && !data.IsInvalid && dataIdentity.HasValue)
        {
            try
            {
                var id = ReadAndVerifyDirectory(data, "data-leaf");
                if (id == dataIdentity.Value) DeleteRelativeHandle(data);
            }
            catch { /* leave in place; fail closed by caller */ }
        }
        if (createdVersion && versionDir is not null && !versionDir.IsInvalid && versionIdentity.HasValue)
        {
            try
            {
                var id = ReadAndVerifyDirectory(versionDir, "version-root");
                if (id == versionIdentity.Value) DeleteRelativeHandle(versionDir);
            }
            catch { /* leave in place; fail closed by caller */ }
        }
        if (createdPostgreSql && postgreSql is not null && !postgreSql.IsInvalid && postgreSqlIdentity.HasValue)
        {
            try
            {
                var id = ReadAndVerifyDirectory(postgreSql, "postgresql-root");
                if (id == postgreSqlIdentity.Value) DeleteRelativeHandle(postgreSql);
            }
            catch { /* leave in place; fail closed by caller */ }
        }
    }

    private static string ParentSddl(SecurityIdentifier bootstrapSid, SecurityIdentifier postgresSid) =>
        $"O:BAG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)" +
        $"(A;OICI;0x{ParentDirectoryMask:X8};;;{bootstrapSid.Value})" +
        $"(A;OICI;0x{ParentDirectoryMask:X8};;;{postgresSid.Value})";

    private static string LeafSddl(SecurityIdentifier bootstrapSid, SecurityIdentifier postgresSid) =>
        $"O:BAG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)" +
        $"(A;OICI;0x{DataLeafMask:X8};;;{bootstrapSid.Value})" +
        $"(A;OICI;0x{DataLeafMask:X8};;;{postgresSid.Value})";

    private static void VerifyDataAcl(
        SafeFileHandle handle, SecurityIdentifier bootstrapSid, SecurityIdentifier postgresSid,
        bool leaf, string label)
    {
        // Exact four-ACE policy for the PostgreSQL-owned chain: owner is
        // BUILTIN\Administrators or LocalSystem, protected DACL, and exactly
        // SYSTEM FA, Administrators FA plus the two service SIDs at either the
        // traversal mask (parent) or the modify mask (data leaf).
        var expectedServiceMask = leaf ? DataLeafMask : ParentDirectoryMask;
        var sd = ReadSecurityDescriptor(handle);
        var admins = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
        var system = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
        if (sd.Owner is null || (!admins.Equals(sd.Owner) && !system.Equals(sd.Owner)))
            throw new ProvisioningException($"acl-owner-mismatch:{label}");
        if ((sd.ControlFlags & ControlFlags.DiscretionaryAclProtected) == 0 ||
            (sd.ControlFlags & ControlFlags.DiscretionaryAclPresent) == 0 ||
            sd.DiscretionaryAcl is null || sd.DiscretionaryAcl.Count != 4)
            throw new ProvisioningException($"acl-dacl-mismatch:{label}");

        bool hasAdminFa = false, hasSystemFa = false, hasBootstrap = false, hasPostgres = false;
        foreach (GenericAce ace in sd.DiscretionaryAcl)
        {
            if (ace is not CommonAce common ||
                common.AceQualifier != AceQualifier.AccessAllowed ||
                common.IsCallback ||
                common.AceFlags != (AceFlags.ObjectInherit | AceFlags.ContainerInherit))
                throw new ProvisioningException($"acl-dacl-mismatch:{label}");
            var sid = common.SecurityIdentifier;
            var mask = unchecked((uint)common.AccessMask);
            if (system.Equals(sid) && mask == FullControlMask && !hasSystemFa) hasSystemFa = true;
            else if (admins.Equals(sid) && mask == FullControlMask && !hasAdminFa) hasAdminFa = true;
            else if (bootstrapSid.Equals(sid) && mask == expectedServiceMask && !hasBootstrap) hasBootstrap = true;
            else if (postgresSid.Equals(sid) && mask == expectedServiceMask && !hasPostgres) hasPostgres = true;
            else throw new ProvisioningException($"acl-dacl-mismatch:{label}");
        }
        if (!hasAdminFa || !hasSystemFa || !hasBootstrap || !hasPostgres)
            throw new ProvisioningException($"acl-dacl-mismatch:{label}");
    }

    private static void VerifyProgramDataAcl(SafeFileHandle handle)
    {
        // ProgramData is OS-managed. We do not impose a leaf policy. We reject
        // obviously unsafe conditions: reparse, non-directory handled elsewhere,
        // and allow ACEs granting write/modify to broad principals (Everyone,
        // Authenticated Users, Users, Anonymous).
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
            0x00000040 | // DELETE_CHILD
            0x00010000 | // DELETE access right
            0x00040000 | // WRITE_DAC
            0x00080000 | // WRITE_OWNER
            0x10000000 | // GENERIC_ALL
            0x40000000;  // GENERIC_WRITE
        foreach (GenericAce ace in sd.DiscretionaryAcl)
        {
            // QualifiedAce covers both ordinary and object-specific allow ACEs.
            if (ace is not QualifiedAce qualified) continue;
            if (qualified.AceQualifier != AceQualifier.AccessAllowed) continue;
            if (!broadWriteSids.Contains(qualified.SecurityIdentifier.Value)) continue;
            var mask = unchecked((uint)qualified.AccessMask);
            if ((mask & dangerousWriteMask) != 0)
                throw new ProvisioningException("programdata-acl-unsafe");
        }
    }

    private static (SafeFileHandle handle, bool created) OpenOrCreateInheritedDirectory(
        SafeFileHandle parent, string name, bool verifyOnly)
    {
        // EnterpriseIT is never re-ACLed here. When it is missing it is created
        // with a NULL security descriptor so the OS-managed ProgramData ACL is
        // inherited at creation, exactly like the previous path-based create.
        var access = FileReadAttributes | ReadControl | Synchronize |
            (verifyOnly ? 0u : FileAddSubdirectory);
        try
        {
            return (OpenRelativeDirectory(parent, name, access, FileOpen), false);
        }
        catch (Win32Exception ex) when (ex.NativeErrorCode == 2)
        {
            if (verifyOnly) throw new ProvisioningException("missing-required-object");
            try
            {
                return (OpenRelativeDirectory(parent, name, access, CreateNew, IntPtr.Zero), true);
            }
            catch (Win32Exception ex2) when (ex2.NativeErrorCode == 183)
            {
                // A concurrent creator won the race; adopt nothing, verify it.
                return (OpenRelativeDirectory(parent, name, access, FileOpen), false);
            }
        }
        catch (ProvisioningException) { throw; }
        catch (Win32Exception ex) { throw new ProvisioningException($"enterprise-root:win32-{ex.NativeErrorCode}"); }
        catch { throw new ProvisioningException("path-validation-failed"); }
    }

    private static (SafeFileHandle handle, bool created) OpenOrCreateChildDirectory(
        SafeFileHandle parent, string name, bool verifyOnly, string sddl, bool deleteOnCreate, string label)
    {
        // Request only the rights required to validate this component and to
        // create the next fixed child. DELETE is retained only on newly created
        // objects so identity-checked rollback can remove exactly this handle.
        var access = FileReadAttributes | ReadControl | Synchronize |
            (verifyOnly ? 0u : FileAddSubdirectory);
        try
        {
            return (OpenRelativeDirectory(parent, name, access, FileOpen), false);
        }
        catch (Win32Exception ex) when (ex.NativeErrorCode == 2)
        {
            if (verifyOnly) throw new ProvisioningException("missing-required-object");
            var sd = SddlToPtr(sddl);
            try
            {
                var creationAccess = access | (deleteOnCreate ? DeleteAccess : 0u);
                try
                {
                    return (OpenRelativeDirectory(parent, name, creationAccess, CreateNew, sd), true);
                }
                catch (Win32Exception ex2) when (ex2.NativeErrorCode == 183)
                {
                    // A concurrent creator won the race; adopt nothing, verify it.
                    return (OpenRelativeDirectory(parent, name, access, FileOpen), false);
                }
            }
            finally
            {
                if (sd != IntPtr.Zero) LocalFree(sd);
            }
        }
        catch (ProvisioningException) { throw; }
        catch (Win32Exception ex) { throw new ProvisioningException($"{label}:win32-{ex.NativeErrorCode}"); }
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

    private static SafeFileHandle OpenRelativeObject(SafeFileHandle parent, string component,
        uint desiredAccess, uint shareAccess, uint disposition, uint createOptions,
        IntPtr securityDescriptor)
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
                IntPtr.Zero, 0, shareAccess, disposition, createOptions, IntPtr.Zero, 0);
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

    private static void VerifyNotReparse(SafeFileHandle handle, string label)
    {
        if (!GetFileInformationByHandleEx(handle, AttributeTagInfoClass, out FileAttributeTagInfo tag, Marshal.SizeOf<FileAttributeTagInfo>()))
            throw new ProvisioningException($"path-validation-failed:{label}");
        if ((tag.FileAttributes & ReparseAttribute) != 0)
            throw new ProvisioningException($"reparse-point:{label}");
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

#if POSTGRES_TEST_FAULTS
    // This hook exists only in the separately built CI fixture executable.
    // Release and published helpers must never define POSTGRES_TEST_FAULTS.
    private static void InjectTestFault(string stage)
    {
        if (string.Equals(Environment.GetEnvironmentVariable("ENTERPRISEIT_PG_TEST_FAULT"), stage, StringComparison.Ordinal))
            throw new ProvisioningException("test-injected-fault");
    }
#endif

    private readonly record struct DirectoryIdentity(ulong VolumeSerialNumber, ulong FileIdLow, ulong FileIdHigh);

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
