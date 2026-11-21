using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace EnterpriseIT.EdgeServiceHost;

internal sealed record EdgeConfiguration(string BindAddress, int Port, string TlsHostname, string CertificateThumbprint)
{
    internal static EdgeConfiguration Load(string path)
    {
        if (!File.Exists(path)) throw new FileNotFoundException("Protected Edge configuration is missing.", path);
        var json = File.ReadAllText(path);
        var value = JsonSerializer.Deserialize<EdgeConfiguration>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
            ?? throw new InvalidDataException("Edge configuration is empty.");
        value.Validate();
        return value;
    }

    internal void Validate()
    {
        if (!IPAddress.TryParse(BindAddress, out var address) ||
            IPAddress.IsLoopback(address) ||
            address.Equals(IPAddress.Any) ||
            address.Equals(IPAddress.IPv6Any))
            throw new InvalidDataException("Edge BindAddress must be a specific non-loopback LAN interface address.");
        if (Port is < 1 or > 65535) throw new InvalidDataException("Edge HTTPS port is outside the valid TCP port range.");
        if (string.IsNullOrWhiteSpace(TlsHostname) || TlsHostname.Length > 253 ||
            !Regex.IsMatch(TlsHostname, @"^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)(?:\.(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?))*$", RegexOptions.CultureInvariant))
            throw new InvalidDataException("Edge TLS hostname must be a valid DNS hostname.");
        var thumbprint = CertificateThumbprint.Replace(" ", string.Empty, StringComparison.Ordinal).ToUpperInvariant();
        if (thumbprint.Length is not (40 or 64) || !Regex.IsMatch(thumbprint, "^[A-F0-9]+$", RegexOptions.CultureInvariant))
            throw new InvalidDataException("Edge certificate thumbprint must be a SHA-1 or SHA-256 hexadecimal thumbprint.");
    }
}
