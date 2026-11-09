{ ohsPluginFramework - plugins on an ohsGantt chart.

    Chart := TohsGanttChart.Create(Self);
    GanttAdapter := TOhsGanttAdapter.Create('main', Chart);   // 'gantt:main'
    Registry.RegisterAdapter(GanttAdapter);

  - Columns: a plugin column on 'gantt:<id>' is added to the chart's table. Its cells
    come from the plugin, through the chart's OnCellText; a handler the host set
    before the adapter was made still runs for the other fields.
  - Context: while an activity is selected, every command and event gets its
    activity.* values (see FillActivityContext), so a ribbon button can act on it.
  - Events: OHS_EVENT_SELECTION when the selected activity changes, with source
    'gantt:<id>'. The host's own OnSelectionChanged handler still runs.

  Set OnActivityContext to hand plugins more of an activity than the standard keys. }
unit ohs.plugin.fresnel.gantt;

{$mode Delphi}{$H+}
{$INTERFACES COM}

interface

uses
  Classes, SysUtils,
  Fresnel.Classes, Fresnel.DOM, Fresnel.Grid,
  ohssched.model, ohssched.layout, ohsgantt.view, ohsgantt.chart,
  ohs.plugin.api, ohs.plugin.helpers, ohs.plugin.registry, ohs.plugin.fresnel.common;

const
  cOhsGanttFieldPrefix = 'ohs:';

  // Context keys besides OHS_CTX_ACTIVITY_CODE and OHS_CTX_ACTIVITY_NAME
  OHS_CTX_ACTIVITY_DURATION = 'activity.duration';
  OHS_CTX_ACTIVITY_START    = 'activity.start';      // yyyy-mm-dd, early start
  OHS_CTX_ACTIVITY_FINISH   = 'activity.finish';     // yyyy-mm-dd, early finish
  OHS_CTX_ACTIVITY_FLOAT    = 'activity.totalfloat';
  OHS_CTX_ACTIVITY_CRITICAL = 'activity.critical';   // 'true' or 'false'
  OHS_CTX_ACTIVITY_MILESTONE = 'activity.milestone';
  OHS_CTX_ROW_KIND          = 'row.kind';            // 'activity', 'group' or 'line'
  OHS_CTX_ROW_CAPTION       = 'row.caption';

type
  TOhsActivityContextEvent = procedure(Sender: TObject; aActivity: TActivity; aContext: TOhsContext) of object;

  TOhsGanttAdapter = class(TOhsFresnelAdapter)
  private
    FId: string;
    FChart: TohsGanttChart;
    FPrevCellText: TohsGanttCellTextEvent;
    FPrevSelection: TNotifyEvent;
    FOnActivityContext: TOhsActivityContextEvent;
    procedure ChartCellText(Sender: TObject; aActivity: TActivity; const aRow: TViewRow;
      const aField: string; var aText: string);
    procedure ChartSelectionChanged(Sender: TObject);
    function ColumnOf(aItem: TOhsContribution): TGridColumn;
  protected
    procedure ComponentFreed(aComponent: TComponent); override;
  public
    constructor Create(const aId: string; aChart: TohsGanttChart);
    destructor Destroy; override;
    function Handles(const aLocation: TOhsLocation): Boolean; override;
    procedure Add(aItem: TOhsContribution); override;
    procedure Remove(aItem: TOhsContribution); override;
    procedure Update(aItem: TOhsContribution); override;
    procedure AddContext(aContext: TOhsContext); override;
    // The activity.* keys; aActivity may be nil
    procedure FillActivityContext(aActivity: TActivity; aContext: TOhsContext); virtual;
    property Id: string read FId;
    property Chart: TohsGanttChart read FChart;
    property OnActivityContext: TOhsActivityContextEvent read FOnActivityContext write FOnActivityContext;
  end;

function OhsSchedDateText(aDate: TSchedDate): string;

implementation

function OhsSchedDateText(aDate: TSchedDate): string;
begin
  if aDate<=0 then
    Result:=''
  else
    Result:=FormatDateTime('yyyy-mm-dd',aDate);
end;

{ TOhsGanttAdapter }

constructor TOhsGanttAdapter.Create(const aId: string; aChart: TohsGanttChart);
begin
  inherited Create;
  FId:=aId;
  FChart:=aChart;
  FPrevCellText:=FChart.OnCellText;
  FChart.OnCellText:=ChartCellText;
  FPrevSelection:=FChart.OnSelectionChanged;
  FChart.OnSelectionChanged:=ChartSelectionChanged;
  Watch(FChart);
end;

destructor TOhsGanttAdapter.Destroy;
begin
  inherited Destroy;
  if FChart<>nil then
  begin
    FChart.OnCellText:=FPrevCellText;
    FChart.OnSelectionChanged:=FPrevSelection;
    Unwatch(FChart);
  end;
end;

procedure TOhsGanttAdapter.ComponentFreed(aComponent: TComponent);
begin
  if aComponent=FChart then
    FChart:=nil;
end;

function TOhsGanttAdapter.Handles(const aLocation: TOhsLocation): Boolean;
begin
  Result:=(FChart<>nil) and (aLocation.Kind='gantt') and SameText(aLocation.Target,FId);
end;

procedure TOhsGanttAdapter.ChartCellText(Sender: TObject; aActivity: TActivity;
  const aRow: TViewRow; const aField: string; var aText: string);
var
  lItem: TOhsContribution;
  lContext: TOhsContext;
  lIntf: IOhsContext;
begin
  if Copy(aField,1,Length(cOhsGanttFieldPrefix))<>cOhsGanttFieldPrefix then
  begin
    if Assigned(FPrevCellText) then
      FPrevCellText(Sender,aActivity,aRow,aField,aText);
    Exit;
  end;
  aText:='';
  if Registry=nil then
    Exit;
  lItem:=Registry.Find(StrToIntDef(Copy(aField,Length(cOhsGanttFieldPrefix)+1,MaxInt),0));
  if (lItem=nil) or (lItem.Adapter<>Self) then
    Exit;
  lContext:=TOhsContext.Create;
  lIntf:=lContext;
  lContext.SetValue('gantt',FId);
  case aRow.Kind of
    vrActivity: lContext.SetValue(OHS_CTX_ROW_KIND,'activity');
    vrGroup: lContext.SetValue(OHS_CTX_ROW_KIND,'group');
  else
    lContext.SetValue(OHS_CTX_ROW_KIND,'line');
  end;
  lContext.SetValue(OHS_CTX_ROW_CAPTION,aRow.Caption);
  FillActivityContext(aActivity,lContext);
  aText:=lItem.CellText(lIntf);
end;

procedure TOhsGanttAdapter.ChartSelectionChanged(Sender: TObject);
var
  lContext: TOhsContext;
begin
  if Assigned(FPrevSelection) then
    FPrevSelection(Sender);
  if Registry=nil then
    Exit;
  lContext:=Registry.BuildContext;
  lContext.SetValue(OHS_CTX_SOURCE,'gantt:'+FId);
  Registry.Publish(OHS_EVENT_SELECTION,lContext);
end;

function TOhsGanttAdapter.ColumnOf(aItem: TOhsContribution): TGridColumn;
var
  i: Integer;
  lField: string;
begin
  Result:=nil;
  if FChart=nil then
    Exit;
  lField:=cOhsGanttFieldPrefix+IntToStr(aItem.Handle);
  for i:=0 to FChart.Grid.Columns.Count-1 do
    if FChart.Grid.Columns[i].FieldName=lField then
      Exit(FChart.Grid.Columns[i]);
end;

procedure TOhsGanttAdapter.Add(aItem: TOhsContribution);
var
  lWidth: Integer;
begin
  if (FChart=nil) or (aItem.Kind<>ockColumn) then
    Exit;
  lWidth:=aItem.Width;
  if lWidth<=0 then
    lWidth:=80;
  FChart.Grid.AddColumn(aItem.Caption,cOhsGanttFieldPrefix+IntToStr(aItem.Handle),lWidth);
  aItem.Element:=FChart.Grid;
end;

procedure TOhsGanttAdapter.Remove(aItem: TOhsContribution);
var
  lColumn: TGridColumn;
begin
  lColumn:=ColumnOf(aItem);
  aItem.Element:=nil;
  if lColumn<>nil then
    lColumn.Free;
end;

procedure TOhsGanttAdapter.Update(aItem: TOhsContribution);
begin
  if FChart<>nil then
    FChart.Grid.Invalidate;
end;

procedure TOhsGanttAdapter.FillActivityContext(aActivity: TActivity; aContext: TOhsContext);
begin
  if aActivity<>nil then
  begin
    aContext.SetValue(OHS_CTX_ACTIVITY_CODE,aActivity.Code);
    aContext.SetValue(OHS_CTX_ACTIVITY_NAME,aActivity.Name);
    aContext.SetValue(OHS_CTX_ACTIVITY_DURATION,IntToStr(aActivity.Duration));
    aContext.SetValue(OHS_CTX_ACTIVITY_START,OhsSchedDateText(aActivity.EarlyStart));
    aContext.SetValue(OHS_CTX_ACTIVITY_FINISH,OhsSchedDateText(aActivity.EarlyFinish));
    aContext.SetValue(OHS_CTX_ACTIVITY_FLOAT,IntToStr(aActivity.TotalFloat));
    aContext.SetValue(OHS_CTX_ACTIVITY_CRITICAL,LowerCase(BoolToStr(aActivity.Critical,True)));
    aContext.SetValue(OHS_CTX_ACTIVITY_MILESTONE,LowerCase(BoolToStr(aActivity.IsMilestone,True)));
  end;
  if Assigned(FOnActivityContext) then
    FOnActivityContext(Self,aActivity,aContext);
end;

procedure TOhsGanttAdapter.AddContext(aContext: TOhsContext);
begin
  if (FChart=nil) or (FChart.Selected=nil) then
    Exit;
  aContext.SetValue('gantt',FId);
  FillActivityContext(FChart.Selected,aContext);
end;

end.
