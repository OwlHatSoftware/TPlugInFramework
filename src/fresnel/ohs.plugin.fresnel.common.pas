{ ohsPluginFramework - Fresnel adapters for toolbars and menus, and what all
  Fresnel adapters share.

    Bar := TDiv.Create(Self);
    Bar.Parent := Body;
    Toolbar := TOhsToolBarAdapter.Create('main', Bar);
    Registry.RegisterAdapter(Toolbar);               // location 'toolbar:main'

    Menus := TOhsMenuAdapter.Create('grid.context', GridPopup.Items);
    Registry.RegisterAdapter(Menus);                 // location 'menu:grid.context'

  Free the adapters after the plugins are unloaded and before the registry, or let
  the host form own nothing of theirs: an adapter notices when its container is
  freed and stops showing anything. }
unit ohs.plugin.fresnel.common;

{$mode Delphi}{$H+}
{$INTERFACES COM}

interface

uses
  Classes, SysUtils, FPImage, FPReadPNG,
  Fresnel.Classes, Fresnel.DOM, Fresnel.Controls, Fresnel.Images, Fresnel.Menus, FCL.Events,
  ohs.plugin.api, ohs.plugin.helpers, ohs.plugin.registry;

const
  cOhsCheckedClass = 'ohs-checked';
  cOhsToolBarClass = 'ohs-toolbar';
  cOhsPluginClass  = 'ohs-plugin';

  { Default look of what the adapters build. Add it to the form's stylesheet, or
    write your own rules for these classes. }
  cOhsPluginCSS =
    '.ohs-toolbar { display: flex; flex-direction: row; align-items: center; gap: 2px; padding: 2px 4px; }'+LineEnding+
    '.ohs-toolbar > button { padding: 3px 6px; }'+LineEnding+
    '.ohs-toolbar .ohs-separator { width: 1px; align-self: stretch; margin: 2px 4px; background-color: #c8c8c8; }'+LineEnding+
    '.ohs-checked { background-color: #cce4f7; border-color: #3a8ee6; }'+LineEnding+
    '.ohs-panel { display: flex; flex-direction: column; gap: 4px; padding: 6px; }'+LineEnding+
    '.ohs-panel-row { display: flex; flex-direction: row; align-items: center; gap: 4px; }'+LineEnding+
    '.ohs-panel-group { display: flex; flex-direction: column; gap: 4px; padding: 4px; }';

type
  { Base for the Fresnel adapters: knows when components it relies on are freed. }
  TOhsFresnelAdapter = class(TOhsUIAdapter)
  private
    FWatcher: TComponent;
  protected
    procedure Watch(aComponent: TComponent);
    procedure Unwatch(aComponent: TComponent);
    // aComponent is being freed; drop every reference to it
    procedure ComponentFreed(aComponent: TComponent); virtual;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  { Ties a Fresnel control or menu item to the contribution it shows. Owned by the
    control, so it goes when the control goes and the contribution then forgets the
    control. }
  TOhsBinding = class(TComponent)
  private
    FItem: TOhsContribution;
    FAdapter: TOhsUIAdapter;
  public
    constructor Create(aControl: TComponent; aAdapter: TOhsUIAdapter; aItem: TOhsContribution); reintroduce;
    destructor Destroy; override;
    procedure Detach;
    procedure HandleEvent(aEvent: TAbstractEvent);
    procedure HandleNotify(Sender: TObject);
    property Item: TOhsContribution read FItem;
    property Adapter: TOhsUIAdapter read FAdapter;
  end;

  { Buttons in a container, usually a TDiv; 'toolbar:<id>'. }
  TOhsToolBarAdapter = class(TOhsFresnelAdapter)
  private
    FId: string;
    FContainer: TFresnelElement;
    FShowCaptions: Boolean;
    procedure Reorder(aFrom: TOhsContribution);
  protected
    procedure ComponentFreed(aComponent: TComponent); override;
    procedure Apply(aItem: TOhsContribution); virtual;
  public
    // Adds cOhsToolBarClass to aContainer
    constructor Create(const aId: string; aContainer: TFresnelElement);
    destructor Destroy; override;
    function Handles(const aLocation: TOhsLocation): Boolean; override;
    procedure Add(aItem: TOhsContribution); override;
    procedure Remove(aItem: TOhsContribution); override;
    procedure Update(aItem: TOhsContribution); override;
    property Id: string read FId;
    property Container: TFresnelElement read FContainer;
    // False shows glyph only buttons when a command has a glyph; captions also go
    // when the command asks for OHS_SIZE_SMALL
    property ShowCaptions: Boolean read FShowCaptions write FShowCaptions;
  end;

  { Items under a menu item: the Items of a TMainMenu or TPopupMenu, or a submenu;
    'menu:<id>'. With a caption the plugin items go in a submenu of that name. }
  TOhsMenuAdapter = class(TOhsFresnelAdapter)
  private
    FId: string;
    FParentItem: TMenuItem;
    FBase: Integer;
  protected
    procedure ComponentFreed(aComponent: TComponent); override;
    procedure Apply(aItem: TOhsContribution); virtual;
  public
    // Plugin items go after the items aParent has now
    constructor Create(const aId: string; aParent: TMenuItem);
    destructor Destroy; override;
    function Handles(const aLocation: TOhsLocation): Boolean; override;
    procedure Add(aItem: TOhsContribution); override;
    procedure Remove(aItem: TOhsContribution); override;
    procedure Update(aItem: TOhsContribution); override;
    property Id: string read FId;
    property ParentItem: TMenuItem read FParentItem;
  end;

{ A command's PNG glyph as image data, or nil. The caller frees it. }
function OhsGlyphImage(const aInfo: TOhsCommandInfo): TImageData;
{ Copies the glyph into a button's image; clears it when there is none. }
procedure OhsApplyGlyph(aButton: TTextButton; const aInfo: TOhsCommandInfo);
procedure OhsSetHidden(aElement: TFresnelElement; aHidden: Boolean);
procedure OhsSetClass(aElement: TFresnelElement; const aClass: string; aOn: Boolean);
{ Frees an element now, or after the command that is running returns when the
  element may be the one that started it. }
procedure OhsFreeElement(aElement: TComponent);
{ Around a call into a plugin from a control's event: elements freed meanwhile
  are freed after it. }
procedure OhsEnterCall;
procedure OhsLeaveCall;

implementation

type
  TOhsWatcher = class(TComponent)
  private
    FAdapter: TOhsFresnelAdapter;
  protected
    procedure Notification(aComponent: TComponent; aOperation: TOperation); override;
  end;

var
  GExecuting: Integer = 0;
  GPendingFree: TList = nil;

procedure OhsFreeElement(aElement: TComponent);
begin
  if aElement=nil then
    Exit;
  if GExecuting>0 then
  begin
    if aElement is TFresnelElement then
      OhsSetHidden(TFresnelElement(aElement),True);
    if GPendingFree=nil then
      GPendingFree:=TList.Create;
    if GPendingFree.IndexOf(aElement)<0 then
      GPendingFree.Add(aElement);
  end
  else
    aElement.Free;
end;

procedure FreePending;
var
  lItem: TObject;
begin
  if GPendingFree=nil then
    Exit;
  while GPendingFree.Count>0 do
  begin
    lItem:=TObject(GPendingFree[GPendingFree.Count-1]);
    GPendingFree.Delete(GPendingFree.Count-1);
    lItem.Free;
  end;
end;

function OhsGlyphImage(const aInfo: TOhsCommandInfo): TImageData;
var
  lStream: TMemoryStream;
  lReader: TFPReaderPNG;
begin
  Result:=nil;
  if (aInfo.GlyphFormat<>OHS_GLYPH_PNG) or (Length(aInfo.Glyph)=0) then
    Exit;
  lStream:=TMemoryStream.Create;
  lReader:=TFPReaderPNG.Create;
  try
    lStream.WriteBuffer(aInfo.Glyph[0],Length(aInfo.Glyph));
    lStream.Position:=0;
    Result:=TImageData.Create(nil);
    try
      Result.LoadFromStream(lStream,lReader);
    except
      FreeAndNil(Result);
    end;
  finally
    lReader.Free;
    lStream.Free;
  end;
end;

procedure OhsApplyGlyph(aButton: TTextButton; const aInfo: TOhsCommandInfo);
var
  lImage: TImageData;
begin
  lImage:=OhsGlyphImage(aInfo);
  try
    if lImage<>nil then
      aButton.Image:=lImage;
  finally
    lImage.Free;
  end;
end;

procedure OhsSetHidden(aElement: TFresnelElement; aHidden: Boolean);
begin
  if aElement=nil then
    Exit;
  if aHidden then
    aElement.Style:='display: none'
  else if aElement.Style='display: none' then
    aElement.Style:='';
end;

procedure OhsSetClass(aElement: TFresnelElement; const aClass: string; aOn: Boolean);
begin
  if aElement=nil then
    Exit;
  if aOn then
  begin
    if not aElement.HasCSSClass(aClass) then
      aElement.AddCSSClass(aClass);
  end
  else if aElement.HasCSSClass(aClass) then
    aElement.RemoveCSSClass(aClass);
end;

{ TOhsWatcher }

procedure TOhsWatcher.Notification(aComponent: TComponent; aOperation: TOperation);
begin
  inherited Notification(aComponent,aOperation);
  if (aOperation=opRemove) and (FAdapter<>nil) then
    FAdapter.ComponentFreed(aComponent);
end;

{ TOhsFresnelAdapter }

constructor TOhsFresnelAdapter.Create;
begin
  inherited Create;
  FWatcher:=TOhsWatcher.Create(nil);
  TOhsWatcher(FWatcher).FAdapter:=Self;
end;

destructor TOhsFresnelAdapter.Destroy;
begin
  // unregisters, which removes the controls, while the watcher still listens
  inherited Destroy;
  TOhsWatcher(FWatcher).FAdapter:=nil;
  FWatcher.Free;
end;

procedure TOhsFresnelAdapter.Watch(aComponent: TComponent);
begin
  if aComponent<>nil then
    aComponent.FreeNotification(FWatcher);
end;

procedure TOhsFresnelAdapter.Unwatch(aComponent: TComponent);
begin
  if aComponent<>nil then
    aComponent.RemoveFreeNotification(FWatcher);
end;

procedure TOhsFresnelAdapter.ComponentFreed(aComponent: TComponent);
begin
end;

{ TOhsBinding }

constructor TOhsBinding.Create(aControl: TComponent; aAdapter: TOhsUIAdapter; aItem: TOhsContribution);
begin
  inherited Create(aControl);
  FAdapter:=aAdapter;
  FItem:=aItem;
end;

destructor TOhsBinding.Destroy;
begin
  if (FItem<>nil) and (FItem.Data=Self) then
  begin
    FItem.Element:=nil;
    FItem.Data:=nil;
  end;
  FItem:=nil;
  inherited Destroy;
end;

procedure TOhsBinding.Detach;
begin
  FItem:=nil;
  FAdapter:=nil;
end;

procedure TOhsBinding.HandleEvent(aEvent: TAbstractEvent);
begin
  HandleNotify(Self);
end;

procedure TOhsBinding.HandleNotify(Sender: TObject);
begin
  if (FItem=nil) or (FAdapter=nil) then
    Exit;
  OhsEnterCall;
  try
    FAdapter.Execute(FItem);
  finally
    OhsLeaveCall;
  end;
end;

procedure OhsEnterCall;
begin
  Inc(GExecuting);
end;

procedure OhsLeaveCall;
begin
  Dec(GExecuting);
  if GExecuting=0 then
    FreePending;
end;

{ TOhsToolBarAdapter }

constructor TOhsToolBarAdapter.Create(const aId: string; aContainer: TFresnelElement);
begin
  inherited Create;
  FId:=aId;
  FContainer:=aContainer;
  FShowCaptions:=True;
  OhsSetClass(FContainer,cOhsToolBarClass,True);
  Watch(FContainer);
end;

destructor TOhsToolBarAdapter.Destroy;
begin
  inherited Destroy;
  Unwatch(FContainer);
end;

procedure TOhsToolBarAdapter.ComponentFreed(aComponent: TComponent);
begin
  if aComponent=FContainer then
    FContainer:=nil;
end;

function TOhsToolBarAdapter.Handles(const aLocation: TOhsLocation): Boolean;
begin
  Result:=(FContainer<>nil) and (aLocation.Kind='toolbar') and SameText(aLocation.Target,FId);
end;

procedure TOhsToolBarAdapter.Reorder(aFrom: TOhsContribution);
var
  lList: TList;
  i, lStart: Integer;
  lElement: TFresnelElement;
begin
  // Fresnel appends children; move the ones that sort after aFrom behind it
  lList:=TList.Create;
  try
    Registry.ItemsAt(aFrom.Location.Text,lList);
    lStart:=lList.IndexOf(aFrom);
    for i:=lStart+1 to lList.Count-1 do
    begin
      lElement:=TFresnelElement(TOhsContribution(lList[i]).Element);
      if lElement<>nil then
      begin
        lElement.Parent:=nil;
        lElement.Parent:=FContainer;
      end;
    end;
  finally
    lList.Free;
  end;
end;

procedure TOhsToolBarAdapter.Add(aItem: TOhsContribution);
var
  lInfo: TOhsCommandInfo;
  lElement: TFresnelElement;
  lButton: TButton;
  lBinding: TOhsBinding;
begin
  if FContainer=nil then
    Exit;
  lInfo:=aItem.ReadCommand;
  if lInfo.Kind=OHS_CMD_SEPARATOR then
  begin
    lElement:=TDiv.Create(FContainer.Owner);
    lElement.AddCSSClass('ohs-separator');
  end
  else
  begin
    lButton:=TButton.Create(FContainer.Owner);
    lButton.AddCSSClass(cOhsPluginClass);
    lElement:=lButton;
  end;
  lBinding:=TOhsBinding.Create(lElement,Self,aItem);
  if lElement is TButton then
    TButton(lElement).OnClick:=lBinding.HandleEvent;
  aItem.Element:=lElement;
  aItem.Data:=lBinding;
  lElement.Parent:=FContainer;
  Apply(aItem);
  Reorder(aItem);
end;

procedure TOhsToolBarAdapter.Apply(aItem: TOhsContribution);
var
  lInfo: TOhsCommandInfo;
  lButton: TButton;
  lHasGlyph: Boolean;
begin
  if aItem.Element=nil then
    Exit;
  lInfo:=aItem.ReadCommand;
  OhsSetHidden(TFresnelElement(aItem.Element),not lInfo.Visible);
  if not (aItem.Element is TButton) then
    Exit;
  lButton:=TButton(aItem.Element);
  lHasGlyph:=lInfo.GlyphFormat<>OHS_GLYPH_NONE;
  OhsApplyGlyph(lButton,lInfo);
  if lHasGlyph and ((not FShowCaptions) or (aItem.Size=OHS_SIZE_SMALL)) then
    lButton.Caption:=''
  else
    lButton.Caption:=lInfo.Caption;
  if lInfo.Hint<>'' then
    lButton.Hint:=lInfo.Hint
  else
    lButton.Hint:=lInfo.Caption;
  lButton.Enabled:=lInfo.Enabled;
  OhsSetClass(lButton,cOhsCheckedClass,lInfo.Checked);
end;

procedure TOhsToolBarAdapter.Remove(aItem: TOhsContribution);
var
  lElement: TComponent;
begin
  if aItem.Data is TOhsBinding then
    TOhsBinding(aItem.Data).Detach;
  lElement:=TComponent(aItem.Element);
  aItem.Element:=nil;
  aItem.Data:=nil;
  OhsFreeElement(lElement);
end;

procedure TOhsToolBarAdapter.Update(aItem: TOhsContribution);
begin
  Apply(aItem);
end;

{ TOhsMenuAdapter }

constructor TOhsMenuAdapter.Create(const aId: string; aParent: TMenuItem);
begin
  inherited Create;
  FId:=aId;
  FParentItem:=aParent;
  if FParentItem<>nil then
    FBase:=FParentItem.Count;
  Watch(FParentItem);
end;

destructor TOhsMenuAdapter.Destroy;
begin
  inherited Destroy;
  Unwatch(FParentItem);
end;

procedure TOhsMenuAdapter.ComponentFreed(aComponent: TComponent);
begin
  if aComponent=FParentItem then
    FParentItem:=nil;
end;

function TOhsMenuAdapter.Handles(const aLocation: TOhsLocation): Boolean;
begin
  Result:=(FParentItem<>nil) and (aLocation.Kind='menu') and SameText(aLocation.Target,FId);
end;

procedure TOhsMenuAdapter.Add(aItem: TOhsContribution);
var
  lMenuItem: TMenuItem;
  lBinding: TOhsBinding;
  lIndex: Integer;
begin
  if FParentItem=nil then
    Exit;
  lMenuItem:=TMenuItem.Create(FParentItem.Owner);
  lBinding:=TOhsBinding.Create(lMenuItem,Self,aItem);
  lMenuItem.OnClick:=lBinding.HandleNotify;
  aItem.Element:=lMenuItem;
  aItem.Data:=lBinding;
  lIndex:=FBase+Registry.IndexAt(aItem);
  if lIndex>FParentItem.Count then
    lIndex:=FParentItem.Count;
  FParentItem.Insert(lIndex,lMenuItem);
  Apply(aItem);
end;

procedure TOhsMenuAdapter.Apply(aItem: TOhsContribution);
var
  lInfo: TOhsCommandInfo;
  lMenuItem: TMenuItem;
begin
  if not (aItem.Element is TMenuItem) then
    Exit;
  lMenuItem:=TMenuItem(aItem.Element);
  lInfo:=aItem.ReadCommand;
  if lInfo.Kind=OHS_CMD_SEPARATOR then
    lMenuItem.Caption:='-'
  else
    lMenuItem.Caption:=lInfo.Caption;
  lMenuItem.Detail:=lInfo.Hint;
  lMenuItem.Enabled:=lInfo.Enabled;
  lMenuItem.Visible:=lInfo.Visible;
  lMenuItem.Checked:=(lInfo.Kind=OHS_CMD_TOGGLE) and lInfo.Checked;
end;

procedure TOhsMenuAdapter.Remove(aItem: TOhsContribution);
var
  lMenuItem: TMenuItem;
begin
  if aItem.Data is TOhsBinding then
    TOhsBinding(aItem.Data).Detach;
  lMenuItem:=TMenuItem(aItem.Element);
  aItem.Element:=nil;
  aItem.Data:=nil;
  if lMenuItem=nil then
    Exit;
  if lMenuItem.Parent<>nil then
    lMenuItem.Parent.Remove(lMenuItem);
  OhsFreeElement(lMenuItem);
end;

procedure TOhsMenuAdapter.Update(aItem: TOhsContribution);
begin
  Apply(aItem);
end;

finalization
  FreePending;
  FreeAndNil(GPendingFree);
end.
