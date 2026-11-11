// Java through JNA (net.java.dev.jna:jna 5.x), no JNI code to compile.
//   javac -cp jna.jar SkyyDeskHost.java && java -cp jna.jar:. -Djna.library.path=. SkyyDeskHost [enroll-key]
import com.sun.jna.Callback;
import com.sun.jna.Library;
import com.sun.jna.Native;
import com.sun.jna.Pointer;

public class SkyyDeskHost {
    public interface SkyyDesk extends Library {
        SkyyDesk LIB = Native.load("skyydesk", SkyyDesk.class);

        int EVENT_INCOMING = 1, EVENT_INCOMING_CLOSED = 2, EVENT_ENROLLED = 3;

        interface EventCb extends Callback {
            void invoke(int kind, String payload, Pointer user);
        }

        int skyydesk_init(String appDir);
        void skyydesk_set_event_callback(EventCb cb, Pointer user);
        int skyydesk_my_id(byte[] out, int len);
        int skyydesk_start(int allowPassword);
        void skyydesk_accept(int connection);
        void skyydesk_close(int connection);
        int skyydesk_password(byte[] out, int len);
        void skyydesk_new_password();
        int skyydesk_set_password(String password);
        int skyydesk_get_option(String key, byte[] out, int len);
        int skyydesk_set_option(String key, String value);
    }

    // Kept in a field: JNA must not let the callback be collected while the library holds it.
    static final SkyyDesk.EventCb ON_EVENT = (kind, payload, user) -> {
        switch (kind) {
            case SkyyDesk.EVENT_INCOMING -> {
                System.out.println("incoming: " + payload);
                // Decide here; this example lets everyone with the password in.
            }
            case SkyyDesk.EVENT_INCOMING_CLOSED -> System.out.println("closed: " + payload);
            case SkyyDesk.EVENT_ENROLLED -> System.out.println("address book: " + payload);
        }
    };

    static String read(java.util.function.ToIntBiFunction<byte[], Integer> f) {
        byte[] b = new byte[512];
        int n = f.applyAsInt(b, b.length);
        return n < 0 ? "" : new String(b, 0, n, java.nio.charset.StandardCharsets.UTF_8);
    }

    public static void main(String[] args) throws InterruptedException {
        SkyyDesk d = SkyyDesk.LIB;
        d.skyydesk_init("skyydesk-data");
        d.skyydesk_set_event_callback(ON_EVENT, null);
        if (args.length > 0) d.skyydesk_set_option("enroll-key", args[0]);
        d.skyydesk_start(1);
        System.out.println("SkyyDesk ID " + read(d::skyydesk_my_id)
                + ", one-time password " + read(d::skyydesk_password));
        Thread.currentThread().join();
    }
}
