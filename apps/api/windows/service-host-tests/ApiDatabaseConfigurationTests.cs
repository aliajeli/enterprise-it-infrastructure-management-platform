using EnterpriseIT.ApiServiceHost;
using Xunit;
namespace EnterpriseIT.ApiServiceHost.Tests;
public sealed class ApiDatabaseConfigurationTests
{
 [Theory]
 [InlineData("postgresql://platform:secret@127.0.0.1:5432/platform?schema=public")]
 [InlineData("postgres://platform:secret@127.0.0.1:5432/platform")]
 public void AcceptsLoopbackDatabaseUrl(string value)=>ApiDatabaseConfiguration.ValidateDatabaseUrl(value);
 [Theory]
 [InlineData("postgresql://platform:secret@192.0.2.10:5432/platform")]
 [InlineData("postgresql://platform:secret@127.0.0.1:5433/platform")]
 [InlineData("https://platform:secret@127.0.0.1:5432/platform")]
 [InlineData("postgresql://127.0.0.1:5432/platform")]
 public void RejectsRemoteOrIncompleteDatabaseUrl(string value)=>Assert.Throws<InvalidDataException>(()=>ApiDatabaseConfiguration.ValidateDatabaseUrl(value));
}