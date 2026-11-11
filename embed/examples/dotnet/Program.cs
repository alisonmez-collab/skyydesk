using SkyyDesk;

var desk = new SkyyDeskHost(Path.Combine(AppContext.BaseDirectory, "skyydesk-data"));
desk.Incoming += (_, c) =>
{
    if (c.Authorized) return;
    Console.Write($"{c.Name} ({c.PeerId}) wants to connect. Allow? [y/N] ");
    if (Console.ReadKey().KeyChar is 'y' or 'Y') desk.Accept(c.Id); else desk.Close(c.Id);
    Console.WriteLine();
};
desk.Closed += (_, id) => Console.WriteLine($"connection {id} closed");
desk.Enrolled += (_, r) => Console.WriteLine(r.Ok ? "added to the address book" : $"enroll failed: {r.Error}");

if (args.Length > 0) desk.SetEnrollKey(args[0]);
desk.Start(allowPassword: true);
Console.WriteLine($"SkyyDesk ID {desk.MyId}, one-time password {desk.OneTimePassword}");
Thread.Sleep(Timeout.Infinite);
