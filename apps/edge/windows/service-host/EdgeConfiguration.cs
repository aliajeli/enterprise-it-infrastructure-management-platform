using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;
namespace EnterpriseIT.EdgeServiceHost;
internal sealed record EdgeConfiguration(string BindAddress,int Port,string TlsHostname,string CertificateThumbprint)
{
 internal static EdgeConfiguration Load(string path)
 {
  if(!File.Exists(path))throw new FileNotFoundException("Protected Edge configuration is missing.",path);
  var value=JsonSerializer.Deserialize<EdgeConfiguration>(File.ReadAllText(path),new JsonSerializerOptions{PropertyNameCaseInsensitive=true})??throw new InvalidDataException("Edge configuration is empty.");
  value.Validate();return value;
 }
 internal void Validate()
 {
  if(!IPAddress.TryParse(BindAddress,out var ip)||IPAddress.IsLoopback(ip)||ip.Equals(IPAddress.Any)||ip.Equals(IPAddress.IPv6Any))throw new InvalidDataException("Edge must bind to a specific non-loopback interface address.");
  if(Port is <1 or >65535)throw new InvalidDataException("Edge HTTPS port is invalid.");
  if(string.IsNullOrWhiteSpace(TlsHostname)||TlsHostname.Length>253||!Regex.IsMatch(TlsHostname,@"^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$"))throw new InvalidDataException("Edge TLS hostname is invalid.");
  var thumb=CertificateThumbprint.Replace(" ","",StringComparison.Ordinal).ToUpperInvariant();
  if(thumb.Length is not (40 or 64)||!Regex.IsMatch(thumb,"^[A-F0-9]+$"))throw new InvalidDataException("Edge certificate thumbprint is invalid.");
 }
}