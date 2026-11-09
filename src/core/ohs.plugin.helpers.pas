{ ohsPluginFramework - ready made implementations of the API interfaces.

  Plugins use these to write commands, event handlers and cell providers with
  ordinary method pointers instead of implementing the interfaces by hand. The host
  side uses TOhsContext too. Every call coming in from the other module is guarded,
  so an exception never crosses the library boundary.

  Only the FCL is used: a plugin built on this unit links no UI library. }
unit ohs.plugin.helpers;

{$IFDEF FPC}
  {$MODE Delphi}{$H+}
  {$INTERFACES COM}
{$ENDIF}

interface

uses
  Classes, SysUtils, ohs.plugin.api;

{ A string from the other side of the boundary as a Pascal string. }
function OhsStr(aValue: POhsChar): string;
// A context value as a string; '' when there is no context
function OhsContextValue(const aContext: IOhsContext; const aKey: string): string;

type
  TOhsBytes = array of Byte;

  { IOhsContext over a list of name=value pairs. }
  TOhsContext = class(TInterfacedObject, IOhsContext)
  private
    FValues: TStringList;
    FLastKey: string;
    FLastValue: string;
  public
    constructor Create;
    destructor Destroy; override;
    procedure SetValue(const aKey, aValue: string);
    procedure AddFrom(const aContext: IOhsContext);
    // IOhsContext
    function GetCount: Integer; stdcall;
    function GetKey(aIndex: Integer): POhsChar; stdcall;
    function GetValue(aKey: POhsChar): POhsChar; stdcall;
    property Values: TStringList read FValues;
  end;

  TOhsCommand = class;
  TOhsCommandEvent = procedure(Sender: TOhsCommand; const aContext: IOhsContext) of object;

  { IOhsCommand with properties. After changing Caption, Enabled, Checked or the
    glyph of a command that is already shown, call Changed so the host updates it. }
  TOhsCommand = class(TInterfacedObject, IOhsCommand)
  private
    FId: string;
    FCaption: string;
    FHint: string;
    FKind: Integer;
    FEnabled: Boolean;
    FChecked: Boolean;
    FVisible: Boolean;
    FGlyph: TOhsBytes;
    FUI: IOhsUI;
    FOnExecute: TOhsCommandEvent;
    FTag: PtrInt;
  public
    constructor Create(const aId, aCaption: string; aOnExecute: TOhsCommandEvent = nil;
      aKind: Integer = OHS_CMD_BUTTON);
    // Tells the host to read caption, glyph and state again. Needs UI to be set,
    // which TOhsPlugin.AddCommand does.
    procedure Changed;
    procedure SetGlyphPNG(const aData: array of Byte);
    procedure LoadGlyphPNG(const aFileName: string);
    // IOhsCommand
    function GetId: POhsChar; stdcall;
    function GetCaption: POhsChar; stdcall;
    function GetHint: POhsChar; stdcall;
    function GetKind: Integer; stdcall;
    function GetState: Integer; stdcall;
    function GetGlyph(out aData: Pointer; out aSize: Integer): Integer; stdcall;
    procedure Execute(const aContext: IOhsContext); stdcall;
    property Id: string read FId;
    property Caption: string read FCaption write FCaption;
    property Hint: string read FHint write FHint;
    property Kind: Integer read FKind write FKind;
    property Enabled: Boolean read FEnabled write FEnabled;
    property Checked: Boolean read FChecked write FChecked;
    property Visible: Boolean read FVisible write FVisible;
    property UI: IOhsUI read FUI write FUI;
    property Tag: PtrInt read FTag write FTag;
    property OnExecute: TOhsCommandEvent read FOnExecute write FOnExecute;
  end;

  TOhsHostEvent = procedure(const aEvent: string; const aContext: IOhsContext) of object;

  { IOhsEventSink calling a method. }
  TOhsEventSink = class(TInterfacedObject, IOhsEventSink)
  private
    FHandler: TOhsHostEvent;
  public
    constructor Create(aHandler: TOhsHostEvent);
    procedure HandleEvent(aEvent: POhsChar; const aContext: IOhsContext); stdcall;
  end;

  TOhsCellTextEvent = function(const aRow: IOhsContext; const aField: string): string of object;

  { IOhsCellProvider calling a method. }
  TOhsCellProvider = class(TInterfacedObject, IOhsCellProvider)
  private
    FHandler: TOhsCellTextEvent;
    FText: string;
  public
    constructor Create(aHandler: TOhsCellTextEvent);
    function GetCellText(const aRow: IOhsContext; aField: POhsChar): POhsChar; stdcall;
  end;

  TOhsControlEventProc = procedure(const aControl: IOhsControl; aEvent: Integer) of object;

  { IOhsControlEvents calling a method. }
  TOhsControlEvents = class(TInterfacedObject, IOhsControlEvents)
  private
    FHandler: TOhsControlEventProc;
  public
    constructor Create(aHandler: TOhsControlEventProc);
    procedure ControlEvent(const aControl: IOhsControl; aEvent: Integer); stdcall;
  end;

  { A base for plugins. Override DoInitialize to add commands and panels, and
    DoFinalize to let go of what you keep. Host is valid between the two. }
  TOhsPlugin = class(TInterfacedObject, IOhsPlugin)
  private
    FHost: IOhsHost;
    FInfo: TStringList;
    FInfoValue: string;
    FSubscriptions: array of Integer;
    FCommands: TInterfaceList; // keeps the commands alive
    FCommandObjects: TList;
  protected
    procedure DoInitialize; virtual; abstract;
    procedure DoFinalize; virtual;
    procedure SetInfo(const aKey, aValue: string);
  public
    constructor Create(const aId, aName, aVersion: string);
    destructor Destroy; override;
    // Shortcuts to the host, safe to call when the host has no such location.
    function AddCommand(const aLocation: string; aCommand: TOhsCommand;
      aSize: Integer = OHS_SIZE_DEFAULT; aOrder: Integer = 100): Integer;
    function AddPanel(const aLocation, aCaption: string; out aPanel: IOhsPanel): Integer;
    function AddColumn(const aLocation, aTitle, aField: string; aWidth: Integer;
      aHandler: TOhsCellTextEvent): Integer;
    function Subscribe(const aEvent: string; aHandler: TOhsHostEvent): Integer;
    function HasLocation(const aLocation: string): Boolean;
    procedure ShowMessage(const aText: string; aKind: Integer = OHS_MSG_INFO);
    procedure Log(const aText: string);
    // IOhsPlugin
    function GetInfo(aKey: POhsChar): POhsChar; stdcall;
    function Initialize(const aHost: IOhsHost): LongBool; stdcall;
    procedure Finalize; stdcall;
    property Host: IOhsHost read FHost;
  end;

function OhsLoadFileBytes(const aFileName: string): TOhsBytes;
function OhsBytesOf(const aData: array of Byte): TOhsBytes;

implementation

function OhsStr(aValue: POhsChar): string;
begin
  if aValue=nil then
    Result:=''
  else
    Result:=string(UTF8String(aValue));
end;

function OhsContextValue(const aContext: IOhsContext; const aKey: string): string;
begin
  if aContext=nil then
    Exit('');
  Result:=OhsStr(aContext.GetValue(POhsChar(UTF8String(aKey))));
end;

function OhsLoadFileBytes(const aFileName: string): TOhsBytes;
var
  lStream: TFileStream;
begin
  Result:=nil;
  if not FileExists(aFileName) then
    Exit;
  lStream:=TFileStream.Create(aFileName,fmOpenRead or fmShareDenyWrite);
  try
    SetLength(Result,lStream.Size);
    if Length(Result)>0 then
      lStream.ReadBuffer(Result[0],Length(Result));
  finally
    lStream.Free;
  end;
end;

function OhsBytesOf(const aData: array of Byte): TOhsBytes;
begin
  Result:=nil;
  SetLength(Result,Length(aData));
  if Length(aData)>0 then
    Move(aData[0],Result[0],Length(aData));
end;

{ TOhsContext }

constructor TOhsContext.Create;
begin
  inherited Create;
  FValues:=TStringList.Create;
end;

destructor TOhsContext.Destroy;
begin
  FValues.Free;
  inherited Destroy;
end;

procedure TOhsContext.SetValue(const aKey, aValue: string);
begin
  FValues.Values[aKey]:=aValue;
  // Values[] deletes the pair on '', keep the key so a reader can see it is known
  if (aValue='') and (FValues.IndexOfName(aKey)<0) then
    FValues.Add(aKey+'=');
end;

procedure TOhsContext.AddFrom(const aContext: IOhsContext);
var
  i: Integer;
  lKey: string;
begin
  if aContext=nil then
    Exit;
  for i:=0 to aContext.GetCount-1 do
  begin
    lKey:=OhsStr(aContext.GetKey(i));
    SetValue(lKey,OhsStr(aContext.GetValue(POhsChar(UTF8String(lKey)))));
  end;
end;

function TOhsContext.GetCount: Integer; stdcall;
begin
  Result:=FValues.Count;
end;

function TOhsContext.GetKey(aIndex: Integer): POhsChar; stdcall;
begin
  if (aIndex<0) or (aIndex>=FValues.Count) then
    FLastKey:=''
  else
    FLastKey:=FValues.Names[aIndex];
  Result:=POhsChar(FLastKey);
end;

function TOhsContext.GetValue(aKey: POhsChar): POhsChar; stdcall;
begin
  FLastValue:=FValues.Values[OhsStr(aKey)];
  Result:=POhsChar(FLastValue);
end;

{ TOhsCommand }

constructor TOhsCommand.Create(const aId, aCaption: string; aOnExecute: TOhsCommandEvent;
  aKind: Integer);
begin
  inherited Create;
  FId:=aId;
  FCaption:=aCaption;
  FOnExecute:=aOnExecute;
  FKind:=aKind;
  FEnabled:=True;
  FVisible:=True;
end;

procedure TOhsCommand.Changed;
begin
  if FUI<>nil then
    FUI.CommandChanged(Self);
end;

procedure TOhsCommand.SetGlyphPNG(const aData: array of Byte);
begin
  FGlyph:=OhsBytesOf(aData);
end;

procedure TOhsCommand.LoadGlyphPNG(const aFileName: string);
begin
  FGlyph:=OhsLoadFileBytes(aFileName);
end;

function TOhsCommand.GetId: POhsChar; stdcall;
begin
  Result:=POhsChar(FId);
end;

function TOhsCommand.GetCaption: POhsChar; stdcall;
begin
  Result:=POhsChar(FCaption);
end;

function TOhsCommand.GetHint: POhsChar; stdcall;
begin
  Result:=POhsChar(FHint);
end;

function TOhsCommand.GetKind: Integer; stdcall;
begin
  Result:=FKind;
end;

function TOhsCommand.GetState: Integer; stdcall;
begin
  Result:=0;
  if not FEnabled then
    Result:=Result or OHS_STATE_DISABLED;
  if FChecked then
    Result:=Result or OHS_STATE_CHECKED;
  if not FVisible then
    Result:=Result or OHS_STATE_HIDDEN;
end;

function TOhsCommand.GetGlyph(out aData: Pointer; out aSize: Integer): Integer; stdcall;
begin
  aSize:=Length(FGlyph);
  if aSize=0 then
  begin
    aData:=nil;
    Exit(OHS_GLYPH_NONE);
  end;
  aData:=@FGlyph[0];
  Result:=OHS_GLYPH_PNG;
end;

procedure TOhsCommand.Execute(const aContext: IOhsContext); stdcall;
begin
  try
    if FKind=OHS_CMD_TOGGLE then
      FChecked:=not FChecked;
    if Assigned(FOnExecute) then
      FOnExecute(Self,aContext);
  except
    // never let an exception reach the host
  end;
end;

{ TOhsEventSink }

constructor TOhsEventSink.Create(aHandler: TOhsHostEvent);
begin
  inherited Create;
  FHandler:=aHandler;
end;

procedure TOhsEventSink.HandleEvent(aEvent: POhsChar; const aContext: IOhsContext); stdcall;
begin
  try
    if Assigned(FHandler) then
      FHandler(OhsStr(aEvent),aContext);
  except
  end;
end;

{ TOhsCellProvider }

constructor TOhsCellProvider.Create(aHandler: TOhsCellTextEvent);
begin
  inherited Create;
  FHandler:=aHandler;
end;

function TOhsCellProvider.GetCellText(const aRow: IOhsContext; aField: POhsChar): POhsChar; stdcall;
begin
  try
    if Assigned(FHandler) then
      FText:=FHandler(aRow,OhsStr(aField))
    else
      FText:='';
  except
    FText:='';
  end;
  Result:=POhsChar(FText);
end;

{ TOhsControlEvents }

constructor TOhsControlEvents.Create(aHandler: TOhsControlEventProc);
begin
  inherited Create;
  FHandler:=aHandler;
end;

procedure TOhsControlEvents.ControlEvent(const aControl: IOhsControl; aEvent: Integer); stdcall;
begin
  try
    if Assigned(FHandler) then
      FHandler(aControl,aEvent);
  except
  end;
end;

{ TOhsPlugin }

constructor TOhsPlugin.Create(const aId, aName, aVersion: string);
begin
  inherited Create;
  FInfo:=TStringList.Create;
  FCommands:=TInterfaceList.Create;
  FCommandObjects:=TList.Create;
  SetInfo(OHS_INFO_ID,aId);
  SetInfo(OHS_INFO_NAME,aName);
  SetInfo(OHS_INFO_VERSION,aVersion);
end;

destructor TOhsPlugin.Destroy;
begin
  FCommandObjects.Free;
  FCommands.Free;
  FInfo.Free;
  inherited Destroy;
end;

procedure TOhsPlugin.DoFinalize;
begin
end;

procedure TOhsPlugin.SetInfo(const aKey, aValue: string);
begin
  FInfo.Values[aKey]:=aValue;
end;

function TOhsPlugin.AddCommand(const aLocation: string; aCommand: TOhsCommand;
  aSize: Integer; aOrder: Integer): Integer;
begin
  Result:=0;
  if FHost=nil then
    Exit;
  aCommand.UI:=FHost.UI;
  // keep the object alive for as long as the plugin is, also when the host has no such location
  FCommands.Add(IOhsCommand(aCommand));
  FCommandObjects.Add(aCommand);
  Result:=FHost.UI.AddCommand(POhsChar(UTF8String(aLocation)),aCommand,aSize,aOrder);
end;

function TOhsPlugin.AddPanel(const aLocation, aCaption: string; out aPanel: IOhsPanel): Integer;
begin
  aPanel:=nil;
  Result:=0;
  if FHost<>nil then
    Result:=FHost.UI.AddPanel(POhsChar(UTF8String(aLocation)),POhsChar(UTF8String(aCaption)),aPanel);
end;

function TOhsPlugin.AddColumn(const aLocation, aTitle, aField: string; aWidth: Integer;
  aHandler: TOhsCellTextEvent): Integer;
begin
  Result:=0;
  if FHost<>nil then
    Result:=FHost.UI.AddColumn(POhsChar(UTF8String(aLocation)),POhsChar(UTF8String(aTitle)),
      POhsChar(UTF8String(aField)),aWidth,TOhsCellProvider.Create(aHandler));
end;

function TOhsPlugin.Subscribe(const aEvent: string; aHandler: TOhsHostEvent): Integer;
begin
  Result:=0;
  if FHost=nil then
    Exit;
  Result:=FHost.Subscribe(POhsChar(UTF8String(aEvent)),TOhsEventSink.Create(aHandler));
  if Result<>0 then
  begin
    SetLength(FSubscriptions,Length(FSubscriptions)+1);
    FSubscriptions[High(FSubscriptions)]:=Result;
  end;
end;

function TOhsPlugin.HasLocation(const aLocation: string): Boolean;
begin
  Result:=(FHost<>nil) and FHost.UI.HasLocation(POhsChar(UTF8String(aLocation)));
end;

procedure TOhsPlugin.ShowMessage(const aText: string; aKind: Integer);
begin
  if FHost<>nil then
    FHost.ShowMessage(aKind,POhsChar(UTF8String(aText)));
end;

procedure TOhsPlugin.Log(const aText: string);
begin
  if FHost<>nil then
    FHost.Log(POhsChar(UTF8String(aText)));
end;

function TOhsPlugin.GetInfo(aKey: POhsChar): POhsChar; stdcall;
begin
  FInfoValue:=FInfo.Values[OhsStr(aKey)];
  Result:=POhsChar(FInfoValue);
end;

function TOhsPlugin.Initialize(const aHost: IOhsHost): LongBool; stdcall;
begin
  FHost:=aHost;
  try
    DoInitialize;
    Result:=True;
  except
    on E: Exception do
    begin
      Log('Initialize failed: '+E.Message);
      Result:=False;
    end;
  end;
end;

procedure TOhsPlugin.Finalize; stdcall;
var
  i: Integer;
begin
  try
    DoFinalize;
  except
  end;
  if FHost<>nil then
    for i:=0 to High(FSubscriptions) do
      FHost.Unsubscribe(FSubscriptions[i]);
  FSubscriptions:=nil;
  for i:=0 to FCommandObjects.Count-1 do
    TOhsCommand(FCommandObjects[i]).UI:=nil;
  FCommandObjects.Clear;
  FCommands.Clear;
  FHost:=nil;
end;

end.
