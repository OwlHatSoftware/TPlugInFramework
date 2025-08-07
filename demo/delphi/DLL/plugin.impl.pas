unit plugin.impl;

interface

uses
  System.Classes,
  System.SysUtils,
  plugin.interfaces;

type
  TMyPlugin = class(TInterfacedObject, IPlugin)
  public
    function GetName: PChar; stdcall;
    function Execute(const Input: PChar): PChar; stdcall;
  end;

function GetPlugin: IPlugin; stdcall;
procedure FreePlugIn; stdcall;

var
  Host: IHost;

implementation

uses
  plugin.framework;

function TMyPlugin.GetName: PChar;
begin
  Result := 'Demo Plugin';
end;

function TMyPlugin.Execute(const Input: PChar): PChar;
begin
  Result := PChar('Hello, ' + StrPas(Input));
end;

function GetPlugin: IPlugin; stdcall;
begin
  Result := TMyPlugin.Create;
  Host := TPlugInFrameWork.LoadPlugin<IHost>('HostApp.exe', 'GetHost');
  if Host <> nil then
    Host.SetSpeedButton('Demo');
end;

procedure FreePlugIn; stdcall;
begin
  if Host <> nil then
    Host := nil;
end;

initialization

finalization

end.
