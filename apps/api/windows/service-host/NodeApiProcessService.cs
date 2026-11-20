using System.Diagnostics;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace EnterpriseIT.ApiServiceHost;

internal sealed class NodeApiProcessService : BackgroundService
{
    private static readonly TimeSpan GracefulShutdownTimeout = TimeSpan.FromSeconds(20);
    private readonly ILogger<NodeApiProcessService> _logger;
    private Process? _process;
    private Task? _stdoutDrain;
    private Task? _stderrDrain;

    public NodeApiProcessService(ILogger<NodeApiProcessService> logger)
    {
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var root = Path.GetFullPath(AppContext.BaseDirectory);
        var nodePath = Path.Combine(root, "runtime", "node.exe");
        var apiEntryPoint = Path.Combine(root, "apps", "api", "dist", "server.js");

        if (!File.Exists(nodePath) || !File.Exists(apiEntryPoint))
        {
            throw new FileNotFoundException(
                "The immutable API runtime payload is incomplete.");
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = nodePath,
            WorkingDirectory = root,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
        };
        startInfo.ArgumentList.Add(apiEntryPoint);
        ConfigureChildEnvironment(startInfo, root);

        var process = new Process
        {
            StartInfo = startInfo,
            EnableRaisingEvents = true,
        };

        if (!process.Start())
        {
            process.Dispose();
            throw new InvalidOperationException("The API child process did not start.");
        }

        _process = process;
        _stdoutDrain = process.StandardOutput.BaseStream.CopyToAsync(Stream.Null);
        _stderrDrain = process.StandardError.BaseStream.CopyToAsync(Stream.Null);
        _logger.LogInformation("API child process started with PID {ProcessId}.", process.Id);

        await process.WaitForExitAsync(stoppingToken);
        await Task.WhenAll(_stdoutDrain, _stderrDrain);

        if (!stoppingToken.IsCancellationRequested)
        {
            throw new InvalidOperationException(
                $"The API child process exited unexpectedly with code {process.ExitCode}.");
        }
    }

    public override async Task StopAsync(CancellationToken cancellationToken)
    {
        var process = _process;
        if (process is not null)
        {
            try
            {
                if (!process.HasExited)
                {
                    await process.StandardInput.WriteLineAsync("SHUTDOWN");
                    await process.StandardInput.FlushAsync(cancellationToken);
                    process.StandardInput.Close();

                    using var timeout = CancellationTokenSource.CreateLinkedTokenSource(
                        cancellationToken);
                    timeout.CancelAfter(GracefulShutdownTimeout);

                    try
                    {
                        await process.WaitForExitAsync(timeout.Token);
                    }
                    catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
                    {
                        _logger.LogWarning(
                            "API child process did not stop within the grace period; terminating its process tree.");
                        if (!process.HasExited)
                        {
                            process.Kill(entireProcessTree: true);
                            await process.WaitForExitAsync(CancellationToken.None);
                        }
                    }
                }
            }
            catch (InvalidOperationException) when (process.HasExited)
            {
                // The child exited while the stop request was being delivered.
            }
        }

        await base.StopAsync(cancellationToken);
        if (_stdoutDrain is not null && _stderrDrain is not null)
        {
            await Task.WhenAll(_stdoutDrain, _stderrDrain);
        }
        process?.Dispose();
        _process = null;
    }

    private static void ConfigureChildEnvironment(ProcessStartInfo startInfo, string root)
    {
        startInfo.Environment.Clear();

        foreach (var name in new[]
        {
            "SystemRoot", "WINDIR", "TEMP", "TMP", "ProgramData",
            "ProgramFiles", "ProgramFiles(x86)", "CommonProgramFiles",
            "CommonProgramW6432",
        })
        {
            var value = Environment.GetEnvironmentVariable(name);
            if (!string.IsNullOrWhiteSpace(value))
            {
                startInfo.Environment[name] = value;
            }
        }

        var systemRoot = Environment.GetEnvironmentVariable("SystemRoot");
        if (string.IsNullOrWhiteSpace(systemRoot))
        {
            throw new InvalidOperationException("The Windows system root is unavailable.");
        }

        startInfo.Environment["PATH"] = string.Join(
            Path.PathSeparator,
            Path.Combine(root, "runtime"),
            Path.Combine(systemRoot, "System32"));
        startInfo.Environment["NODE_ENV"] = "production";
        startInfo.Environment["API_HOST"] = "127.0.0.1";
        startInfo.Environment["API_PORT"] = "13001";
        startInfo.Environment["COOKIE_SECURE"] = "true";
    }
}
