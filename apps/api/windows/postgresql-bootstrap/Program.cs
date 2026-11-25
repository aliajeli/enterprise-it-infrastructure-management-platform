using EnterpriseIT.PostgreSQLBootstrap;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

if (!OperatingSystem.IsWindows())
    throw new PlatformNotSupportedException("PostgreSQL bootstrap is Windows-only.");

var builder = Host.CreateApplicationBuilder(new HostApplicationBuilderSettings
{
    ContentRootPath = AppContext.BaseDirectory
});
builder.Services.AddWindowsService(options =>
    options.ServiceName = PostgreSqlBootstrapService.ServiceName);
builder.Services.Configure<HostOptions>(options =>
    options.ShutdownTimeout = TimeSpan.FromSeconds(20));
var diagnosticsEnabled = args.Contains("--smoke-diagnostics", StringComparer.Ordinal);
builder.Services.AddSingleton(new BootstrapDiagnosticOptions(diagnosticsEnabled));
builder.Services.AddHostedService<PostgreSqlBootstrapService>();
await builder.Build().RunAsync();

