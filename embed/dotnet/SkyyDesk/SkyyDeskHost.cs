using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;

namespace SkyyDesk;

/// <summary>Someone is connecting. Call <see cref="SkyyDeskHost.Accept"/> or <see cref="SkyyDeskHost.Close"/>
/// when <see cref="Authorized"/> is false.</summary>
public sealed record IncomingConnection(int Id, string Name, string PeerId, bool Authorized);

public sealed record EnrollResult(bool Ok, string? Error);

/// <summary>
/// Makes this machine reachable from SkyyDesk. One per process: the library behind it is a
/// process-wide singleton. Events arrive on a library thread.
/// </summary>
public sealed unsafe class SkyyDeskHost
{
    private const int EventIncoming = 1, EventIncomingClosed = 2, EventEnrolled = 3;
    private static SkyyDeskHost? _instance;

    public event EventHandler<IncomingConnection>? Incoming;
    public event EventHandler<int>? Closed;
    public event EventHandler<EnrollResult>? Enrolled;

    public SkyyDeskHost(string appDir)
    {
        if (Interlocked.CompareExchange(ref _instance, this, null) != null)
            throw new InvalidOperationException("SkyyDeskHost is already created in this process.");
        Native.skyydesk_init(appDir);
        Native.skyydesk_set_event_callback(&OnEvent, 0);
    }

    public string MyId => ReadString(Native.skyydesk_my_id);
    public string OneTimePassword => ReadString(Native.skyydesk_password);

    /// <param name="allowPassword">false: every connection waits for <see cref="Accept"/>.</param>
    public void Start(bool allowPassword)
    {
        if (Native.skyydesk_start(allowPassword ? 1 : 0) != 0)
            throw new InvalidOperationException("SkyyDesk could not start.");
    }

    public void Accept(int connection) => Native.skyydesk_accept(connection);
    public void Close(int connection) => Native.skyydesk_close(connection);
    public void NewOneTimePassword() => Native.skyydesk_new_password();

    /// <summary>Permanent password; empty removes it.</summary>
    public bool SetPassword(string password) => Native.skyydesk_set_password(password) == 0;

    public string GetOption(string key) =>
        ReadString((p, n) => Native.skyydesk_get_option(key, p, n));

    /// <summary>False for server and account options, which the library does not change.</summary>
    public bool SetOption(string key, string value) => Native.skyydesk_set_option(key, value) == 0;

    /// <summary>Key from skyydesk.com/panel → Settings → Enrollment keys.</summary>
    public void SetEnrollKey(string key) => SetOption("enroll-key", key);

    private delegate int Reader(byte* output, int len);

    private static string ReadString(Reader read)
    {
        var buf = stackalloc byte[512];
        int n = read(buf, 512);
        return n < 0 ? "" : Encoding.UTF8.GetString(buf, n);
    }

    [UnmanagedCallersOnly(CallConvs = new[] { typeof(System.Runtime.CompilerServices.CallConvCdecl) })]
    private static void OnEvent(int kind, byte* payload, nint user)
    {
        var host = _instance;
        if (host == null) return;
        string text = Marshal.PtrToStringUTF8((nint)payload) ?? "";
        try
        {
            switch (kind)
            {
                case EventIncoming:
                    var c = JsonDocument.Parse(text).RootElement;
                    host.Incoming?.Invoke(host, new IncomingConnection(
                        c.GetProperty("id").GetInt32(),
                        c.GetProperty("name").GetString() ?? "",
                        c.GetProperty("peer_id").GetString() ?? "",
                        c.GetProperty("authorized").GetBoolean()));
                    break;
                case EventIncomingClosed:
                    host.Closed?.Invoke(host, int.Parse(text));
                    break;
                case EventEnrolled:
                    var e = JsonDocument.Parse(text).RootElement;
                    host.Enrolled?.Invoke(host, new EnrollResult(
                        e.GetProperty("ok").GetBoolean(),
                        e.TryGetProperty("error", out var err) ? err.GetString() : null));
                    break;
            }
        }
        catch (Exception ex)
        {
            // An exception must not cross into native code; it would end the process.
            Console.Error.WriteLine($"SkyyDesk event {kind}: {ex.Message}");
        }
    }
}
