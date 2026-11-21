using System.Net;
using System.Security.Authentication;
using EnterpriseIT.EdgeServiceHost;
using Microsoft.AspNetCore.HttpOverrides;
using Yarp.ReverseProxy.Configuration;

var configurationPath = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),
    "EnterpriseIT", "Edge", "edge.json");
var edge = EdgeConfiguration.Load(configurationPath);
var certificate = EdgeCertificate.Load(edge);

var builder = WebApplication.CreateBuilder(new WebApplicationOptions
{
    ContentRootPath = AppContext.BaseDirectory,
});
builder.Services.AddWindowsService(options => options.ServiceName = "EnterpriseITEdge");
builder.Services.Configure<HostOptions>(options => options.ShutdownTimeout = TimeSpan.FromSeconds(20));
builder.WebHost.ConfigureKestrel(options =>
{
    options.Limits.MaxRequestBodySize = 50 * 1024 * 1024;
    options.Limits.RequestHeadersTimeout = TimeSpan.FromSeconds(15);
    options.Limits.KeepAliveTimeout = TimeSpan.FromMinutes(2);
    options.Listen(IPAddress.Parse(edge.BindAddress), edge.Port, listen =>
        listen.UseHttps(certificate, https => https.SslProtocols = SslProtocols.Tls12 | SslProtocols.Tls13));
});

var transforms = new[]
{
    new Dictionary<string, string> { ["X-Forwarded"] = "Set" },
    new Dictionary<string, string> { ["Forwarded"] = "Off" },
};
var routes = new[]
{
    new RouteConfig
    {
        RouteId = "api",
        ClusterId = "api",
        Order = 0,
        Match = new RouteMatch { Path = "/api/{**catch-all}" },
        Transforms = transforms,
    },
    new RouteConfig
    {
        RouteId = "web",
        ClusterId = "web",
        Order = 1,
        Match = new RouteMatch { Path = "/{**catch-all}" },
        Transforms = transforms,
    },
};
var clusters = new[]
{
    new ClusterConfig
    {
        ClusterId = "api",
        Destinations = new Dictionary<string, DestinationConfig>
        {
            ["api-loopback"] = new() { Address = "http://127.0.0.1:13001/" },
        },
    },
    new ClusterConfig
    {
        ClusterId = "web",
        Destinations = new Dictionary<string, DestinationConfig>
        {
            ["web-loopback"] = new() { Address = "http://127.0.0.1:13000/" },
        },
    },
};
builder.Services.AddReverseProxy().LoadFromMemory(routes, clusters);
builder.Services.AddHttpClient("edge-readiness", client => client.Timeout = TimeSpan.FromSeconds(2));

var app = builder.Build();
app.Use(async (context, next) =>
{
    if (!context.Request.Path.Equals("/health/ready", StringComparison.OrdinalIgnoreCase) &&
        !string.Equals(context.Request.Host.Host, edge.TlsHostname, StringComparison.OrdinalIgnoreCase))
    {
        context.Response.StatusCode = StatusCodes.Status421MisdirectedRequest;
        return;
    }
    context.Response.Headers.StrictTransportSecurity = "max-age=31536000";
    await next();
});
app.MapGet("/health/ready", async (IHttpClientFactory clients, CancellationToken cancellationToken) =>
{
    var client = clients.CreateClient("edge-readiness");
    var apiReady = await IsReady(client, "http://127.0.0.1:13001/health/ready", cancellationToken);
    var webReady = await IsReady(client, "http://127.0.0.1:13000/health/ready", cancellationToken);
    var certificateReady = DateTime.UtcNow >= certificate.NotBefore.ToUniversalTime() &&
        DateTime.UtcNow < certificate.NotAfter.ToUniversalTime() && certificate.HasPrivateKey;
    return apiReady && webReady && certificateReady
        ? Results.Ok(new { status = "ready", api = true, web = true, tlsCertificate = true })
        : Results.Problem(statusCode: StatusCodes.Status503ServiceUnavailable,
            title: "Edge dependencies are not ready",
            extensions: new Dictionary<string, object?> { ["api"] = apiReady, ["web"] = webReady, ["tlsCertificate"] = certificateReady });
});
app.MapReverseProxy();
await app.RunAsync();

static async Task<bool> IsReady(HttpClient client, string url, CancellationToken cancellationToken)
{
    try
    {
        using var response = await client.GetAsync(url, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        return response.StatusCode == HttpStatusCode.OK;
    }
    catch (HttpRequestException) { return false; }
    catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested) { return false; }
}
