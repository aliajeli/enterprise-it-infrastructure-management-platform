using EnterpriseIT.WorkerServiceHost;
using Xunit;
namespace EnterpriseIT.WorkerServiceHost.Tests;
public sealed class WorkerDatabaseConfigurationTests
{
 [Theory]
 [InlineData("postgresql://platform:secret@127.0.0.1:5432/platform?schema=public")]
 [InlineData("postgres://platform:secret@127.0.0.1:5432/platform")]
 public void AcceptsLoopbackPostgreSqlUrl(string value)=>WorkerDatabaseConfiguration.ValidateDatabaseUrl(value);
 [Theory]
 [InlineData("postgresql://platform:secret@192.0.2.10:5432/platform")]
 [InlineData("postgresql://platform:secret@127.0.0.1:5433/platform")]
 [InlineData("https://platform:secret@127.0.0.1:5432/platform")]
 [InlineData("postgresql://127.0.0.1:5432/platform")]
 public void RejectsNonLoopbackOrIncompleteUrl(string value)=>Assert.Throws<InvalidDataException>(()=>WorkerDatabaseConfiguration.ValidateDatabaseUrl(value));
}