namespace EnterpriseIT.ApiServiceHost;

internal static class ChildProcessTermination
{
    internal static async Task TerminateAndReapAsync(
        Func<bool> hasExited,
        Action killProcessTree,
        Func<CancellationToken, Task> waitForExit,
        TimeSpan reapTimeout)
    {
        ArgumentNullException.ThrowIfNull(hasExited);
        ArgumentNullException.ThrowIfNull(killProcessTree);
        ArgumentNullException.ThrowIfNull(waitForExit);
        ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(reapTimeout, TimeSpan.Zero);

        if (hasExited())
            return;

        try
        {
            killProcessTree();
        }
        catch (InvalidOperationException) when (hasExited())
        {
            // The child exited between the state check and the termination request.
            return;
        }

        if (hasExited())
            return;

        using var timeout = new CancellationTokenSource(reapTimeout);
        try
        {
            await waitForExit(timeout.Token);
            if (!hasExited())
                throw new InvalidOperationException(
                    "The API child-process wait completed without confirming process exit.");
        }
        catch (OperationCanceledException) when (timeout.IsCancellationRequested)
        {
            throw new TimeoutException(
                $"The API child process could not be reaped within {reapTimeout}.");
        }
    }
}
