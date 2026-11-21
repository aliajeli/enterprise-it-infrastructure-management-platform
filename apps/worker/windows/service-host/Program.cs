using EnterpriseIT.WorkerServiceHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
var builder = Host.CreateApplicationBuilder(new HostApplicationBuilderSettings { ContentRootPath = AppContext.BaseDirectory });
builder.Services.AddWindowsService(options => options.ServiceName = "EnterpriseITWorker");
builder.Services.Configure<HostOptions>(options => options.ShutdownTimeout = TimeSpan.FromSeconds(25));
builder.Services.AddHostedService<NodeWorkerProcessService>();
await builder.Build().RunAsync();
