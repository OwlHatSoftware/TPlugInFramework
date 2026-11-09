{ The ohsPluginFramework demo host: a Fresnel form with an ohsRibbon, a toolbar, a
  Gantt chart with a context menu and a side area, all open to plugins.

  Switches for scripted checks:
    --selftest          print what the plugins added, run some of it, unload and load
                        the plugins again, print again, and exit with 1 on a failure
    --capture=file.png  write a screenshot (after the self test, when both are given)
    --tab=caption       show this ribbon tab before the capture
    --noplugins         start without loading plugins }
unit hostform;

{$mode Delphi}{$H+}

interface

uses
  Classes, SysUtils, Fresnel.Classes, Fresnel.DOM, Fresnel.Forms, Fresnel.Controls,
  Fresnel.Menus, Fresnel.Edit, Fresnel.AnimationTimer, Fresnel.App, Fresnel.Grid, FCL.Events,
  ohssched.model, ohssched.document, ohsgantt.chart, ohsmultigrid.image,
  ohsribbon.model.sizing, ohsribbon.ui.ribbon,
  ohs.plugin.api, ohs.plugin.helpers, ohs.plugin.registry, ohs.plugin.manager,
  ohs.plugin.fresnel.common, ohs.plugin.fresnel.panels, ohs.plugin.fresnel.ribbon,
  ohs.plugin.fresnel.gantt;

type
  TMainForm = class(TFresnelForm)
  private
    FRegistry: TOhsUIRegistry;
    FPlugins: TOhsPluginManager;
    FRibbonAdapter: TOhsRibbonAdapter;
    FToolBarAdapter: TOhsToolBarAdapter;
    FMenuAdapter: TOhsMenuAdapter;
    FPanelAdapter: TOhsPanelAdapter;
    FGanttAdapter: TOhsGanttAdapter;
    FRibbon: TRibbon;
    FToolBar: TDiv;
    FSide: TDiv;
    FChart: TohsGanttChart;
    FPopup: TPopupMenu;
    FStatus: TLabel;
    FSchedule: TOhsSchedule;
    FTimer: TFresnelAnimationTimer;
    FStep: Integer;
    FFailures: Integer;
    FCapture: string;
    FSelfTest: Boolean;
    FLastMessage: string;
    procedure BuildSchedule;
    procedure BuildUI;
    procedure LoadPlugins;
    procedure UnloadPlugins;
    procedure LoadClick(aEvent: TAbstractEvent);
    procedure UnloadClick(aEvent: TAbstractEvent);
    procedure ZoomClick(aEvent: TAbstractEvent);
    procedure ZoomMenuClick(Sender: TObject);
    procedure ChartSelectionChanged(Sender: TObject);
    procedure PluginMessage(aKind: Integer; const aText: string);
    procedure PluginLog(const aText: string);
    procedure PluginError(const aFileName, aMessage: string);
    procedure Tick(Sender: TObject);
    // self test
    procedure Check(aOk: Boolean; const aWhat: string);
    procedure Dump(const aTitle: string);
    function FindContribution(const aCommandId, aKind: string): TOhsContribution;
    function FindPanelElement(aRoot: TFresnelElement; aClass: TClass; const aCaption: string): TFresnelElement;
    function PluginColumnTexts(aRow: Integer): string;
    function VisibleRibbonCaptions: string;
    procedure RunChecks;
    function HasSwitch(const aName: string; out aValue: string): Boolean;
  public
    constructor CreateNew(aOwner: TComponent); override;
    destructor Destroy; override;
    procedure Show; override;
  end;

var
  MainForm: TMainForm;

implementation

const
  cCSS =
    'body { margin:0; padding:0; display:flex; flex-direction:column; height:100%; background-color:#f4f6f8; color:#1f2733; font-size:13px; }'#10+
    '.toolbar { background-color:#e6eaef; border-bottom:1px solid #c5ccd4; min-height:30px; }'#10+
    '.main { flex:1 1 0; display:flex; flex-direction:row; min-height:0; }'#10+
    'ganttchart { flex:1 1 0; min-width:0; }'#10+
    '.side { width:260px; flex:0 0 260px; display:flex; flex-direction:column; gap:6px; padding:6px; border-left:1px solid #c5ccd4; background-color:#fafbfc; overflow:auto; }'#10+
    '.status { padding:4px 8px; border-top:1px solid #c5ccd4; background-color:#e6eaef; }'#10;

  cContext = 'Activity tools';

{ TMainForm }

constructor TMainForm.CreateNew(aOwner: TComponent);
var
  lValue: string;
begin
  inherited CreateNew(aOwner);
  Caption:='ohsPluginFramework demo';
  FormWidth:=1280;
  FormHeight:=720;
  Application.ColorScheme:=fcsLight;
  Stylesheet.Text:=cCSS+cOhsPluginCSS;
  FSelfTest:=HasSwitch('selftest',lValue);
  HasSwitch('capture',FCapture);

  FRegistry:=TOhsUIRegistry.Create;
  FRegistry.Info.Values[OHS_HOST_NAME]:='ohsPluginFramework demo';
  FRegistry.Info.Values[OHS_HOST_VERSION]:='1.0';
  FRegistry.Info.Values[OHS_HOST_UI]:='fresnel';
  FRegistry.Info.Values[OHS_HOST_PLUGINDIR]:=ExtractFilePath(ParamStr(0))+'plugins';
  FRegistry.OnMessage:=PluginMessage;
  FRegistry.OnLog:=PluginLog;
  FPlugins:=TOhsPluginManager.Create(FRegistry);
  FPlugins.OnError:=PluginError;

  BuildSchedule;
  BuildUI;
  if not HasSwitch('noplugins',lValue) then
    LoadPlugins;
end;

destructor TMainForm.Destroy;
begin
  FreeAndNil(FTimer);
  // plugins first, while the controls they use are still there; then the adapters
  FreeAndNil(FPlugins);
  FreeAndNil(FGanttAdapter);
  FreeAndNil(FPanelAdapter);
  FreeAndNil(FMenuAdapter);
  FreeAndNil(FToolBarAdapter);
  FreeAndNil(FRibbonAdapter);
  FreeAndNil(FRegistry);
  if FresnelApplication<>nil then
    FresnelApplication.Terminate;
  inherited Destroy;
end;

procedure TMainForm.BuildSchedule;
var
  lProject: TScheduleProject;
  a, b, c, d, e, f, g: TActivity;
begin
  FSchedule:=TOhsSchedule.Create(Self);
  lProject:=FSchedule.Project;
  lProject.ProjectStart:=SchedDate(2027,1,4);
  a:=lProject.AddActivity('A100','Site setup',3);
  b:=lProject.AddActivity('A110','Excavate',8);
  c:=lProject.AddActivity('A120','Foundations',12);
  d:=lProject.AddActivity('A130','Order steel',6);
  e:=lProject.AddActivity('A140','Steel frame',15);
  f:=lProject.AddActivity('A150','Landscaping',5);
  g:=lProject.AddActivity('A160','Handover',0);
  lProject.AddRelationship(a,b);
  lProject.AddRelationship(b,c);
  lProject.AddRelationship(a,d);
  lProject.AddRelationship(c,e);
  lProject.AddRelationship(d,e);
  lProject.AddRelationship(b,f);
  lProject.AddRelationship(e,g);
  lProject.AddRelationship(f,g);
  FSchedule.Reschedule;
end;

procedure TMainForm.BuildUI;
var
  lBody: TBody;
  lMain: TDiv;
  lTab: TRibbonTab;
  lGroup: TRibbonGroup;
  lItem: TMenuItem;
begin
  lBody:=TBody.Create(Self);
  lBody.Parent:=Self;

  FRibbon:=TRibbon.Create(Self);
  FRibbon.Parent:=lBody;
  lTab:=FRibbon.AddTab('Home');
  lGroup:=lTab.AddGroup('Plugins');
  lGroup.AddButton('Load plugins',risLarge,LoadClick);
  lGroup.AddButton('Unload plugins',risLarge,UnloadClick);
  lGroup:=lTab.AddGroup('View');
  lGroup.AddButton('Zoom to fit',risLarge,ZoomClick);

  FToolBar:=TDiv.Create(Self);
  FToolBar.AddCSSClass('toolbar');
  FToolBar.Parent:=lBody;

  lMain:=TDiv.Create(Self);
  lMain.AddCSSClass('main');
  lMain.Parent:=lBody;

  FChart:=TohsGanttChart.Create(Self);
  FChart.Parent:=lMain;
  FChart.Schedule:=FSchedule;
  // the host's own handler; the gantt adapter chains it
  FChart.OnSelectionChanged:=ChartSelectionChanged;

  FSide:=TDiv.Create(Self);
  FSide.AddCSSClass('side');
  FSide.Parent:=lMain;

  FPopup:=TPopupMenu.Create(Self);
  lItem:=TMenuItem.Create(Self);
  lItem.Caption:='Zoom to fit';
  lItem.OnClick:=ZoomMenuClick;
  FPopup.Items.Add(lItem);
  FPopup.AddHook(FChart.Grid);

  FStatus:=TLabel.Create(Self);
  FStatus.AddCSSClass('status');
  FStatus.Caption:='Ready';
  FStatus.Parent:=lBody;

  // Open the UI to plugins. Each adapter makes one kind of location exist.
  FRibbonAdapter:=TOhsRibbonAdapter.Create(FRibbon);
  FRegistry.RegisterAdapter(FRibbonAdapter);
  FToolBarAdapter:=TOhsToolBarAdapter.Create('main',FToolBar);
  FRegistry.RegisterAdapter(FToolBarAdapter);
  FMenuAdapter:=TOhsMenuAdapter.Create('gantt.context',FPopup.Items);
  FRegistry.RegisterAdapter(FMenuAdapter);
  FPanelAdapter:=TOhsPanelAdapter.Create('side',FSide);
  FRegistry.RegisterAdapter(FPanelAdapter);
  FGanttAdapter:=TOhsGanttAdapter.Create('main',FChart);
  FRegistry.RegisterAdapter(FGanttAdapter);
end;

procedure TMainForm.LoadPlugins;
var
  lDir: string;
  lCount, i: Integer;
begin
  lDir:=FRegistry.Info.Values[OHS_HOST_PLUGINDIR];
  lCount:=FPlugins.LoadFromDirectory(lDir);
  for i:=0 to FPlugins.Count-1 do
    PluginLog(Format('loaded %s %s (%s)',[FPlugins[i].Name,FPlugins[i].Version,FPlugins[i].Id]));
  FStatus.Caption:=Format('%d plugin(s) loaded from %s',[lCount,lDir]);
end;

procedure TMainForm.UnloadPlugins;
begin
  FPlugins.UnloadAll;
  FStatus.Caption:='Plugins unloaded';
end;

procedure TMainForm.LoadClick(aEvent: TAbstractEvent);
begin
  if FPlugins.Count=0 then
    LoadPlugins;
end;

procedure TMainForm.UnloadClick(aEvent: TAbstractEvent);
begin
  UnloadPlugins;
end;

procedure TMainForm.ZoomClick(aEvent: TAbstractEvent);
begin
  FChart.ZoomToFit;
end;

procedure TMainForm.ZoomMenuClick(Sender: TObject);
begin
  FChart.ZoomToFit;
end;

procedure TMainForm.ChartSelectionChanged(Sender: TObject);
begin
  FRibbon.SetContextVisible(cContext,FChart.Selected<>nil);
  if FChart.Selected<>nil then
    FStatus.Caption:='Selected '+FChart.Selected.Code+' '+FChart.Selected.Name;
end;

procedure TMainForm.PluginMessage(aKind: Integer; const aText: string);
const
  cKinds: array[OHS_MSG_INFO..OHS_MSG_ERROR] of string = ('','Warning: ','Error: ');
begin
  FLastMessage:=aText;
  if (aKind>=OHS_MSG_INFO) and (aKind<=OHS_MSG_ERROR) then
    FStatus.Caption:=cKinds[aKind]+aText
  else
    FStatus.Caption:=aText;
  PluginLog('message: '+aText);
end;

procedure TMainForm.PluginLog(const aText: string);
begin
  if IsConsole then
  begin
    Writeln(aText);
    Flush(Output);
  end;
end;

procedure TMainForm.PluginError(const aFileName, aMessage: string);
begin
  FStatus.Caption:='Plugin '+ExtractFileName(aFileName)+': '+aMessage;
end;

function TMainForm.HasSwitch(const aName: string; out aValue: string): Boolean;
var
  i: Integer;
  lPrefix: string;
begin
  aValue:='';
  lPrefix:='--'+aName;
  for i:=1 to ParamCount do
    if ParamStr(i)=lPrefix then
      Exit(True)
    else if Copy(ParamStr(i),1,Length(lPrefix)+1)=lPrefix+'=' then
    begin
      aValue:=Copy(ParamStr(i),Length(lPrefix)+2,MaxInt);
      Exit(True);
    end;
  Result:=False;
end;

procedure TMainForm.Show;
begin
  inherited Show;
  if FSelfTest or (FCapture<>'') then
  begin
    FTimer:=TFresnelAnimationTimer.Create;
    FTimer.Interval:=800;
    FTimer.OnTick:=Tick;
    FTimer.Enabled:=True;
  end;
end;

procedure TMainForm.Tick(Sender: TObject);
var
  lValue: string;
  i: Integer;
begin
  Inc(FStep);
  case FStep of
    1:
      begin
        // select an activity, so context, panel and contextual tab have something to show
        FChart.Selected:=FSchedule.Project.FindActivity('A120');
        if HasSwitch('tab',lValue) then
          for i:=0 to FRibbon.TabCount-1 do
            if SameText(FRibbon.Tabs[i].Caption,lValue) then
              FRibbon.ActiveTab:=FRibbon.Tabs[i];
      end;
    2:
      if FSelfTest then
        RunChecks;
    3:
      begin
        FTimer.Enabled:=False;
        if FCapture<>'' then
          try
            SaveFormToPNG(Self,FCapture);
            PluginLog('captured '+FCapture);
          except
            on E: Exception do
            begin
              PluginLog('capture failed: '+E.Message);
              Inc(FFailures);
            end;
          end;
        if FSelfTest then
          PluginLog(Format('SELFTEST %s, %d failure(s)',[BoolToStr(FFailures=0,'PASSED','FAILED'),FFailures]));
        if FFailures>0 then
          ExitCode:=1;
        FresnelApplication.Terminate;
      end;
  end;
end;

{ self test }

procedure TMainForm.Check(aOk: Boolean; const aWhat: string);
begin
  if aOk then
    PluginLog('  ok    '+aWhat)
  else
  begin
    PluginLog('  FAIL  '+aWhat);
    Inc(FFailures);
  end;
end;

function TMainForm.FindContribution(const aCommandId, aKind: string): TOhsContribution;
var
  i: Integer;
begin
  for i:=0 to FRegistry.Count-1 do
  begin
    Result:=FRegistry.Items[i];
    if (Result.Command<>nil) and (Result.Location.Kind=aKind)
      and (Result.ReadCommand.Id=aCommandId) then
      Exit;
  end;
  Result:=nil;
end;

function TMainForm.FindPanelElement(aRoot: TFresnelElement; aClass: TClass; const aCaption: string): TFresnelElement;
var
  i: Integer;
begin
  for i:=0 to aRoot.NodeCount-1 do
  begin
    Result:=aRoot.Nodes[i];
    if (Result is aClass) and ((aCaption='') or ((Result is TTextButton) and (TTextButton(Result).Caption=aCaption))) then
      Exit;
    Result:=FindPanelElement(Result,aClass,aCaption);
    if Result<>nil then
      Exit;
  end;
  Result:=nil;
end;

function TMainForm.PluginColumnTexts(aRow: Integer): string;
var
  i: Integer;
  lColumn: TGridColumn;
begin
  Result:='';
  for i:=0 to FChart.Grid.Columns.Count-1 do
  begin
    lColumn:=FChart.Grid.Columns[i];
    if Copy(lColumn.FieldName,1,4)='ohs:' then
      Result:=Result+lColumn.Title+'='+FChart.Grid.Provider.GetCellText(aRow,lColumn.FieldName)+'; ';
  end;
end;

function TMainForm.VisibleRibbonCaptions: string;
var
  i, j, k: Integer;
  lTab: TRibbonTab;
  lGroup: TRibbonGroup;
begin
  Result:='';
  for i:=0 to FRibbon.TabCount-1 do
  begin
    lTab:=FRibbon.Tabs[i];
    if lTab.Header.HasCSSClass(cRibbonHiddenClass) then
      Continue;
    for j:=0 to lTab.GroupCount-1 do
    begin
      lGroup:=lTab.Groups[j];
      if lGroup.HasCSSClass(cRibbonHiddenClass) then
        Continue;
      for k:=0 to lGroup.ItemCount-1 do
        if (lGroup.Items[k] is TRibbonItem) and not lGroup.Items[k].HasCSSClass(cRibbonHiddenClass) then
          Result:=Result+lTab.Caption+'/'+lGroup.Caption+'/'+TRibbonItem(lGroup.Items[k]).Caption+'; ';
    end;
  end;
  for i:=0 to FRibbon.QuickItemCount-1 do
    if not FRibbon.QuickItems[i].HasCSSClass(cRibbonHiddenClass) then
      Result:=Result+'quick/'+FRibbon.QuickItems[i].Caption+'; ';
end;

procedure TMainForm.Dump(const aTitle: string);
var
  i: Integer;
  s: string;
begin
  PluginLog('== '+aTitle);
  PluginLog('  plugins: '+IntToStr(FPlugins.Count)+', contributions: '+IntToStr(FRegistry.Count));
  PluginLog('  ribbon: '+VisibleRibbonCaptions);
  s:='';
  for i:=0 to FToolBar.NodeCount-1 do
    if FToolBar.Nodes[i] is TButton then
      s:=s+'['+TButton(FToolBar.Nodes[i]).Caption+'] '
    else
      s:=s+'| ';
  PluginLog('  toolbar: '+s);
  s:='';
  for i:=0 to FPopup.Items.Count-1 do
    s:=s+FPopup.Items[i].Caption+'; ';
  PluginLog('  context menu: '+s);
  PluginLog('  side panels: '+IntToStr(FSide.NodeCount));
  s:='';
  for i:=0 to FChart.Grid.Columns.Count-1 do
    s:=s+FChart.Grid.Columns[i].Title+'; ';
  PluginLog('  gantt columns: '+s);
end;

procedure TMainForm.RunChecks;
var
  lItem: TOhsContribution;
  lEdit: TEdit;
  lSave: TFresnelElement;
  lRow: Integer;
  lRibbon: string;
begin
  Dump('after loading');
  Check(FPlugins.Count=2,'two plugins loaded');
  lRibbon:=VisibleRibbonCaptions;
  Check(Pos('Plugins/Hello/Say hello',lRibbon)>0,'hello button on the ribbon');
  Check(Pos('Plugins/Schedule check/Check float',lRibbon)>0,'float button on the ribbon');
  Check(Pos('Activity tools',lRibbon)=0,'contextual tab not counted as a normal tab');
  Check(Pos('quick/Say hello',lRibbon)>0,'quick access button');
  Check(FToolBar.NodeCount=3,'toolbar has button, separator, toggle');
  Check(FPopup.Items.Count=3,'context menu has host item and two plugin items');
  Check(FSide.NodeCount=1,'one panel in the side area');
  Check(FChart.Grid.Columns.Count=8,'two plugin columns in the gantt table');

  // run a command the way a click does
  lItem:=FindContribution('hello.say','toolbar');
  Check((lItem<>nil) and (lItem.Data is TOhsBinding),'toolbar command is bound');
  if (lItem<>nil) and (lItem.Data is TOhsBinding) then
  begin
    FLastMessage:='';
    TOhsBinding(lItem.Data).HandleNotify(nil);
    Check(Pos('Hello, Foundations!',FLastMessage)>0,'command got the selected activity: '+FLastMessage);
  end;
  lItem:=FindContribution('float.check','menu');
  if lItem<>nil then
  begin
    FLastMessage:='';
    TOhsBinding(lItem.Data).HandleNotify(nil);
    Check(Pos('A120 Foundations',FLastMessage)>0,'menu command ran: '+FLastMessage);
  end;

  // the panel: type a note and press Save; the Note column shows it
  lEdit:=TEdit(FindPanelElement(FSide,TEdit,''));
  lSave:=FindPanelElement(FSide,TButton,'Save note');
  Check((lEdit<>nil) and (lSave<>nil),'panel has the edit and the button');
  if (lEdit<>nil) and (lSave<>nil) then
  begin
    lEdit.Value:='Check the rebar';
    TButton(lSave).OnClick(nil);
    lRow:=FChart.View.Layout.RowIndexOfActivity(FSchedule.Project.FindActivity('A120'));
    PluginLog('  row '+IntToStr(lRow)+': '+PluginColumnTexts(lRow));
    Check(Pos('Note=Check the rebar',PluginColumnTexts(lRow))>0,'note column shows the saved note');
    Check(Pos('Float status=critical',PluginColumnTexts(lRow))>0,'float column for a critical activity');
  end;

  // the toggle removes and adds a column
  lItem:=FindContribution('hello.notes','ribbon');
  if lItem<>nil then
  begin
    TOhsBinding(lItem.Data).HandleNotify(nil);
    Check(FChart.Grid.Columns.Count=7,'toggle removed the Note column');
    Check(not TRibbonItem(lItem.Element).Checked,'ribbon toggle shows unchecked');
    TOhsBinding(lItem.Data).HandleNotify(nil);
    Check(FChart.Grid.Columns.Count=8,'toggle added it again');
  end;

  UnloadPlugins;
  Dump('after unloading');
  Check(FRegistry.Count=0,'no contributions left');
  Check(FToolBar.NodeCount=0,'toolbar empty');
  Check(FPopup.Items.Count=1,'only the host menu item');
  Check(FSide.NodeCount=0,'side area empty');
  Check(FChart.Grid.Columns.Count=6,'only the chart''s own columns');
  Check(VisibleRibbonCaptions='Home/Plugins/Load plugins; Home/Plugins/Unload plugins; Home/View/Zoom to fit; ',
    'ribbon back to the host''s own buttons');

  LoadPlugins;
  Dump('after loading again');
  Check(FPlugins.Count=2,'plugins loaded again');
  Check(Pos('Plugins/Hello/Say hello',VisibleRibbonCaptions)>0,'ribbon group shown again');
  Check(FToolBar.NodeCount=3,'toolbar filled again');
  Check(FChart.Grid.Columns.Count=8,'columns back');
end;

end.
