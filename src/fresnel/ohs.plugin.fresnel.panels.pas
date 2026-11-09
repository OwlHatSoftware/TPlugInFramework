{ ohsPluginFramework - plugin panels built from standard Fresnel controls.

    Side := TDiv.Create(Self);
    Side.Parent := Body;
    Panels := TOhsPanelAdapter.Create('side', Side);
    Registry.RegisterAdapter(Panels);                // location 'panel:side'

  A plugin asks for a panel and adds controls by kind; this unit makes a TLabel,
  TButton, TEdit, TMemo, TCheckBox, TComboBox, TGroupBox or a row TDiv for each.
  The plugin sees them only as IOhsControl, so it never touches a Fresnel object.
  When the host frees a control, its IOhsControl keeps working and does nothing. }
unit ohs.plugin.fresnel.panels;

{$mode Delphi}{$H+}
{$INTERFACES COM}

interface

uses
  Classes, SysUtils,
  Fresnel.Classes, Fresnel.DOM, Fresnel.Controls, Fresnel.Edit, Fresnel.Memo, Fresnel.Toggles,
  Fresnel.ComboBox, FCL.Events,
  ohs.plugin.api, ohs.plugin.helpers, ohs.plugin.registry, ohs.plugin.fresnel.common;

const
  cOhsPanelClass = 'ohs-panel';
  cOhsPanelRowClass = 'ohs-panel-row';
  cOhsPanelGroupClass = 'ohs-panel-group';

type
  TOhsFresnelPanel = class;

  { IOhsControl over one Fresnel element. }
  TOhsFresnelControl = class(TInterfacedObject, IOhsControl)
  private
    FTop: TOhsFresnelPanel;
    FElement: TFresnelElement;
    FKind: Integer;
    FId: string;
    FText: string;
    FSubPanel: IOhsPanel;
    procedure Fire(aEvent: Integer);
    procedure Clicked(aEvent: TAbstractEvent);
    procedure Changed(Sender: TObject);
  public
    function GetId: POhsChar; stdcall;
    function GetKind: Integer; stdcall;
    function GetText: POhsChar; stdcall;
    procedure SetText(aText: POhsChar); stdcall;
    function GetChecked: LongBool; stdcall;
    procedure SetChecked(aValue: LongBool); stdcall;
    function GetItemIndex: Integer; stdcall;
    procedure SetItemIndex(aValue: Integer); stdcall;
    procedure SetItems(aItems: POhsChar); stdcall;
    procedure SetEnabled(aValue: LongBool); stdcall;
    procedure SetVisible(aValue: LongBool); stdcall;
    procedure SetHint(aText: POhsChar); stdcall;
    function AsPanel: IOhsPanel; stdcall;
    property Element: TFresnelElement read FElement;
  end;

  { IOhsPanel over a container element. The panel a plugin gets is the top one;
    groups and rows are panels inside it that share its events. }
  TOhsFresnelPanel = class(TInterfacedObject, IOhsPanel)
  private
    FTop: TOhsFresnelPanel;          // Self for the top panel; nil once dead
    FContainer: TFresnelElement;     // where controls go
    FCaptioned: TCustomCaptionedBox; // SetCaption changes this, when there is one
    FControls: TInterfaceList;       // of IOhsControl, this panel's own; keeps them alive
    FOwn: TList;                     // the same, as TOhsFresnelControl
    // only on the top panel:
    FEvents: IOhsControlEvents;
    FAll: TList;                     // every TOhsFresnelControl
    FPanels: TList;                  // every nested TOhsFresnelPanel
    FWatcher: TComponent;
    procedure ElementFreed(aComponent: TComponent);
    function Owner: TComponent;
  public
    constructor Create(aContainer: TFresnelElement; aCaptioned: TCustomCaptionedBox; aTop: TOhsFresnelPanel);
    destructor Destroy; override;
    // Frees the controls and cuts the plugin off; for the top panel only
    procedure Kill;
    function AddControl(aKind: Integer; aId, aCaption: POhsChar): IOhsControl; stdcall;
    function FindControl(aId: POhsChar): IOhsControl; stdcall;
    procedure SetEvents(const aEvents: IOhsControlEvents); stdcall;
    procedure SetCaption(aCaption: POhsChar); stdcall;
    procedure Clear; stdcall;
    property Container: TFresnelElement read FContainer;
  end;

  { Panels inside a host container; 'panel:<id>'. Each panel is a TGroupBox with the
    caption the plugin gave, or a TDiv without one. }
  TOhsPanelAdapter = class(TOhsFresnelAdapter)
  private
    FId: string;
    FContainer: TFresnelElement;
  protected
    procedure ComponentFreed(aComponent: TComponent); override;
  public
    constructor Create(const aId: string; aContainer: TFresnelElement);
    destructor Destroy; override;
    function Handles(const aLocation: TOhsLocation): Boolean; override;
    procedure Add(aItem: TOhsContribution); override;
    function CreatePanel(aItem: TOhsContribution): IOhsPanel; override;
    procedure Remove(aItem: TOhsContribution); override;
    property Id: string read FId;
    property Container: TFresnelElement read FContainer;
  end;

implementation

type
  TOhsPanelWatcher = class(TComponent)
  private
    FPanel: TOhsFresnelPanel;
  protected
    procedure Notification(aComponent: TComponent; aOperation: TOperation); override;
  end;

procedure TOhsPanelWatcher.Notification(aComponent: TComponent; aOperation: TOperation);
begin
  inherited Notification(aComponent,aOperation);
  if (aOperation=opRemove) and (FPanel<>nil) then
    FPanel.ElementFreed(aComponent);
end;

{ TOhsFresnelControl }

procedure TOhsFresnelControl.Fire(aEvent: Integer);
var
  lEvents: IOhsControlEvents;
begin
  if (FTop=nil) or (FElement=nil) then
    Exit;
  lEvents:=FTop.FEvents;
  if lEvents=nil then
    Exit;
  OhsEnterCall;
  try
    try
      lEvents.ControlEvent(Self,aEvent);
    except
    end;
  finally
    OhsLeaveCall;
  end;
end;

procedure TOhsFresnelControl.Clicked(aEvent: TAbstractEvent);
begin
  Fire(OHS_EVT_CLICK);
end;

procedure TOhsFresnelControl.Changed(Sender: TObject);
begin
  Fire(OHS_EVT_CHANGE);
end;

function TOhsFresnelControl.GetId: POhsChar; stdcall;
begin
  Result:=POhsChar(FId);
end;

function TOhsFresnelControl.GetKind: Integer; stdcall;
begin
  Result:=FKind;
end;

function TOhsFresnelControl.GetText: POhsChar; stdcall;
var
  lCombo: TComboBox;
begin
  FText:='';
  try
    if FElement is TLabel then
      FText:=TLabel(FElement).Caption
    else if FElement is TTextButton then
      FText:=TTextButton(FElement).Caption
    else if FElement is TEdit then
      FText:=TEdit(FElement).Value
    else if FElement is TMemo then
      FText:=TMemo(FElement).Text
    else if FElement is TCheckBox then
      FText:=TCheckBox(FElement).Caption
    else if FElement is TComboBox then
    begin
      lCombo:=TComboBox(FElement);
      if (lCombo.ItemIndex>=0) and (lCombo.ItemIndex<lCombo.Items.Count) then
        FText:=lCombo.Items[lCombo.ItemIndex];
    end
    else if FElement is TCustomCaptionedBox then
      FText:=TCustomCaptionedBox(FElement).Caption;
  except
    FText:='';
  end;
  Result:=POhsChar(FText);
end;

procedure TOhsFresnelControl.SetText(aText: POhsChar); stdcall;
var
  lText: string;
  lCombo: TComboBox;
begin
  lText:=OhsStr(aText);
  try
    if FElement is TLabel then
      TLabel(FElement).Caption:=lText
    else if FElement is TTextButton then
      TTextButton(FElement).Caption:=lText
    else if FElement is TEdit then
      TEdit(FElement).Value:=lText
    else if FElement is TMemo then
      TMemo(FElement).Text:=lText
    else if FElement is TCheckBox then
      TCheckBox(FElement).Caption:=lText
    else if FElement is TComboBox then
    begin
      lCombo:=TComboBox(FElement);
      lCombo.ItemIndex:=lCombo.Items.IndexOf(lText);
    end
    else if FElement is TCustomCaptionedBox then
      TCustomCaptionedBox(FElement).Caption:=lText;
  except
  end;
end;

function TOhsFresnelControl.GetChecked: LongBool; stdcall;
begin
  Result:=False;
  try
    if FElement is TCheckBox then
      Result:=TCheckBox(FElement).Checked;
  except
  end;
end;

procedure TOhsFresnelControl.SetChecked(aValue: LongBool); stdcall;
begin
  try
    if FElement is TCheckBox then
      TCheckBox(FElement).Checked:=aValue;
  except
  end;
end;

function TOhsFresnelControl.GetItemIndex: Integer; stdcall;
begin
  Result:=-1;
  try
    if FElement is TComboBox then
      Result:=TComboBox(FElement).ItemIndex;
  except
  end;
end;

procedure TOhsFresnelControl.SetItemIndex(aValue: Integer); stdcall;
begin
  try
    if FElement is TComboBox then
      TComboBox(FElement).ItemIndex:=aValue;
  except
  end;
end;

procedure TOhsFresnelControl.SetItems(aItems: POhsChar); stdcall;
var
  lLines: TStringList;
begin
  try
    lLines:=TStringList.Create;
    try
      lLines.LineBreak:=#10;
      lLines.Text:=StringReplace(OhsStr(aItems),#13,'',[rfReplaceAll]);
      if FElement is TComboBox then
        TComboBox(FElement).Items.Assign(lLines)
      else if FElement is TMemo then
        TMemo(FElement).Lines.Assign(lLines);
    finally
      lLines.Free;
    end;
  except
  end;
end;

procedure TOhsFresnelControl.SetEnabled(aValue: LongBool); stdcall;
begin
  try
    if FElement is TCustomButton then
      TCustomButton(FElement).Enabled:=aValue
    else if FElement is TEdit then
      TEdit(FElement).Enabled:=aValue
    else if FElement is TMemo then
      TMemo(FElement).Enabled:=aValue
    else if FElement is TComboBox then
      TComboBox(FElement).Enabled:=aValue;
  except
  end;
end;

procedure TOhsFresnelControl.SetVisible(aValue: LongBool); stdcall;
begin
  try
    OhsSetHidden(FElement,not aValue);
  except
  end;
end;

procedure TOhsFresnelControl.SetHint(aText: POhsChar); stdcall;
begin
  if FElement<>nil then
    FElement.Hint:=OhsStr(aText);
end;

function TOhsFresnelControl.AsPanel: IOhsPanel; stdcall;
begin
  Result:=FSubPanel;
end;

{ TOhsFresnelPanel }

constructor TOhsFresnelPanel.Create(aContainer: TFresnelElement; aCaptioned: TCustomCaptionedBox;
  aTop: TOhsFresnelPanel);
begin
  inherited Create;
  FContainer:=aContainer;
  FCaptioned:=aCaptioned;
  FControls:=TInterfaceList.Create;
  FOwn:=TList.Create;
  if aTop=nil then
  begin
    FTop:=Self;
    FAll:=TList.Create;
    FPanels:=TList.Create;
    FWatcher:=TOhsPanelWatcher.Create(nil);
    TOhsPanelWatcher(FWatcher).FPanel:=Self;
    FContainer.FreeNotification(FWatcher);
  end
  else
  begin
    FTop:=aTop;
    aTop.FPanels.Add(Self);
  end;
end;

destructor TOhsFresnelPanel.Destroy;
begin
  if FTop=Self then
    Kill
  else if FTop<>nil then
    FTop.FPanels.Remove(Self);
  FControls.Free;
  FOwn.Free;
  FAll.Free;
  FPanels.Free;
  if FWatcher<>nil then
  begin
    TOhsPanelWatcher(FWatcher).FPanel:=nil;
    FWatcher.Free;
  end;
  inherited Destroy;
end;

function TOhsFresnelPanel.Owner: TComponent;
begin
  Result:=FContainer.Owner;
  if Result=nil then
    Result:=FContainer;
end;

procedure TOhsFresnelPanel.ElementFreed(aComponent: TComponent);
var
  i: Integer;
  lPanel: TOhsFresnelPanel;
begin
  // only the top panel watches; anything that goes stops being usable
  for i:=0 to FAll.Count-1 do
    if TOhsFresnelControl(FAll[i]).FElement=aComponent then
      TOhsFresnelControl(FAll[i]).FElement:=nil;
  for i:=0 to FPanels.Count-1 do
  begin
    lPanel:=TOhsFresnelPanel(FPanels[i]);
    if lPanel.FContainer=aComponent then
      lPanel.FContainer:=nil;
    if lPanel.FCaptioned=aComponent then
      lPanel.FCaptioned:=nil;
  end;
  if FContainer=aComponent then
    FContainer:=nil;
  if FCaptioned=aComponent then
    FCaptioned:=nil;
end;

procedure TOhsFresnelPanel.Kill;
var
  i: Integer;
  lRoot: TFresnelElement;
  lPanel: TOhsFresnelPanel;
begin
  if FTop<>Self then
    Exit;
  FEvents:=nil;
  for i:=0 to FAll.Count-1 do
  begin
    TOhsFresnelControl(FAll[i]).FTop:=nil;
    TOhsFresnelControl(FAll[i]).FElement:=nil;
  end;
  for i:=FPanels.Count-1 downto 0 do
  begin
    lPanel:=TOhsFresnelPanel(FPanels[i]);
    lPanel.FTop:=nil;
    lPanel.FContainer:=nil;
    lPanel.FCaptioned:=nil;
  end;
  FPanels.Clear;
  FAll.Clear;
  lRoot:=FContainer;
  FContainer:=nil;
  FCaptioned:=nil;
  if lRoot<>nil then
  begin
    lRoot.RemoveFreeNotification(FWatcher);
    OhsFreeElement(lRoot);
  end;
  // the controls hold the nested panels; let go of them last
  FOwn.Clear;
  FControls.Clear;
  FTop:=nil;
end;

function TOhsFresnelPanel.AddControl(aKind: Integer; aId, aCaption: POhsChar): IOhsControl; stdcall;
var
  lControl: TOhsFresnelControl;
  lElement: TFresnelElement;
  lCaption: string;
  lSub: TOhsFresnelPanel;
begin
  Result:=nil;
  if (FTop=nil) or (FContainer=nil) then
    Exit;
  try
    lCaption:=OhsStr(aCaption);
    lControl:=TOhsFresnelControl.Create;
    lControl.FTop:=FTop;
    lControl.FKind:=aKind;
    lControl.FId:=OhsStr(aId);
    case aKind of
      OHS_CTRL_LABEL:
        begin
          lElement:=TLabel.Create(Owner);
          TLabel(lElement).Caption:=lCaption;
        end;
      OHS_CTRL_BUTTON:
        begin
          lElement:=TButton.Create(Owner);
          TButton(lElement).Caption:=lCaption;
          TButton(lElement).OnClick:=lControl.Clicked;
        end;
      OHS_CTRL_EDIT:
        begin
          lElement:=TEdit.Create(Owner);
          TEdit(lElement).PlaceHolder:=lCaption;
          TEdit(lElement).OnChange:=lControl.Changed;
        end;
      OHS_CTRL_MEMO:
        begin
          lElement:=TMemo.Create(Owner);
          TMemo(lElement).Text:=lCaption;
          TMemo(lElement).Style:='height: 80px';
          TMemo(lElement).OnChange:=lControl.Changed;
        end;
      OHS_CTRL_CHECKBOX:
        begin
          lElement:=TCheckBox.Create(Owner);
          TCheckBox(lElement).Caption:=lCaption;
          TCheckBox(lElement).OnChange:=lControl.Changed;
        end;
      OHS_CTRL_COMBOBOX:
        begin
          lElement:=TComboBox.Create(Owner);
          TComboBox(lElement).OnChange:=lControl.Changed;
        end;
      OHS_CTRL_GROUP:
        begin
          lElement:=TGroupBox.Create(Owner);
          TGroupBox(lElement).Caption:=lCaption;
          lElement.AddCSSClass(cOhsPanelGroupClass);
          lSub:=TOhsFresnelPanel.Create(lElement,TGroupBox(lElement),FTop);
          lControl.FSubPanel:=lSub;
        end;
      OHS_CTRL_ROW:
        begin
          lElement:=TDiv.Create(Owner);
          lElement.AddCSSClass(cOhsPanelRowClass);
          lSub:=TOhsFresnelPanel.Create(lElement,nil,FTop);
          lControl.FSubPanel:=lSub;
        end;
    else
      lControl.Free;
      Exit;
    end;
    lElement.AddCSSClass(cOhsPluginClass);
    lElement.Parent:=FContainer;
    lControl.FElement:=lElement;
    lElement.FreeNotification(FTop.FWatcher);
    FTop.FAll.Add(lControl);
    Result:=lControl;
    FControls.Add(Result);
    FOwn.Add(lControl);
  except
    Result:=nil;
  end;
end;

function TOhsFresnelPanel.FindControl(aId: POhsChar): IOhsControl; stdcall;
var
  i: Integer;
  lId: string;
begin
  Result:=nil;
  if FTop=nil then
    Exit;
  lId:=OhsStr(aId);
  for i:=0 to FTop.FAll.Count-1 do
    if SameText(TOhsFresnelControl(FTop.FAll[i]).FId,lId) then
      Exit(TOhsFresnelControl(FTop.FAll[i]));
end;

procedure TOhsFresnelPanel.SetEvents(const aEvents: IOhsControlEvents); stdcall;
begin
  if FTop<>nil then
    FTop.FEvents:=aEvents;
end;

procedure TOhsFresnelPanel.SetCaption(aCaption: POhsChar); stdcall;
begin
  if FCaptioned<>nil then
    FCaptioned.Caption:=OhsStr(aCaption);
end;

procedure TOhsFresnelPanel.Clear; stdcall;
var
  i: Integer;
  lControl: TOhsFresnelControl;
  lElement: TFresnelElement;
begin
  if FTop=nil then
    Exit;
  for i:=FOwn.Count-1 downto 0 do
  begin
    lControl:=TOhsFresnelControl(FOwn[i]);
    lElement:=lControl.FElement;
    lControl.FElement:=nil;
    lControl.FTop:=nil;
    FTop.FAll.Remove(lControl);
    if lElement<>nil then
    begin
      lElement.RemoveFreeNotification(FTop.FWatcher);
      OhsFreeElement(lElement);
    end;
  end;
  FOwn.Clear;
  FControls.Clear;
end;

{ TOhsPanelAdapter }

constructor TOhsPanelAdapter.Create(const aId: string; aContainer: TFresnelElement);
begin
  inherited Create;
  FId:=aId;
  FContainer:=aContainer;
  Watch(FContainer);
end;

destructor TOhsPanelAdapter.Destroy;
begin
  inherited Destroy;
  Unwatch(FContainer);
end;

procedure TOhsPanelAdapter.ComponentFreed(aComponent: TComponent);
begin
  if aComponent=FContainer then
    FContainer:=nil;
end;

function TOhsPanelAdapter.Handles(const aLocation: TOhsLocation): Boolean;
begin
  Result:=(FContainer<>nil) and (aLocation.Kind='panel') and SameText(aLocation.Target,FId);
end;

procedure TOhsPanelAdapter.Add(aItem: TOhsContribution);
begin
  // commands and columns have no place in a panel area
end;

function TOhsPanelAdapter.CreatePanel(aItem: TOhsContribution): IOhsPanel;
var
  lBox: TGroupBox;
  lDiv: TDiv;
  lPanel: TOhsFresnelPanel;
  lOwner: TComponent;
begin
  Result:=nil;
  if FContainer=nil then
    Exit;
  lOwner:=FContainer.Owner;
  if aItem.Caption<>'' then
  begin
    lBox:=TGroupBox.Create(lOwner);
    lBox.Caption:=aItem.Caption;
    lBox.AddCSSClass(cOhsPanelClass);
    lBox.AddCSSClass(cOhsPluginClass);
    lBox.Parent:=FContainer;
    lPanel:=TOhsFresnelPanel.Create(lBox,lBox,nil);
  end
  else
  begin
    lDiv:=TDiv.Create(lOwner);
    lDiv.AddCSSClass(cOhsPanelClass);
    lDiv.AddCSSClass(cOhsPluginClass);
    lDiv.Parent:=FContainer;
    lPanel:=TOhsFresnelPanel.Create(lDiv,nil,nil);
  end;
  aItem.Element:=lPanel.Container;
  aItem.Data:=lPanel;
  Result:=lPanel;
end;

procedure TOhsPanelAdapter.Remove(aItem: TOhsContribution);
begin
  if aItem.Data is TOhsFresnelPanel then
    TOhsFresnelPanel(aItem.Data).Kill;
  aItem.Element:=nil;
  aItem.Data:=nil;
end;

end.
