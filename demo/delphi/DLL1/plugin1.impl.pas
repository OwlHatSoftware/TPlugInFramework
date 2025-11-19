unit plugin1.impl;

interface

uses
  System.Classes,
  System.SysUtils,
  plugin.framework,
  plugin.interfaces;

type
  TMyPlugin = class(TInterfacedObject, IPlugin1)
  public
    function GetName: PChar; stdcall;
    function Execute(const Input: PChar): PChar; stdcall;
  end;

function GetPlugin: IPlugin1; stdcall;
procedure FreeHost; stdcall;

var
  Host: IHost;
  PlugInFramework: TPlugInFrameWork;

implementation

function TMyPlugin.GetName: PChar;
begin
  Result := 'Demo Plugin1';
end;

function TMyPlugin.Execute(const Input: PChar): PChar;
begin
  Result := PChar('Hello, ' + StrPas(Input));
end;

function GetPlugin: IPlugin1; stdcall;
begin
  Result := TMyPlugin.Create;
  Host := PlugInFrameWork.LoadPlugin<IHost>('HostApp.exe', 'GetHost');
  if Host <> nil then
    Host.SetSpeedButton(1, 'Demo1');
end;

procedure FreeHost; stdcall;
begin
  if Host <> nil then
    Host := nil;
end;

initialization

PlugInFramework := TPlugInFrameWork.Create;

finalization

PlugInFramework.Free;

end.
