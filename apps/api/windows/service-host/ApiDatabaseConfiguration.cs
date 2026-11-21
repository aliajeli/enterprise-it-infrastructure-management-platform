using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
namespace EnterpriseIT.ApiServiceHost;
internal static class ApiDatabaseConfiguration
{
 private static readonly byte[] Magic=Encoding.ASCII.GetBytes("EITAPIDB");
 private const int MaxUrlBytes=8192;private const uint UiForbidden=1;private const uint LocalMachine=4;
 internal static void ValidateDatabaseUrl(string value)
 {
  if(string.IsNullOrWhiteSpace(value)||value.Length>MaxUrlBytes||value.Any(c=>c>0x7f)||!Uri.TryCreate(value,UriKind.Absolute,out var uri)||uri.Scheme is not ("postgresql" or "postgres")||uri.Host!="127.0.0.1"||uri.Port!=5432||string.IsNullOrWhiteSpace(uri.UserInfo)||string.IsNullOrWhiteSpace(uri.AbsolutePath)||uri.AbsolutePath=="/")
   throw new InvalidDataException("API database URL must use PostgreSQL credentials and loopback 127.0.0.1:5432.");
 }
 internal static string Load(string path,SecurityIdentifier sid)
 {
  if(!OperatingSystem.IsWindows())throw new PlatformNotSupportedException("API DPAPI configuration requires Windows.");
  var file=File.ReadAllBytes(path);byte[] entropy=[];byte[] cipher=[];byte[] plain=[];
  try{
   if(file.Length<25||file.Length>MaxUrlBytes*2||!file.AsSpan(0,8).SequenceEqual(Magic))throw new InvalidDataException("API database config envelope is invalid.");
   var id=new Guid(file.AsSpan(8,16));entropy=Entropy(sid,id);cipher=file.AsSpan(24).ToArray();plain=Dpapi.Unprotect(cipher,entropy);
   var value=new UTF8Encoding(false,true).GetString(plain);ValidateDatabaseUrl(value);return value;
  }finally{CryptographicOperations.ZeroMemory(file);CryptographicOperations.ZeroMemory(entropy);CryptographicOperations.ZeroMemory(cipher);CryptographicOperations.ZeroMemory(plain);}
 }
 internal static void ProvisionFromStandardInput(string path)
 {
  if(!OperatingSystem.IsWindows())throw new PlatformNotSupportedException("API DPAPI configuration requires Windows.");
  using var reader=new StreamReader(Console.OpenStandardInput(),new UTF8Encoding(false,true),false,1024,false);
  var value=reader.ReadToEnd();ValidateDatabaseUrl(value);
  var sid=new NTAccount("NT SERVICE","EnterpriseITApi").Translate(typeof(SecurityIdentifier)) as SecurityIdentifier??throw new UnauthorizedAccessException("API service SID could not be resolved.");
  var id=Guid.NewGuid();var entropy=Entropy(sid,id);var plain=Encoding.UTF8.GetBytes(value);byte[] cipher=[];
  try{
   cipher=Dpapi.Protect(plain,entropy);var envelope=new byte[24+cipher.Length];Magic.CopyTo(envelope,0);id.TryWriteBytes(envelope.AsSpan(8,16));cipher.CopyTo(envelope,24);
   var directory=Path.GetDirectoryName(Path.GetFullPath(path))??throw new InvalidOperationException("API config directory is invalid.");
   Directory.CreateDirectory(directory);var temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";
   try{File.WriteAllBytes(temp,envelope);File.Move(temp,path,true);}finally{if(File.Exists(temp))File.Delete(temp);CryptographicOperations.ZeroMemory(envelope);}
   Console.Out.WriteLine("OK");
  }finally{CryptographicOperations.ZeroMemory(entropy);CryptographicOperations.ZeroMemory(plain);CryptographicOperations.ZeroMemory(cipher);}
 }
 private static byte[] Entropy(SecurityIdentifier sid,Guid id)=>SHA256.HashData(Encoding.UTF8.GetBytes("EnterpriseIT.Api.Database.v1|"+sid.Value+"|"+id.ToString("D")));
 private static class Dpapi
 {
  [StructLayout(LayoutKind.Sequential)]private struct Blob{public int Length;public IntPtr Data;}
  [DllImport("crypt32.dll",SetLastError=true,CharSet=CharSet.Unicode)][return:MarshalAs(UnmanagedType.Bool)]
  private static extern bool CryptProtectData(ref Blob input,string description,ref Blob entropy,IntPtr reserved,IntPtr prompt,uint flags,out Blob output);
  [DllImport("crypt32.dll",SetLastError=true)][return:MarshalAs(UnmanagedType.Bool)]
  private static extern bool CryptUnprotectData(ref Blob input,IntPtr description,ref Blob entropy,IntPtr reserved,IntPtr prompt,uint flags,out Blob output);
  [DllImport("kernel32.dll",SetLastError=true)]private static extern IntPtr LocalFree(IntPtr memory);
  internal static byte[] Protect(byte[] value,byte[] entropy)=>Transform(value,entropy,true);
  internal static byte[] Unprotect(byte[] value,byte[] entropy)=>Transform(value,entropy,false);
  private static byte[] Transform(byte[] value,byte[] entropy,bool protect)
  {
   var vp=Marshal.AllocHGlobal(value.Length);var ep=Marshal.AllocHGlobal(entropy.Length);Blob output=default;
   try{
    Marshal.Copy(value,0,vp,value.Length);Marshal.Copy(entropy,0,ep,entropy.Length);
    var input=new Blob{Length=value.Length,Data=vp};var optional=new Blob{Length=entropy.Length,Data=ep};
    var ok=protect?CryptProtectData(ref input,"Enterprise IT API database configuration",ref optional,IntPtr.Zero,IntPtr.Zero,UiForbidden|LocalMachine,out output):CryptUnprotectData(ref input,IntPtr.Zero,ref optional,IntPtr.Zero,IntPtr.Zero,UiForbidden,out output);
    if(!ok||output.Data==IntPtr.Zero||output.Length<1||output.Length>MaxUrlBytes*2)throw new CryptographicException("API DPAPI operation failed.");
    var result=new byte[output.Length];Marshal.Copy(output.Data,result,0,output.Length);return result;
   }finally{
    Zero(vp,value.Length);Marshal.FreeHGlobal(vp);Zero(ep,entropy.Length);Marshal.FreeHGlobal(ep);
    if(output.Data!=IntPtr.Zero){Zero(output.Data,output.Length);_ = LocalFree(output.Data);}
   }
  }
  private static void Zero(IntPtr p,int n){if(p==IntPtr.Zero||n<=0)return;var zeros=new byte[n];Marshal.Copy(zeros,0,p,n);CryptographicOperations.ZeroMemory(zeros);}
 }
}