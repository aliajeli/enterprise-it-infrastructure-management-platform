using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = Host.CreateApplicationBuilder(new HostApplicationBuilderSettings
{
    ContentRootPath = AppContext.BaseDirectory,
});

builder.Services.AddWindowsService(options =>
{
    options.ServiceName = "EnterpriseITApi";
});

builder.Services.Configure<HostOptions>(options =>
{
    options.ShutdownTimeout = TimeSpan.FromSeconds(25);
});

builder.Services.AddHostedService<NodeApiProcessService>();

await builder.Build().RunAsync();
