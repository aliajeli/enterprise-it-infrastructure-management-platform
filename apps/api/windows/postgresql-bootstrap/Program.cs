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
builder.Services.AddHostedService<PostgreSqlBootstrapService>();
await builder.Build().RunAsync();
