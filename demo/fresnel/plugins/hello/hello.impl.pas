{ The hello plugin: one of everything a plugin can add.

  - ribbon:Plugins/Hello      a large button with a glyph, and a toggle
  - ribbon.quick:             the same button in the quick access toolbar
  - toolbar:main              button, separator and toggle
  - menu:gantt.context        an item on the table's context menu
  - panel:side                a panel with a label, an edit, a combo box, a check box
                              and a button; it follows the selected activity
  - gantt:main                a Note column with the notes typed in the panel

  It uses only ohs.plugin.api and ohs.plugin.helpers: no Fresnel, no LCL. }
unit hello.impl;

{$mode Delphi}{$H+}
{$INTERFACES COM}

interface

uses
  Classes, SysUtils, ohs.plugin.api, ohs.plugin.helpers;

type
  THelloPlugin = class(TOhsPlugin)
  private
    FSayHello: TOhsCommand;
    FShowNotes: TOhsCommand;
    FNotes: TStringList; // activity code=note
    FPanel: IOhsPanel;
    FActivityLabel: IOhsControl;
    FNoteEdit: IOhsControl;
    FGreeting: IOhsControl;
    FNoteColumn: Integer;
    FCurrentCode: string;
    procedure SayHello(Sender: TOhsCommand; const aContext: IOhsContext);
    procedure ToggleNotes(Sender: TOhsCommand; const aContext: IOhsContext);
    procedure CopyCode(Sender: TOhsCommand; const aContext: IOhsContext);
    procedure SelectionChanged(const aEvent: string; const aContext: IOhsContext);
    procedure PanelEvent(const aControl: IOhsControl; aEvent: Integer);
    function NoteText(const aRow: IOhsContext; const aField: string): string;
    procedure ShowActivity(const aContext: IOhsContext);
    function Greeting: string;
  protected
    procedure DoInitialize; override;
    procedure DoFinalize; override;
  public
    constructor Create;
    destructor Destroy; override;
  end;

function OhsPluginEntry(aApiVersion: Integer; out aPlugin: IOhsPlugin): Integer; stdcall;

implementation

{$I ..\common\demoglyphs.inc}

function OhsPluginEntry(aApiVersion: Integer; out aPlugin: IOhsPlugin): Integer; stdcall;
begin
  aPlugin:=nil;
  if aApiVersion<>OHS_PLUGIN_API_VERSION then
    Exit(OHS_E_API_VERSION);
  try
    aPlugin:=THelloPlugin.Create;
    Result:=OHS_OK;
  except
    Result:=OHS_E_FAILED;
  end;
end;

{ THelloPlugin }

constructor THelloPlugin.Create;
begin
  inherited Create('com.owlhat.demo.hello','Hello plugin','1.0');
  SetInfo(OHS_INFO_AUTHOR,'OwlHat Software');
  SetInfo(OHS_INFO_DESCRIPTION,'Shows every kind of contribution a plugin can make.');
  FNotes:=TStringList.Create;
end;

destructor THelloPlugin.Destroy;
begin
  FNotes.Free;
  inherited Destroy;
end;

procedure THelloPlugin.DoInitialize;
var
  lCommand: TOhsCommand;
  lRow: IOhsPanel;
begin
  FSayHello:=TOhsCommand.Create('hello.say','Say hello',SayHello);
  FSayHello.Hint:='Greets the selected activity';
  FSayHello.SetGlyphPNG(cGlyph_hello);
  AddCommand('ribbon:Plugins/Hello',FSayHello,OHS_SIZE_LARGE,10);
  AddCommand('ribbon.quick:',FSayHello,OHS_SIZE_SMALL,10);
  AddCommand('toolbar:main',FSayHello,OHS_SIZE_DEFAULT,10);

  FShowNotes:=TOhsCommand.Create('hello.notes','Notes column',ToggleNotes,OHS_CMD_TOGGLE);
  FShowNotes.Hint:='Shows or hides the Note column';
  FShowNotes.SetGlyphPNG(cGlyph_note);
  FShowNotes.Checked:=True;
  AddCommand('ribbon:Plugins/Hello',FShowNotes,OHS_SIZE_MEDIUM,20);
  AddCommand('toolbar:main',TOhsCommand.Create('hello.sep','-',nil,OHS_CMD_SEPARATOR),OHS_SIZE_DEFAULT,15);
  AddCommand('toolbar:main',FShowNotes,OHS_SIZE_DEFAULT,20);

  lCommand:=TOhsCommand.Create('hello.copy','Show activity code (hello)',CopyCode);
  AddCommand('menu:gantt.context',lCommand);

  // A panel, when the host has a side area
  if AddPanel('panel:side','Hello plugin',FPanel)<>0 then
  begin
    FActivityLabel:=FPanel.AddControl(OHS_CTRL_LABEL,'activity','No activity selected');
    FPanel.AddControl(OHS_CTRL_LABEL,'',POhsChar('Note for this activity:'));
    FNoteEdit:=FPanel.AddControl(OHS_CTRL_EDIT,'note','Type a note');
    lRow:=FPanel.AddControl(OHS_CTRL_ROW,'buttons','').AsPanel;
    lRow.AddControl(OHS_CTRL_BUTTON,'save','Save note');
    lRow.AddControl(OHS_CTRL_BUTTON,'clear','Clear');
    FGreeting:=FPanel.AddControl(OHS_CTRL_COMBOBOX,'greeting','');
    FGreeting.SetItems('Hello'#10'Hallo'#10'Bonjour'#10'Hola');
    FGreeting.SetItemIndex(0);
    FPanel.AddControl(OHS_CTRL_CHECKBOX,'shownotes','Show the Note column').SetChecked(True);
    FPanel.SetEvents(TOhsControlEvents.Create(PanelEvent));
  end;

  FNoteColumn:=AddColumn('gantt:main','Note','note',140,NoteText);
  Subscribe(OHS_EVENT_SELECTION,SelectionChanged);
  ShowActivity(Host.GetContext);
  Log('started');
end;

procedure THelloPlugin.DoFinalize;
begin
  // drop every host object; the host removes the controls itself
  FActivityLabel:=nil;
  FNoteEdit:=nil;
  FGreeting:=nil;
  if FPanel<>nil then
    FPanel.SetEvents(nil);
  FPanel:=nil;
end;

function THelloPlugin.Greeting: string;
begin
  Result:='Hello';
  if FGreeting<>nil then
    Result:=OhsStr(FGreeting.GetText);
  if Result='' then
    Result:='Hello';
end;

procedure THelloPlugin.SayHello(Sender: TOhsCommand; const aContext: IOhsContext);
var
  lName: string;
begin
  lName:=OhsContextValue(aContext,OHS_CTX_ACTIVITY_NAME);
  if lName='' then
    lName:='world';
  ShowMessage(Format('%s, %s! (from %s)',[Greeting,lName,OhsContextValue(aContext,OHS_CTX_LOCATION)]));
end;

procedure THelloPlugin.ToggleNotes(Sender: TOhsCommand; const aContext: IOhsContext);
var
  lCheck: IOhsControl;
begin
  // the toggle already flipped Checked
  if Sender.Checked then
  begin
    if FNoteColumn=0 then
      FNoteColumn:=AddColumn('gantt:main','Note','note',140,NoteText);
  end
  else if FNoteColumn<>0 then
  begin
    Host.UI.Remove(FNoteColumn);
    FNoteColumn:=0;
  end;
  Sender.Changed;
  if FPanel<>nil then
  begin
    lCheck:=FPanel.FindControl('shownotes');
    if (lCheck<>nil) and (lCheck.GetChecked<>Sender.Checked) then
      lCheck.SetChecked(Sender.Checked);
  end;
end;

procedure THelloPlugin.CopyCode(Sender: TOhsCommand; const aContext: IOhsContext);
var
  lCode: string;
begin
  lCode:=OhsContextValue(aContext,OHS_CTX_ACTIVITY_CODE);
  if lCode='' then
    ShowMessage('Select an activity first',OHS_MSG_WARNING)
  else
    ShowMessage('Activity code: '+lCode);
end;

procedure THelloPlugin.ShowActivity(const aContext: IOhsContext);
var
  lName: string;
begin
  FCurrentCode:=OhsContextValue(aContext,OHS_CTX_ACTIVITY_CODE);
  lName:=OhsContextValue(aContext,OHS_CTX_ACTIVITY_NAME);
  if FActivityLabel<>nil then
    if FCurrentCode='' then
      FActivityLabel.SetText('No activity selected')
    else
      FActivityLabel.SetText(POhsChar(UTF8String(Format('%s  %s',[FCurrentCode,lName]))));
  if FNoteEdit<>nil then
    FNoteEdit.SetText(POhsChar(UTF8String(FNotes.Values[FCurrentCode])));
  FSayHello.Enabled:=True;
end;

procedure THelloPlugin.SelectionChanged(const aEvent: string; const aContext: IOhsContext);
begin
  ShowActivity(aContext);
end;

procedure THelloPlugin.PanelEvent(const aControl: IOhsControl; aEvent: Integer);
var
  lId: string;
begin
  lId:=OhsStr(aControl.GetId);
  if (lId='save') and (aEvent=OHS_EVT_CLICK) then
  begin
    if FCurrentCode='' then
    begin
      ShowMessage('Select an activity first',OHS_MSG_WARNING);
      Exit;
    end;
    FNotes.Values[FCurrentCode]:=OhsStr(FNoteEdit.GetText);
    if FNoteColumn<>0 then
      Host.UI.ColumnChanged(FNoteColumn);
    ShowMessage('Note saved for '+FCurrentCode);
  end
  else if (lId='clear') and (aEvent=OHS_EVT_CLICK) then
    FNoteEdit.SetText('')
  else if (lId='shownotes') and (aEvent=OHS_EVT_CHANGE) then
  begin
    if aControl.GetChecked<>FShowNotes.Checked then
      FShowNotes.Execute(Host.GetContext);
  end;
end;

function THelloPlugin.NoteText(const aRow: IOhsContext; const aField: string): string;
begin
  Result:=FNotes.Values[OhsContextValue(aRow,OHS_CTX_ACTIVITY_CODE)];
end;

end.
