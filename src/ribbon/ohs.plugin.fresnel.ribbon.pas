{ ohsPluginFramework - plugin buttons on an ohsRibbon.

    Ribbon := TRibbon.Create(Self);
    Ribbon.Parent := Body;
    RibbonAdapter := TOhsRibbonAdapter.Create(Ribbon);
    Registry.RegisterAdapter(RibbonAdapter);

  Locations:

    ribbon:<Tab>/<Group>                    a button in a group; tab and group are made
                                            when the ribbon has none of that caption
    ribbon:<Tab>                            the same, in a group named DefaultGroup
    ribbon.quick:                           a button in the quick access toolbar
    ribbon.context:<Context>/<Tab>/<Group>  a group on a contextual tab; the host shows
                                            it with Ribbon.SetContextVisible

  OHS_SIZE_LARGE and OHS_SIZE_DEFAULT make large buttons, OHS_SIZE_MEDIUM medium and
  OHS_SIZE_SMALL small ones; the ribbon makes them smaller when the window narrows.
  OHS_CMD_TOGGLE makes a ribbon toggle that shows the command's checked state.

  ohsRibbon cannot take items, groups or tabs out again. When a plugin goes its
  buttons are hidden and cut off from it, groups and tabs this adapter made are
  hidden when nothing visible is left in them, and a plugin loaded again gets the
  same group back. }
unit ohs.plugin.fresnel.ribbon;

{$mode Delphi}{$H+}
{$INTERFACES COM}

interface

uses
  Classes, SysUtils,
  Fresnel.Classes, Fresnel.DOM, Fresnel.Controls, FCL.Events,
  ohsribbon.model.sizing, ohsribbon.ui.ribbon,
  ohs.plugin.api, ohs.plugin.helpers, ohs.plugin.registry, ohs.plugin.fresnel.common;

type
  TOhsRibbonAdapter = class(TOhsFresnelAdapter)
  private
    FRibbon: TRibbon;
    FDefaultGroup: string;
    FMadeTabs: TList;
    FMadeGroups: TList;
    function FindTab(const aContext, aCaption: string): TRibbonTab;
    function FindGroup(aTab: TRibbonTab; const aCaption: string): TRibbonGroup;
    function PlaceFor(aItem: TOhsContribution): TRibbonGroup;
    function GroupOf(aElement: TFresnelElement): TRibbonGroup;
    function TabOf(aGroup: TRibbonGroup): TRibbonTab;
    procedure TidyUp;
  protected
    procedure ComponentFreed(aComponent: TComponent); override;
    procedure Apply(aItem: TOhsContribution); virtual;
  public
    constructor Create(aRibbon: TRibbon);
    destructor Destroy; override;
    function Handles(const aLocation: TOhsLocation): Boolean; override;
    procedure Add(aItem: TOhsContribution); override;
    procedure Remove(aItem: TOhsContribution); override;
    procedure Update(aItem: TOhsContribution); override;
    property Ribbon: TRibbon read FRibbon;
    // The group used for 'ribbon:<Tab>' without a group; 'Plugins' to start with
    property DefaultGroup: string read FDefaultGroup write FDefaultGroup;
  end;

function OhsRibbonSize(aSize: Integer): TRibbonItemSize;

implementation

function OhsRibbonSize(aSize: Integer): TRibbonItemSize;
begin
  case aSize of
    OHS_SIZE_MEDIUM: Result:=risMedium;
    OHS_SIZE_SMALL: Result:=risSmall;
  else
    Result:=risLarge;
  end;
end;

{ TOhsRibbonAdapter }

constructor TOhsRibbonAdapter.Create(aRibbon: TRibbon);
begin
  inherited Create;
  FRibbon:=aRibbon;
  FDefaultGroup:='Plugins';
  FMadeTabs:=TList.Create;
  FMadeGroups:=TList.Create;
  Watch(FRibbon);
end;

destructor TOhsRibbonAdapter.Destroy;
begin
  inherited Destroy;
  Unwatch(FRibbon);
  FMadeGroups.Free;
  FMadeTabs.Free;
end;

procedure TOhsRibbonAdapter.ComponentFreed(aComponent: TComponent);
begin
  if aComponent=FRibbon then
  begin
    FRibbon:=nil;
    FMadeTabs.Clear;
    FMadeGroups.Clear;
  end;
end;

function TOhsRibbonAdapter.Handles(const aLocation: TOhsLocation): Boolean;
begin
  Result:=False;
  if FRibbon=nil then
    Exit;
  if aLocation.Kind='ribbon' then
    Result:=aLocation.Target<>''
  else if aLocation.Kind='ribbon.quick' then
    Result:=True
  else if aLocation.Kind='ribbon.context' then
    Result:=(aLocation.Part(0)<>'') and (aLocation.Part(1)<>'');
end;

function TOhsRibbonAdapter.FindTab(const aContext, aCaption: string): TRibbonTab;
var
  i: Integer;
begin
  for i:=0 to FRibbon.TabCount-1 do
  begin
    Result:=FRibbon.Tabs[i];
    if SameText(Result.ContextName,aContext) and SameText(Result.Caption,aCaption) then
      Exit;
  end;
  Result:=nil;
end;

function TOhsRibbonAdapter.FindGroup(aTab: TRibbonTab; const aCaption: string): TRibbonGroup;
var
  i: Integer;
begin
  for i:=0 to aTab.GroupCount-1 do
  begin
    Result:=aTab.Groups[i];
    if SameText(Result.Caption,aCaption) then
      Exit;
  end;
  Result:=nil;
end;

function TOhsRibbonAdapter.PlaceFor(aItem: TOhsContribution): TRibbonGroup;
var
  lContext, lTabCaption, lGroupCaption: string;
  lTab: TRibbonTab;
begin
  if aItem.Location.Kind='ribbon.context' then
  begin
    lContext:=aItem.Location.Part(0);
    lTabCaption:=aItem.Location.Part(1);
    lGroupCaption:=aItem.Location.Part(2);
  end
  else
  begin
    lContext:='';
    lTabCaption:=aItem.Location.Part(0);
    lGroupCaption:=aItem.Location.Part(1);
  end;
  if lGroupCaption='' then
    lGroupCaption:=FDefaultGroup;
  lTab:=FindTab(lContext,lTabCaption);
  if lTab=nil then
  begin
    if lContext='' then
      lTab:=FRibbon.AddTab(lTabCaption)
    else
      lTab:=FRibbon.AddContextualTab(lContext,lTabCaption);
    FMadeTabs.Add(lTab);
  end;
  Result:=FindGroup(lTab,lGroupCaption);
  if Result=nil then
  begin
    Result:=lTab.AddGroup(lGroupCaption);
    FMadeGroups.Add(Result);
  end;
  // it may have been hidden when an earlier plugin went
  OhsSetClass(Result,cRibbonHiddenClass,False);
  if (FMadeTabs.IndexOf(lTab)>=0) and ((lContext='') or FRibbon.IsContextVisible(lContext)) then
    OhsSetClass(lTab.Header,cRibbonHiddenClass,False);
end;

function TOhsRibbonAdapter.GroupOf(aElement: TFresnelElement): TRibbonGroup;
var
  lNode: TFresnelElement;
begin
  lNode:=aElement;
  while (lNode<>nil) and not (lNode is TRibbonGroup) do
    lNode:=lNode.Parent;
  Result:=TRibbonGroup(lNode);
end;

function TOhsRibbonAdapter.TabOf(aGroup: TRibbonGroup): TRibbonTab;
var
  i, j: Integer;
begin
  if (aGroup<>nil) and (FRibbon<>nil) then
    for i:=0 to FRibbon.TabCount-1 do
      for j:=0 to FRibbon.Tabs[i].GroupCount-1 do
        if FRibbon.Tabs[i].Groups[j]=aGroup then
          Exit(FRibbon.Tabs[i]);
  Result:=nil;
end;

procedure TOhsRibbonAdapter.Add(aItem: TOhsContribution);
var
  lInfo: TOhsCommandInfo;
  lGroup: TRibbonGroup;
  lButton: TRibbonItem;
  lBinding: TOhsBinding;
  lSize: TRibbonItemSize;
begin
  if FRibbon=nil then
    Exit;
  lInfo:=aItem.ReadCommand;
  // the ribbon has no separators: groups do that job
  if lInfo.Kind=OHS_CMD_SEPARATOR then
    Exit;
  lSize:=OhsRibbonSize(aItem.Size);
  if aItem.Location.Kind='ribbon.quick' then
    lButton:=FRibbon.AddQuickButton(lInfo.Caption)
  else
  begin
    lGroup:=PlaceFor(aItem);
    if lInfo.Kind=OHS_CMD_TOGGLE then
      lButton:=lGroup.AddToggle(lInfo.Caption,lSize)
    else
      lButton:=lGroup.AddButton(lInfo.Caption,lSize);
  end;
  lBinding:=TOhsBinding.Create(lButton,Self,aItem);
  lButton.OnClick:=lBinding.HandleEvent;
  lButton.AddCSSClass(cOhsPluginClass);
  aItem.Element:=lButton;
  aItem.Data:=lBinding;
  Apply(aItem);
end;

procedure TOhsRibbonAdapter.Apply(aItem: TOhsContribution);
var
  lInfo: TOhsCommandInfo;
  lButton: TRibbonItem;
  lGroup: TRibbonGroup;
begin
  if not (aItem.Element is TRibbonItem) then
    Exit;
  lButton:=TRibbonItem(aItem.Element);
  lInfo:=aItem.ReadCommand;
  lButton.Caption:=lInfo.Caption;
  OhsApplyGlyph(lButton,lInfo);
  if lInfo.Hint<>'' then
    lButton.Hint:=lInfo.Hint
  else
    lButton.Hint:=lInfo.Caption;
  lButton.Enabled:=lInfo.Enabled;
  if lButton.Kind=rikToggle then
    lButton.Checked:=lInfo.Checked;
  if lButton.HasCSSClass(cRibbonHiddenClass)=lInfo.Visible then
  begin
    OhsSetClass(lButton,cRibbonHiddenClass,not lInfo.Visible);
    lGroup:=GroupOf(lButton);
    if TabOf(lGroup)<>nil then
      TabOf(lGroup).InvalidateLayout;
  end;
end;

procedure TOhsRibbonAdapter.Remove(aItem: TOhsContribution);
var
  lButton: TRibbonItem;
  lGroup: TRibbonGroup;
begin
  if aItem.Data is TOhsBinding then
    TOhsBinding(aItem.Data).Detach;
  lButton:=TRibbonItem(aItem.Element);
  aItem.Element:=nil;
  aItem.Data:=nil;
  if (lButton=nil) or (FRibbon=nil) then
    Exit;
  lButton.OnClick:=nil;
  OhsSetClass(lButton,cRibbonHiddenClass,True);
  lGroup:=GroupOf(lButton);
  if TabOf(lGroup)<>nil then
    TabOf(lGroup).InvalidateLayout;
  TidyUp;
end;

procedure TOhsRibbonAdapter.TidyUp;
var
  i, j: Integer;
  lGroup: TRibbonGroup;
  lTab: TRibbonTab;
  lVisible: Boolean;

  function GroupHasVisible(aGroup: TRibbonGroup): Boolean;
  var
    k: Integer;
  begin
    for k:=0 to aGroup.ItemCount-1 do
      if not aGroup.Items[k].HasCSSClass(cRibbonHiddenClass) then
        Exit(True);
    Result:=False;
  end;

begin
  for i:=0 to FMadeGroups.Count-1 do
  begin
    lGroup:=TRibbonGroup(FMadeGroups[i]);
    OhsSetClass(lGroup,cRibbonHiddenClass,not GroupHasVisible(lGroup));
  end;
  for i:=0 to FMadeTabs.Count-1 do
  begin
    lTab:=TRibbonTab(FMadeTabs[i]);
    lVisible:=False;
    for j:=0 to lTab.GroupCount-1 do
      if not lTab.Groups[j].HasCSSClass(cRibbonHiddenClass) then
        lVisible:=True;
    if not lVisible then
    begin
      if FRibbon.ActiveTab=lTab then
        FRibbon.ActiveTab:=FRibbon.Tabs[0];
      OhsSetClass(lTab.Header,cRibbonHiddenClass,True);
    end;
  end;
end;

procedure TOhsRibbonAdapter.Update(aItem: TOhsContribution);
begin
  Apply(aItem);
end;

end.
