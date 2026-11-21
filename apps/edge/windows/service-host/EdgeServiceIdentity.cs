using System.Security.Principal;
namespace EnterpriseIT.EdgeServiceHost;
internal static class EdgeServiceIdentity
{
 internal static void RequireEnabledServiceSid()
 {
  if(!OperatingSystem.IsWindows())throw new PlatformNotSupportedException();
  var sid=new NTAccount("NT SERVICE","EnterpriseITEdge").Translate(typeof(SecurityIdentifier)) as SecurityIdentifier??throw new UnauthorizedAccessException("Edge service SID could not be resolved.");
  using var identity=WindowsIdentity.GetCurrent();
  if(!sid.Equals(identity.User)&&!new WindowsPrincipal(identity).IsInRole(sid))throw new UnauthorizedAccessException("Edge service SID is not enabled in this process token.");
 }
}