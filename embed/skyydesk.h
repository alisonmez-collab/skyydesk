/*
 * SkyyDesk embedding interface — skyydesk.dll (Windows), libskyydesk.so (Linux).
 *
 * The library makes the machine it runs on reachable: SkyyDesk users connect to it
 * from the SkyyDesk client or the web panel. Signing in, users and address books are
 * managed in the panel; there is no sign-in in this library.
 *
 * License: AGPL-3.0, the same as the SkyyDesk client it is built from. See LICENSE.
 *
 * Strings are UTF-8 and NUL-terminated. The payload passed to the event callback is
 * valid only during that call. The callback runs on a library thread.
 */
#ifndef SKYYDESK_H
#define SKYYDESK_H

#ifdef __cplusplus
extern "C" {
#endif

/* kind values of skyydesk_event_cb */
#define SKYYDESK_EVENT_INCOMING        1 /* payload: client JSON; "authorized":false waits for skyydesk_accept */
#define SKYYDESK_EVENT_INCOMING_CLOSED 2 /* payload: connection id                                          */
#define SKYYDESK_EVENT_ENROLLED        3 /* payload: {"ok":true} or {"ok":false,"error":"..."}              */

typedef void (*skyydesk_event_cb)(int kind, const char *payload, void *user);

/* Call once, as the first thing in main. The library starts copies of the host
 * executable for its own helper roles, and those copies exit inside this call.
 * Settings live in the user's configuration folder (%APPDATA%\SkyyDeskHost\config
 * on Windows, ~/.config/skyydeskhost on Linux); app_dir is reserved for platforms
 * without one. Returns 0, or -1 if app_dir is NULL. */
int  skyydesk_init(const char *app_dir);
void skyydesk_set_event_callback(skyydesk_event_cb cb, void *user);

/* This machine's SkyyDesk ID. Returns its length, or -1 if out is too small. */
int  skyydesk_my_id(char *out, int len);

/* Lets SkyyDesk users connect. allow_password 0: every connection waits for
 * skyydesk_accept. Requires an event callback. Returns 0, or -2 without one. */
int  skyydesk_start(int allow_password);
void skyydesk_accept(int connection);
void skyydesk_close(int connection);

/* Passwords */
int  skyydesk_password(char *out, int len);       /* current one-time password    */
void skyydesk_new_password(void);                 /* generate a new one-time one  */
int  skyydesk_set_password(const char *password); /* permanent; "" removes. 0/-1  */

/* Settings — the same keys as the desktop client's settings page:
 *   verification-method  use-permanent-password | use-temporary-password | use-both-passwords
 *   enable-keyboard, enable-clipboard, enable-file-transfer, enable-audio   Y | N
 *   enroll-key           key from the panel; puts this machine in its owner's address book
 * Server and account options are refused with -1. */
int  skyydesk_get_option(const char *key, char *out, int len);
int  skyydesk_set_option(const char *key, const char *value);

#ifdef __cplusplus
}
#endif

#endif /* SKYYDESK_H */
