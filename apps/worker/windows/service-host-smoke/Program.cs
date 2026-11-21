using System.Net;
using System.Net.Sockets;
using System.Text;
var entry=Environment.GetCommandLineArgs().Skip(1).FirstOrDefault(x=>x.EndsWith("main.js",StringComparison.OrdinalIgnoreCase));
if(string.IsNullOrWhiteSpace(entry))throw new InvalidOperationException("Worker smoke entry point was not supplied.");
var failReady=File.ReadAllText(entry).Contains("NO_READY",StringComparison.Ordinal);
var listener=new TcpListener(IPAddress.Loopback,13002);
listener.Start();
var stopping=0;
var accept=Task.Run(async()=>{
 while(Volatile.Read(ref stopping)==0){
  TcpClient client;
  try{client=await listener.AcceptTcpClientAsync();}
  catch(SocketException)when(Volatile.Read(ref stopping)!=0){break;}
  catch(ObjectDisposedException){break;}
  _=Task.Run(()=>Handle(client,failReady));
 }
});
var command=Console.ReadLine();
if(string.Equals(command?.Trim(),"SHUTDOWN",StringComparison.Ordinal)){
 Interlocked.Exchange(ref stopping,1);listener.Stop();
 try{await accept;}catch{}
}
static async Task Handle(TcpClient client,bool failReady){
 using(client){
  try{
   using var stream=client.GetStream();using var reader=new StreamReader(stream,Encoding.ASCII,false,1024,true);
   var line=await reader.ReadLineAsync();while(!string.IsNullOrEmpty(await reader.ReadLineAsync())){}
   var failed=failReady&&line?.Contains("/health/ready",StringComparison.OrdinalIgnoreCase)==true;
   var status=failed?503:200;var body=failed?"NOT_READY":"OK";
   var response=Encoding.ASCII.GetBytes($"HTTP/1.1 {status} {(failed?"Service Unavailable":"OK")}\r\nContent-Type: text/plain\r\nContent-Length: {body.Length}\r\nConnection: close\r\n\r\n{body}");
   await stream.WriteAsync(response);
  }catch(IOException){}catch(ObjectDisposedException){}
 }
}