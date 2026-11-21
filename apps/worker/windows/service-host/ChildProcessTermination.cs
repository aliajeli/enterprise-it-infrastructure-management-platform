namespace EnterpriseIT.WorkerServiceHost;
internal static class ChildProcessTermination
{
    internal static async Task TerminateAndReapAsync(Func<bool> hasExited, Action kill, Func<CancellationToken,Task> wait, TimeSpan timeout)
    {
        ArgumentNullException.ThrowIfNull(hasExited); ArgumentNullException.ThrowIfNull(kill); ArgumentNullException.ThrowIfNull(wait); ArgumentOutOfRangeException.ThrowIfLessThanOrEqual(timeout,TimeSpan.Zero);
        if(hasExited()) return;
        try { kill(); } catch(InvalidOperationException) when(hasExited()) { return; }
        if(hasExited()) return;
        using var cts=new CancellationTokenSource(timeout);
        try { await wait(cts.Token); if(!hasExited()) throw new InvalidOperationException("Worker child wait completed without confirming exit."); }
        catch(OperationCanceledException) when(cts.IsCancellationRequested) { throw new TimeoutException("Worker child could not be reaped within the configured deadline."); }
    }
}