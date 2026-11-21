using EnterpriseIT.ApiServiceHost;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
if(args.Length>0)
{
 if(args.Length==3&&args[0]=="--provision-database-config"&&args[2]=="EnterpriseITApi"){ApiDatabaseConfiguration.ProvisionFromStandardInput(args[1]);return;}
 throw new ArgumentException("Unsupported API service-host command.");
}
var builder = Host.CreateApplicationBuilder(new HostApplicationBuilderSettings { ContentRootPath = AppContext.BaseDirectory });
builder.Services.AddWindowsService(options => options.ServiceName = "EnterpriseITApi");
builder.Services.Configure<HostOptions>(options => options.ShutdownTimeout = TimeSpan.FromSeconds(25));
builder.Services.AddHostedService<NodeApiProcessService>();
await builder.Build().RunAsync();
