using EnterpriseIT.WorkerServiceHost;
using Xunit;
namespace EnterpriseIT.WorkerServiceHost.Tests;
public sealed class LifecycleTests
{
 [Fact] public async Task TerminationKillsAndWaitsForExit(){var exited=false;var kills=0;await ChildProcessTermination.TerminateAndReapAsync(()=>exited,()=>{kills++;},_=>{exited=true;return Task.CompletedTask;},TimeSpan.FromSeconds(1));Assert.True(exited);Assert.Equal(1,kills);}
 [Fact] public async Task TerminationTimesOutIfChildDoesNotExit(){await Assert.ThrowsAsync<TimeoutException>(()=>ChildProcessTermination.TerminateAndReapAsync(()=>false,()=>{},ct=>Task.Delay(Timeout.Infinite,ct),TimeSpan.FromMilliseconds(30)));}
 [Fact] public async Task GracefulShutdownSendsCommandAndWaits(){var exited=false;var sent=false;await WorkerChildShutdown.StopAsync(()=>exited,_=>{sent=true;return Task.CompletedTask;},_=>{exited=true;return Task.CompletedTask;},()=>Task.CompletedTask,TimeSpan.FromSeconds(1),CancellationToken.None);Assert.True(sent);Assert.True(exited);}
 [Fact] public async Task BrokenPipeFallsBackToKill(){var exited=false;var killed=false;await WorkerChildShutdown.StopAsync(()=>exited,_=>Task.FromException(new IOException()),_=>Task.CompletedTask,()=>{killed=true;exited=true;return Task.CompletedTask;},TimeSpan.FromSeconds(1),CancellationToken.None);Assert.True(killed);Assert.True(exited);}
}