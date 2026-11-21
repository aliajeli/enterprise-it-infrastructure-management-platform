using System.IO;
using System.Runtime.ExceptionServices;
namespace EnterpriseIT.WorkerServiceHost;
internal static class WorkerChildShutdown
{
    internal static async Task StopAsync(Func<bool> hasExited,Func<CancellationToken,Task> request,Func<CancellationToken,Task> wait,Func<Task> force,TimeSpan timeout,CancellationToken cancellation,Action<Exception?>? warning=null)
    {
        if(hasExited()) return;
        OperationCanceledException? cancelled=null; var forced=false;
        using(var cts=CancellationTokenSource.CreateLinkedTokenSource(cancellation))
        {
            cts.CancelAfter(timeout);
            try { await request(cts.Token); await wait(cts.Token); if(!hasExited()){forced=true;warning?.Invoke(null);} }
            catch(OperationCanceledException ex){forced=true;if(cancellation.IsCancellationRequested)cancelled=ex;warning?.Invoke(ex);}
            catch(IOException ex){forced=true;warning?.Invoke(ex);}
            catch(InvalidOperationException ex){if(hasExited())return;forced=true;warning?.Invoke(ex);}
        }
        if(cancellation.IsCancellationRequested&&cancelled is null)cancelled=new OperationCanceledException(cancellation);
        if(forced&&!hasExited()) { try{await force();}catch(Exception cleanup) when(cancelled is not null){throw new AggregateException("Worker shutdown cancellation and process cleanup both failed.",cancelled,cleanup);} }
        if(cancelled is not null) ExceptionDispatchInfo.Capture(cancelled).Throw();
    }
}