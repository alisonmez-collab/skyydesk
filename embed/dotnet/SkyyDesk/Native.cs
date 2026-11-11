using System.Runtime.InteropServices;

namespace SkyyDesk;

// One-to-one with embed/skyydesk.h. "skyydesk" resolves to skyydesk.dll on Windows and
// libskyydesk.so on Linux.
internal static unsafe partial class Native
{
    private const string Lib = "skyydesk";

    [LibraryImport(Lib, StringMarshalling = StringMarshalling.Utf8)]
    internal static partial int skyydesk_init(string appDir);

    [LibraryImport(Lib)]
    internal static partial void skyydesk_set_event_callback(delegate* unmanaged[Cdecl]<int, byte*, nint, void> cb, nint user);

    [LibraryImport(Lib)]
    internal static partial int skyydesk_my_id(byte* output, int len);

    [LibraryImport(Lib)]
    internal static partial int skyydesk_start(int allowPassword);

    [LibraryImport(Lib)]
    internal static partial void skyydesk_accept(int connection);

    [LibraryImport(Lib)]
    internal static partial void skyydesk_close(int connection);

    [LibraryImport(Lib)]
    internal static partial int skyydesk_password(byte* output, int len);

    [LibraryImport(Lib)]
    internal static partial void skyydesk_new_password();

    [LibraryImport(Lib, StringMarshalling = StringMarshalling.Utf8)]
    internal static partial int skyydesk_set_password(string password);

    [LibraryImport(Lib, StringMarshalling = StringMarshalling.Utf8)]
    internal static partial int skyydesk_get_option(string key, byte* output, int len);

    [LibraryImport(Lib, StringMarshalling = StringMarshalling.Utf8)]
    internal static partial int skyydesk_set_option(string key, string value);
}
