using System.Diagnostics;
using System.Net;
using System.Security.Principal;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
namespace EnterpriseIT.WorkerServiceHost;
internal sealed class NodeWorkerProcessService : BackgroundService
{
    private static readonly TimeSpan StartupBudget=TimeSpan.FromSeconds(20), ReadinessBudget=TimeSpan.FromSeconds(60), GracefulBudget=TimeSpan.FromSeconds(20), ReapBudget=TimeSpan.FromSeconds(5);
    private static readonly Uri ReadyUri=new("http://127.0.0.1:13002/health/ready");
    private readonly ILogger<NodeWorkerProcessService> logger; private readonly TaskCompletionSource ready=new(TaskCreationOptions.RunContinuationsAsynchronously);
    private Process? child; private Task? stdout,stderr;
    internal NodeWorkerProcessService(ILogger<NodeWorkerProcessService> logger)=>this.logger=logger;
    public override async Task StartAsync(CancellationToken token)
    {
        await base.StartAsync(token);
        try{await ready.Task.WaitAsync(StartupBudget,token);}
        catch{await StopAsync(CancellationToken.None);throw;}
    }
    protected override async Task ExecuteAsync(CancellationToken token)
    {
        try
        {
            var sid=WindowsServiceIdentity.RequireEnabledServiceSid("EnterpriseITWorker");
            var root=Path.GetFullPath(AppContext.BaseDirectory); var node=Path.Combine(root,"runtime","node.exe"); var entry=Path.Combine(root,"apps","worker","dist","main.js");
            if(!File.Exists(node)||!File.Exists(entry)) throw new FileNotFoundException("The immutable Worker runtime payload is incomplete.");
            var info=new ProcessStartInfo{FileName=node,WorkingDirectory=root,UseShellExecute=false,CreateNoWindow=true,RedirectStandardInput=true,RedirectStandardOutput=true,RedirectStandardError=true};
            info.ArgumentList.Add(entry); ConfigureEnvironment(info,root,sid);
            var process=new Process{StartInfo=info,EnableRaisingEvents=true}; if(!process.Start()){process.Dispose();throw new InvalidOperationException("Worker child did not start.");}
            child=process;
            var childSid=WindowsServiceIdentity.RequireEnabledServiceSid("EnterpriseITWorker",process.Handle);
            if(!sid.Equals(childSid)){await KillAndReap(process);throw new UnauthorizedAccessException("Worker child token has an unexpected service SID.");}
            stdout=process.StandardOutput.BaseStream.CopyToAsync(Stream.Null); stderr=process.StandardError.BaseStream.CopyToAsync(Stream.Null);
            await WaitReady(process,token); ready.TrySetResult(); await process.WaitForExitAsync(token); await Task.WhenAll(stdout,stderr);
            if(!token.IsCancellationRequested) throw new InvalidOperationException("Worker child exited unexpectedly with code "+process.ExitCode+".");
        }
        catch(OperationCanceledException) when(token.IsCancellationRequested){ready.TrySetCanceled(token);throw;}
        catch(Exception ex){ready.TrySetException(ex);throw;}
    }
    public override async Task StopAsync(CancellationToken token)
    {
        var process=child;
        if(process is not null)
        {
            try { await WorkerChildShutdown.StopAsync(()=>process.HasExited,async ct=>{await process.StandardInput.WriteLineAsync("SHUTDOWN");await process.StandardInput.FlushAsync(ct);process.StandardInput.Close();},process.WaitForExitAsync,()=>KillAndReap(process),GracefulBudget,token,ex=>logger.LogWarning(ex,"Worker graceful shutdown required forced termination.")); }
            finally { await base.StopAsync(token); process.Dispose(); child=null; }
        }
        else await base.StopAsync(token);
    }
    private async Task KillAndReap(Process process)
    {
        if(process.HasExited)return;
        await ChildProcessTermination.TerminateAndReapAsync(()=>process.HasExited,()=>process.Kill(true),process.WaitForExitAsync,ReapBudget);
    }
    private static async Task WaitReady(Process process,CancellationToken token)
    {
        using var client=new HttpClient(new SocketsHttpHandler{ConnectTimeout=TimeSpan.FromSeconds(1),AllowAutoRedirect=false}){Timeout=TimeSpan.FromSeconds(2)};
        using var deadline=CancellationTokenSource.CreateLinkedTokenSource(token);deadline.CancelAfter(ReadinessBudget);
        while(true){deadline.Token.ThrowIfCancellationRequested();if(process.HasExited)throw new InvalidOperationException("Worker exited before readiness.");
            try{using var response=await client.GetAsync(ReadyUri,HttpCompletionOption.ResponseHeadersRead,deadline.Token);if(response.StatusCode==HttpStatusCode.OK)return;}
            catch(HttpRequestException){} catch(OperationCanceledException) when(!token.IsCancellationRequested&&!deadline.IsCancellationRequested){}
            await Task.Delay(1000,deadline.Token);
        }
    }
    private static void ConfigureEnvironment(ProcessStartInfo info,string root,SecurityIdentifier serviceSid)
    {
        info.Environment.Clear();
        foreach(var name in new[]{"SystemRoot","WINDIR","TEMP","TMP","ProgramData","ProgramFiles","ProgramFiles(x86)"}){var value=Environment.GetEnvironmentVariable(name);if(!string.IsNullOrWhiteSpace(value))info.Environment[name]=value;}
        var systemRoot=Environment.GetEnvironmentVariable("SystemRoot");if(string.IsNullOrWhiteSpace(systemRoot))throw new InvalidOperationException("Windows system root is unavailable.");
        info.Environment["PATH"]=string.Join(Path.PathSeparator,Path.Combine(root,"runtime"),Path.Combine(systemRoot,"System32"));
        info.Environment["NODE_ENV"]="production";info.Environment["WORKER_ID"]="windows-service";info.Environment["WORKER_POLL_INTERVAL_MS"]="2000";
        var configPath=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),"EnterpriseIT","Worker","database.config.dpapi");
        var databaseUrl=WorkerDatabaseConfiguration.Load(configPath,serviceSid);
        info.Environment["DATABASE_URL"]=databaseUrl;
    }
}