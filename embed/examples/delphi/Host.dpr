program Host;

{ Smallest host: makes this machine reachable and asks on the terminal before letting anyone in.
    Host.exe [enroll-key] }

{$APPTYPE CONSOLE}

uses
  SysUtils, SkyyDesk;

var
  { The connection waiting for an answer. Only the main thread reads the terminal: the callback
    runs on a library thread, and two readers of stdin would take each other's answers. }
  Pending: Integer = -1;

{ Runs on a library thread. In a VCL/FMX application, hand the event to the main thread
  with TThread.Queue before touching any form. }
procedure OnEvent(Kind: Integer; Payload: PAnsiChar; User: Pointer); cdecl;
var
  S: string;
  P, Id: Integer;
begin
  S := UTF8ToString(Payload);
  case Kind of
    SKYYDESK_EVENT_INCOMING:
      begin
        { S is JSON; "id" is the connection, "name" and "peer_id" say who is coming }
        Writeln('incoming: ', S);
        if Pos('"authorized":false', S) > 0 then
        begin
          P := Pos('"id":', S) + 5;
          Id := 0;
          while (P <= Length(S)) and (S[P] >= '0') and (S[P] <= '9') do
          begin
            Id := Id * 10 + Ord(S[P]) - Ord('0');
            Inc(P);
          end;
          Pending := Id;
          Write('allow connection ', Id, '? [y/N] ');
        end;
      end;
    SKYYDESK_EVENT_INCOMING_CLOSED: Writeln('closed: ', S);
    SKYYDESK_EVENT_ENROLLED:        Writeln('address book: ', S);
  end;
end;

var
  Buf: array[0..511] of AnsiChar;
  Line: string;
  Conn: Integer;
begin
  skyydesk_init('skyydesk-data');
  skyydesk_set_event_callback(OnEvent, nil);
  if ParamCount > 0 then
    skyydesk_set_option('enroll-key', PAnsiChar(UTF8String(ParamStr(1))));
  if skyydesk_start(1) <> 0 then
    Halt(1);
  skyydesk_my_id(Buf, SizeOf(Buf));
  Write('SkyyDesk ID ', UTF8ToString(PAnsiChar(@Buf)));
  skyydesk_password(Buf, SizeOf(Buf));
  Writeln(', one-time password ', UTF8ToString(PAnsiChar(@Buf)));

  while not Eof(Input) do
  begin
    Readln(Line);
    Conn := Pending;
    if Conn < 0 then
      Continue;
    Pending := -1;
    if (Line <> '') and (UpCase(Line[1]) = 'Y') then
      skyydesk_accept(Conn)
    else
      skyydesk_close(Conn);
  end;
  while True do
    Sleep(1000000); { no terminal left: keep the machine reachable }
end.
