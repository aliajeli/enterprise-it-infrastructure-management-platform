using System.Net;
using System.Net.Sockets;
using System.Text;

var noReadiness = args.Length > 0 &&
    File.Exists(args[0]) &&
    File.ReadAllText(args[0]).Contains("NO_READY", StringComparison.Ordinal);

using var shutdown = new CancellationTokenSource();
TcpListener? listener = null;
Task? listenerTask = null;

if (!noReadiness)
{
    listener = new TcpListener(IPAddress.Loopback, 13001);
    listener.Start();
    listenerTask = RunHealthEndpointAsync(listener, shutdown.Token);
}

while (await Console.In.ReadLineAsync() is { } command)
{
    if (string.Equals(command, "SHUTDOWN", StringComparison.Ordinal))
        break;
}

shutdown.Cancel();
listener?.Stop();

if (listenerTask is not null)
{
    try { await listenerTask; }
    catch (OperationCanceledException) when (shutdown.IsCancellationRequested) { }
    catch (SocketException) when (shutdown.IsCancellationRequested) { }
}

static async Task RunHealthEndpointAsync(TcpListener listener, CancellationToken cancellationToken)
{
    while (!cancellationToken.IsCancellationRequested)
    {
        using var client = await listener.AcceptTcpClientAsync(cancellationToken);
        await using var stream = client.GetStream();
        var request = new byte[4096];
        _ = await stream.ReadAsync(request, cancellationToken);
        var response = Encoding.ASCII.GetBytes(
            "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        await stream.WriteAsync(response, cancellationToken);
        await stream.FlushAsync(cancellationToken);
    }
}
