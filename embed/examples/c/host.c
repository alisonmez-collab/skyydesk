/* Smallest host: makes this machine reachable and asks on the terminal before letting anyone in.
 *
 *   Linux:   cc host.c -o host -L. -lskyydesk -Wl,-rpath,'$ORIGIN'
 *   Windows: cl host.c skyydesk.lib
 *
 *   ./host [enroll-key]
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "skyydesk.h"
#ifdef _WIN32
#include <windows.h>
#define wait_forever() for (;;) Sleep(INFINITE)
#else
#include <unistd.h>
#define wait_forever() for (;;) pause()
#endif

/* The connection waiting for an answer. Only main reads the terminal: the callback runs on a
 * library thread, and two readers of stdin would take each other's answers. */
static volatile int pending = -1;

static void on_event(int kind, const char *payload, void *user)
{
    (void)user;
    switch (kind) {
    case SKYYDESK_EVENT_INCOMING:
        /* payload is JSON; "id" is the connection, "name" and "peer_id" say who is coming */
        printf("incoming: %s\n", payload);
        if (strstr(payload, "\"authorized\":false")) {
            const char *p = strstr(payload, "\"id\":");
            pending = p ? atoi(p + 5) : -1;
            printf("allow connection %d? [y/N] ", pending);
        }
        break;
    case SKYYDESK_EVENT_INCOMING_CLOSED:
        printf("closed: %s\n", payload);
        break;
    case SKYYDESK_EVENT_ENROLLED:
        printf("address book: %s\n", payload);
        break;
    }
}

int main(int argc, char **argv)
{
    char id[32], pw[64], line[16];

    setvbuf(stdout, NULL, _IONBF, 0); /* events print from a library thread */
    skyydesk_init("./skyydesk-data");
    skyydesk_set_event_callback(on_event, NULL);
    if (argc > 1) skyydesk_set_option("enroll-key", argv[1]);
    if (skyydesk_start(1) != 0) return 1;

    skyydesk_my_id(id, sizeof id);
    skyydesk_password(pw, sizeof pw);
    printf("SkyyDesk ID %s, one-time password %s\n", id, pw);

    while (fgets(line, sizeof line, stdin)) {
        int conn = pending;
        if (conn < 0) continue;
        pending = -1;
        if (line[0] == 'y' || line[0] == 'Y') skyydesk_accept(conn); else skyydesk_close(conn);
    }
    wait_forever(); /* no terminal left: keep the machine reachable */
}
