unit plugin.framework;

interface

{$IFDEF FPC}
{$mode delphi}
{$ENDIF}

uses
  {$IFDEF FPC}
  Windows
  , SysUtils
  , Variants
  , Classes
  //, generics.Collections //see github: https://github.com/maciej-izak/generics.collections
  {$ELSE}
  Winapi.Windows
  , Winapi.Messages
  , System.SysUtils
  , System.Variants
  , System.Classes
  {$ENDIF};

type
  TPlugInFrameWork = class
  private
    class var LibHandle: THandle;
  public
    class function LoadPlugin<I: IInterface>(const ALibName,
      AFuncName: string): I;
    class procedure FreePlugIn(const AFuncName: string);
  end;

implementation

{ TPlugInFrameWork }

class procedure TPlugInFrameWork.FreePlugIn(const AFuncName: string);
type
  TFreePluginProc = procedure; stdcall;
var
  FreePluginProc: TFreePluginProc;
begin
  if (LibHandle <> 0) then
  begin
    if (AFuncName <> '') then
    begin
      @FreePluginProc := GetProcAddress(HMODULE(LibHandle), PChar(AFuncName));
      if Assigned(FreePluginProc) then
      begin
        FreePluginProc;
        Exit; // don't free the library, the interface is released automatically!
      end;
    end;
    FreeLibrary(LibHandle);
    LibHandle := 0;
  end;
end;

class function TPlugInFrameWork.LoadPlugin<I>(const ALibName,
  AFuncName: string): I;
type
  TGetPluginFunc = function: I; stdcall;
var
  GetPluginFunc: TGetPluginFunc;
begin
  LibHandle := LoadLibrary(PChar(ALibName));
  if LibHandle <> 0 then
  begin
    @GetPluginFunc := GetProcAddress(HMODULE(LibHandle), PChar(AFuncName));
    if Assigned(GetPluginFunc) then
    begin
      result := GetPluginFunc;
      Exit; // don't free the library, the interface is released automatically!
    end;
    FreeLibrary(LibHandle); // only free the library if the plugin wasn't found!
  end
  else
    result := nil;
end;

end.
