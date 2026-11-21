using EnterpriseIT.WebServiceHost;
using Xunit;

namespace EnterpriseIT.WebServiceHost.Tests;

public sealed class WebChildShutdownTests
{
    [Fact]
    public async Task AlreadyExitedChild_DoesNotRequestOrForceShutdown()
    {
        var requests=0; var forces=0;
        var forced=await WebChildShutdown.StopAsync(()=>true,_=>{requests++;return Task.CompletedTask;},_=>Task.CompletedTask,()=>{forces++;return Task.CompletedTask;},TimeSpan.FromSeconds(1),CancellationToken.None);
        Assert.False(forced); Assert.Equal(0,requests); Assert.Equal(0,forces);
    }

    [Fact]
    public async Task GracefulShutdown_RequestsCommandAndWaitsWithoutKilling()
    {
        var exited=false; var requests=0; var waits=0; var forces=0;
        var forced=await WebChildShutdown.StopAsync(()=>exited,_=>{requests++;return Task.CompletedTask;},_=>{waits++;exited=true;return Task.CompletedTask;},()=>{forces++;return Task.CompletedTask;},TimeSpan.FromSeconds(1),CancellationToken.None);
        Assert.False(forced); Assert.Equal(1,requests); Assert.Equal(1,waits); Assert.Equal(0,forces);
    }

    [Fact]
    public async Task BrokenControlPipe_FallsBackToTerminationAndReap()
    {
        var exited=false; Exception? reported=null; var forces=0;
        var forced=await WebChildShutdown.StopAsync(()=>exited,_=>Task.FromException(new IOException("Pipe is closed.")),_=>Task.CompletedTask,()=>{forces++;exited=true;return Task.CompletedTask;},TimeSpan.FromSeconds(1),CancellationToken.None,exception=>reported=exception);
        Assert.True(forced); Assert.True(exited); Assert.Equal(1,forces); Assert.IsType<IOException>(reported);
    }

    [Fact]
    public async Task GracefulTimeout_FallsBackToTerminationAndReap()
    {
        var exited=false; var forces=0;
        var forced=await WebChildShutdown.StopAsync(()=>exited,_=>Task.CompletedTask,token=>Task.Delay(Timeout.InfiniteTimeSpan,token),()=>{forces++;exited=true;return Task.CompletedTask;},TimeSpan.FromMilliseconds(40),CancellationToken.None);
        Assert.True(forced); Assert.True(exited); Assert.Equal(1,forces);
    }

    [Fact]
    public async Task HostCancellation_ReapsChildThenPropagatesCancellation()
    {
        var exited=false; var forces=0; using var cts=new CancellationTokenSource(); cts.Cancel();
        await Assert.ThrowsAnyAsync<OperationCanceledException>(()=>WebChildShutdown.StopAsync(()=>exited,token=>Task.FromCanceled(token),_=>Task.CompletedTask,()=>{forces++;exited=true;return Task.CompletedTask;},TimeSpan.FromSeconds(1),cts.Token));
        Assert.True(exited); Assert.Equal(1,forces);
    }

    [Fact]
    public async Task UnexpectedControlChannelState_FallsBackWhenChildStillRunning()
    {
        var exited=false; var forces=0;
        var forced=await WebChildShutdown.StopAsync(()=>exited,_=>Task.FromException(new InvalidOperationException("Pipe unavailable.")),_=>Task.CompletedTask,()=>{forces++;exited=true;return Task.CompletedTask;},TimeSpan.FromSeconds(1),CancellationToken.None);
        Assert.True(forced); Assert.True(exited); Assert.Equal(1,forces);
    }

    [Fact]
    public async Task WaitCompletesButChildStillRuns_FallsBackToTermination()
    {
        var exited=false; var forces=0;
        var forced=await WebChildShutdown.StopAsync(()=>exited,_=>Task.CompletedTask,_=>Task.CompletedTask,()=>{forces++;exited=true;return Task.CompletedTask;},TimeSpan.FromSeconds(1),CancellationToken.None);
        Assert.True(forced); Assert.True(exited); Assert.Equal(1,forces);
    }

    [Fact]
    public async Task InvalidGracefulTimeout_IsRejectedBeforeActions()
    {
        var requests=0;
        await Assert.ThrowsAsync<ArgumentOutOfRangeException>(()=>WebChildShutdown.StopAsync(()=>false,_=>{requests++;return Task.CompletedTask;},_=>Task.CompletedTask,()=>Task.CompletedTask,TimeSpan.Zero,CancellationToken.None));
        Assert.Equal(0,requests);
    }
}
