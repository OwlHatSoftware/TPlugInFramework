{ ohsPluginFramework - loading and unloading plugin libraries.

    Registry := TOhsUIRegistry.Create;
    Plugins := TOhsPluginManager.Create(Registry);
    Plugins.LoadFromDirectory(ExtractFilePath(ParamStr(0))+'plugins');
    ...
    Plugins.UnloadAll;   // before the controls the plugins added to are freed

  A plugin library exports OHS_PLUGIN_ENTRY as TOhsPluginEntry. A plugin compiled
  into the host itself is added with AddPlugin; it goes through the same steps
  without a library.

  Unloading a plugin: Finalize, then everything it added is removed and its host
  object is cut off, then the plugin object is released, and only then is the
  library unloaded. }
unit ohs.plugin.manager;

{$IFDEF FPC}
  {$MODE Delphi}{$H+}
  {$INTERFACES COM}
{$ENDIF}

interface

uses
  Classes, SysUtils, dynlibs, ohs.plugin.api, ohs.plugin.helpers, ohs.plugin.registry;

type
  { A plugin the manager loaded. }
  TOhsLoadedPlugin = class
  private
    FFileName: string;
    FLibrary: TLibHandle;
    FPlugin: IOhsPlugin;
    FSite: TOhsPluginSite;
    FSiteRef: IOhsHost; // keeps the site alive while the plugin is loaded
    FId: string;
    FName: string;
    FVersion: string;
    FDescription: string;
  public
    // Empty for a plugin added with AddPlugin
    property FileName: string read FFileName;
    property Plugin: IOhsPlugin read FPlugin;
    property Site: TOhsPluginSite read FSite;
    property Id: string read FId;
    property Name: string read FName;
    property Version: string read FVersion;
    property Description: string read FDescription;
  end;

  TOhsPluginErrorEvent = procedure(const aFileName, aMessage: string) of object;

  TOhsPluginManager = class
  private
    FRegistry: TOhsUIRegistry;
    FPlugins: TList;
    FOnError: TOhsPluginErrorEvent;
    FLastError: string;
    function GetCount: Integer;
    function GetPlugin(aIndex: Integer): TOhsLoadedPlugin;
    procedure Error(const aFileName, aMessage: string);
    function Start(aLoaded: TOhsLoadedPlugin): Boolean;
    procedure Stop(aLoaded: TOhsLoadedPlugin);
  public
    constructor Create(aRegistry: TOhsUIRegistry);
    // Unloads what is still loaded
    destructor Destroy; override;
    // nil when it fails; LastError and OnError say why
    function LoadPlugin(const aFileName: string): TOhsLoadedPlugin;
    // A plugin that is part of the host, or of a library the host loaded itself
    function AddPlugin(const aPlugin: IOhsPlugin): TOhsLoadedPlugin;
    // Loads every library in aDirectory; returns how many loaded
    function LoadFromDirectory(const aDirectory: string; const aMask: string = ''): Integer;
    function FindPlugin(const aId: string): TOhsLoadedPlugin;
    procedure UnloadPlugin(aPlugin: TOhsLoadedPlugin);
    // In the reverse order of loading
    procedure UnloadAll;
    property Registry: TOhsUIRegistry read FRegistry;
    property Count: Integer read GetCount;
    property Plugins[aIndex: Integer]: TOhsLoadedPlugin read GetPlugin; default;
    property LastError: string read FLastError;
    property OnError: TOhsPluginErrorEvent read FOnError write FOnError;
  end;

implementation

{ TOhsPluginManager }

constructor TOhsPluginManager.Create(aRegistry: TOhsUIRegistry);
begin
  inherited Create;
  FRegistry:=aRegistry;
  FPlugins:=TList.Create;
end;

destructor TOhsPluginManager.Destroy;
begin
  UnloadAll;
  FPlugins.Free;
  inherited Destroy;
end;

function TOhsPluginManager.GetCount: Integer;
begin
  Result:=FPlugins.Count;
end;

function TOhsPluginManager.GetPlugin(aIndex: Integer): TOhsLoadedPlugin;
begin
  Result:=TOhsLoadedPlugin(FPlugins[aIndex]);
end;

procedure TOhsPluginManager.Error(const aFileName, aMessage: string);
begin
  FLastError:=aMessage;
  if FRegistry<>nil then
    FRegistry.Log(Format('Plugin %s: %s',[aFileName,aMessage]));
  if Assigned(FOnError) then
    FOnError(aFileName,aMessage);
end;

function TOhsPluginManager.Start(aLoaded: TOhsLoadedPlugin): Boolean;
begin
  Result:=False;
  try
    aLoaded.FId:=OhsStr(aLoaded.FPlugin.GetInfo(OHS_INFO_ID));
    aLoaded.FName:=OhsStr(aLoaded.FPlugin.GetInfo(OHS_INFO_NAME));
    aLoaded.FVersion:=OhsStr(aLoaded.FPlugin.GetInfo(OHS_INFO_VERSION));
    aLoaded.FDescription:=OhsStr(aLoaded.FPlugin.GetInfo(OHS_INFO_DESCRIPTION));
  except
    on E: Exception do
    begin
      Error(aLoaded.FFileName,'GetInfo failed: '+E.Message);
      Exit;
    end;
  end;
  if aLoaded.FId='' then
    aLoaded.FId:=ChangeFileExt(ExtractFileName(aLoaded.FFileName),'');
  if aLoaded.FName='' then
    aLoaded.FName:=aLoaded.FId;
  if FindPlugin(aLoaded.FId)<>nil then
  begin
    Error(aLoaded.FFileName,'a plugin with id '+aLoaded.FId+' is already loaded');
    Exit;
  end;
  aLoaded.FSite:=TOhsPluginSite.Create(FRegistry,aLoaded.FName);
  aLoaded.FSiteRef:=aLoaded.FSite;
  try
    Result:=aLoaded.FPlugin.Initialize(aLoaded.FSiteRef);
    if not Result then
      Error(aLoaded.FFileName,'Initialize returned False');
  except
    on E: Exception do
      Error(aLoaded.FFileName,'Initialize failed: '+E.Message);
  end;
  if Result then
    FPlugins.Add(aLoaded)
  else
    Stop(aLoaded);
end;

procedure TOhsPluginManager.Stop(aLoaded: TOhsLoadedPlugin);
begin
  if aLoaded.FPlugin<>nil then
    try
      aLoaded.FPlugin.Finalize;
    except
      on E: Exception do
        Error(aLoaded.FFileName,'Finalize failed: '+E.Message);
    end;
  if aLoaded.FSite<>nil then
    aLoaded.FSite.Detach;
  // release the plugin's objects while its code is still loaded
  aLoaded.FPlugin:=nil;
  aLoaded.FSite:=nil;
  aLoaded.FSiteRef:=nil;
  if aLoaded.FLibrary<>NilHandle then
  begin
    UnloadLibrary(aLoaded.FLibrary);
    aLoaded.FLibrary:=NilHandle;
  end;
end;

function TOhsPluginManager.LoadPlugin(const aFileName: string): TOhsLoadedPlugin;
var
  lLib: TLibHandle;
  lEntry: TOhsPluginEntry;
  lPlugin: IOhsPlugin;
  lCode: Integer;
begin
  Result:=nil;
  lLib:=dynlibs.LoadLibrary(aFileName);
  if lLib=NilHandle then
  begin
    Error(aFileName,'cannot load the library');
    Exit;
  end;
  lEntry:=TOhsPluginEntry(GetProcedureAddress(lLib,OHS_PLUGIN_ENTRY));
  if not Assigned(lEntry) then
  begin
    UnloadLibrary(lLib);
    Error(aFileName,'not a plugin: it does not export '+OHS_PLUGIN_ENTRY);
    Exit;
  end;
  lPlugin:=nil;
  try
    lCode:=lEntry(OHS_PLUGIN_API_VERSION,lPlugin);
  except
    on E: Exception do
    begin
      lCode:=OHS_E_FAILED;
      FLastError:=E.Message;
    end;
  end;
  if (lCode<>OHS_OK) or (lPlugin=nil) then
  begin
    lPlugin:=nil;
    UnloadLibrary(lLib);
    if lCode=OHS_E_API_VERSION then
      Error(aFileName,Format('the plugin does not support API version %d',[OHS_PLUGIN_API_VERSION]))
    else
      Error(aFileName,Format('the entry point failed with %d',[lCode]));
    Exit;
  end;
  Result:=TOhsLoadedPlugin.Create;
  Result.FFileName:=aFileName;
  Result.FLibrary:=lLib;
  Result.FPlugin:=lPlugin;
  lPlugin:=nil;
  if not Start(Result) then
    FreeAndNil(Result);
end;

function TOhsPluginManager.AddPlugin(const aPlugin: IOhsPlugin): TOhsLoadedPlugin;
begin
  Result:=nil;
  if aPlugin=nil then
    Exit;
  Result:=TOhsLoadedPlugin.Create;
  Result.FLibrary:=NilHandle;
  Result.FPlugin:=aPlugin;
  if not Start(Result) then
    FreeAndNil(Result);
end;

function TOhsPluginManager.LoadFromDirectory(const aDirectory: string; const aMask: string): Integer;
var
  lInfo: TSearchRec;
  lDir, lMask: string;
  lFiles: TStringList;
  i: Integer;
begin
  Result:=0;
  lDir:=IncludeTrailingPathDelimiter(aDirectory);
  lMask:=aMask;
  if lMask='' then
    lMask:='*.'+SharedSuffix;
  lFiles:=TStringList.Create;
  try
    if FindFirst(lDir+lMask,faAnyFile,lInfo)=0 then
      try
        repeat
          if (lInfo.Attr and faDirectory)=0 then
            lFiles.Add(lDir+lInfo.Name);
        until FindNext(lInfo)<>0;
      finally
        FindClose(lInfo);
      end;
    // a fixed order, so plugins that use the same place line up the same way each time
    lFiles.Sort;
    for i:=0 to lFiles.Count-1 do
      if LoadPlugin(lFiles[i])<>nil then
        Inc(Result);
  finally
    lFiles.Free;
  end;
end;

function TOhsPluginManager.FindPlugin(const aId: string): TOhsLoadedPlugin;
var
  i: Integer;
begin
  for i:=0 to FPlugins.Count-1 do
  begin
    Result:=TOhsLoadedPlugin(FPlugins[i]);
    if SameText(Result.FId,aId) then
      Exit;
  end;
  Result:=nil;
end;

procedure TOhsPluginManager.UnloadPlugin(aPlugin: TOhsLoadedPlugin);
begin
  if (aPlugin=nil) or (FPlugins.IndexOf(aPlugin)<0) then
    Exit;
  FPlugins.Remove(aPlugin);
  Stop(aPlugin);
  aPlugin.Free;
end;

procedure TOhsPluginManager.UnloadAll;
begin
  while FPlugins.Count>0 do
    UnloadPlugin(TOhsLoadedPlugin(FPlugins[FPlugins.Count-1]));
end;

end.
