program HostApp;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  {$IFDEF HASAMIGA}
  athreads,
  {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms, MainForm, plugin.interfaces, plugin.framework;

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

procedure THost.SetSpeedButton(AName: PChar); stdcall;
begin
  if Form1 = nil then
    Exit;
  Form1.AddButtonToToolbar(Form1.ToolBar1, AName);
end;

exports
  GetHost;

begin
  RequireDerivedFormResource:=True;
  Application.Scaled:=True;
  Application.Initialize;
  Application.CreateForm(TForm1, Form1);
  Application.Run;
end.

