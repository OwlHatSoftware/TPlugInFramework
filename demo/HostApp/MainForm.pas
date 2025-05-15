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
  plugin.interfaces;

type
  TForm1 = class(TForm)
    Memo1: TMemo;
    ToolBar1: TToolBar;
    Label1: TLabel;
    Label2: TLabel;
    procedure ButtonClick(Sender: TObject);
    procedure FormShow(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
  private
    { Private declarations }
    plugin: IPlugin;

  public
    { Public declarations }
    procedure AddButtonToToolbar(var bar: TToolBar; caption: string);
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

uses
  plugin.framework;

procedure TForm1.AddButtonToToolbar(var bar: TToolBar; caption: string);
var
  newbtn: TToolButton;
  lastbtnidx: integer;
begin
  newbtn := TToolButton.Create(bar);
  newbtn.OnClick := ButtonClick;
  newbtn.caption := caption;
  lastbtnidx := bar.ButtonCount - 1;
  if lastbtnidx > -1 then
    newbtn.Left := bar.Buttons[lastbtnidx].Left + bar.Buttons[lastbtnidx].Width
  else
    newbtn.Left := 0;
  newbtn.Parent := bar;
end;

procedure TForm1.ButtonClick;
begin
  if plugin = nil then
    Exit;
  Memo1.Lines.Add('Plugin Name: ' + plugin.GetName);
  Memo1.Lines.Add('Execute: ' + plugin.Execute('world'));
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  TPlugInFrameWork.FreePlugIn('FreePlugIn');
end;

procedure TForm1.FormShow(Sender: TObject);
begin
  plugin := TPlugInFrameWork.LoadPlugin<IPlugin>('PluginDLL.dll', 'GetPlugin');
  if plugin = nil then
    ShowMessage('DLL niet gevonden');
end;

end.
