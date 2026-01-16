unit plugin.framework;

interface

{$IFDEF FPC}
{$MODE delphi}
{$ENDIF}

uses
{$IFDEF FPC}
  Windows, SysUtils, Variants, Classes
{$ELSE}
    Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, System.Generics.Collections
{$ENDIF};

type
  TPlugInFrameWork = class
  private
    LibHandleDic: TDictionary<string, THandle>;
  public
    constructor Create;
    destructor Destroy; override;
    function LoadPlugin<I: IInterface>(const ALibName, AFuncName: string): I;
    // function LoadPackage<I: IInterface>(const APackageName, AFuncName: string): I;
    procedure FreePlugIn(const ALibName, AFuncName: string);
  end;

var
  PlugInFrameWork: TPlugInFrameWork;

implementation

{ TPlugInFrameWork }

constructor TPlugInFrameWork.Create;
begin
  inherited;
  LibHandleDic := TDictionary<string, THandle>.Create;
end;

destructor TPlugInFrameWork.Destroy;
begin
  LibHandleDic.Free;
  inherited;
end;

procedure TPlugInFrameWork.FreePlugIn(const ALibName, AFuncName: string);
type
  TFreePluginProc = procedure; stdcall;
var
  LibHandle: THandle;
  FreePluginProc: TFreePluginProc;
begin
  if LibHandleDic.TryGetValue(ALibName, LibHandle) then
  begin
    if LibHandle <> 0 then
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
    end;
    // FreeLibrary(LibHandle);
    // LibHandle := 0;
  end;
end;

// function TPlugInFrameWork.LoadPackage<I>(const APackageName,
// AFuncName: string): I;
// type
// TGetPluginFunc = function: I; stdcall;
// var
// PackageModule: HModule;
// GetPluginFunc: TGetPluginFunc;
// begin
// Result := nil;
// PackageModule := System.SysUtils.LoadPackage(APackageName);
// if PackageModule <> 0 then
// begin
// @GetPluginFunc := GetProcAddress(PackageModule, PChar(AFuncName));
// if Assigned(GetPluginFunc) then
// begin
// Result := GetPluginFunc;
// Exit; // don't free the library, the interface is released automatically!
// end;
// FreeLibrary(PackageModule); // only free the library if the plugin wasn't found!
// end;
// end;

function TPlugInFrameWork.LoadPlugin<I>(const ALibName, AFuncName: string): I;
type
  TGetPluginFunc = function: I; stdcall;
var
  LibHandle: THandle;
  GetPluginFunc: TGetPluginFunc;
begin
  Result := nil;
  LibHandle := LoadLibrary(PChar(ALibName));
  if LibHandle <> 0 then
  begin
    LibHandleDic.AddOrSetValue(ALibName, LibHandle);
    @GetPluginFunc := GetProcAddress(HMODULE(LibHandle), PChar(AFuncName));
    if Assigned(GetPluginFunc) then
    begin
      Result := GetPluginFunc;
      Exit; // don't free the library, the interface is released automatically!
    end;
    FreeLibrary(LibHandle);
    LibHandleDic.Remove(ALibName);
  end;
end;

initialization

if not Assigned(PlugInFrameWork) then
  PlugInFrameWork := TPlugInFrameWork.Create;

finalization

if Assigned(PlugInFrameWork) then
  PlugInFrameWork.Free;

end.
