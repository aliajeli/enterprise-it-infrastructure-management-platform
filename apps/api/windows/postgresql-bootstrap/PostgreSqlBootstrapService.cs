using System.Buffers.Binary;
using System.Diagnostics;
using System.Globalization;
using System.Security.Cryptography;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.ComponentModel;
using Microsoft.Win32.SafeHandles;
using System.Runtime.InteropServices;
using Microsoft.Extensions.Hosting;

namespace EnterpriseIT.PostgreSQLBootstrap;

internal sealed record BootstrapDiagnosticOptions(bool Enabled);

internal sealed class PostgreSqlBootstrapService : BackgroundService
{
    internal const string ServiceName = "EnterpriseITPostgreSQLBootstrap";
    internal const string PipeName = "EnterpriseIT.PostgreSQL.Bootstrap.v2";
    private const int MaximumPasswordBytes = 4096;
    private static readonly TimeSpan RequestTimeout = TimeSpan.FromMinutes(3);
    private readonly bool _diagnosticsEnabled;

    public PostgreSqlBootstrapService(BootstrapDiagnosticOptions diagnostics) =>
        _diagnosticsEnabled = diagnostics.Enabled;

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        WriteTrace("worker-entered");
        RequireServiceIdentity();
        WriteTrace("service-identity-passed");
        while (!stoppingToken.IsCancellationRequested)
        {
            await using var pipe = CreateServerPipe();
            try
            {
                await pipe.WaitForConnectionAsync(stoppingToken);
                WriteTrace("client-connected");
                if (!IsAuthorizedInstaller(pipe))
                {
                    WriteTrace("client-authorization-denied");
                    await WriteStatusAsync(pipe, 1, stoppingToken);
                    continue;
                }

                // Explicit preflight acknowledgement: the client must not send
                // credential bytes until the service has authenticated its token.
                WriteTrace("client-authorization-passed");
                await WriteStatusAsync(pipe, 0, stoppingToken);

                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
                timeout.CancelAfter(RequestTimeout);
                var password = await ReadPasswordAsync(pipe, timeout.Token);
                try
                {
                    await InitializeClusterAsync(password, timeout.Token);
                    await WriteStatusAsync(pipe, 0, stoppingToken);
                }
                finally
                {
                    Array.Clear(password, 0, password.Length);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                WriteTrace("host-shutdown-cancellation");
                break;
            }
            catch (Exception)
            {
                // Do not log exception text, process output, paths supplied by clients,
                // or any request bytes. A fixed event is sufficient for diagnosis.
                WriteTrace("request-failed");
                try { await WriteStatusAsync(pipe, 1, CancellationToken.None); }
                catch { /* client may already have disconnected */ }
            }
        }
        WriteTrace("request-loop-exited");
    }

    private static SecurityIdentifier CreateServiceSid(string serviceName)
    {
        var nameBytes = Encoding.Unicode.GetBytes(serviceName.ToUpperInvariant());
        var hash = SHA1.HashData(nameBytes);
        try
        {
            var parts = new string[5];
            for (var index = 0; index < parts.Length; index++)
            {
                var subAuthority = BinaryPrimitives.ReadUInt32LittleEndian(hash.AsSpan(index * 4, 4));
                parts[index] = subAuthority.ToString(CultureInfo.InvariantCulture);
            }

            return new SecurityIdentifier("S-1-5-80-" + string.Join("-", parts));
        }
        finally
        {
            CryptographicOperations.ZeroMemory(hash);
            Array.Clear(nameBytes, 0, nameBytes.Length);
        }
    }

    private void WriteTrace(string marker)
    {
        if (!_diagnosticsEnabled) return;
        try
        {
            var tracePath = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "EnterpriseIT", "PostgreSQL", "18", "bootstrap-smoke.log");
            File.AppendAllText(tracePath, marker + Environment.NewLine, new UTF8Encoding(false));
        }
        catch
        {
            // Diagnostics must never alter service lifecycle or authorization behavior.
        }
    }

    private static NamedPipeServerStream CreateServerPipe()
    {
        var systemSid = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
        var adminSid = new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid, null);
        var serviceSid = (SecurityIdentifier)new NTAccount("NT SERVICE", ServiceName)
            .Translate(typeof(SecurityIdentifier));
        var security = new PipeSecurity();
        security.SetAccessRuleProtection(isProtected: true, preserveInheritance: false);
        // Keep the kernel-selected owner from the service process token.
        // Under the production virtual account this is the dedicated service identity;
        // the service SID remains explicitly authorized by the protected DACL below.
        security.AddAccessRule(new PipeAccessRule(serviceSid, PipeAccessRights.FullControl,
            AccessControlType.Allow));
        security.AddAccessRule(new PipeAccessRule(systemSid, PipeAccessRights.FullControl,
            AccessControlType.Allow));
        security.AddAccessRule(new PipeAccessRule(adminSid, PipeAccessRights.ReadWrite,
            AccessControlType.Allow));
        return NamedPipeServerStreamAcl.Create(
            PipeName, PipeDirection.InOut, 1, PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous, 4096, 4096, security);
    }

    private static bool IsAuthorizedInstaller(NamedPipeServerStream pipe)
    {
        var authorized = false;
        pipe.RunAsClient(() =>
        {
            using var identity = WindowsIdentity.GetCurrent(ifImpersonating: true);
            if (identity is null) return;
            var principal = new WindowsPrincipal(identity);
            var system = new SecurityIdentifier(WellKnownSidType.LocalSystemSid, null);
            authorized = identity.User is SecurityIdentifier userSid && system.Equals(userSid) ||
                principal.IsInRole(WindowsBuiltInRole.Administrator);
        });
        return authorized;
    }

    private const uint GroupEnabled = 0x00000004;
    private const uint GroupUseForDenyOnly = 0x00000010;
    private const int TokenGroupsInformation = 2;

    [StructLayout(LayoutKind.Sequential)]
    private struct SidAndAttributes
    {
        public IntPtr Sid;
        public uint Attributes;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct TokenGroupsHeader
    {
        public uint GroupCount;
        public SidAndAttributes FirstGroup;
    }

    [DllImport("advapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetTokenInformation(
        SafeAccessTokenHandle tokenHandle,
        int tokenInformationClass,
        IntPtr tokenInformation,
        int tokenInformationLength,
        out int returnLength);

    private static (bool Enabled, bool DenyOnly) ReadServiceSidAttributes(
        SafeAccessTokenHandle token, SecurityIdentifier expected)
    {
        _ = GetTokenInformation(token, TokenGroupsInformation, IntPtr.Zero, 0, out var required);
        var error = Marshal.GetLastWin32Error();
        if (required <= 0 || error != 122) // ERROR_INSUFFICIENT_BUFFER
            throw new Win32Exception(error, "Unable to query service token groups.");

        var buffer = Marshal.AllocHGlobal(required);
        try
        {
            if (!GetTokenInformation(token, TokenGroupsInformation, buffer, required, out var returned))
                throw new Win32Exception(Marshal.GetLastWin32Error(), "Unable to read service token groups.");
            if (returned < required)
                throw new InvalidDataException("Windows returned a truncated token-groups buffer.");

            var firstGroupOffset = Marshal.OffsetOf<TokenGroupsHeader>(
                nameof(TokenGroupsHeader.FirstGroup)).ToInt32();
            var entrySize = Marshal.SizeOf<SidAndAttributes>();
            var groupCount = Marshal.ReadInt32(buffer);
            if (groupCount < 0 || groupCount > (returned - firstGroupOffset) / entrySize)
                throw new InvalidDataException("Windows returned an invalid token-groups count.");

            var found = false;
            var enabled = false;
            var denyOnly = false;
            for (var index = 0; index < groupCount; index++)
            {
                var entryAddress = IntPtr.Add(buffer, firstGroupOffset + index * entrySize);
                var entry = Marshal.PtrToStructure<SidAndAttributes>(entryAddress);
                if (entry.Sid == IntPtr.Zero || !expected.Equals(new SecurityIdentifier(entry.Sid)))
                    continue;

                found = true;
                enabled |= (entry.Attributes & GroupEnabled) != 0;
                denyOnly |= (entry.Attributes & GroupUseForDenyOnly) != 0;
            }

            return (found && enabled && !denyOnly, found && denyOnly);
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }
    }

    private void RequireServiceIdentity()
    {
        WriteTrace("identity-check-entered");
        try
        {
            using var identity = WindowsIdentity.GetCurrent(TokenAccessLevels.Query);
            var expected = CreateServiceSid(ServiceName);
            var userSid = identity.User as SecurityIdentifier;
            var primaryIdentityMatch = userSid is not null && expected.Equals(userSid);
            var groupAttributes = ReadServiceSidAttributes(identity.AccessToken, expected);

            WriteTrace("service-sid-primary-identity-match:" + primaryIdentityMatch);
            WriteTrace("service-sid-enabled:" + groupAttributes.Enabled);
            WriteTrace("service-sid-deny-only:" + groupAttributes.DenyOnly);

            if (!primaryIdentityMatch && (!groupAttributes.Enabled || groupAttributes.DenyOnly))
                throw new UnauthorizedAccessException(
                    "Bootstrap service SID is absent, disabled, or deny-only in the service token.");
        }
        catch
        {
            WriteTrace("identity-check-failed");
            throw;
        }
    }

    private static async Task<byte[]> ReadPasswordAsync(
        NamedPipeServerStream pipe, CancellationToken cancellationToken)
    {
        var prefix = new byte[4];
        await pipe.ReadExactlyAsync(prefix, cancellationToken);
        var length = BinaryPrimitives.ReadInt32BigEndian(prefix);
        Array.Clear(prefix, 0, prefix.Length);
        if (length is < 16 or > MaximumPasswordBytes)
            throw new InvalidDataException("Invalid bootstrap request.");

        var password = new byte[length];
        try
        {
            await pipe.ReadExactlyAsync(password, cancellationToken);
            var charCount = new UTF8Encoding(false, true).GetCharCount(password);
            if (charCount is < 16 or > 1024)
                throw new InvalidDataException("Invalid bootstrap request.");
            var chars = new char[charCount];
            try
            {
                new UTF8Encoding(false, true).GetChars(password, chars);
                if (Array.Exists(chars, c => c is '\0' or '\r' or '\n'))
                    throw new InvalidDataException("Invalid bootstrap request.");
            }
            finally
            {
                Array.Clear(chars, 0, chars.Length);
            }
            return password;
        }
        catch
        {
            Array.Clear(password, 0, password.Length);
            throw;
        }
    }

    private async Task InitializeClusterAsync(byte[] password, CancellationToken cancellationToken)
    {
        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
        var installRoot = Path.GetFullPath(AppContext.BaseDirectory)
            .TrimEnd(Path.DirectorySeparatorChar);
        var expectedPrefix = Path.GetFullPath(Path.Combine(programFiles, "EnterpriseIT")) +
            Path.DirectorySeparatorChar;
        if (!installRoot.StartsWith(expectedPrefix, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Bootstrap payload is outside Program Files.");

        var versionPart = installRoot[expectedPrefix.Length..];
        if (versionPart.Contains(Path.DirectorySeparatorChar) ||
            !System.Text.RegularExpressions.Regex.IsMatch(versionPart, @"^\d+\.\d+\.\d+$"))
            throw new InvalidOperationException("Bootstrap payload root is not versioned.");

        var initdb = Path.Combine(installRoot, "postgresql", "pgsql", "bin", "initdb.exe");
        if (!File.Exists(initdb))
            throw new FileNotFoundException("PostgreSQL initdb payload is missing.");

        WriteTrace("initdb-version-check-started");
        using (var versionProcess = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = initdb,
                WorkingDirectory = Path.GetDirectoryName(initdb)!,
                UseShellExecute = false,
                CreateNoWindow = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            }
        })
        {
            versionProcess.StartInfo.ArgumentList.Add("--version");
            if (!versionProcess.Start())
                throw new InvalidOperationException("PostgreSQL version check did not start.");
            var versionOutput = await versionProcess.StandardOutput.ReadToEndAsync(cancellationToken);
            _ = await versionProcess.StandardError.ReadToEndAsync(cancellationToken);
            await versionProcess.WaitForExitAsync(cancellationToken);
            WriteTrace("initdb-version-check-finished:" + versionProcess.ExitCode.ToString(CultureInfo.InvariantCulture));
            if (versionProcess.ExitCode != 0 ||
                !System.Text.RegularExpressions.Regex.IsMatch(
                    versionOutput.Trim(), @"^initdb \(PostgreSQL\) 18\.7(?:\s|$)"))
                throw new InvalidDataException("Unsupported PostgreSQL initdb version.");
        }

        using var dataDirectory = PostgreSqlDataDirectoryHandleChain.OpenKnownDataRoot();
        var dataRoot = dataDirectory.DisplayPath;
        dataDirectory.VerifyStillBound();
        // Do not create or adopt a path here. The privileged provisioner must
        // create the fixed directory and establish its ACL before this service runs.
        WriteTrace("initdb-data-root-handle-verified");
        var start = new ProcessStartInfo
        {
            FileName = initdb,
            WorkingDirectory = Path.GetDirectoryName(initdb)!,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true
        };
        foreach (var argument in new[]
        {
            $"--pgdata={dataRoot}",
            "--username=platform_admin",
            "--auth=scram-sha-256",
            "--pwprompt",
            "--encoding=UTF8"
        })
            start.ArgumentList.Add(argument);

        foreach (var key in start.Environment.Keys
            .Where(key => key.StartsWith("PG", StringComparison.OrdinalIgnoreCase)).ToArray())
            start.Environment.Remove(key);
        start.Environment["OSTYPE"] = "msys";
        start.Environment["LC_ALL"] = "C";

        using var process = new Process { StartInfo = start };
        WriteTrace("initdb-process-start-requested");
        if (!process.Start())
            throw new InvalidOperationException("PostgreSQL initdb did not start.");

        WriteTrace("initdb-process-started:" + process.Id.ToString(CultureInfo.InvariantCulture));
        var stdoutDrain = DrainAndDiscardAsync(process.StandardOutput);
        var stderrDrain = DrainAndDiscardAsync(process.StandardError);
        var stdin = new byte[checked((password.Length + 1) * 2)];
        try
        {
            var smokePauseMarker = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
                "EnterpriseIT", "PostgreSQL", "18", "bootstrap-smoke.pause-initdb");
            if (_diagnosticsEnabled && File.Exists(smokePauseMarker))
            {
                WriteTrace("initdb-smoke-hold-entered");
                await Task.Delay(TimeSpan.FromSeconds(45), cancellationToken);
                WriteTrace("initdb-smoke-hold-released");
            }

            Buffer.BlockCopy(password, 0, stdin, 0, password.Length);
            stdin[password.Length] = (byte)'\n';
            Buffer.BlockCopy(password, 0, stdin, password.Length + 1, password.Length);
            stdin[^1] = (byte)'\n';
            await process.StandardInput.BaseStream.WriteAsync(stdin, cancellationToken);
            await process.StandardInput.BaseStream.FlushAsync(cancellationToken);
            process.StandardInput.Close();

            await process.WaitForExitAsync(cancellationToken);
            await Task.WhenAll(stdoutDrain, stderrDrain).WaitAsync(TimeSpan.FromSeconds(10), cancellationToken);
            if (process.ExitCode != 0)
                throw new InvalidOperationException("PostgreSQL initdb failed.");
            dataDirectory.VerifyStillBound();
            using (var versionHandle = dataDirectory.OpenDataFileForRead("PG_VERSION"))
            using (var versionReader = new StreamReader(new FileStream(versionHandle, FileAccess.Read, 4096, isAsync: false), Encoding.UTF8, detectEncodingFromByteOrderMarks: true))
            {
                if (!string.Equals((await versionReader.ReadToEndAsync(cancellationToken)).Trim(), "18", StringComparison.Ordinal))
                    throw new InvalidDataException("PostgreSQL cluster verification failed.");
            }
            using (var hbaHandle = dataDirectory.OpenDataFileForRead("pg_hba.conf"))
            using (var hbaReader = new StreamReader(new FileStream(hbaHandle, FileAccess.Read, 4096, isAsync: false), Encoding.UTF8, detectEncodingFromByteOrderMarks: true))
            {
                if (!(await hbaReader.ReadToEndAsync(cancellationToken)).Contains("scram-sha-256", StringComparison.OrdinalIgnoreCase))
                    throw new InvalidDataException("PostgreSQL SCRAM authentication policy was not created.");
            }
            dataDirectory.VerifyStillBound();
        }
        catch
        {
            try
            {
                if (!process.HasExited)
                {
                    process.Kill(entireProcessTree: true);
                    await process.WaitForExitAsync(CancellationToken.None).WaitAsync(TimeSpan.FromSeconds(10));
                }
            }
            catch { /* leave the data directory for operator inspection */ }
            throw;
        }
        finally
        {
            Array.Clear(stdin, 0, stdin.Length);
        }
    }

    private static async Task DrainAndDiscardAsync(StreamReader reader)
    {
        var buffer = new char[1024];
        try
        {
            int count;
            while ((count = await reader.ReadAsync(buffer.AsMemory(), CancellationToken.None)) > 0)
                Array.Clear(buffer, 0, count);
        }
        finally
        {
            Array.Clear(buffer, 0, buffer.Length);
        }
    }

    private static async Task WriteStatusAsync(
        Stream pipe, byte status, CancellationToken cancellationToken)
    {
        await pipe.WriteAsync(new[] { status }, cancellationToken);
        await pipe.FlushAsync(cancellationToken);
    }
}
