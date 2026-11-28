using EnterpriseIT.PostgreSQLBootstrap;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

if (!OperatingSystem.IsWindows())
    throw new PlatformNotSupportedException("PostgreSQL bootstrap is Windows-only.");

// Single-purpose elevated provisioning/verify mode for the fixed data
// directory chain. It runs before any host is built and never starts the
// service loop, so provisioning cannot be triggered by a service start.
if (PostgreSqlDataDirectoryProvisioner.IsProvisioningMode(args))
    return PostgreSqlDataDirectoryProvisioner.Execute(args);

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
return 0;

