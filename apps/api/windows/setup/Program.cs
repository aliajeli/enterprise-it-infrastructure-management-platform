using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;

namespace EnterpriseIT.Setup;

/// <summary>
/// Thin, fail-closed wrapper around the reviewed offline install and uninstall
/// PowerShell entry points. All policy (archive digest verification, capability
/// gates, staging, orchestration, ownership) stays inside those scripts; this
/// executable only validates its own arguments, discovers pwsh and the script
/// root, and transports secrets exclusively through the child process
/// environment - never argv, never files, never its own output.
/// </summary>
internal static class Program
{
    private static readonly string[] SecretEnvironmentVariables =
    {
        "EIT_SETUP_API_DATABASE_URL",
        "EIT_SETUP_WORKER_DATABASE_URL",
        "EIT_SETUP_BOOTSTRAP_ADMIN_PASSWORD",
        "EIT_SETUP_MIGRATION_PASSWORD",
        "EIT_SETUP_API_PASSWORD",
        "EIT_SETUP_WORKER_PASSWORD",
    };

    private static int Main(string[] args)
    {
        try
        {
            if (args.Length == 0)
            {
                PrintUsage();
                return 1;
            }

            var options = ParseOptions(args.Skip(1).ToArray());
            return args[0].ToLowerInvariant() switch
            {
                "verify" => RunVerify(options),
                "install" => RunInstall(options),
                "uninstall" => RunUninstall(options),
                _ => Fail($"Unknown mode '{args[0]}'."),
            };
        }
        catch (Exception ex)
        {
            return Fail(ex.Message);
        }
    }

    private static void PrintUsage()
    {
        Console.Error.WriteLine(
            "EnterpriseIT.Setup modes:" + Environment.NewLine +
            "  verify    --payload <zip> --sha256 <hex64>" + Environment.NewLine +
            "  install   --payload <zip> --sha256 <hex64> --edge-bind-address <ip> --edge-tls-hostname <host> --edge-certificate-thumbprint <hex> [--bootstrap-admin-user <name>] [--min-free-space-gb <n>]" + Environment.NewLine +
            "  uninstall --install-root <path> [--purge-data]" + Environment.NewLine +
            "Secrets (API/Worker database URLs and bootstrap passwords) are read from the EIT_SETUP_* environment variables.");
    }

    private static Dictionary<string, string?> ParseOptions(string[] args)
    {
        var options = new Dictionary<string, string?>(StringComparer.Ordinal);
        for (var i = 0; i < args.Length; i++)
        {
            var key = args[i];
            if (!key.StartsWith("--", StringComparison.Ordinal))
            {
                throw new InvalidOperationException($"Unexpected argument '{key}'.");
            }

            if (key == "--purge-data")
            {
                options[key] = "true";
                continue;
            }

            if (i + 1 >= args.Length)
            {
                throw new InvalidOperationException($"Option '{key}' requires a value.");
            }

            options[key] = args[++i];
        }

        return options;
    }

    private static string RequireOption(Dictionary<string, string?> options, string key)
    {
        if (!options.TryGetValue(key, out var value) || string.IsNullOrWhiteSpace(value))
        {
            throw new InvalidOperationException($"Required option '{key}' is missing.");
        }

        return value;
    }

    private static string RequireEnvironmentVariable(string name)
    {
        var value = Environment.GetEnvironmentVariable(name);
        if (string.IsNullOrEmpty(value))
        {
            var message = name switch
            {
                "EIT_SETUP_API_DATABASE_URL" or "EIT_SETUP_WORKER_DATABASE_URL"
                    => "Separate SecureString API and Worker database URLs are required.",
                _ => "Bootstrap requires admin, migration, API runtime and Worker runtime SecureString passwords.",
            };
            throw new InvalidOperationException(message);
        }

        return value;
    }

    private static string ResolvePowerShell()
    {
        var overridePath = Environment.GetEnvironmentVariable("EIT_SETUP_PWSH");
        if (!string.IsNullOrEmpty(overridePath))
        {
            if (!File.Exists(overridePath))
            {
                throw new InvalidOperationException($"pwsh override '{overridePath}' does not exist.");
            }

            return overridePath;
        }

        var candidates = new List<string>
        {
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                "PowerShell", "7", "pwsh.exe"),
            Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86),
                "PowerShell", "7", "pwsh.exe"),
        };
        var pathValue = Environment.GetEnvironmentVariable("PATH") ?? string.Empty;
        candidates.AddRange(
            pathValue.Split(Path.PathSeparator, StringSplitOptions.RemoveEmptyEntries)
                .Select(directory => Path.Combine(directory.Trim(), "pwsh.exe")));

        foreach (var candidate in candidates)
        {
            if (File.Exists(candidate))
            {
                return candidate;
            }
        }

        throw new InvalidOperationException(
            "PowerShell 7 (pwsh.exe) was not found; install it or set EIT_SETUP_PWSH.");
    }

    private static string ResolveScriptsRoot()
    {
        var required = new[] { "install-offline-payload.ps1", "uninstall-offline-payload.ps1" };
        var candidates = new List<string>();
        var overrideRoot = Environment.GetEnvironmentVariable("EIT_SETUP_SCRIPTS_ROOT");
        if (!string.IsNullOrEmpty(overrideRoot))
        {
            candidates.Add(overrideRoot);
        }
        else
        {
            var baseDirectory = AppContext.BaseDirectory;
            candidates.Add(baseDirectory);
            candidates.Add(Path.Combine(baseDirectory, "scripts", "windows"));
        }

        foreach (var candidate in candidates)
        {
            if (required.All(name => File.Exists(Path.Combine(candidate, name))))
            {
                return Path.GetFullPath(candidate);
            }
        }

        throw new InvalidOperationException(
            "Offline installer scripts were not found next to EnterpriseIT.Setup.exe; " +
            "ship scripts\\windows with the setup executable or set EIT_SETUP_SCRIPTS_ROOT.");
    }

    private static string ValidateSha256(string sha256)
    {
        if (!Regex.IsMatch(sha256, "^[0-9A-Fa-f]{64}$"))
        {
            throw new InvalidOperationException("Expected SHA-256 must be exactly 64 hex characters.");
        }

        return sha256.ToUpperInvariant();
    }

    private static string PsQuote(string value) => "'" + value.Replace("'", "''") + "'";

    private static int RunVerify(Dictionary<string, string?> options)
    {
        var payload = Path.GetFullPath(RequireOption(options, "--payload"));
        var sha256 = ValidateSha256(RequireOption(options, "--sha256"));
        var scriptsRoot = ResolveScriptsRoot();
        var pwsh = ResolvePowerShell();
        // Dot-sourcing with real bound arguments loads the reviewed archive
        // validator without executing the installer main block.
        var command =
            ". " + PsQuote(Path.Combine(scriptsRoot, "install-offline-payload.ps1")) +
            " -PayloadArchive " + PsQuote(payload) +
            " -ExpectedSha256 " + PsQuote(sha256) +
            "; try { Test-OfflineInstallerArchive -ArchivePath " + PsQuote(payload) +
            " -ExpectedSha256 " + PsQuote(sha256) + " | Out-Null; exit 0 }" +
            " catch { Write-Output $_.Exception.Message; exit 1 }";
        return RunPowerShell(pwsh, command);
    }

    private static int RunInstall(Dictionary<string, string?> options)
    {
        var payload = Path.GetFullPath(RequireOption(options, "--payload"));
        var sha256 = ValidateSha256(RequireOption(options, "--sha256"));
        var edgeBind = RequireOption(options, "--edge-bind-address");
        var edgeHost = RequireOption(options, "--edge-tls-hostname");
        var edgeThumbprint = RequireOption(options, "--edge-certificate-thumbprint");
        var scriptsRoot = ResolveScriptsRoot();
        var pwsh = ResolvePowerShell();

        // Fail fast on the same conditions the capability gate enforces, before
        // spawning anything: connection URLs are mandatory, and a declared
        // bootstrap user requires the complete credential set.
        RequireEnvironmentVariable("EIT_SETUP_API_DATABASE_URL");
        RequireEnvironmentVariable("EIT_SETUP_WORKER_DATABASE_URL");
        options.TryGetValue("--bootstrap-admin-user", out var bootstrapUser);
        if (!string.IsNullOrWhiteSpace(bootstrapUser))
        {
            RequireEnvironmentVariable("EIT_SETUP_BOOTSTRAP_ADMIN_PASSWORD");
            RequireEnvironmentVariable("EIT_SETUP_MIGRATION_PASSWORD");
            RequireEnvironmentVariable("EIT_SETUP_API_PASSWORD");
            RequireEnvironmentVariable("EIT_SETUP_WORKER_PASSWORD");
        }

        var command = new StringBuilder();
        command.Append("& ").Append(PsQuote(Path.Combine(scriptsRoot, "install-offline-payload.ps1")));
        command.Append(" -PayloadArchive ").Append(PsQuote(payload));
        command.Append(" -ExpectedSha256 ").Append(PsQuote(sha256));
        command.Append(" -ApiDatabaseUrl (ConvertTo-SecureString $env:EIT_SETUP_API_DATABASE_URL -AsPlainText -Force)");
        command.Append(" -WorkerDatabaseUrl (ConvertTo-SecureString $env:EIT_SETUP_WORKER_DATABASE_URL -AsPlainText -Force)");
        command.Append(" -EdgeBindAddress ").Append(PsQuote(edgeBind));
        command.Append(" -EdgeTlsHostname ").Append(PsQuote(edgeHost));
        command.Append(" -EdgeCertificateThumbprint ").Append(PsQuote(edgeThumbprint));
        if (!string.IsNullOrWhiteSpace(bootstrapUser))
        {
            command.Append(" -BootstrapAdminUser ").Append(PsQuote(bootstrapUser));
            command.Append(" -BootstrapAdminPassword (ConvertTo-SecureString $env:EIT_SETUP_BOOTSTRAP_ADMIN_PASSWORD -AsPlainText -Force)");
            command.Append(" -MigrationPassword (ConvertTo-SecureString $env:EIT_SETUP_MIGRATION_PASSWORD -AsPlainText -Force)");
            command.Append(" -ApiRuntimePassword (ConvertTo-SecureString $env:EIT_SETUP_API_PASSWORD -AsPlainText -Force)");
            command.Append(" -WorkerRuntimePassword (ConvertTo-SecureString $env:EIT_SETUP_WORKER_PASSWORD -AsPlainText -Force)");
        }

        if (options.TryGetValue("--min-free-space-gb", out var minFreeSpace) &&
            !string.IsNullOrWhiteSpace(minFreeSpace))
        {
            if (!int.TryParse(minFreeSpace, out var minFree) || minFree < 1 || minFree > 1024)
            {
                throw new InvalidOperationException("--min-free-space-gb must be between 1 and 1024.");
            }

            command.Append(" -MinimumFreeSpaceGB ").Append(minFree);
        }

        command.Append(" -Confirm:$false");
        return RunPowerShell(pwsh, command.ToString());
    }

    private static int RunUninstall(Dictionary<string, string?> options)
    {
        var installRoot = Path.GetFullPath(RequireOption(options, "--install-root"));
        var scriptsRoot = ResolveScriptsRoot();
        var pwsh = ResolvePowerShell();
        var command =
            "& " + PsQuote(Path.Combine(scriptsRoot, "uninstall-offline-payload.ps1")) +
            " -InstallRoot " + PsQuote(installRoot) +
            (options.ContainsKey("--purge-data") ? " -PurgeData" : string.Empty) +
            " -Confirm:$false";
        return RunPowerShell(pwsh, command);
    }

    private static int RunPowerShell(string pwsh, string command)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = pwsh,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        startInfo.ArgumentList.Add("-NoLogo");
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-NonInteractive");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-Command");
        startInfo.ArgumentList.Add(command);
        // Secrets must never persist in this process environment longer than
        // needed; they are only read for fail-fast validation and redaction.
        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("Failed to start pwsh.");
        var stdoutTask = process.StandardOutput.ReadToEndAsync();
        var stderrTask = process.StandardError.ReadToEndAsync();
        process.WaitForExit();
        var stdout = stdoutTask.GetAwaiter().GetResult();
        var stderr = stderrTask.GetAwaiter().GetResult();
        var exitCode = process.ExitCode;
        Console.Out.Write(RedactSecrets(stdout));
        Console.Error.Write(RedactSecrets(stderr));
        return exitCode;
    }

    private static string RedactSecrets(string text)
    {
        if (string.IsNullOrEmpty(text))
        {
            return text;
        }

        foreach (var name in SecretEnvironmentVariables)
        {
            var value = Environment.GetEnvironmentVariable(name);
            if (!string.IsNullOrEmpty(value))
            {
                text = text.Replace(value, "***", StringComparison.Ordinal);
            }
        }

        return text;
    }

    private static int Fail(string message)
    {
        Console.Error.WriteLine(message);
        return 1;
    }
}
