unit MainForm;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Variants,
  System.Classes,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.Dialogs,
  Vcl.StdCtrls,
  Vcl.ToolWin,
  Vcl.ComCtrls,
  plugin.framework,
  plugin.interfaces;

type
  TForm1 = class(TForm, IHost)
    Memo1: TMemo;
    ToolBar1: TToolBar;
    Label1: TLabel;
    Label2: TLabel;
    procedure Button1Click(Sender: TObject);
    procedure Button2Click(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    { Private declarations }
    plugin1: IPlugin1;
    plugin2: IPlugin2;

    // Event fired from DLL
    procedure SetSpeedButton(Source: integer; AName: PChar); stdcall;
  public
    { Public declarations }
    procedure AddButton1ToToolbar(var bar: TToolBar; caption: string);
    procedure AddButton2ToToolbar(var bar: TToolBar; caption: string);
  end;

function GetHost: IHost; stdcall;

var
  Form1: TForm1;
  PlugInFramework: TPlugInFrameWork;

implementation

{$R *.dfm}

function GetHost: IHost;
begin
  Result := nil;
  if Assigned(Form1) then
    Result := Form1;
end;

procedure TForm1.AddButton1ToToolbar(var bar: TToolBar; caption: string);
var
  newbtn: TToolButton;
  lastbtnidx: integer;
begin
  newbtn := TToolButton.Create(bar);
  newbtn.OnClick := Button1Click;
  newbtn.caption := caption;
  lastbtnidx := bar.ButtonCount - 1;
  if lastbtnidx > -1 then
    newbtn.Left := bar.Buttons[lastbtnidx].Left + bar.Buttons[lastbtnidx].Width
  else
    newbtn.Left := 0;
  newbtn.Parent := bar;
end;

procedure TForm1.AddButton2ToToolbar(var bar: TToolBar; caption: string);
var
  newbtn: TToolButton;
  lastbtnidx: integer;
begin
  newbtn := TToolButton.Create(bar);
  newbtn.OnClick := Button2Click;
  newbtn.caption := caption;
  lastbtnidx := bar.ButtonCount - 1;
  if lastbtnidx > -1 then
    newbtn.Left := bar.Buttons[lastbtnidx].Left + bar.Buttons[lastbtnidx].Width
  else
    newbtn.Left := 0;
  newbtn.Parent := bar;
end;

procedure TForm1.Button1Click;
begin
  if plugin1 <> nil then
  begin
    Memo1.Lines.Add('Plugin Name: ' + plugin1.GetName);
    Memo1.Lines.Add('Execute: ' + plugin1.Execute('world from DLL1'));
  end;
end;

procedure TForm1.Button2Click(Sender: TObject);
begin
  if plugin2 <> nil then
  begin
    Memo1.Lines.Add('Plugin Name: ' + plugin2.GetName);
    Memo1.Lines.Add('Execute: ' + plugin2.Execute('world from DLL2'));
  end;
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  PlugInFramework.FreePlugIn('PluginDLL1.dll', 'FreeHost');
  PlugInFramework.FreePlugIn('PluginDLL2.dll', 'FreeHost');
end;

procedure TForm1.FormShow(Sender: TObject);
begin
  plugin1 := PlugInFramework.LoadPlugin<IPlugin1>('PluginDLL1.dll',
    'GetPlugin');
  if plugin1 = nil then
    ShowMessage('DLL niet gevonden');
  plugin2 := PlugInFramework.LoadPlugin<IPlugin2>('PluginDLL2.dll',
    'GetPlugin');
  if plugin2 = nil then
    ShowMessage('DLL niet gevonden');
end;

procedure TForm1.SetSpeedButton(Source: integer; AName: PChar);
begin
  case Source of
    1:
      AddButton1ToToolbar(ToolBar1, AName);
    2:
      AddButton2ToToolbar(ToolBar1, AName);
  end;

end;

initialization

PlugInFramework := TPlugInFrameWork.Create;

finalization

PlugInFramework.Free;

end.
