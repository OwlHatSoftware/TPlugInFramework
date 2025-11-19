program HostApp;

uses
  Vcl.Forms,
  MainForm in 'MainForm.pas' {Form1},
  plugin.interfaces in '..\..\Shared\plugin.interfaces.pas';

{$R *.res}



exports
  GetHost;

begin
  ReportMemoryLeaksOnShutdown := True;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm1, Form1);
  Application.Run;

end.
