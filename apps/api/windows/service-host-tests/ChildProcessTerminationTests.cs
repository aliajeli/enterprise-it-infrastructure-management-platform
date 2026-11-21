using EnterpriseIT.ApiServiceHost;
using Xunit;

namespace EnterpriseIT.ApiServiceHost.Tests;

public sealed class ChildProcessTerminationTests
{
    [Fact]
    public async Task AlreadyExitedChild_IsNotKilledOrWaited()
    {
        var killCount = 0;
        var waitCount = 0;

        await ChildProcessTermination.TerminateAndReapAsync(
            () => true,
            () => killCount++,
            _ =>
            {
                waitCount++;
                return Task.CompletedTask;
            },
            TimeSpan.FromSeconds(1));

        Assert.Equal(0, killCount);
        Assert.Equal(0, waitCount);
    }

    [Fact]
    public async Task RunningChild_IsKilledAndReaped()
    {
        var exited = false;
        var killCount = 0;
        var waitCount = 0;

        await ChildProcessTermination.TerminateAndReapAsync(
            () => exited,
            () => killCount++,
            _ =>
            {
                waitCount++;
                exited = true;
                return Task.CompletedTask;
            },
            TimeSpan.FromSeconds(1));

        Assert.Equal(1, killCount);
        Assert.Equal(1, waitCount);
        Assert.True(exited);
    }

    [Fact]
    public async Task ExitRaceDuringKill_IsTreatedAsAlreadyExited()
    {
        var exited = false;
        var waitCount = 0;

        await ChildProcessTermination.TerminateAndReapAsync(
            () => exited,
            () =>
            {
                exited = true;
                throw new InvalidOperationException("Process already exited.");
            },
            _ =>
            {
                waitCount++;
                return Task.CompletedTask;
            },
            TimeSpan.FromSeconds(1));

        Assert.Equal(0, waitCount);
    }

    [Fact]
    public async Task KillFailure_IsPropagated()
    {
        var exception = new System.ComponentModel.Win32Exception(5);

        var actual = await Assert.ThrowsAsync<System.ComponentModel.Win32Exception>(
            () => ChildProcessTermination.TerminateAndReapAsync(
                () => false,
                () => throw exception,
                _ => Task.CompletedTask,
                TimeSpan.FromSeconds(1)));

        Assert.Same(exception, actual);
    }

    [Fact]
    public async Task ReapTimeout_IsReported()
    {
        await Assert.ThrowsAsync<TimeoutException>(
            () => ChildProcessTermination.TerminateAndReapAsync(
                () => false,
                () => { },
                token => Task.Delay(Timeout.InfiniteTimeSpan, token),
                TimeSpan.FromMilliseconds(50)));
    }
    [Fact]
    public async Task ExternalCancellation_IsPropagatedWithoutBecomingReapTimeout()
    {
        var actual = await Assert.ThrowsAnyAsync<OperationCanceledException>(
            () => ChildProcessTermination.TerminateAndReapAsync(
                () => false,
                () => { },
                token => Task.Delay(Timeout.InfiniteTimeSpan, token),
                TimeSpan.FromSeconds(5)));

        Assert.IsNotType<TimeoutException>(actual);
    }

    [Fact]
    public async Task UnexpectedInvalidOperationDuringKill_IsPropagated()
    {
        var exception = new InvalidOperationException("Unexpected process state.");

        var actual = await Assert.ThrowsAsync<InvalidOperationException>(
            () => ChildProcessTermination.TerminateAndReapAsync(
                () => false,
                () => throw exception,
                _ => Task.CompletedTask,
                TimeSpan.FromSeconds(1)));

        Assert.Same(exception, actual);
    }

    [Fact]
    public async Task NonPositiveReapTimeout_IsRejectedBeforeProcessActions()
    {
        var killCount = 0;

        await Assert.ThrowsAsync<ArgumentOutOfRangeException>(
            () => ChildProcessTermination.TerminateAndReapAsync(
                () => false,
                () => killCount++,
                _ => Task.CompletedTask,
                TimeSpan.Zero));

        Assert.Equal(0, killCount);
    }
}
