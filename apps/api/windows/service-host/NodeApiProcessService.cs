using System.Diagnostics;
using System.Net;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace EnterpriseIT.ApiServiceHost;

internal sealed class NodeApiProcessService : BackgroundService
{
    private static readonly TimeSpan GracefulShutdownTimeout = TimeSpan.FromSeconds(20);
    private static readonly TimeSpan StartupReadinessTimeout = TimeSpan.FromSeconds(20);
    private static readonly TimeSpan ReadinessTimeout = TimeSpan.FromSeconds(60);
    private static readonly TimeSpan ProcessReapTimeout = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan OutputDrainTimeout = TimeSpan.FromSeconds(5);
    private static readonly TimeSpan ReadinessPollInterval = TimeSpan.FromSeconds(1);
    private static readonly Uri ReadinessEndpoint = new("http://127.0.0.1:13001/health/ready");
    private readonly ILogger<NodeApiProcessService> _logger;
    private readonly TaskCompletionSource _readiness = new(
        TaskCreationOptions.RunContinuationsAsynchronously);
    private Process? _process;
    private Task? _stdoutDrain;
    private Task? _stderrDrain;

    public NodeApiProcessService(ILogger<NodeApiProcessService> logger)
    {
        _logger = logger;
    }

    public override async Task StartAsync(CancellationToken cancellationToken)
    {
        await base.StartAsync(cancellationToken);
        try
        {
            // Keep SCM's synchronous service-start phase bounded. The longer background
            // readiness budget remains useful only after startup has been accepted.
            await _readiness.Task.WaitAsync(StartupReadinessTimeout, cancellationToken);
        }
        catch (TimeoutException)
        {
            _logger.LogError(
                "API readiness was not reached within the service startup budget of {StartupTimeout}.",
                StartupReadinessTimeout);
            await base.StopAsync(CancellationToken.None);
            throw new TimeoutException(
                $"The API did not become ready within {StartupReadinessTimeout}.");
        }
        catch (OperationCanceledException)
        {
            await base.StopAsync(CancellationToken.None);
            throw;
        }
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        try
        {
            var serviceSid = WindowsServiceIdentity.RequireEnabledServiceSid("EnterpriseITApi");
            _logger.LogInformation("Validated enabled Windows service SID {ServiceSid}.", serviceSid.Value);

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

            try
            {
                var childServiceSid = WindowsServiceIdentity.RequireEnabledServiceSid(
                    "EnterpriseITApi", process.Handle);
                if (!serviceSid.Equals(childServiceSid))
                    throw new UnauthorizedAccessException(
                        "The API child process does not have the expected enabled service SID.");
            }
            catch (Exception startupException)
            {
                try
                {
                    await TerminateAndReapAsync(
                        process,
                        "The API child failed service-SID validation.");
                }
                catch (Exception cleanupException)
                {
                    _logger.LogCritical(
                        cleanupException,
                        "API child cleanup failed after service-SID validation failed.");
                    throw new AggregateException(
                        "API child identity validation and cleanup both failed.",
                        startupException,
                        cleanupException);
                }
                finally
                {
                    process.Dispose();
                }

                throw;
            }

            _process = process;
            _stdoutDrain = process.StandardOutput.BaseStream.CopyToAsync(Stream.Null);
            _stderrDrain = process.StandardError.BaseStream.CopyToAsync(Stream.Null);
            _logger.LogInformation("API child process started with PID {ProcessId}.", process.Id);

            try
            {
                await WaitForReadinessAsync(process, stoppingToken);
            }
            catch (Exception readinessException)
            {
                try
                {
                    await TerminateAndReapAsync(
                        process,
                        "The API child failed readiness startup.");
                }
                catch (Exception cleanupException)
                {
                    _logger.LogCritical(
                        cleanupException,
                        "API child cleanup failed after readiness startup failed.");
                    throw new AggregateException(
                        "API readiness and child cleanup both failed.",
                        readinessException,
                        cleanupException);
                }

                throw;
            }

            _logger.LogInformation(
                "API readiness check succeeded at {ReadinessEndpoint}.",
                ReadinessEndpoint);
            _readiness.TrySetResult();

            await process.WaitForExitAsync(stoppingToken);
            await Task.WhenAll(_stdoutDrain, _stderrDrain);

            if (!stoppingToken.IsCancellationRequested)
            {
                throw new InvalidOperationException(
                    $"The API child process exited unexpectedly with code {process.ExitCode}.");
            }
        }
        catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
        {
            _readiness.TrySetCanceled(stoppingToken);
            throw;
        }
        catch (Exception exception)
        {
            _readiness.TrySetException(exception);
            throw;
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
                    try
                    {
                        await process.StandardInput.WriteLineAsync("SHUTDOWN");
                        await process.StandardInput.FlushAsync(cancellationToken);
                        process.StandardInput.Close();

                        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(
                            cancellationToken);
                        timeout.CancelAfter(GracefulShutdownTimeout);
                        await process.WaitForExitAsync(timeout.Token);
                    }
                    catch (OperationCanceledException)
                    {
                        _logger.LogWarning(
                            "API child process did not complete graceful shutdown before the stop deadline; terminating its process tree.");
                    }
                    catch (InvalidOperationException) when (process.HasExited)
                    {
                        // The child exited while the stop request was being delivered.
                    }
                    catch (IOException exception)
                    {
                        _logger.LogWarning(
                            exception,
                            "The API shutdown command could not be delivered; terminating the child process tree.");
                    }
                    catch (InvalidOperationException exception)
                    {
                        _logger.LogWarning(
                            exception,
                            "The API shutdown channel was unavailable; terminating the child process tree.");
                    }
                }

                // Cancellation or a broken stdin pipe must not bypass child cleanup.
                await TerminateAndReapAsync(
                    process,
                    "Service shutdown requires API child process-tree termination.");
            }
            finally
            {
                try
                {
                    await base.StopAsync(cancellationToken);
                }
                finally
                {
                    if (_stdoutDrain is not null && _stderrDrain is not null)
                    {
                        try
                        {
                            await Task.WhenAll(_stdoutDrain, _stderrDrain)
                                .WaitAsync(OutputDrainTimeout);
                        }
                        catch (TimeoutException)
                        {
                            _logger.LogError(
                                "API child output streams did not close within {DrainTimeout}; continuing bounded host cleanup.",
                                OutputDrainTimeout);
                        }
                    }
                    process.Dispose();
                    _process = null;
                }
            }

            return;
        }

        await base.StopAsync(cancellationToken);
    }

    private async Task TerminateAndReapAsync(Process process, string reason)
    {
        if (process.HasExited)
            return;

        _logger.LogWarning("{CleanupReason}", reason);
        try
        {
            await ChildProcessTermination.TerminateAndReapAsync(
                () => process.HasExited,
                () => process.Kill(entireProcessTree: true),
                process.WaitForExitAsync,
                ProcessReapTimeout);
        }
        catch (Exception exception)
        {
            _logger.LogCritical(
                exception,
                "Failed to terminate and reap the API child process tree.");
            throw;
        }
    }

    private static async Task WaitForReadinessAsync(
        Process process,
        CancellationToken stoppingToken)
    {
        using var handler = new SocketsHttpHandler
        {
            ConnectTimeout = TimeSpan.FromSeconds(1),
            UseCookies = false,
            AllowAutoRedirect = false,
        };
        using var client = new HttpClient(handler)
        {
            Timeout = TimeSpan.FromSeconds(2),
        };
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(stoppingToken);
        timeout.CancelAfter(ReadinessTimeout);

        while (true)
        {
            timeout.Token.ThrowIfCancellationRequested();

            if (process.HasExited)
            {
                throw new InvalidOperationException(
                    $"The API child process exited before readiness with code {process.ExitCode}.");
            }

            try
            {
                using var response = await client.GetAsync(
                    ReadinessEndpoint,
                    HttpCompletionOption.ResponseHeadersRead,
                    timeout.Token);

                if (response.StatusCode == HttpStatusCode.OK)
                {
                    return;
                }
            }
            catch (HttpRequestException)
            {
                // The API may still be binding its loopback listener or waiting for the database.
            }
            catch (OperationCanceledException) when (
                !stoppingToken.IsCancellationRequested && !timeout.IsCancellationRequested)
            {
                // A single bounded HTTP request timed out; retry within the overall startup budget.
            }

            await Task.Delay(ReadinessPollInterval, timeout.Token);
        }
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
