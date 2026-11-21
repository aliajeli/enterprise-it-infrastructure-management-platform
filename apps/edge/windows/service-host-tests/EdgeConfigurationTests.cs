using EnterpriseIT.EdgeServiceHost;

namespace EnterpriseIT.EdgeServiceHost.Tests;

public sealed class EdgeConfigurationTests
{
    [Fact]
    public void AcceptsSpecificLanAddressAndServerCertificateIdentity()
    {
        var value = new EdgeConfiguration("192.0.2.10", 443, "it.example.internal", new string('A', 40));
        value.Validate();
    }

    [Theory]
    [InlineData("127.0.0.1")]
    [InlineData("0.0.0.0")]
    [InlineData("::")]
    [InlineData("not-an-ip")]
    public void RejectsLoopbackWildcardAndInvalidBindAddresses(string address)
    {
        var value = new EdgeConfiguration(address, 443, "it.example.internal", new string('A', 40));
        Assert.Throws<InvalidDataException>(value.Validate);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(65536)]
    public void RejectsInvalidHttpsPorts(int port)
    {
        var value = new EdgeConfiguration("192.0.2.10", port, "it.example.internal", new string('A', 40));
        Assert.Throws<InvalidDataException>(value.Validate);
    }

    [Theory]
    [InlineData("https://bad.example")]
    [InlineData("*.example.internal")]
    [InlineData("bad host")]
    public void RejectsNonDnsTlsHostnames(string hostname)
    {
        var value = new EdgeConfiguration("192.0.2.10", 443, hostname, new string('A', 40));
        Assert.Throws<InvalidDataException>(value.Validate);
    }

    [Fact]
    public void RejectsMalformedCertificateThumbprints()
    {
        var value = new EdgeConfiguration("192.0.2.10", 443, "it.example.internal", "not-a-thumbprint");
        Assert.Throws<InvalidDataException>(value.Validate);
    }
}
