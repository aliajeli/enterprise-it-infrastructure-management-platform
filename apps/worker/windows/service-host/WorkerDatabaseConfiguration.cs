using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
namespace EnterpriseIT.WorkerServiceHost;
internal static class WorkerDatabaseConfiguration
{
 private static readonly byte[] Magic=Encoding.ASCII.GetBytes("EITWDB01");
 private const int MaxDatabaseUrlBytes=8192;
 private const uint CryptProtectUiForbidden=0x1;
 private const uint CryptProtectLocalMachine=0x4;
 internal static void ValidateDatabaseUrl(string value)
 {
  if(string.IsNullOrWhiteSpace(value)||value.Length>MaxDatabaseUrlBytes||value.Any(c=>c>0x7f)||!Uri.TryCreate(value,UriKind.Absolute,out var uri)||uri.Scheme is not ("postgresql" or "postgres")||uri.Host!="127.0.0.1"||uri.Port!=5432||string.IsNullOrWhiteSpace(uri.UserInfo)||string.IsNullOrWhiteSpace(uri.AbsolutePath)||uri.AbsolutePath=="/")
   throw new InvalidDataException("Worker database URL must use PostgreSQL credentials and loopback 127.0.0.1:5432.");
 }
 internal static string Load(string path,SecurityIdentifier serviceSid)
 {
  if(!OperatingSystem.IsWindows())throw new PlatformNotSupportedException("DPAPI worker configuration requires Windows.");
  var file=File.ReadAllBytes(path);byte[] entropy=[];byte[] encrypted=[];byte[] plain=[];
  try{
   if(file.Length<25||file.Length>MaxDatabaseUrlBytes*2||!file.AsSpan(0,8).SequenceEqual(Magic))throw new InvalidDataException("Worker database configuration envelope is invalid.");
   var id=new Guid(file.AsSpan(8,16));entropy=CreateEntropy(serviceSid,id);encrypted=file.AsSpan(24).ToArray();plain=Dpapi.Unprotect(encrypted,entropy);
   var value=new UTF8Encoding(false,true).GetString(plain);ValidateDatabaseUrl(value);return value;
  }finally{CryptographicOperations.ZeroMemory(file);CryptographicOperations.ZeroMemory(entropy);CryptographicOperations.ZeroMemory(encrypted);CryptographicOperations.ZeroMemory(plain);}
 }
 internal static void ProvisionFromStandardInput(string path)
 {
  if(!OperatingSystem.IsWindows())throw new PlatformNotSupportedException("DPAPI worker configuration requires Windows.");
  using var reader=new StreamReader(Console.OpenStandardInput(),new UTF8Encoding(false,true),false,1024,false);
  var value=reader.ReadToEnd();ValidateDatabaseUrl(value);
  var sid=new NTAccount("NT SERVICE","EnterpriseITWorker").Translate(typeof(SecurityIdentifier)) as SecurityIdentifier??throw new UnauthorizedAccessException("Worker service SID could not be resolved.");
  var id=Guid.NewGuid();var entropy=CreateEntropy(sid,id);var plain=Encoding.UTF8.GetBytes(value);byte[] encrypted=[];
  try{
   encrypted=Dpapi.Protect(plain,entropy);var envelope=new byte[24+encrypted.Length];Magic.CopyTo(envelope,0);id.TryWriteBytes(envelope.AsSpan(8,16));encrypted.CopyTo(envelope,24);
   var directory=Path.GetDirectoryName(Path.GetFullPath(path))??throw new InvalidOperationException("Worker config directory is invalid.");
   Directory.CreateDirectory(directory);var temp=path+"."+Guid.NewGuid().ToString("N")+".tmp";
   try{File.WriteAllBytes(temp,envelope);File.Move(temp,path,true);}finally{if(File.Exists(temp))File.Delete(temp);CryptographicOperations.ZeroMemory(envelope);}
   Console.Out.WriteLine("OK");
  }finally{CryptographicOperations.ZeroMemory(entropy);CryptographicOperations.ZeroMemory(plain);CryptographicOperations.ZeroMemory(encrypted);}
 }
 private static byte[] CreateEntropy(SecurityIdentifier sid,Guid id)=>SHA256.HashData(Encoding.UTF8.GetBytes("EnterpriseIT.Worker.Database.v1|"+sid.Value+"|"+id.ToString("D")));
 private static class Dpapi
 {
  [StructLayout(LayoutKind.Sequential)]private struct DataBlob{public int Length;public IntPtr Data;}
  [DllImport("crypt32.dll",SetLastError=true,CharSet=CharSet.Unicode)][return:MarshalAs(UnmanagedType.Bool)]
  private static extern bool CryptProtectData(ref DataBlob input,string description,ref DataBlob entropy,IntPtr reserved,IntPtr prompt,uint flags,out DataBlob output);
  [DllImport("crypt32.dll",SetLastError=true)][return:MarshalAs(UnmanagedType.Bool)]
  private static extern bool CryptUnprotectData(ref DataBlob input,IntPtr description,ref DataBlob entropy,IntPtr reserved,IntPtr prompt,uint flags,out DataBlob output);
  [DllImport("kernel32.dll",SetLastError=true)]private static extern IntPtr LocalFree(IntPtr memory);
  internal static byte[] Protect(byte[] source,byte[] entropy)=>Transform(source,entropy,true);
  internal static byte[] Unprotect(byte[] source,byte[] entropy)=>Transform(source,entropy,false);
  private static byte[] Transform(byte[] source,byte[] entropy,bool protect)
  {
   var sourcePtr=Marshal.AllocHGlobal(source.Length);var entropyPtr=Marshal.AllocHGlobal(entropy.Length);DataBlob output=default;
   try{
    Marshal.Copy(source,0,sourcePtr,source.Length);Marshal.Copy(entropy,0,entropyPtr,entropy.Length);
    var input=new DataBlob{Length=source.Length,Data=sourcePtr};var optional=new DataBlob{Length=entropy.Length,Data=entropyPtr};
    var ok=protect?CryptProtectData(ref input,"Enterprise IT Worker database configuration",ref optional,IntPtr.Zero,IntPtr.Zero,CryptProtectUiForbidden|CryptProtectLocalMachine,out output):CryptUnprotectData(ref input,IntPtr.Zero,ref optional,IntPtr.Zero,IntPtr.Zero,CryptProtectUiForbidden,out output);
    if(!ok||output.Data==IntPtr.Zero||output.Length<1||output.Length>MaxDatabaseUrlBytes*2)throw new CryptographicException("Worker DPAPI operation failed.");
    var result=new byte[output.Length];Marshal.Copy(output.Data,result,0,output.Length);return result;
   }finally{
    Zero(sourcePtr,source.Length);Marshal.FreeHGlobal(sourcePtr);Zero(entropyPtr,entropy.Length);Marshal.FreeHGlobal(entropyPtr);
    if(output.Data!=IntPtr.Zero){Zero(output.Data,output.Length);_ = LocalFree(output.Data);}
   }
  }
  private static void Zero(IntPtr p,int n){if(p==IntPtr.Zero||n<=0)return;var zeros=new byte[n];Marshal.Copy(zeros,0,p,n);CryptographicOperations.ZeroMemory(zeros);}
 }
}