program testframework;

{ Checks the parts of ohsPluginFramework that need no screen: locations, the
  registry with a fake adapter, plugin life cycle and the ohsMultiGrid adapter's
  provider. Pass the plugins folder of the demo to also load the plugin libraries:

    testframework.exe ..\demo\fresnel\out\i386-win32\plugins

  Ends with "TESTS PASSED" and exit code 0, or lists the failures and exits with 1. }

{$mode Delphi}{$H+}
{$apptype console}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Classes, SysUtils,
  ohsmultigrid.data, ohsmultigrid.grid,
  ohs.plugin.api, ohs.plugin.helpers, ohs.plugin.registry, ohs.plugin.manager,
  ohs.plugin.fresnel.multigrid;

var
  Failures: Integer = 0;
  Checks: Integer = 0;

procedure Check(aOk: Boolean; const aWhat: string);
begin
  Inc(Checks);
  if not aOk then
  begin
    Inc(Failures);
    Writeln('  FAIL  ',aWhat);
  end;
end;

type
  { Records what it is asked to show, as 'location|caption' lines. }
  TFakeAdapter = class(TOhsUIAdapter)
  public
    Kind: string;
    Shown: TStringList;
    Updates: Integer;
    constructor Create(const aKind: string);
    destructor Destroy; override;
    function Handles(const aLocation: TOhsLocation): Boolean; override;
    procedure Add(aItem: TOhsContribution); override;
    procedure Remove(aItem: TOhsContribution); override;
    procedure Update(aItem: TOhsContribution); override;
    procedure AddContext(aContext: TOhsContext); override;
  end;

  TTestPlugin = class(TOhsPlugin)
  public
    Executed: string;
    Events: Integer;
    Cmd: TOhsCommand;
    procedure Run(Sender: TOhsCommand; const aContext: IOhsContext);
    procedure Event(const aEvent: string; const aContext: IOhsContext);
    function Cell(const aRow: IOhsContext; const aField: string): string;
  protected
    procedure DoInitialize; override;
  end;

constructor TFakeAdapter.Create(const aKind: string);
begin
  inherited Create;
  Kind:=aKind;
  Shown:=TStringList.Create;
end;

destructor TFakeAdapter.Destroy;
begin
  inherited Destroy; // unregisters first, which calls Remove
  Shown.Free;
end;

function TFakeAdapter.Handles(const aLocation: TOhsLocation): Boolean;
begin
  Result:=aLocation.Kind=Kind;
end;

procedure TFakeAdapter.Add(aItem: TOhsContribution);
var
  lCaption: string;
begin
  if aItem.Kind=ockCommand then
    lCaption:=aItem.ReadCommand.Caption
  else
    lCaption:=aItem.Caption;
  // keep the order the registry asks for
  Shown.InsertObject(Registry.IndexAt(aItem),aItem.Location.Text+'|'+lCaption,aItem);
  aItem.Element:=Self;
end;

procedure TFakeAdapter.Remove(aItem: TOhsContribution);
var
  i: Integer;
begin
  i:=Shown.IndexOfObject(aItem);
  if i>=0 then
    Shown.Delete(i);
end;

procedure TFakeAdapter.Update(aItem: TOhsContribution);
begin
  Inc(Updates);
end;

procedure TFakeAdapter.AddContext(aContext: TOhsContext);
begin
  aContext.SetValue('fake.'+Kind,'yes');
end;

procedure TTestPlugin.Run(Sender: TOhsCommand; const aContext: IOhsContext);
begin
  Executed:=OhsContextValue(aContext,OHS_CTX_LOCATION)+'/'+OhsContextValue(aContext,'fake.toolbar');
end;

procedure TTestPlugin.Event(const aEvent: string; const aContext: IOhsContext);
begin
  Inc(Events);
end;

function TTestPlugin.Cell(const aRow: IOhsContext; const aField: string): string;
begin
  Result:=aField+'@'+OhsContextValue(aRow,OHS_CTX_ROW)+'/'+OhsContextValue(aRow,'key');
end;

procedure TTestPlugin.DoInitialize;
begin
  Cmd:=TOhsCommand.Create('t.run','Run',Run);
  AddCommand('toolbar:main',Cmd,OHS_SIZE_DEFAULT,20);
  AddCommand('toolbar:main',TOhsCommand.Create('t.first','First'),OHS_SIZE_DEFAULT,10);
  AddCommand('later:x',TOhsCommand.Create('t.later','Later'));
  Subscribe('ping',Event);
end;

procedure TestLocations;
var
  l: TOhsLocation;
begin
  l:=OhsParseLocation('ribbon:Home/My Group');
  Check((l.Kind='ribbon') and (l.Target='Home') and (l.Part(1)='My Group') and (l.PartCount=2),'parse ribbon location');
  l:=OhsParseLocation('Ribbon.Quick:');
  Check((l.Kind='ribbon.quick') and (l.PartCount=0),'parse location without target');
  l:=OhsParseLocation('menu:grid.context');
  Check((l.Kind='menu') and (l.Target='grid.context'),'dots belong to the target');
end;

procedure TestRegistry;
var
  lRegistry: TOhsUIRegistry;
  lManager: TOhsPluginManager;
  lToolbar, lLater: TFakeAdapter;
  lPlugin: TTestPlugin;
  lRef: IOhsPlugin;
  lLoaded: TOhsLoadedPlugin;
  lHost: IOhsHost;
  i: Integer;
begin
  lRegistry:=TOhsUIRegistry.Create;
  lManager:=TOhsPluginManager.Create(lRegistry);
  lToolbar:=TFakeAdapter.Create('toolbar');
  lLater:=TFakeAdapter.Create('later');
  try
    lRegistry.RegisterAdapter(lToolbar);
    lPlugin:=TTestPlugin.Create('test.plugin','Test','1');
    lRef:=lPlugin;
    lLoaded:=lManager.AddPlugin(lRef);
    Check(lLoaded<>nil,'in-process plugin added');
    Check(lManager.AddPlugin(TTestPlugin.Create('test.plugin','Again','1'))=nil,'same id refused');
    Check(lToolbar.Shown.CommaText='toolbar:main|First,toolbar:main|Run','order by order, not by arrival: '+lToolbar.Shown.CommaText);
    Check(lRegistry.HasLocation('toolbar:main') and not lRegistry.HasLocation('later:x'),'HasLocation');

    // a location that appears later gets what was waiting for it
    lRegistry.RegisterAdapter(lLater);
    Check(lLater.Shown.CommaText='later:x|Later','pending contribution handed over');

    // run a command as an adapter does
    for i:=0 to lRegistry.Count-1 do
      if lRegistry.Items[i].ReadCommand.Id='t.run' then
        lToolbar.Execute(lRegistry.Items[i]);
    Check(lPlugin.Executed='toolbar:main/yes','command gets location and adapter context: '+lPlugin.Executed);

    lPlugin.Cmd.Caption:='Run now';
    lPlugin.Cmd.Changed;
    Check(lToolbar.Updates=1,'CommandChanged reaches the adapter');

    lRegistry.Publish('ping');
    lRegistry.Publish('other');
    Check(lPlugin.Events=1,'event delivered to its subscriber only');

    lHost:=lLoaded.Site; // a plugin keeping its host after it is unloaded
    lManager.UnloadPlugin(lLoaded);
    Check(lRegistry.Count=0,'unload removes every contribution');
    Check((lToolbar.Shown.Count=0) and (lLater.Shown.Count=0),'adapters asked to remove them');
    lRegistry.Publish('ping');
    Check(lPlugin.Events=1,'no events after unload');
    Check(lHost.UI.AddCommand('toolbar:main',TOhsCommand.Create('x','x'),0,0)=0,'a detached host does nothing');
    lHost:=nil;
    lRef:=nil;
  finally
    lManager.Free;
    lToolbar.Free;
    lLater.Free;
    lRegistry.Free;
  end;
end;

procedure TestLibraries(const aDir: string);
var
  lRegistry: TOhsUIRegistry;
  lManager: TOhsPluginManager;
  lToolbar: TFakeAdapter;
begin
  lRegistry:=TOhsUIRegistry.Create;
  lManager:=TOhsPluginManager.Create(lRegistry);
  lToolbar:=TFakeAdapter.Create('toolbar');
  try
    lRegistry.RegisterAdapter(lToolbar);
    Check(lManager.LoadFromDirectory(aDir)=2,'two plugin libraries load: '+lManager.LastError);
    Check(lManager.FindPlugin('com.owlhat.demo.hello')<>nil,'hello plugin found by id');
    Check(lToolbar.Shown.Count=3,'hello plugin put three items on the toolbar');
    Check(lRegistry.Count>3,'and kept the others for locations to come');
    Check(lManager.LoadPlugin(IncludeTrailingPathDelimiter(aDir)+'hello.dll')=nil,'loading it twice is refused');
    Check(lManager.LoadPlugin(ParamStr(0))=nil,'a library without the entry point is refused');
    lManager.UnloadAll;
    Check((lRegistry.Count=0) and (lToolbar.Shown.Count=0),'libraries unloaded cleanly');
  finally
    lManager.Free;
    lToolbar.Free;
    lRegistry.Free;
  end;
end;

procedure TestMultiGrid;
var
  lRegistry: TOhsUIRegistry;
  lManager: TOhsPluginManager;
  lGrid: TohsMultiGrid;
  lProvider: TohsMultiGridTableProvider;
  lAdapter: TOhsMultiGridAdapter;
  lPlugin: TTestPlugin;
  lField: string;
  i: Integer;
begin
  lRegistry:=TOhsUIRegistry.Create;
  lManager:=TOhsPluginManager.Create(lRegistry);
  lGrid:=TohsMultiGrid.Create(nil);
  lProvider:=TohsMultiGridTableProvider.Create(nil);
  try
    lProvider.Fields.CommaText:='name,qty';
    lProvider.AddRow(['A','1']);
    lProvider.AddRow(['B','2']);
    lGrid.AddColumn('Name','name',80);
    lGrid.Provider:=lProvider;
    lAdapter:=TOhsMultiGridAdapter.Create('orders',lGrid);
    lAdapter.OnRowContext:=nil;
    lRegistry.RegisterAdapter(lAdapter);
    Check(lGrid.Provider<>lProvider,'adapter stands in front of the provider');
    Check(lGrid.Provider.GetCellText(1,'name')='B','host cells pass through');
    lPlugin:=TTestPlugin.Create('grid.plugin','Grid','1');
    lManager.AddPlugin(lPlugin);
    lPlugin.AddColumn('grid:orders','Extra','extra',60,lPlugin.Cell);
    Check(lGrid.Columns.Count=2,'plugin column added to the grid');
    lField:=lGrid.Columns[1].FieldName;
    Check(lGrid.Provider.GetCellText(1,lField)='extra@1/','plugin cell text: '+lGrid.Provider.GetCellText(1,lField));
    Check(not lGrid.Provider.CanEditCell(1,lField),'plugin cells are read only');
    lManager.UnloadAll;
    Check(lGrid.Columns.Count=1,'column gone with the plugin');
    lAdapter.Free;
    Check(lGrid.Provider=lProvider,'provider restored when the adapter goes');
    i:=lGrid.Columns.Count;
    Check(i=1,'grid untouched');
  finally
    lManager.Free;
    lGrid.Free;
    lProvider.Free;
    lRegistry.Free;
  end;
end;

begin
  TestLocations;
  TestRegistry;
  TestMultiGrid;
  if ParamCount>0 then
    TestLibraries(ParamStr(1));
  Writeln(Checks,' checks, ',Failures,' failed');
  if Failures=0 then
    Writeln('TESTS PASSED')
  else
    ExitCode:=1;
end.
