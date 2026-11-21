using System.Security.Cryptography.X509Certificates;

namespace EnterpriseIT.EdgeServiceHost;

internal static class EdgeCertificate
{
    private const string ServerAuthenticationOid = "1.3.6.1.5.5.7.3.1";

    internal static X509Certificate2 Load(EdgeConfiguration configuration)
    {
        configuration.Validate();
        using var store = new X509Store(StoreName.My, StoreLocation.LocalMachine);
        store.Open(OpenFlags.ReadOnly | OpenFlags.OpenExistingOnly);
        var thumbprint = configuration.CertificateThumbprint.Replace(" ", string.Empty, StringComparison.Ordinal);
        var matches = store.Certificates.Find(X509FindType.FindByThumbprint, thumbprint, validOnly: false);
        if (matches.Count != 1) throw new InvalidOperationException("The configured Edge certificate was not found uniquely in LocalMachine\My.");
        var certificate = matches[0];
        var now = DateTime.UtcNow;
        if (!certificate.HasPrivateKey || now < certificate.NotBefore.ToUniversalTime() || now >= certificate.NotAfter.ToUniversalTime())
            throw new InvalidOperationException("The Edge certificate must have an accessible private key and be currently valid.");
        var dnsName = certificate.GetNameInfo(X509NameType.DnsName, forIssuer: false);
        if (!string.Equals(dnsName, configuration.TlsHostname, StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("The Edge certificate DNS name does not exactly match the configured TLS hostname.");
        var eku = certificate.Extensions.OfType<X509EnhancedKeyUsageExtension>().SingleOrDefault();
        if (eku is null || !eku.EnhancedKeyUsages.Cast<System.Security.Cryptography.Oid>().Any(oid => oid.Value == ServerAuthenticationOid))
            throw new InvalidOperationException("The Edge certificate does not permit TLS server authentication.");
        using var chain = new X509Chain();
        chain.ChainPolicy.RevocationMode = X509RevocationMode.Online;
        chain.ChainPolicy.RevocationFlag = X509RevocationFlag.ExcludeRoot;
        if (!chain.Build(certificate))
            throw new InvalidOperationException("The Edge certificate chain is not trusted or could not be validated.");
        return certificate;
    }
}
