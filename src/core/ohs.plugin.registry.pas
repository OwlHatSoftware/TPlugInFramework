{ ohsPluginFramework - the host side of the user interface contract.

  TOhsUIRegistry keeps everything plugins contributed: commands, panels and
  columns, each at a location. It does not know any UI library. Adapters do:
  an adapter says which locations it handles and turns contributions into real
  controls. The Fresnel adapters are in the ohspluginframework_fresnel,
  _ribbon, _multigrid and _gantt packages; a host can write its own by deriving
  from TOhsUIAdapter.

  Contributions that arrive before an adapter for their location exists are kept
  and handed over when it is registered, so the order in which the host builds
  its UI and loads its plugins does not matter.

  Each plugin talks to its own TOhsPluginSite, which implements IOhsHost and
  IOhsUI and tags every contribution with the plugin, so all of them can be
  removed when the plugin goes. }
unit ohs.plugin.registry;

{$IFDEF FPC}
  {$MODE Delphi}{$H+}
  {$INTERFACES COM}
{$ENDIF}

interface

uses
  Classes, SysUtils, ohs.plugin.api, ohs.plugin.helpers;

type
  { A parsed location, '<kind>:<target>[/<path>...]'. 'ribbon:Home/Plugins' has
    Kind 'ribbon' and Parts ['Home','Plugins']; Target is the first part. }
  TOhsLocation = record
    Text: string;
    Kind: string;
    Parts: array of string;
    function Target: string;
    function Part(aIndex: Integer): string;
    function PartCount: Integer;
  end;

  TOhsContributionKind = (ockCommand, ockPanel, ockColumn);

  { What a command says about itself, read in one guarded go. }
  TOhsCommandInfo = record
    Id: string;
    Caption: string;
    Hint: string;
    Kind: Integer;
    State: Integer;
    GlyphFormat: Integer;
    Glyph: TOhsBytes;
    function Enabled: Boolean;
    function Checked: Boolean;
    function Visible: Boolean;
  end;

  TOhsUIRegistry = class;
  TOhsUIAdapter = class;

  { One thing a plugin added. The adapter that shows it may keep its control in
    Element, and anything else in Data. }
  TOhsContribution = class
  private
    FHandle: Integer;
    FKind: TOhsContributionKind;
    FLocation: TOhsLocation;
    FOwner: TObject;
    FOrder: Integer;
    FSize: Integer;
    FCommand: IOhsCommand;
    FCaption: string;
    FField: string;
    FWidth: Integer;
    FProvider: IOhsCellProvider;
    FPanel: IOhsPanel;
    FAdapter: TOhsUIAdapter;
  public
    Element: TObject;
    Data: TObject;
    function ReadCommand: TOhsCommandInfo;
    // The text of a cell of a column contribution, '' when the provider fails
    function CellText(const aRow: IOhsContext): string;
    property Handle: Integer read FHandle;
    property Kind: TOhsContributionKind read FKind;
    property Location: TOhsLocation read FLocation;
    // The TOhsPluginSite that added it, or nil when the host added it itself
    property Owner: TObject read FOwner;
    property Order: Integer read FOrder;
    property Size: Integer read FSize;
    property Command: IOhsCommand read FCommand;
    // Panel caption or column title
    property Caption: string read FCaption;
    property Field: string read FField;
    property Width: Integer read FWidth;
    property Provider: IOhsCellProvider read FProvider;
    property Panel: IOhsPanel read FPanel;
    property Adapter: TOhsUIAdapter read FAdapter;
  end;

  { Turns contributions into controls for the locations it handles. }
  TOhsUIAdapter = class
  private
    FRegistry: TOhsUIRegistry;
  public
    // Run a command contribution with the context of the moment; aExtra may add values
    procedure Execute(aItem: TOhsContribution; aExtra: TOhsContext = nil);
  public
    destructor Destroy; override;
    function Handles(const aLocation: TOhsLocation): Boolean; virtual; abstract;
    // Show a command or column contribution
    procedure Add(aItem: TOhsContribution); virtual; abstract;
    // Build a panel; return nil when this adapter has no panels
    function CreatePanel(aItem: TOhsContribution): IOhsPanel; virtual;
    // Take the control away again; the contribution goes after this
    procedure Remove(aItem: TOhsContribution); virtual; abstract;
    // The command's caption, glyph or state, or the column's cells changed
    procedure Update(aItem: TOhsContribution); virtual;
    // Add what this adapter knows of the current state, such as a selected row
    procedure AddContext(aContext: TOhsContext); virtual;
    property Registry: TOhsUIRegistry read FRegistry;
  end;

  TOhsMessageEvent = procedure(aKind: Integer; const aText: string) of object;
  TOhsLogEvent = procedure(const aText: string) of object;
  TOhsContextEvent = procedure(aContext: TOhsContext) of object;

  TOhsUIRegistry = class
  private
    FAdapters: TList;
    FItems: TList;
    FSubscriptions: TList;
    FNextHandle: Integer;
    FInfo: TStringList;
    FOnMessage: TOhsMessageEvent;
    FOnLog: TOhsLogEvent;
    FOnGetContext: TOhsContextEvent;
    function NewHandle: Integer;
    function FindAdapter(const aLocation: TOhsLocation): TOhsUIAdapter;
    function AddItem(aOwner: TObject; aKind: TOhsContributionKind; const aLocation: string): TOhsContribution;
    procedure Show(aItem: TOhsContribution);
    procedure Hide(aItem: TOhsContribution);
    function GetCount: Integer;
    function GetItem(aIndex: Integer): TOhsContribution;
  public
    constructor Create;
    destructor Destroy; override;
    // Adapters are not owned; free them after the registry or unregister them first
    procedure RegisterAdapter(aAdapter: TOhsUIAdapter);
    procedure UnregisterAdapter(aAdapter: TOhsUIAdapter);
    function HasLocation(const aLocation: string): Boolean;
    function AddCommand(aOwner: TObject; const aLocation: string; const aCommand: IOhsCommand;
      aSize: Integer = OHS_SIZE_DEFAULT; aOrder: Integer = 100): Integer;
    function AddPanel(aOwner: TObject; const aLocation, aCaption: string; out aPanel: IOhsPanel): Integer;
    function AddColumn(aOwner: TObject; const aLocation, aTitle, aField: string; aWidth: Integer;
      const aProvider: IOhsCellProvider): Integer;
    function Find(aHandle: Integer): TOhsContribution;
    // aOwner nil removes whatever the handle is
    procedure Remove(aHandle: Integer; aOwner: TObject = nil);
    procedure RemoveOwner(aOwner: TObject);
    procedure CommandChanged(const aCommand: IOhsCommand);
    procedure ColumnChanged(aHandle: Integer);
    // The contributions shown at one location, sorted by order
    procedure ItemsAt(const aLocation: string; aList: TList);
    // Where a new item goes among those already shown at its location
    function IndexAt(aItem: TOhsContribution): Integer;
    // The current context: what adapters and the host add
    function BuildContext: TOhsContext;
    procedure ExecuteCommand(aItem: TOhsContribution; aExtra: TOhsContext = nil);
    function Subscribe(aOwner: TObject; const aEvent: string; const aSink: IOhsEventSink): Integer;
    procedure Unsubscribe(aHandle: Integer);
    procedure UnsubscribeOwner(aOwner: TObject);
    // Tell the plugins listening to aEvent; aContext may be nil
    procedure Publish(const aEvent: string; aContext: TOhsContext = nil);
    procedure Message(aKind: Integer; const aText: string);
    procedure Log(const aText: string);
    property Count: Integer read GetCount;
    property Items[aIndex: Integer]: TOhsContribution read GetItem;
    // Answers to IOhsHost.GetInfo, as name=value
    property Info: TStringList read FInfo;
    property OnMessage: TOhsMessageEvent read FOnMessage write FOnMessage;
    property OnLog: TOhsLogEvent read FOnLog write FOnLog;
    property OnGetContext: TOhsContextEvent read FOnGetContext write FOnGetContext;
  end;

  { IOhsHost and IOhsUI for one plugin. Detach cuts it off from the registry, after
    which every call does nothing, so a plugin keeping a reference cannot do harm. }
  TOhsPluginSite = class(TInterfacedObject, IOhsHost, IOhsUI)
  private
    FRegistry: TOhsUIRegistry;
    FName: string;
    FInfoValue: string;
  public
    constructor Create(aRegistry: TOhsUIRegistry; const aName: string);
    procedure Detach;
    // IOhsHost
    function GetApiVersion: Integer; stdcall;
    function GetInfo(aKey: POhsChar): POhsChar; stdcall;
    function UI: IOhsUI; stdcall;
    procedure ShowMessage(aKind: Integer; aText: POhsChar); stdcall;
    procedure Log(aText: POhsChar); stdcall;
    function GetContext: IOhsContext; stdcall;
    function Subscribe(aEvent: POhsChar; const aSink: IOhsEventSink): Integer; stdcall;
    procedure Unsubscribe(aHandle: Integer); stdcall;
    // IOhsUI
    function HasLocation(aLocation: POhsChar): LongBool; stdcall;
    function AddCommand(aLocation: POhsChar; const aCommand: IOhsCommand;
      aSize, aOrder: Integer): Integer; stdcall;
    function AddPanel(aLocation, aCaption: POhsChar; out aPanel: IOhsPanel): Integer; stdcall;
    function AddColumn(aLocation, aTitle, aField: POhsChar; aWidth: Integer;
      const aProvider: IOhsCellProvider): Integer; stdcall;
    procedure Remove(aHandle: Integer); stdcall;
    procedure CommandChanged(const aCommand: IOhsCommand); stdcall;
    procedure ColumnChanged(aHandle: Integer); stdcall;
    property Name: string read FName write FName;
    property Registry: TOhsUIRegistry read FRegistry;
  end;

function OhsParseLocation(const aText: string): TOhsLocation;

implementation

type
  TOhsSubscription = class
    Handle: Integer;
    Owner: TObject;
    Event: string;
    Sink: IOhsEventSink;
  end;

function OhsParseLocation(const aText: string): TOhsLocation;
var
  lColon, i, lStart: Integer;
  lRest: string;
begin
  Result.Text:=aText;
  Result.Parts:=nil;
  lColon:=Pos(':',aText);
  if lColon=0 then
  begin
    Result.Kind:=LowerCase(Trim(aText));
    Exit;
  end;
  Result.Kind:=LowerCase(Trim(Copy(aText,1,lColon-1)));
  lRest:=Copy(aText,lColon+1,MaxInt);
  if lRest='' then
    Exit;
  lStart:=1;
  for i:=1 to Length(lRest)+1 do
    if (i>Length(lRest)) or (lRest[i]='/') then
    begin
      SetLength(Result.Parts,Length(Result.Parts)+1);
      Result.Parts[High(Result.Parts)]:=Trim(Copy(lRest,lStart,i-lStart));
      lStart:=i+1;
    end;
end;

{ TOhsLocation }

function TOhsLocation.Target: string;
begin
  Result:=Part(0);
end;

function TOhsLocation.Part(aIndex: Integer): string;
begin
  if (aIndex>=0) and (aIndex<Length(Parts)) then
    Result:=Parts[aIndex]
  else
    Result:='';
end;

function TOhsLocation.PartCount: Integer;
begin
  Result:=Length(Parts);
end;

{ TOhsCommandInfo }

function TOhsCommandInfo.Enabled: Boolean;
begin
  Result:=(State and OHS_STATE_DISABLED)=0;
end;

function TOhsCommandInfo.Checked: Boolean;
begin
  Result:=(State and OHS_STATE_CHECKED)<>0;
end;

function TOhsCommandInfo.Visible: Boolean;
begin
  Result:=(State and OHS_STATE_HIDDEN)=0;
end;

{ TOhsContribution }

function TOhsContribution.ReadCommand: TOhsCommandInfo;
var
  lData: Pointer;
  lSize: Integer;
begin
  Result.Id:='';
  Result.Caption:='';
  Result.Hint:='';
  Result.Kind:=OHS_CMD_BUTTON;
  Result.State:=OHS_STATE_HIDDEN;
  Result.GlyphFormat:=OHS_GLYPH_NONE;
  Result.Glyph:=nil;
  if FCommand=nil then
    Exit;
  try
    Result.Id:=OhsStr(FCommand.GetId);
    Result.Caption:=OhsStr(FCommand.GetCaption);
    Result.Hint:=OhsStr(FCommand.GetHint);
    Result.Kind:=FCommand.GetKind;
    Result.State:=FCommand.GetState;
    lData:=nil;
    lSize:=0;
    Result.GlyphFormat:=FCommand.GetGlyph(lData,lSize);
    if (Result.GlyphFormat<>OHS_GLYPH_NONE) and (lData<>nil) and (lSize>0) then
    begin
      SetLength(Result.Glyph,lSize);
      Move(lData^,Result.Glyph[0],lSize);
    end
    else
      Result.GlyphFormat:=OHS_GLYPH_NONE;
  except
    Result.State:=OHS_STATE_DISABLED;
  end;
end;

function TOhsContribution.CellText(const aRow: IOhsContext): string;
begin
  Result:='';
  if FProvider=nil then
    Exit;
  try
    Result:=OhsStr(FProvider.GetCellText(aRow,POhsChar(UTF8String(FField))));
  except
    Result:='';
  end;
end;

{ TOhsUIAdapter }

destructor TOhsUIAdapter.Destroy;
begin
  if FRegistry<>nil then
    FRegistry.UnregisterAdapter(Self);
  inherited Destroy;
end;

procedure TOhsUIAdapter.Execute(aItem: TOhsContribution; aExtra: TOhsContext);
begin
  if FRegistry<>nil then
    FRegistry.ExecuteCommand(aItem,aExtra);
end;

function TOhsUIAdapter.CreatePanel(aItem: TOhsContribution): IOhsPanel;
begin
  Result:=nil;
end;

procedure TOhsUIAdapter.Update(aItem: TOhsContribution);
begin
end;

procedure TOhsUIAdapter.AddContext(aContext: TOhsContext);
begin
end;

{ TOhsUIRegistry }

constructor TOhsUIRegistry.Create;
begin
  inherited Create;
  FAdapters:=TList.Create;
  FItems:=TList.Create;
  FSubscriptions:=TList.Create;
  FInfo:=TStringList.Create;
  FInfo.Values[OHS_HOST_UI]:='none';
end;

destructor TOhsUIRegistry.Destroy;
var
  i: Integer;
begin
  for i:=FSubscriptions.Count-1 downto 0 do
    TObject(FSubscriptions[i]).Free;
  FSubscriptions.Free;
  // the controls belong to the host and go with it; only let go of the plugin objects
  for i:=FItems.Count-1 downto 0 do
    TOhsContribution(FItems[i]).Free;
  FItems.Free;
  for i:=0 to FAdapters.Count-1 do
    TOhsUIAdapter(FAdapters[i]).FRegistry:=nil;
  FAdapters.Free;
  FInfo.Free;
  inherited Destroy;
end;

function TOhsUIRegistry.NewHandle: Integer;
begin
  Inc(FNextHandle);
  Result:=FNextHandle;
end;

function TOhsUIRegistry.GetCount: Integer;
begin
  Result:=FItems.Count;
end;

function TOhsUIRegistry.GetItem(aIndex: Integer): TOhsContribution;
begin
  Result:=TOhsContribution(FItems[aIndex]);
end;

function TOhsUIRegistry.FindAdapter(const aLocation: TOhsLocation): TOhsUIAdapter;
var
  i: Integer;
begin
  // the adapter registered last wins, so a host can override a standard one
  for i:=FAdapters.Count-1 downto 0 do
  begin
    Result:=TOhsUIAdapter(FAdapters[i]);
    if Result.Handles(aLocation) then
      Exit;
  end;
  Result:=nil;
end;

procedure TOhsUIRegistry.RegisterAdapter(aAdapter: TOhsUIAdapter);
var
  i: Integer;
  lItem: TOhsContribution;
begin
  if FAdapters.IndexOf(aAdapter)>=0 then
    Exit;
  if aAdapter.FRegistry<>nil then
    aAdapter.FRegistry.UnregisterAdapter(aAdapter);
  aAdapter.FRegistry:=Self;
  FAdapters.Add(aAdapter);
  // hand over what was waiting for it, in order
  for i:=0 to FItems.Count-1 do
  begin
    lItem:=TOhsContribution(FItems[i]);
    if (lItem.FAdapter=nil) and (lItem.FKind<>ockPanel) and aAdapter.Handles(lItem.FLocation) then
      Show(lItem);
  end;
end;

procedure TOhsUIRegistry.UnregisterAdapter(aAdapter: TOhsUIAdapter);
var
  i: Integer;
  lItem: TOhsContribution;
begin
  if FAdapters.IndexOf(aAdapter)<0 then
    Exit;
  for i:=FItems.Count-1 downto 0 do
  begin
    lItem:=TOhsContribution(FItems[i]);
    if lItem.FAdapter=aAdapter then
    begin
      Hide(lItem);
      // a panel cannot wait for another adapter: its plugin holds the controls
      if lItem.FKind=ockPanel then
      begin
        FItems.Delete(i);
        lItem.Free;
      end;
    end;
  end;
  FAdapters.Remove(aAdapter);
  aAdapter.FRegistry:=nil;
end;

procedure TOhsUIRegistry.Show(aItem: TOhsContribution);
var
  lAdapter: TOhsUIAdapter;
begin
  lAdapter:=FindAdapter(aItem.FLocation);
  if lAdapter=nil then
    Exit;
  aItem.FAdapter:=lAdapter;
  try
    lAdapter.Add(aItem);
  except
    on E: Exception do
    begin
      aItem.FAdapter:=nil;
      Log(Format('Cannot show %s: %s',[aItem.FLocation.Text,E.Message]));
    end;
  end;
end;

procedure TOhsUIRegistry.Hide(aItem: TOhsContribution);
begin
  if aItem.FAdapter=nil then
    Exit;
  try
    aItem.FAdapter.Remove(aItem);
  except
    on E: Exception do
      Log(Format('Cannot remove from %s: %s',[aItem.FLocation.Text,E.Message]));
  end;
  aItem.FAdapter:=nil;
  aItem.Element:=nil;
  aItem.Data:=nil;
end;

function TOhsUIRegistry.HasLocation(const aLocation: string): Boolean;
begin
  Result:=FindAdapter(OhsParseLocation(aLocation))<>nil;
end;

function TOhsUIRegistry.AddItem(aOwner: TObject; aKind: TOhsContributionKind;
  const aLocation: string): TOhsContribution;
begin
  Result:=TOhsContribution.Create;
  Result.FHandle:=NewHandle;
  Result.FKind:=aKind;
  Result.FOwner:=aOwner;
  Result.FLocation:=OhsParseLocation(aLocation);
  Result.FOrder:=100;
end;

function TOhsUIRegistry.AddCommand(aOwner: TObject; const aLocation: string;
  const aCommand: IOhsCommand; aSize: Integer; aOrder: Integer): Integer;
var
  lItem: TOhsContribution;
begin
  Result:=0;
  if (aCommand=nil) or (aLocation='') then
    Exit;
  lItem:=AddItem(aOwner,ockCommand,aLocation);
  lItem.FCommand:=aCommand;
  lItem.FSize:=aSize;
  lItem.FOrder:=aOrder;
  FItems.Add(lItem);
  Show(lItem);
  Result:=lItem.FHandle;
end;

function TOhsUIRegistry.AddPanel(aOwner: TObject; const aLocation, aCaption: string;
  out aPanel: IOhsPanel): Integer;
var
  lItem: TOhsContribution;
  lAdapter: TOhsUIAdapter;
begin
  Result:=0;
  aPanel:=nil;
  lItem:=AddItem(aOwner,ockPanel,aLocation);
  lItem.FCaption:=aCaption;
  lAdapter:=FindAdapter(lItem.FLocation);
  if lAdapter<>nil then
    try
      lItem.FAdapter:=lAdapter;
      lItem.FPanel:=lAdapter.CreatePanel(lItem);
    except
      on E: Exception do
      begin
        lItem.FPanel:=nil;
        Log(Format('Cannot make a panel in %s: %s',[aLocation,E.Message]));
      end;
    end;
  if lItem.FPanel=nil then
  begin
    lItem.Free;
    Exit;
  end;
  FItems.Add(lItem);
  aPanel:=lItem.FPanel;
  Result:=lItem.FHandle;
end;

function TOhsUIRegistry.AddColumn(aOwner: TObject; const aLocation, aTitle, aField: string;
  aWidth: Integer; const aProvider: IOhsCellProvider): Integer;
var
  lItem: TOhsContribution;
begin
  Result:=0;
  if (aProvider=nil) or (aLocation='') then
    Exit;
  lItem:=AddItem(aOwner,ockColumn,aLocation);
  lItem.FCaption:=aTitle;
  lItem.FField:=aField;
  lItem.FWidth:=aWidth;
  lItem.FProvider:=aProvider;
  FItems.Add(lItem);
  Show(lItem);
  Result:=lItem.FHandle;
end;

function TOhsUIRegistry.Find(aHandle: Integer): TOhsContribution;
var
  i: Integer;
begin
  for i:=0 to FItems.Count-1 do
  begin
    Result:=TOhsContribution(FItems[i]);
    if Result.FHandle=aHandle then
      Exit;
  end;
  Result:=nil;
end;

procedure TOhsUIRegistry.Remove(aHandle: Integer; aOwner: TObject);
var
  lItem: TOhsContribution;
begin
  lItem:=Find(aHandle);
  if (lItem=nil) or ((aOwner<>nil) and (lItem.FOwner<>aOwner)) then
    Exit;
  Hide(lItem);
  FItems.Remove(lItem);
  lItem.Free;
end;

procedure TOhsUIRegistry.RemoveOwner(aOwner: TObject);
var
  i: Integer;
  lItem: TOhsContribution;
begin
  for i:=FItems.Count-1 downto 0 do
  begin
    lItem:=TOhsContribution(FItems[i]);
    if lItem.FOwner=aOwner then
    begin
      Hide(lItem);
      FItems.Delete(i);
      lItem.Free;
    end;
  end;
  UnsubscribeOwner(aOwner);
end;

procedure TOhsUIRegistry.CommandChanged(const aCommand: IOhsCommand);
var
  i: Integer;
  lItem: TOhsContribution;
begin
  for i:=0 to FItems.Count-1 do
  begin
    lItem:=TOhsContribution(FItems[i]);
    if (lItem.FAdapter<>nil) and (lItem.FCommand=aCommand) then
      try
        lItem.FAdapter.Update(lItem);
      except
        on E: Exception do
          Log('Cannot update a command: '+E.Message);
      end;
  end;
end;

procedure TOhsUIRegistry.ColumnChanged(aHandle: Integer);
var
  lItem: TOhsContribution;
begin
  lItem:=Find(aHandle);
  if (lItem<>nil) and (lItem.FAdapter<>nil) then
    try
      lItem.FAdapter.Update(lItem);
    except
      on E: Exception do
        Log('Cannot update a column: '+E.Message);
    end;
end;

function CompareItems(aLeft, aRight: Pointer): Integer;
begin
  Result:=TOhsContribution(aLeft).Order-TOhsContribution(aRight).Order;
  if Result=0 then
    Result:=TOhsContribution(aLeft).Handle-TOhsContribution(aRight).Handle;
end;

procedure TOhsUIRegistry.ItemsAt(const aLocation: string; aList: TList);
var
  i: Integer;
  lItem: TOhsContribution;
begin
  aList.Clear;
  for i:=0 to FItems.Count-1 do
  begin
    lItem:=TOhsContribution(FItems[i]);
    if (lItem.FAdapter<>nil) and SameText(lItem.FLocation.Text,aLocation) then
      aList.Add(lItem);
  end;
  aList.Sort(CompareItems);
end;

function TOhsUIRegistry.IndexAt(aItem: TOhsContribution): Integer;
var
  i: Integer;
  lItem: TOhsContribution;
begin
  Result:=0;
  for i:=0 to FItems.Count-1 do
  begin
    lItem:=TOhsContribution(FItems[i]);
    if (lItem<>aItem) and (lItem.FAdapter<>nil) and (lItem.Element<>nil)
      and SameText(lItem.FLocation.Text,aItem.FLocation.Text)
      and (CompareItems(lItem,aItem)<0) then
      Inc(Result);
  end;
end;

function TOhsUIRegistry.BuildContext: TOhsContext;
var
  i: Integer;
begin
  Result:=TOhsContext.Create;
  for i:=0 to FAdapters.Count-1 do
    try
      TOhsUIAdapter(FAdapters[i]).AddContext(Result);
    except
    end;
  if Assigned(FOnGetContext) then
    FOnGetContext(Result);
end;

procedure TOhsUIRegistry.ExecuteCommand(aItem: TOhsContribution; aExtra: TOhsContext);
var
  lContext: TOhsContext;
  lIntf: IOhsContext;
begin
  if (aItem=nil) or (aItem.FCommand=nil) then
    Exit;
  lContext:=BuildContext;
  lIntf:=lContext;
  lContext.SetValue(OHS_CTX_LOCATION,aItem.FLocation.Text);
  if aExtra<>nil then
    lContext.AddFrom(aExtra);
  try
    aItem.FCommand.Execute(lIntf);
  except
    on E: Exception do
      Log('Command failed: '+E.Message);
  end;
end;

function TOhsUIRegistry.Subscribe(aOwner: TObject; const aEvent: string;
  const aSink: IOhsEventSink): Integer;
var
  lSub: TOhsSubscription;
begin
  Result:=0;
  if aSink=nil then
    Exit;
  lSub:=TOhsSubscription.Create;
  lSub.Handle:=NewHandle;
  lSub.Owner:=aOwner;
  lSub.Event:=aEvent;
  lSub.Sink:=aSink;
  FSubscriptions.Add(lSub);
  Result:=lSub.Handle;
end;

procedure TOhsUIRegistry.Unsubscribe(aHandle: Integer);
var
  i: Integer;
begin
  for i:=FSubscriptions.Count-1 downto 0 do
    if TOhsSubscription(FSubscriptions[i]).Handle=aHandle then
    begin
      TObject(FSubscriptions[i]).Free;
      FSubscriptions.Delete(i);
    end;
end;

procedure TOhsUIRegistry.UnsubscribeOwner(aOwner: TObject);
var
  i: Integer;
begin
  for i:=FSubscriptions.Count-1 downto 0 do
    if TOhsSubscription(FSubscriptions[i]).Owner=aOwner then
    begin
      TObject(FSubscriptions[i]).Free;
      FSubscriptions.Delete(i);
    end;
end;

procedure TOhsUIRegistry.Publish(const aEvent: string; aContext: TOhsContext);
var
  i: Integer;
  lSinks: array of IOhsEventSink;
  lIntf: IOhsContext;
begin
  // copy first: a handler may subscribe or unsubscribe
  lSinks:=nil;
  for i:=0 to FSubscriptions.Count-1 do
    if SameText(TOhsSubscription(FSubscriptions[i]).Event,aEvent) then
    begin
      SetLength(lSinks,Length(lSinks)+1);
      lSinks[High(lSinks)]:=TOhsSubscription(FSubscriptions[i]).Sink;
    end;
  if lSinks=nil then
  begin
    if aContext<>nil then
      aContext.Free;
    Exit;
  end;
  if aContext=nil then
    aContext:=BuildContext;
  lIntf:=aContext;
  for i:=0 to High(lSinks) do
    try
      lSinks[i].HandleEvent(POhsChar(UTF8String(aEvent)),lIntf);
    except
      on E: Exception do
        Log('Event handler failed: '+E.Message);
    end;
end;

procedure TOhsUIRegistry.Message(aKind: Integer; const aText: string);
begin
  if Assigned(FOnMessage) then
    FOnMessage(aKind,aText)
  else
    Log(aText);
end;

procedure TOhsUIRegistry.Log(const aText: string);
begin
  if Assigned(FOnLog) then
    FOnLog(aText);
end;

{ TOhsPluginSite }

constructor TOhsPluginSite.Create(aRegistry: TOhsUIRegistry; const aName: string);
begin
  inherited Create;
  FRegistry:=aRegistry;
  FName:=aName;
end;

procedure TOhsPluginSite.Detach;
begin
  if FRegistry<>nil then
    FRegistry.RemoveOwner(Self);
  FRegistry:=nil;
end;

function TOhsPluginSite.GetApiVersion: Integer; stdcall;
begin
  Result:=OHS_PLUGIN_API_VERSION;
end;

function TOhsPluginSite.GetInfo(aKey: POhsChar): POhsChar; stdcall;
begin
  if FRegistry=nil then
    FInfoValue:=''
  else
    FInfoValue:=FRegistry.Info.Values[OhsStr(aKey)];
  Result:=POhsChar(FInfoValue);
end;

function TOhsPluginSite.UI: IOhsUI; stdcall;
begin
  Result:=Self;
end;

procedure TOhsPluginSite.ShowMessage(aKind: Integer; aText: POhsChar); stdcall;
begin
  if FRegistry<>nil then
    try
      FRegistry.Message(aKind,OhsStr(aText));
    except
    end;
end;

procedure TOhsPluginSite.Log(aText: POhsChar); stdcall;
begin
  if FRegistry<>nil then
    try
      FRegistry.Log('['+FName+'] '+OhsStr(aText));
    except
    end;
end;

function TOhsPluginSite.GetContext: IOhsContext; stdcall;
begin
  if FRegistry=nil then
    Result:=TOhsContext.Create
  else
    try
      Result:=FRegistry.BuildContext;
    except
      Result:=TOhsContext.Create;
    end;
end;

function TOhsPluginSite.Subscribe(aEvent: POhsChar; const aSink: IOhsEventSink): Integer; stdcall;
begin
  Result:=0;
  if FRegistry<>nil then
    try
      Result:=FRegistry.Subscribe(Self,OhsStr(aEvent),aSink);
    except
      Result:=0;
    end;
end;

procedure TOhsPluginSite.Unsubscribe(aHandle: Integer); stdcall;
begin
  if FRegistry<>nil then
    try
      FRegistry.Unsubscribe(aHandle);
    except
    end;
end;

function TOhsPluginSite.HasLocation(aLocation: POhsChar): LongBool; stdcall;
begin
  Result:=False;
  if FRegistry<>nil then
    try
      Result:=FRegistry.HasLocation(OhsStr(aLocation));
    except
      Result:=False;
    end;
end;

function TOhsPluginSite.AddCommand(aLocation: POhsChar; const aCommand: IOhsCommand;
  aSize, aOrder: Integer): Integer; stdcall;
begin
  Result:=0;
  if FRegistry<>nil then
    try
      Result:=FRegistry.AddCommand(Self,OhsStr(aLocation),aCommand,aSize,aOrder);
    except
      on E: Exception do
      begin
        FRegistry.Log('AddCommand failed: '+E.Message);
        Result:=0;
      end;
    end;
end;

function TOhsPluginSite.AddPanel(aLocation, aCaption: POhsChar; out aPanel: IOhsPanel): Integer; stdcall;
begin
  Result:=0;
  aPanel:=nil;
  if FRegistry<>nil then
    try
      Result:=FRegistry.AddPanel(Self,OhsStr(aLocation),OhsStr(aCaption),aPanel);
    except
      on E: Exception do
      begin
        FRegistry.Log('AddPanel failed: '+E.Message);
        Result:=0;
      end;
    end;
end;

function TOhsPluginSite.AddColumn(aLocation, aTitle, aField: POhsChar; aWidth: Integer;
  const aProvider: IOhsCellProvider): Integer; stdcall;
begin
  Result:=0;
  if FRegistry<>nil then
    try
      Result:=FRegistry.AddColumn(Self,OhsStr(aLocation),OhsStr(aTitle),OhsStr(aField),aWidth,aProvider);
    except
      on E: Exception do
      begin
        FRegistry.Log('AddColumn failed: '+E.Message);
        Result:=0;
      end;
    end;
end;

procedure TOhsPluginSite.Remove(aHandle: Integer); stdcall;
begin
  if FRegistry<>nil then
    try
      FRegistry.Remove(aHandle,Self);
    except
    end;
end;

procedure TOhsPluginSite.CommandChanged(const aCommand: IOhsCommand); stdcall;
begin
  if FRegistry<>nil then
    try
      FRegistry.CommandChanged(aCommand);
    except
    end;
end;

procedure TOhsPluginSite.ColumnChanged(aHandle: Integer); stdcall;
begin
  if FRegistry<>nil then
    try
      FRegistry.ColumnChanged(aHandle);
    except
    end;
end;

end.
