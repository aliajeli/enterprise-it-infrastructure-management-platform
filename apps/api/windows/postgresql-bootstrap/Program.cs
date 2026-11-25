using EnterpriseIT.PostgreSQLBootstrap;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

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
builder.Logging.AddEventLog(settings => settings.SourceName = "Application");
builder.Logging.SetMinimumLevel(LogLevel.Information);
builder.Services.AddHostedService<PostgreSqlBootstrapService>();
var host = builder.Build();
var lifecycleLogger = host.Services.GetRequiredService<ILoggerFactory>()
    .CreateLogger("EnterpriseIT.PostgreSQLBootstrap.Lifecycle");
lifecycleLogger.LogWarning("Bootstrap host is starting.");
await host.RunAsync();
lifecycleLogger.LogWarning("Bootstrap host stopped normally.");

