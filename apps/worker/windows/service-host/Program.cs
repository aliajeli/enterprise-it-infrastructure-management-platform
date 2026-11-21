using EnterpriseIT.WorkerServiceHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
if(args.Length>0)
{
 if(args.Length==2&&args[0]=="--provision-database-config"){WorkerDatabaseConfiguration.ProvisionFromStandardInput(args[1]);return;}
 throw new ArgumentException("Unsupported Worker service-host command.");
}
var builder=Host.CreateApplicationBuilder(new HostApplicationBuilderSettings { ContentRootPath = AppContext.BaseDirectory });
builder.Services.AddWindowsService(options => options.ServiceName = "EnterpriseITWorker");
builder.Services.Configure<HostOptions>(options => options.ShutdownTimeout = TimeSpan.FromSeconds(25));
builder.Services.AddHostedService<NodeWorkerProcessService>();
await builder.Build().RunAsync();
