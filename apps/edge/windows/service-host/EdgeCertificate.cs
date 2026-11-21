using System.Security.Cryptography.X509Certificates;
namespace EnterpriseIT.EdgeServiceHost;
internal static class EdgeCertificate
{
 internal static X509Certificate2 Load(EdgeConfiguration c)
 {
  c.Validate();using var store=new X509Store(StoreName.My,StoreLocation.LocalMachine);store.Open(OpenFlags.ReadOnly|OpenFlags.OpenExistingOnly);
  var found=store.Certificates.Find(X509FindType.FindByThumbprint,c.CertificateThumbprint.Replace(" ","",StringComparison.Ordinal),false);
  if(found.Count!=1)throw new InvalidOperationException("Edge certificate was not found uniquely in LocalMachine My.");
  var x=found[0];var now=DateTime.UtcNow;
  if(!x.HasPrivateKey||now<x.NotBefore.ToUniversalTime()||now>=x.NotAfter.ToUniversalTime())throw new InvalidOperationException("Edge certificate is expired or has no private key.");
  if(!string.Equals(x.GetNameInfo(X509NameType.DnsName,false),c.TlsHostname,StringComparison.OrdinalIgnoreCase))throw new InvalidOperationException("Edge certificate DNS name mismatch.");
  var e=x.Extensions.Cast<X509Extension>().SingleOrDefault(v=>v.Oid?.Value=="2.5.29.37")??throw new InvalidOperationException("Edge certificate has no EKU.");
  var eku=new X509EnhancedKeyUsageExtension(e,e.Critical);
  if(!eku.EnhancedKeyUsages.Cast<System.Security.Cryptography.Oid>().Any(v=>v.Value=="1.3.6.1.5.5.7.3.1"))throw new InvalidOperationException("Edge certificate lacks Server Authentication EKU.");
  using var chain=new X509Chain();chain.ChainPolicy.RevocationMode=X509RevocationMode.Online;
  if(!chain.Build(x))throw new InvalidOperationException("Edge certificate chain validation failed.");
  return x;
 }
}