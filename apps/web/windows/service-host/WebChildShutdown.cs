using System.IO;
using System.Runtime.ExceptionServices;

namespace EnterpriseIT.WebServiceHost;

internal static class WebChildShutdown
{
    internal static async Task<bool> StopAsync(
        Func<bool> hasExited,
        Func<CancellationToken, Task> requestGracefulShutdown,
        Func<CancellationToken, Task> waitForExit,
        Func<Task> terminateAndReap,
        TimeSpan gracefulTimeout,
        CancellationToken cancellationToken,
        Action<Exception?>? onForcedShutdown = null)
    {
        ArgumentNullException.ThrowIfNull(hasExited);
        ArgumentNullException.ThrowIfNull(requestGracefulShutdown);
        ArgumentNullException.ThrowIfNull(waitForExit);
        ArgumentNullException.ThrowIfNull(terminateAndReap);
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(gracefulTimeout, TimeSpan.Zero);
        if (hasExited()) return false;

        OperationCanceledException? cancellation = null;
        var requiresForcedShutdown = false;
        using (var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken))
        {
            timeout.CancelAfter(gracefulTimeout);
            try
            {
                await requestGracefulShutdown(timeout.Token);
                await waitForExit(timeout.Token);
                if (hasExited()) return false;
                requiresForcedShutdown = true;
                onForcedShutdown?.Invoke(null);
            }
            catch (OperationCanceledException exception)
            {
                requiresForcedShutdown = true;
                if (cancellationToken.IsCancellationRequested) cancellation = exception;
                onForcedShutdown?.Invoke(cancellation);
            }
            catch (IOException exception)
            {
                requiresForcedShutdown = true;
                onForcedShutdown?.Invoke(exception);
            }
            catch (InvalidOperationException exception)
            {
                if (hasExited()) return false;
                requiresForcedShutdown = true;
                onForcedShutdown?.Invoke(exception);
            }
        }

        if (cancellationToken.IsCancellationRequested && cancellation is null)
            cancellation = new OperationCanceledException(cancellationToken);

        var forced = false;
        if (requiresForcedShutdown && !hasExited())
        {
            try { await terminateAndReap(); forced = true; }
            catch (Exception cleanupException) when (cancellation is not null)
            {
                throw new AggregateException(
                    "The Web child shutdown was cancelled and forced cleanup also failed.",
                    cancellation, cleanupException);
            }
        }
        if (cancellation is not null) ExceptionDispatchInfo.Capture(cancellation).Throw();
        return forced;
    }
}
