program Host;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, SkyyDesk;

{ Runs on a library thread. In a VCL/FMX application, hand the event to the main thread
  with TThread.Queue before touching any form. }
procedure OnEvent(Kind: Integer; Payload: PAnsiChar; User: Pointer); cdecl;
begin
  case Kind of
    SKYYDESK_EVENT_INCOMING:        Writeln('incoming: ', UTF8ToString(Payload));
    SKYYDESK_EVENT_INCOMING_CLOSED: Writeln('closed: ', UTF8ToString(Payload));
    SKYYDESK_EVENT_ENROLLED:        Writeln('address book: ', UTF8ToString(Payload));
  end;
end;

var
  Buf: array[0..511] of AnsiChar;
begin
  skyydesk_init('skyydesk-data');
  skyydesk_set_event_callback(OnEvent, nil);
  if ParamCount > 0 then
    skyydesk_set_option('enroll-key', PAnsiChar(UTF8String(ParamStr(1))));
  skyydesk_start(1);
  skyydesk_my_id(Buf, SizeOf(Buf));
  Write('SkyyDesk ID ', UTF8ToString(Buf));
  skyydesk_password(Buf, SizeOf(Buf));
  Writeln(', one-time password ', UTF8ToString(Buf));
  Readln;
end.
