using System.Net;
using System.Security.Authentication;
using EnterpriseIT.EdgeServiceHost;
using Yarp.ReverseProxy.Configuration;
EdgeServiceIdentity.RequireEnabledServiceSid();
var path=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),"EnterpriseIT","Edge","edge.json");
var edge=EdgeConfiguration.Load(path);var certificate=EdgeCertificate.Load(edge);
var builder=WebApplication.CreateBuilder(new WebApplicationOptions{ContentRootPath=AppContext.BaseDirectory});
builder.Services.AddWindowsService(o=>o.ServiceName="EnterpriseITEdge");
builder.Services.Configure<HostOptions>(o=>o.ShutdownTimeout=TimeSpan.FromSeconds(20));
builder.WebHost.ConfigureKestrel(o=>{
 o.Limits.MaxRequestBodySize=50*1024*1024;o.Limits.RequestHeadersTimeout=TimeSpan.FromSeconds(15);o.Limits.KeepAliveTimeout=TimeSpan.FromMinutes(2);
 o.Listen(IPAddress.Parse(edge.BindAddress),edge.Port,l=>l.UseHttps(certificate,h=>h.SslProtocols=SslProtocols.Tls12|SslProtocols.Tls13));
});
var transforms=new[]{new Dictionary<string,string>{{"X-Forwarded","Set"}},new Dictionary<string,string>{{"Forwarded","Off"}}};
var routes=new[]{
 new RouteConfig{RouteId="api",ClusterId="api",Order=0,Match=new RouteMatch{Path="/api/{**catch-all}"},Transforms=transforms},
 new RouteConfig{RouteId="web",ClusterId="web",Order=1,Match=new RouteMatch{Path="/{**catch-all}"},Transforms=transforms}};
var clusters=new[]{
 new ClusterConfig{ClusterId="api",Destinations=new Dictionary<string,DestinationConfig>{{"api-loopback",new(){Address="http://127.0.0.1:13001/"}}}},
 new ClusterConfig{ClusterId="web",Destinations=new Dictionary<string,DestinationConfig>{{"web-loopback",new(){Address="http://127.0.0.1:13000/"}}}}};
builder.Services.AddReverseProxy().LoadFromMemory(routes,clusters);
builder.Services.AddHttpClient("edge-ready",c=>c.Timeout=TimeSpan.FromSeconds(2));
var app=builder.Build();
app.Use(async(ctx,next)=>{
 if(!string.Equals(ctx.Request.Path.Value,"/health/ready",StringComparison.OrdinalIgnoreCase)&&!string.Equals(ctx.Request.Host.Host,edge.TlsHostname,StringComparison.OrdinalIgnoreCase)){ctx.Response.StatusCode=421;return;}
 ctx.Response.Headers["Strict-Transport-Security"]="max-age=31536000";await next();
});
app.MapGet("/health/ready",async(IHttpClientFactory f,CancellationToken ct)=>{
 var c=f.CreateClient("edge-ready");var api=await Ready(c,"http://127.0.0.1:13001/health/ready",ct);var web=await Ready(c,"http://127.0.0.1:13000/health/ready",ct);
 var tls=DateTime.UtcNow>=certificate.NotBefore.ToUniversalTime()&&DateTime.UtcNow<certificate.NotAfter.ToUniversalTime()&&certificate.HasPrivateKey;
 return api&&web&&tls?Results.Ok(new{status="ready"}):Results.Problem(statusCode:503,title: "Edge dependency readiness failed");
});
app.MapReverseProxy();await app.RunAsync();
static async Task<bool> Ready(HttpClient c,string u,CancellationToken t){try{using var r=await c.GetAsync(u,HttpCompletionOption.ResponseHeadersRead,t);return r.StatusCode==HttpStatusCode.OK;}catch(HttpRequestException){return false;}catch(TaskCanceledException)when(!t.IsCancellationRequested){return false;}}