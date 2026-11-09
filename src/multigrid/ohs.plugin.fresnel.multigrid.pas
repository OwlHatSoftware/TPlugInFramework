{ ohsPluginFramework - plugin columns on an ohsMultiGrid.

    Grid.Provider := MyProvider;
    GridAdapter := TOhsMultiGridAdapter.Create('orders', Grid);  // 'grid:orders'
    GridAdapter.OnRowContext := OrderRowContext;                 // optional
    Registry.RegisterAdapter(GridAdapter);

  The adapter puts its own provider in front of the grid's provider. It answers the
  cells of plugin columns by asking the plugin, and passes everything else on.
  To change the grid's provider later, set GridAdapter.Provider instead of
  Grid.Provider.

  What a plugin gets for a row: OHS_CTX_ROW, 'grid' (the id), and whatever
  OnRowContext adds, such as a key that identifies the record. The same goes into
  the context of every command while the grid has a focused row, and into the
  OHS_EVENT_SELECTION event, sent when the focused row changes. }
unit ohs.plugin.fresnel.multigrid;

{$mode Delphi}{$H+}
{$INTERFACES COM}

interface

uses
  Classes, SysUtils,
  Fresnel.Classes, Fresnel.DOM, Fresnel.Grid,
  ohsmultigrid.data, ohsmultigrid.grid,
  ohs.plugin.api, ohs.plugin.helpers, ohs.plugin.registry, ohs.plugin.fresnel.common;

const
  cOhsFieldPrefix = 'ohs:';

type
  TOhsMultiGridAdapter = class;

  { Passes a grid's provider through and adds the plugin columns. }
  TOhsGridProviderWrapper = class(TohsMultiGridProvider)
  private
    FAdapter: TOhsMultiGridAdapter;
    FInner: TohsMultiGridProvider;
    procedure SetInner(aValue: TohsMultiGridProvider);
    procedure InnerChanged(Sender: TObject);
  protected
    procedure Notification(aComponent: TComponent; aOperation: TOperation); override;
  public
    destructor Destroy; override;
    function GetRowCount: Integer; override;
    function GetCellText(aRow: Integer; const aField: string): string; override;
    function IsFlat: Boolean; override;
    procedure GetRowInfo(aRow: Integer; out aInfo: TMGRowInfo); override;
    function ManagesCollapse: Boolean; override;
    procedure ToggleRow(aRow: Integer); override;
    function CanEditCell(aRow: Integer; const aField: string): Boolean; override;
    procedure SetCellText(aRow: Integer; const aField, aText: string); override;
    property Inner: TohsMultiGridProvider read FInner write SetInner;
  end;

  TOhsRowContextEvent = procedure(Sender: TObject; aRow: Integer; aContext: TOhsContext) of object;

  TOhsMultiGridAdapter = class(TOhsFresnelAdapter)
  private
    FId: string;
    FGrid: TohsMultiGrid;
    FWrapper: TOhsGridProviderWrapper;
    FLastFocused: Integer;
    FOnRowContext: TOhsRowContextEvent;
    function GetProvider: TohsMultiGridProvider;
    procedure SetProvider(aValue: TohsMultiGridProvider);
    procedure LinkChanged(Sender: TObject);
    function ColumnOf(aItem: TOhsContribution): TGridColumn;
  protected
    procedure ComponentFreed(aComponent: TComponent); override;
  public
    constructor Create(const aId: string; aGrid: TohsMultiGrid);
    destructor Destroy; override;
    function Handles(const aLocation: TOhsLocation): Boolean; override;
    procedure Add(aItem: TOhsContribution); override;
    procedure Remove(aItem: TOhsContribution); override;
    procedure Update(aItem: TOhsContribution); override;
    procedure AddContext(aContext: TOhsContext); override;
    // What a plugin knows of a row
    procedure FillRowContext(aRow: Integer; aContext: TOhsContext); virtual;
    // The text of a plugin column; '' for any other field
    function PluginCellText(aRow: Integer; const aField: string; out aText: string): Boolean;
    property Id: string read FId;
    property Grid: TohsMultiGrid read FGrid;
    // The grid's own provider, behind the adapter's
    property Provider: TohsMultiGridProvider read GetProvider write SetProvider;
    property OnRowContext: TOhsRowContextEvent read FOnRowContext write FOnRowContext;
  end;

implementation

{ TOhsGridProviderWrapper }

destructor TOhsGridProviderWrapper.Destroy;
begin
  SetInner(nil);
  inherited Destroy;
end;

procedure TOhsGridProviderWrapper.SetInner(aValue: TohsMultiGridProvider);
begin
  if FInner=aValue then
    Exit;
  if FInner<>nil then
  begin
    FInner.RemoveListener(InnerChanged);
    FInner.RemoveFreeNotification(Self);
  end;
  FInner:=aValue;
  if FInner<>nil then
  begin
    FInner.AddListener(InnerChanged);
    FInner.FreeNotification(Self);
  end;
  Changed;
end;

procedure TOhsGridProviderWrapper.InnerChanged(Sender: TObject);
begin
  Changed;
end;

procedure TOhsGridProviderWrapper.Notification(aComponent: TComponent; aOperation: TOperation);
begin
  inherited Notification(aComponent,aOperation);
  if (aOperation=opRemove) and (aComponent=FInner) then
  begin
    FInner:=nil;
    Changed;
  end;
end;

function TOhsGridProviderWrapper.GetRowCount: Integer;
begin
  if FInner=nil then
    Result:=0
  else
    Result:=FInner.GetRowCount;
end;

function TOhsGridProviderWrapper.GetCellText(aRow: Integer; const aField: string): string;
begin
  if (FAdapter<>nil) and FAdapter.PluginCellText(aRow,aField,Result) then
    Exit;
  if FInner=nil then
    Result:=''
  else
    Result:=FInner.GetCellText(aRow,aField);
end;

function TOhsGridProviderWrapper.IsFlat: Boolean;
begin
  Result:=(FInner=nil) or FInner.IsFlat;
end;

procedure TOhsGridProviderWrapper.GetRowInfo(aRow: Integer; out aInfo: TMGRowInfo);
begin
  if FInner=nil then
    aInfo:=Default(TMGRowInfo)
  else
    FInner.GetRowInfo(aRow,aInfo);
end;

function TOhsGridProviderWrapper.ManagesCollapse: Boolean;
begin
  Result:=(FInner<>nil) and FInner.ManagesCollapse;
end;

procedure TOhsGridProviderWrapper.ToggleRow(aRow: Integer);
begin
  if FInner<>nil then
    FInner.ToggleRow(aRow);
end;

function TOhsGridProviderWrapper.CanEditCell(aRow: Integer; const aField: string): Boolean;
begin
  if Copy(aField,1,Length(cOhsFieldPrefix))=cOhsFieldPrefix then
    Exit(False);
  Result:=(FInner<>nil) and FInner.CanEditCell(aRow,aField);
end;

procedure TOhsGridProviderWrapper.SetCellText(aRow: Integer; const aField, aText: string);
begin
  if FInner<>nil then
    FInner.SetCellText(aRow,aField,aText);
end;

{ TOhsMultiGridAdapter }

constructor TOhsMultiGridAdapter.Create(const aId: string; aGrid: TohsMultiGrid);
begin
  inherited Create;
  FId:=aId;
  FGrid:=aGrid;
  FLastFocused:=-1;
  FWrapper:=TOhsGridProviderWrapper.Create(nil);
  FWrapper.FAdapter:=Self;
  FWrapper.Inner:=FGrid.Provider;
  FGrid.Provider:=FWrapper;
  Watch(FGrid);
  if FGrid.Link<>nil then
  begin
    Watch(FGrid.Link);
    FGrid.Link.AddListener(LinkChanged);
  end;
end;

destructor TOhsMultiGridAdapter.Destroy;
begin
  inherited Destroy;
  if FGrid<>nil then
  begin
    if FGrid.Link<>nil then
      FGrid.Link.RemoveListener(LinkChanged);
    if FGrid.Provider=FWrapper then
      FGrid.Provider:=FWrapper.Inner;
    Unwatch(FGrid);
  end;
  FWrapper.FAdapter:=nil;
  FWrapper.Free;
end;

procedure TOhsMultiGridAdapter.ComponentFreed(aComponent: TComponent);
begin
  if aComponent=FGrid then
    FGrid:=nil;
end;

function TOhsMultiGridAdapter.GetProvider: TohsMultiGridProvider;
begin
  Result:=FWrapper.Inner;
end;

procedure TOhsMultiGridAdapter.SetProvider(aValue: TohsMultiGridProvider);
begin
  FWrapper.Inner:=aValue;
  if (FGrid<>nil) and (FGrid.Provider<>FWrapper) then
    FGrid.Provider:=FWrapper;
end;

procedure TOhsMultiGridAdapter.LinkChanged(Sender: TObject);
var
  lContext: TOhsContext;
begin
  if (FGrid=nil) or (FGrid.Link=nil) or (Registry=nil) then
    Exit;
  if FGrid.Link.FocusedRow=FLastFocused then
    Exit;
  FLastFocused:=FGrid.Link.FocusedRow;
  lContext:=Registry.BuildContext;
  lContext.SetValue(OHS_CTX_SOURCE,'grid:'+FId);
  Registry.Publish(OHS_EVENT_SELECTION,lContext);
end;

function TOhsMultiGridAdapter.Handles(const aLocation: TOhsLocation): Boolean;
begin
  Result:=(FGrid<>nil) and (aLocation.Kind='grid') and SameText(aLocation.Target,FId);
end;

function TOhsMultiGridAdapter.ColumnOf(aItem: TOhsContribution): TGridColumn;
var
  i: Integer;
  lField: string;
begin
  Result:=nil;
  if FGrid=nil then
    Exit;
  lField:=cOhsFieldPrefix+IntToStr(aItem.Handle);
  for i:=0 to FGrid.Columns.Count-1 do
    if FGrid.Columns[i].FieldName=lField then
      Exit(FGrid.Columns[i]);
end;

procedure TOhsMultiGridAdapter.Add(aItem: TOhsContribution);
var
  lWidth: Integer;
begin
  if (FGrid=nil) or (aItem.Kind<>ockColumn) then
    Exit;
  lWidth:=aItem.Width;
  if lWidth<=0 then
    lWidth:=80;
  FGrid.AddColumn(aItem.Caption,cOhsFieldPrefix+IntToStr(aItem.Handle),lWidth);
  aItem.Element:=FGrid;
end;

procedure TOhsMultiGridAdapter.Remove(aItem: TOhsContribution);
var
  lColumn: TGridColumn;
begin
  lColumn:=ColumnOf(aItem);
  aItem.Element:=nil;
  if lColumn<>nil then
    lColumn.Free;
end;

procedure TOhsMultiGridAdapter.Update(aItem: TOhsContribution);
begin
  FWrapper.Changed;
end;

procedure TOhsMultiGridAdapter.FillRowContext(aRow: Integer; aContext: TOhsContext);
begin
  aContext.SetValue('grid',FId);
  aContext.SetValue(OHS_CTX_ROW,IntToStr(aRow));
  if Assigned(FOnRowContext) then
    FOnRowContext(Self,aRow,aContext);
end;

procedure TOhsMultiGridAdapter.AddContext(aContext: TOhsContext);
begin
  if (FGrid=nil) or (FGrid.Link=nil) or (FGrid.Link.FocusedRow<0) then
    Exit;
  FillRowContext(FGrid.Link.FocusedRow,aContext);
end;

function TOhsMultiGridAdapter.PluginCellText(aRow: Integer; const aField: string; out aText: string): Boolean;
var
  lHandle: Integer;
  lItem: TOhsContribution;
  lContext: TOhsContext;
  lIntf: IOhsContext;
begin
  aText:='';
  Result:=Copy(aField,1,Length(cOhsFieldPrefix))=cOhsFieldPrefix;
  if not Result or (Registry=nil) then
    Exit;
  lHandle:=StrToIntDef(Copy(aField,Length(cOhsFieldPrefix)+1,MaxInt),0);
  lItem:=Registry.Find(lHandle);
  if (lItem=nil) or (lItem.Adapter<>Self) then
    Exit;
  lContext:=TOhsContext.Create;
  lIntf:=lContext;
  FillRowContext(aRow,lContext);
  aText:=lItem.CellText(lIntf);
end;

end.
