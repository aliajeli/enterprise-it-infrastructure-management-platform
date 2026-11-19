using System.Buffers.Binary;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;

internal static class Program
{
    private const byte ProtocolVersion = 1;
    private const byte ProtectOperation = 1;
    private const byte UnprotectOperation = 2;
    private const int KeyBytes = 32;
    private const int MaxFrameBytes = 16 * 1024;
    private const uint CryptProtectUiForbidden = 0x1;
    private const uint CryptProtectLocalMachine = 0x4;

    private static async Task<int> Main()
    {
        byte status = 2;
        byte[] output = [];
        byte[] frame = [];
        byte[] payload = [];
        byte[] entropy = [];
        try
        {
            using var input = Console.OpenStandardInput();
            using var stdout = Console.OpenStandardOutput();
            var prefix = new byte[4];
            await ReadExactly(input, prefix);
            var frameLength = BinaryPrimitives.ReadInt32BigEndian(prefix);
            if (frameLength < 8 || frameLength > MaxFrameBytes)
                throw new InvalidDataException();

            frame = new byte[frameLength];
            await ReadExactly(input, frame);
            if (frame[0] != ProtocolVersion)
                throw new InvalidDataException();

            var operation = frame[1];
            var installationLength = BinaryPrimitives.ReadUInt16BigEndian(frame.AsSpan(2, 2));
            var payloadLength = BinaryPrimitives.ReadInt32BigEndian(frame.AsSpan(4, 4));
            if (installationLength is < 1 or > 128 ||
                payloadLength < 1 ||
                payloadLength > MaxFrameBytes - 8 - installationLength ||
                (operation == ProtectOperation && payloadLength != KeyBytes) ||
                frameLength != 8 + installationLength + payloadLength ||
                operation is not (ProtectOperation or UnprotectOperation))
                throw new InvalidDataException();

            var installationId = Encoding.UTF8.GetString(frame, 8, installationLength);
            if (!Guid.TryParseExact(installationId, "D", out _))
                throw new InvalidDataException();

            var sid = WindowsIdentity.GetCurrent().User?.Value
                ?? throw new InvalidOperationException();
            var entropyText = "EnterpriseIT.CredentialVault.DPAPI.v1|" + sid + "|" + installationId;
            entropy = SHA256.HashData(Encoding.UTF8.GetBytes(entropyText));
            payload = frame.AsSpan(8 + installationLength, payloadLength).ToArray();

            try
            {
                output = operation == ProtectOperation
                    ? Dpapi.Protect(payload, entropy)
                    : Dpapi.Unprotect(payload, entropy);
                if (operation == UnprotectOperation && output.Length != KeyBytes)
                    throw new CryptographicException();
                status = 0;
            }
            finally
            {
            }

            var response = new byte[5 + output.Length];
            response[0] = status;
            BinaryPrimitives.WriteInt32BigEndian(response.AsSpan(1, 4), output.Length);
            output.CopyTo(response, 5);
            var responsePrefix = new byte[4];
            BinaryPrimitives.WriteInt32BigEndian(responsePrefix, response.Length);
            await stdout.WriteAsync(responsePrefix);
            await stdout.WriteAsync(response);
            await stdout.FlushAsync();
            CryptographicOperations.ZeroMemory(response);
            return 0;
        }
        catch
        {
            // stdout is a binary-only protocol. Never write exception details or key material.
            try
            {
                using var stdout = Console.OpenStandardOutput();
                var response = new byte[9];
                BinaryPrimitives.WriteInt32BigEndian(response, 5);
                response[4] = status;
                BinaryPrimitives.WriteInt32BigEndian(response.AsSpan(5, 4), 0);
                await stdout.WriteAsync(response);
                await stdout.FlushAsync();
            }
            catch { /* fail closed */ }
            return 1;
        }
        finally
        {
            CryptographicOperations.ZeroMemory(frame);
            CryptographicOperations.ZeroMemory(payload);
            CryptographicOperations.ZeroMemory(entropy);
            CryptographicOperations.ZeroMemory(output);
        }
    }

    private static async Task ReadExactly(Stream stream, byte[] buffer)
    {
        var offset = 0;
        while (offset < buffer.Length)
        {
            var count = await stream.ReadAsync(buffer.AsMemory(offset));
            if (count == 0) throw new EndOfStreamException();
            offset += count;
        }
    }

    private static class Dpapi
    {
        [StructLayout(LayoutKind.Sequential)]
        private struct DataBlob
        {
            public int Length;
            public IntPtr Data;
        }

        [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CryptProtectData(
            ref DataBlob input,
            string description,
            ref DataBlob optionalEntropy,
            IntPtr reserved,
            IntPtr prompt,
            uint flags,
            out DataBlob output);

        [DllImport("crypt32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CryptUnprotectData(
            ref DataBlob input,
            IntPtr description,
            ref DataBlob optionalEntropy,
            IntPtr reserved,
            IntPtr prompt,
            uint flags,
            out DataBlob output);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr LocalFree(IntPtr memory);

        public static byte[] Protect(byte[] plaintext, byte[] entropy)
            => Transform(plaintext, entropy, protect: true);

        public static byte[] Unprotect(byte[] protectedData, byte[] entropy)
            => Transform(protectedData, entropy, protect: false);

        private static byte[] Transform(byte[] source, byte[] entropy, bool protect)
        {
            var sourcePointer = Marshal.AllocHGlobal(source.Length);
            var entropyPointer = Marshal.AllocHGlobal(entropy.Length);
            DataBlob output = default;
            try
            {
                Marshal.Copy(source, 0, sourcePointer, source.Length);
                Marshal.Copy(entropy, 0, entropyPointer, entropy.Length);
                var inputBlob = new DataBlob { Length = source.Length, Data = sourcePointer };
                var entropyBlob = new DataBlob { Length = entropy.Length, Data = entropyPointer };
                var success = protect
                    ? CryptProtectData(ref inputBlob, "Enterprise IT Credential Vault", ref entropyBlob,
                        IntPtr.Zero, IntPtr.Zero, CryptProtectUiForbidden | CryptProtectLocalMachine, out output)
                    : CryptUnprotectData(ref inputBlob, IntPtr.Zero, ref entropyBlob,
                        IntPtr.Zero, IntPtr.Zero, CryptProtectUiForbidden, out output);
                if (!success || output.Data == IntPtr.Zero || output.Length < 1 || output.Length > MaxFrameBytes)
                    throw new CryptographicException();

                var result = new byte[output.Length];
                Marshal.Copy(output.Data, result, 0, output.Length);
                return result;
            }
            finally
            {
                ZeroUnmanaged(sourcePointer, source.Length);
                Marshal.FreeHGlobal(sourcePointer);
                ZeroUnmanaged(entropyPointer, entropy.Length);
                Marshal.FreeHGlobal(entropyPointer);
                if (output.Data != IntPtr.Zero)
                {
                    ZeroUnmanaged(output.Data, output.Length);
                    _ = LocalFree(output.Data);
                }
            }
        }

        private static void ZeroUnmanaged(IntPtr pointer, int length)
        {
            if (pointer == IntPtr.Zero || length <= 0) return;
            var zeros = new byte[length];
            Marshal.Copy(zeros, 0, pointer, length);
            CryptographicOperations.ZeroMemory(zeros);
        }
    }
}
