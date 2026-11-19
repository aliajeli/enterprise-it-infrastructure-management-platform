using System.Buffers.Binary;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Security.AccessControl;
using System.Text;
using System.Text.Json;
using Microsoft.Win32.SafeHandles;

internal static class Program
{
    private const byte V=1, Begin=1, Read=2, Write=3, End=4, BeginOk=0x81, ReadResult=0x82, WriteOk=0x83, EndOk=0x84, Error=0xff;
    private const int Header=6, Max=32768;
    private const uint ReadControl=0x20000, FileReadAttributes=0x80, GenericRead=0x80000000, GenericWrite=0x40000000;
    private const uint OpenExisting=3, CreateNew=1, FileNormal=0x80, Reparse=0x400, WriteThrough=0x80000000, OpenReparse=0x200000, BackupSemantics=0x2000000;
    private const uint ShareRead=1, ShareWrite=2, ShareDelete=4, ReplaceExisting=1, MoveWriteThrough=8;
    private const uint FileObject=1, OwnerInfo=1, DaclInfo=4, FullControl=0x001F01FF;
    private static readonly Encoding Utf8=new UTF8Encoding(false,true);
    private static readonly string Root=Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.CommonApplicationData),"EnterpriseIT","CredentialVault");
    private static readonly string Registry=Path.Combine(Root,"keyring.v1.json"), Lock=Path.Combine(Root,"keyring.lock");
    private static FileStream? heldLock;
    private static SecurityIdentifier? serviceSid;

    private static async Task<int> Main()
    {
        if(!OperatingSystem.IsWindows()) return 1;
        try
        {
            using var input=Console.OpenStandardInput();
            using var output=Console.OpenStandardOutput();
            while(true)
            {
                var frame=await ReadFrame(input);
                if(frame is null) return heldLock is null ? 0 : 1;
                var op=frame[1];
                var payload=frame.AsSpan(Header).ToArray();
                try
                {
                    if(op==Begin && payload.Length==0)
                    {
                        if(heldLock is not null) throw new InvalidDataException();
                        await BeginTransaction();
                        await Send(output,BeginOk,[]);
                    }
                    else if(op==Read && payload.Length==0)
                    {
                        RequireLock();
                        var text=ReadRegistry();
                        if(text is null) await Send(output,ReadResult,[1]);
                        else
                        {
                            var data=Utf8.GetBytes(text);
                            var result=new byte[data.Length+1]; result[0]=0; data.CopyTo(result,1);
                            await Send(output,ReadResult,result);
                            CryptographicOperations.ZeroMemory(data); CryptographicOperations.ZeroMemory(result);
                        }
                    }
                    else if(op==Write)
                    {
                        RequireLock();
                        var json=Utf8.GetString(payload);
                        using var doc=JsonDocument.Parse(json,new JsonDocumentOptions{MaxDepth=16});
                        if(doc.RootElement.ValueKind!=JsonValueKind.Object) throw new InvalidDataException();
                        WriteRegistry(payload);
                        await Send(output,WriteOk,[]);
                    }
                    else if(op==End && payload.Length==0)
                    {
                        RequireLock();
                        heldLock.Dispose(); heldLock=null;
                        await Send(output,EndOk,[]);
                        return 0;
                    }
                    else throw new InvalidDataException();
                }
                catch
                {
                    await Send(output,Error,[1]);
                    return 1;
                }
                finally { CryptographicOperations.ZeroMemory(payload); CryptographicOperations.ZeroMemory(frame); }
            }
        }
        catch { return 1; }
        finally { heldLock?.Dispose(); heldLock=null; }
    }

    private static void RequireLock(){if(heldLock is null || serviceSid is null) throw new InvalidOperationException();}

    private static async Task BeginTransaction()
    {
        serviceSid=GetServiceSid();
        VerifyDirectory();
        var timer=Stopwatch.StartNew();
        while(true)
        {
            try
            {
                var h=Open(Lock,GenericRead|GenericWrite|ReadControl,0,OpenExisting,OpenReparse);
                try
                {
                    VerifyAcl(h,serviceSid); VerifyNotReparse(h);
                    heldLock=new FileStream(h,FileAccess.ReadWrite);
                    return;
                }
                catch {h.Dispose(); throw;}
            }
            catch(IOException) when(timer.Elapsed<TimeSpan.FromSeconds(10)){await Task.Delay(50);}
        }
    }

    private static string? ReadRegistry()
    {
        var h=CreateFile(Registry,GenericRead|ReadControl,ShareRead,IntPtr.Zero,OpenExisting,OpenReparse,IntPtr.Zero);
        if(h.IsInvalid) { var error=Marshal.GetLastWin32Error(); h.Dispose(); if(error==2) return null; throw new IOException(); }
        using(h)
        {
            VerifyAcl(h,serviceSid!); VerifyNotReparse(h);
            using var s=new FileStream(h,FileAccess.Read);
            if(s.Length is <1 or >Max) throw new InvalidDataException();
            var b=new byte[(int)s.Length]; s.ReadExactly(b);
            try{return Utf8.GetString(b);}finally{CryptographicOperations.ZeroMemory(b);}
        }
    }

    private static void WriteRegistry(byte[] data)
    {
        if(data.Length is <1 or >Max) throw new InvalidDataException();
        var existing=CreateFile(Registry,GenericRead|ReadControl,ShareRead,IntPtr.Zero,OpenExisting,OpenReparse,IntPtr.Zero);
        if(!existing.IsInvalid) { using(existing) { VerifyAcl(existing,serviceSid!); VerifyNotReparse(existing); } }
        else { var error=Marshal.GetLastWin32Error(); existing.Dispose(); if(error!=2) throw new IOException(); }
        var temp=Path.Combine(Root,".keyring-"+Guid.NewGuid().ToString("N")+".tmp");
        var sddl=$"O:{serviceSid!.Value}D:P(A;;FA;;;{serviceSid.Value})(A;;FA;;;SY)";
        IntPtr sd=IntPtr.Zero;
        try
        {
            if(!ConvertSddl(sddl,1,out sd,out _)) throw new IOException();
            var sa=new SecurityAttributes{Length=Marshal.SizeOf<SecurityAttributes>(),SecurityDescriptor=sd,InheritHandle=false};
            using(var h=CreateFileWithSecurity(temp,GenericRead|GenericWrite|ReadControl,0,ref sa,CreateNew,FileNormal|WriteThrough,IntPtr.Zero))
            {
                if(h.IsInvalid) throw new IOException();
                VerifyAcl(h,serviceSid); VerifyNotReparse(h);
                using var s=new FileStream(h,FileAccess.Write); s.Write(data); s.Flush(true);
            }
            VerifyDirectory();
            if(!MoveFileEx(temp,Registry,ReplaceExisting|MoveWriteThrough)) throw new IOException();
            using var committed=Open(Registry,GenericRead|ReadControl,ShareRead,OpenExisting,OpenReparse);
            VerifyAcl(committed,serviceSid); VerifyNotReparse(committed);
            using var verify=new FileStream(committed,FileAccess.Read);
            if(verify.Length!=data.Length) throw new IOException();
            var check=new byte[data.Length]; verify.ReadExactly(check);
            try{if(!CryptographicOperations.FixedTimeEquals(check,data)) throw new IOException();}
            finally{CryptographicOperations.ZeroMemory(check);}
        }
        finally
        {
            if(sd!=IntPtr.Zero) _=LocalFree(sd);
            try
            {
                if(File.Exists(temp))
                {
                    using var orphan=Open(temp,ReadControl|FileReadAttributes,ShareRead|ShareWrite|ShareDelete,OpenExisting,OpenReparse);
                    VerifyAcl(orphan,serviceSid!); VerifyNotReparse(orphan); File.Delete(temp);
                }
            }catch{}
        }
    }

    private static void VerifyDirectory()
    {
        if(!Directory.Exists(Root)) throw new DirectoryNotFoundException();
        using var h=Open(Root,ReadControl|FileReadAttributes,ShareRead|ShareWrite|ShareDelete,OpenExisting,BackupSemantics|OpenReparse);
        VerifyAcl(h,serviceSid!); VerifyNotReparse(h);
    }

    private static SecurityIdentifier GetServiceSid()
    {
        using var id=WindowsIdentity.GetCurrent(TokenAccessLevels.Query);
        var found=id.Groups?.OfType<SecurityIdentifier>().Where(x=>x.Value.StartsWith("S-1-5-80-",StringComparison.Ordinal)).ToArray() ?? [];
        if(found.Length!=1) throw new UnauthorizedAccessException();
        return found[0];
    }

    private static void VerifyAcl(SafeFileHandle h,SecurityIdentifier expected)
    {
        var status=GetSecurityInfo(h,FileObject,OwnerInfo|DaclInfo,out _,out _,out _,out _,out var ptr);
        if(status!=0 || ptr==IntPtr.Zero) throw new UnauthorizedAccessException();
        try
        {
            var len=GetSecurityDescriptorLength(ptr);
            if(len==0 || len>65536) throw new UnauthorizedAccessException();
            var bytes=new byte[(int)len]; Marshal.Copy(ptr,bytes,0,bytes.Length);
            var sd=new RawSecurityDescriptor(bytes,0); CryptographicOperations.ZeroMemory(bytes);
            if(!expected.Equals(sd.Owner) || (sd.ControlFlags&ControlFlags.DiscretionaryAclProtected)==0 ||
               (sd.ControlFlags&ControlFlags.DiscretionaryAclPresent)==0 || sd.DiscretionaryAcl is null || sd.DiscretionaryAcl.Count!=2)
                throw new UnauthorizedAccessException();
            var user=false; var system=false;
            foreach(GenericAce ace in sd.DiscretionaryAcl)
            {
                if(ace is not CommonAce a || a.AceQualifier!=AceQualifier.AccessAllowed || a.AceFlags!=AceFlags.None ||
                   a.IsCallback || a.AccessMask!=unchecked((int)FullControl)) throw new UnauthorizedAccessException();
                if(expected.Equals(a.SecurityIdentifier) && !user) user=true;
                else if(new SecurityIdentifier(WellKnownSidType.LocalSystemSid,null).Equals(a.SecurityIdentifier) && !system) system=true;
                else throw new UnauthorizedAccessException();
            }
            if(!user || !system) throw new UnauthorizedAccessException();
        }
        finally{_=LocalFree(ptr);}
    }

    private static void VerifyNotReparse(SafeFileHandle h)
    {
        if(!GetFileInformationByHandleEx(h,9,out var info,Marshal.SizeOf<FileAttributeTagInfo>()) ||
           (info.FileAttributes&Reparse)!=0) throw new UnauthorizedAccessException();
    }

    private static SafeFileHandle Open(string path,uint access,uint share,uint disposition,uint flags)
    {
        var h=CreateFile(path,access,share,IntPtr.Zero,disposition,flags,IntPtr.Zero);
        if(h.IsInvalid){h.Dispose();throw new IOException();} return h;
    }

    private static async Task<byte[]?> ReadFrame(Stream input)
    {
        using var timeout=new CancellationTokenSource(TimeSpan.FromSeconds(30));
        var head=new byte[Header]; var n=await input.ReadAsync(head.AsMemory(0,1),timeout.Token); if(n==0)return null;
        await input.ReadExactlyAsync(head.AsMemory(1),timeout.Token);
        var length=BinaryPrimitives.ReadUInt32BigEndian(head.AsSpan(2,4));
        if(head[0]!=V || length>Max) throw new InvalidDataException();
        var frame=new byte[Header+(int)length]; head.CopyTo(frame,0); await input.ReadExactlyAsync(frame.AsMemory(Header),timeout.Token); return frame;
    }

    private static async Task Send(Stream output,byte op,byte[] payload)
    {
        var frame=new byte[Header+payload.Length]; frame[0]=V; frame[1]=op;
        BinaryPrimitives.WriteUInt32BigEndian(frame.AsSpan(2,4),(uint)payload.Length); payload.CopyTo(frame,Header);
        await output.WriteAsync(frame); await output.FlushAsync(); CryptographicOperations.ZeroMemory(frame);
    }

    [StructLayout(LayoutKind.Sequential)] private struct SecurityAttributes{public int Length;public IntPtr SecurityDescriptor;[MarshalAs(UnmanagedType.Bool)]public bool InheritHandle;}
    [StructLayout(LayoutKind.Sequential)] private struct FileAttributeTagInfo{public uint FileAttributes;public uint ReparseTag;}
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern SafeFileHandle CreateFile(string n,uint a,uint s,IntPtr sa,uint d,uint f,IntPtr t);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] private static extern SafeFileHandle CreateFileWithSecurity(string n,uint a,uint s,ref SecurityAttributes sa,uint d,uint f,IntPtr t,EntryPoint="CreateFileW");
    [DllImport("kernel32.dll",SetLastError=true)] private static extern bool GetFileInformationByHandleEx(SafeFileHandle h,int c,out FileAttributeTagInfo i,int z);
    [DllImport("advapi32.dll",SetLastError=true)] private static extern uint GetSecurityInfo(SafeFileHandle h,uint t,uint i,out IntPtr o,out IntPtr g,out IntPtr d,out IntPtr s,out IntPtr p);
    [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true,EntryPoint="ConvertStringSecurityDescriptorToSecurityDescriptorW")] private static extern bool ConvertSddl(string s,uint r,out IntPtr p,out uint z);
    [DllImport("kernel32.dll",SetLastError=true)] private static extern IntPtr LocalFree(IntPtr p);
    [DllImport("advapi32.dll",SetLastError=true)] private static extern uint GetSecurityDescriptorLength(IntPtr p);
    [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true,EntryPoint="MoveFileExW")] private static extern bool MoveFileEx(string a,string b,uint f);
}