unit SkyyDesk;

{ Delphi import of embed/skyydesk.h. Strings are UTF-8: pass PAnsiChar(UTF8String(s)). }

interface

const
{$IFDEF MSWINDOWS}
  SkyyDeskLib = 'skyydesk.dll';
{$ELSE}
  SkyyDeskLib = 'libskyydesk.so';
{$ENDIF}

  SKYYDESK_EVENT_INCOMING        = 1;
  SKYYDESK_EVENT_INCOMING_CLOSED = 2;
  SKYYDESK_EVENT_ENROLLED        = 3;

type
  TSkyyDeskEventCb = procedure(Kind: Integer; Payload: PAnsiChar; User: Pointer); cdecl;

function  skyydesk_init(AppDir: PAnsiChar): Integer; cdecl; external SkyyDeskLib;
procedure skyydesk_set_event_callback(Cb: TSkyyDeskEventCb; User: Pointer); cdecl; external SkyyDeskLib;
function  skyydesk_my_id(Output: PAnsiChar; Len: Integer): Integer; cdecl; external SkyyDeskLib;
function  skyydesk_start(AllowPassword: Integer): Integer; cdecl; external SkyyDeskLib;
procedure skyydesk_accept(Connection: Integer); cdecl; external SkyyDeskLib;
procedure skyydesk_close(Connection: Integer); cdecl; external SkyyDeskLib;
function  skyydesk_password(Output: PAnsiChar; Len: Integer): Integer; cdecl; external SkyyDeskLib;
procedure skyydesk_new_password; cdecl; external SkyyDeskLib;
function  skyydesk_set_password(Password: PAnsiChar): Integer; cdecl; external SkyyDeskLib;
function  skyydesk_get_option(Key, Output: PAnsiChar; Len: Integer): Integer; cdecl; external SkyyDeskLib;
function  skyydesk_set_option(Key, Value: PAnsiChar): Integer; cdecl; external SkyyDeskLib;

implementation

end.
