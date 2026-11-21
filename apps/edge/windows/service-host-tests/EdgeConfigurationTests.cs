using EnterpriseIT.EdgeServiceHost;
using Xunit;
namespace EnterpriseIT.EdgeServiceHost.Tests;
public sealed class EdgeConfigurationTests
{
 [Fact]public void AcceptsSpecificLanAddress()=>new EdgeConfiguration("192.0.2.10",443,"it.example.internal",new string('A',40)).Validate();
 [Theory][InlineData("127.0.0.1")][InlineData("0.0.0.0")][InlineData("::")][InlineData("bad")]
 public void RejectsUnsafeBind(string ip)=>Assert.Throws<InvalidDataException>(()=>new EdgeConfiguration(ip,443,"it.example.internal",new string('A',40)).Validate());
 [Theory][InlineData(0)][InlineData(65536)]
 public void RejectsBadPort(int port)=>Assert.Throws<InvalidDataException>(()=>new EdgeConfiguration("192.0.2.10",port,"it.example.internal",new string('A',40)).Validate());
 [Theory][InlineData("https://host")][InlineData("*.example.internal")][InlineData("bad host")]
 public void RejectsBadHostname(string host)=>Assert.Throws<InvalidDataException>(()=>new EdgeConfiguration("192.0.2.10",443,host,new string('A',40)).Validate());
 [Fact]public void RejectsBadThumbprint()=>Assert.Throws<InvalidDataException>(()=>new EdgeConfiguration("192.0.2.10",443,"it.example.internal","bad").Validate());
}