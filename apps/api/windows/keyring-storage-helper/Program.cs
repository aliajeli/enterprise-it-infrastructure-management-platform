using System.Buffers.Binary;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Security.AccessControl;
using System.Text;
using System.Text.Json;
using Microsoft.Win32.SafeHandles;
using CredentialVault.KeyringStorageHelper;

internal static class Program
{
    private const byte V=1, Begin=1, Read=2, Write=3, End=4, BeginOk=0x81, ReadResult=0x82, WriteOk=0x83, EndOk=0x84, Error=0xff;
    private const int Header=6, Max=32768;
    private const int TokenGroupsInformation=2;
    private const uint GroupEnabled=0x00000004, GroupUseForDenyOnly=0x00000010;
    private const uint ReadControl=0x20000, GenericRead=0x80000000, GenericWrite=0x40000000;
    private const uint Reparse=0x400, DeleteAccess=0x10000;
    private const uint ShareRead=1;
    private const uint FileObject=1, OwnerInfo=1, DaclInfo=4, FullControl=0x001F01FF;
    private static readonly Encoding Utf8=new UTF8Encoding(false,true);
    private static FileStream? heldLock;
    private static SecurityIdentifier? serviceSid;
    private static WindowsDirectoryHandleChain? directoryChain;

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
                        heldLock!.Dispose(); heldLock=null;
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
        finally
        {
            heldLock?.Dispose(); heldLock=null;
            directoryChain?.Dispose(); directoryChain=null;
        }
    }

    private static void RequireLock(){if(heldLock is null || serviceSid is null) throw new InvalidOperationException();}

    // NtCreateFile failures are surfaced as Win32Exception by OpenVaultFile.
    // A missing registry is an expected first-run state; all other failures remain fail-closed.
    private static SafeFileHandle? TryOpenVaultFile(string name,uint access,uint share)
    {
        try { return directoryChain!.OpenVaultFile(name,access,share); }
        catch(Win32Exception ex) when(ex.NativeErrorCode==2) { return null; }
    }

    private static async Task BeginTransaction()
    {
        serviceSid=GetServiceSid();
        directoryChain=WindowsDirectoryHandleChain.OpenKnownProgramData();
        VerifyDirectory();
        var timer=Stopwatch.StartNew();
        while(true)
        {
            try
            {
                var h=directoryChain!.OpenVaultFile("keyring.lock",GenericRead|GenericWrite|ReadControl,0);
                try
                {
                    VerifyAcl(h,serviceSid); VerifyNotReparse(h);
                    heldLock=new FileStream(h,FileAccess.ReadWrite);
                    return;
                }
                catch {h.Dispose(); throw;}
            }
            catch(Win32Exception ex) when((ex.NativeErrorCode is 32 or 33) && timer.Elapsed<TimeSpan.FromSeconds(10))
            {
                await Task.Delay(50);
            }
        }
    }

    private static string? ReadRegistry()
    {
        var h=TryOpenVaultFile("keyring.v1.json",GenericRead|ReadControl,ShareRead);
        if(h is null) return null;
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
        using(var existing=TryOpenVaultFile("keyring.v1.json",GenericRead|ReadControl,ShareRead))
        {
            if(existing is not null) { VerifyAcl(existing,serviceSid!); VerifyNotReparse(existing); }
        }
        var tempName=".keyring-"+Guid.NewGuid().ToString("N")+".tmp";
        var sddl=$"O:{serviceSid!.Value}D:P(A;;FA;;;{serviceSid.Value})(A;;FA;;;SY)";
        IntPtr sd=IntPtr.Zero;
        SafeFileHandle? tempHandle=null;
        var renamed=false;
        try
        {
            if(!ConvertSddl(sddl,1,out sd,out _)) throw new IOException();
            tempHandle=directoryChain!.OpenVaultFile(tempName,GenericRead|GenericWrite|ReadControl|DeleteAccess,0,2,sd);
            VerifyAcl(tempHandle,serviceSid);
            VerifyNotReparse(tempHandle);
            // Keep writes and cleanup bound to the exact handle; no owning FileStream.
            var originalIdentity=directoryChain.GetVaultFileIdentity(tempHandle);
            RandomAccess.Write(tempHandle,data,0);
            RandomAccess.FlushToDisk(tempHandle);
            directoryChain.RenameVaultFile(tempHandle,"keyring.v1.json",replaceIfExists:true);
            renamed=true;
            // Source was opened without FILE_SHARE_READ/WRITE/DELETE.
            tempHandle.Dispose();
            tempHandle=null;
            using var committed=directoryChain.OpenVaultFile("keyring.v1.json",GenericRead|ReadControl,ShareRead);
            VerifyAcl(committed,serviceSid);
            VerifyNotReparse(committed);
            if(directoryChain.GetVaultFileIdentity(committed)!=originalIdentity)
                throw new IOException("Committed keyring file identity changed during rename.");
            if(RandomAccess.GetLength(committed)!=data.Length) throw new IOException();
            var check=new byte[data.Length];
            try
            {
                var offset=0;
                while(offset<check.Length)
                {
                    var read=RandomAccess.Read(committed,check.AsSpan(offset),offset);
                    if(read<=0) throw new IOException();
                    offset+=read;
                }
                if(!CryptographicOperations.FixedTimeEquals(check,data)) throw new IOException();
            }
            finally { CryptographicOperations.ZeroMemory(check); }
        }
        finally
        {
            try
            {
                // Includes failures after create but before the previous FileStream
                // construction point; deletion is bound to the created file handle.
                if(tempHandle is not null && !renamed) directoryChain!.DeleteVaultFile(tempHandle);
            }
            finally
            {
                tempHandle?.Dispose();
                if(sd!=IntPtr.Zero) _=LocalFree(sd);
            }
        }
    }

    private static void VerifyDirectory()
    {
        var chain=directoryChain ?? throw new UnauthorizedAccessException();
        // The trusted ProgramData -> EnterpriseIT -> CredentialVault chain stays
        // open for the entire helper transaction. All keyring leaf opens, rename
        // and delete operations are relative to the retained Vault handle.
        var vault=chain.VaultHandle;
        VerifyAcl(vault,serviceSid!);
        VerifyNotReparse(vault);
    }

    private static SecurityIdentifier GetServiceSid()
    {
        using var identity=WindowsIdentity.GetCurrent(TokenAccessLevels.Query);
        var candidates=new List<SecurityIdentifier>();

        // A service SID may be the token user for a virtual service account.
        if(identity.User is SecurityIdentifier user &&
           user.Value.StartsWith("S-1-5-80-",StringComparison.Ordinal))
            candidates.Add(user);

        // When represented as a token group, accept only an enabled SID that is
        // not marked deny-only. Merely appearing in TokenGroups is insufficient.
        var token=identity.AccessToken;
        _=GetTokenInformation(token.DangerousGetHandle(),TokenGroupsInformation,IntPtr.Zero,0,out var required);
        var firstGroupOffset=Marshal.OffsetOf<TokenGroupsLayout>(nameof(TokenGroupsLayout.FirstGroup)).ToInt32();
        if(required<firstGroupOffset || required>1024*1024) throw new UnauthorizedAccessException();

        var buffer=Marshal.AllocHGlobal(required);
        try
        {
            if(!GetTokenInformation(token.DangerousGetHandle(),TokenGroupsInformation,buffer,required,out var returned) ||
               returned<firstGroupOffset || returned>required)
                throw new UnauthorizedAccessException();

            var count=Marshal.ReadInt32(buffer);
            var entrySize=Marshal.SizeOf<SidAndAttributes>();
            if(count<0 || count>4096 || returned<firstGroupOffset+(long)count*entrySize)
                throw new UnauthorizedAccessException();

            for(var i=0;i<count;i++)
            {
                var entry=Marshal.PtrToStructure<SidAndAttributes>(IntPtr.Add(buffer,firstGroupOffset+i*entrySize));
                if(entry.Sid==IntPtr.Zero ||
                   (entry.Attributes&GroupEnabled)==0 ||
                   (entry.Attributes&GroupUseForDenyOnly)!=0)
                    continue;

                var sid=new SecurityIdentifier(entry.Sid);
                if(sid.Value.StartsWith("S-1-5-80-",StringComparison.Ordinal))
                    candidates.Add(sid);
            }
        }
        finally
        {
            Marshal.FreeHGlobal(buffer);
        }

        var unique=candidates.GroupBy(x=>x.Value,StringComparer.Ordinal).Select(x=>x.First()).ToArray();
        if(unique.Length!=1) throw new UnauthorizedAccessException();
        return unique[0];
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
            if(sd.Owner is null || !expected.Equals(sd.Owner) || (sd.ControlFlags&ControlFlags.DiscretionaryAclProtected)==0 ||
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

    [StructLayout(LayoutKind.Sequential)] private struct SidAndAttributes{public IntPtr Sid;public uint Attributes;}
    [StructLayout(LayoutKind.Sequential)] private struct TokenGroupsLayout{public uint GroupCount;public SidAndAttributes FirstGroup;}
    [StructLayout(LayoutKind.Sequential)] private struct FileAttributeTagInfo{public uint FileAttributes;public uint ReparseTag;}
    [DllImport("advapi32.dll",SetLastError=true)] private static extern bool GetTokenInformation(IntPtr token,int informationClass,IntPtr information,int informationLength,out int returnLength);
    [DllImport("kernel32.dll",SetLastError=true)] private static extern bool GetFileInformationByHandleEx(SafeFileHandle h,int c,out FileAttributeTagInfo i,int z);
    [DllImport("advapi32.dll",SetLastError=true)] private static extern uint GetSecurityInfo(SafeFileHandle h,uint t,uint i,out IntPtr o,out IntPtr g,out IntPtr d,out IntPtr s,out IntPtr p);
    [DllImport("advapi32.dll",CharSet=CharSet.Unicode,SetLastError=true,EntryPoint="ConvertStringSecurityDescriptorToSecurityDescriptorW")] private static extern bool ConvertSddl(string s,uint r,out IntPtr p,out uint z);
    [DllImport("kernel32.dll",SetLastError=true)] private static extern IntPtr LocalFree(IntPtr p);
    [DllImport("advapi32.dll",SetLastError=true)] private static extern uint GetSecurityDescriptorLength(IntPtr p);
}