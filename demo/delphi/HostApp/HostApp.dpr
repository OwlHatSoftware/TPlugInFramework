program HostApp;

uses
  Vcl.Forms,
  MainForm in 'MainForm.pas' {Form1},
  plugin.interfaces in '..\Shared\plugin.interfaces.pas',
  plugin.framework in '..\..\src\plugin.framework.pas';

{$R *.res}

type
  THost = class(TInterfacedObject, IHost)
  public
    procedure SetSpeedButton(AName: PChar); stdcall;
  end;

function GetHost: IHost; stdcall;
begin
  Result := THost.Create;
end;

{ THost }

procedure THost.SetSpeedButton(AName: PChar);
begin
  if Form1 = nil then
    Exit;
  Form1.AddButtonToToolbar(Form1.ToolBar1, AName);
end;

exports
  GetHost;

begin
  ReportMemoryLeaksOnShutdown := True;
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TForm1, Form1);
  Application.Run;

end.
