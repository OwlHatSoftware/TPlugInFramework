{ The float check plugin: reads the schedule through the context it is given.

  - gantt:main                              a Float status column
  - ribbon:Plugins/Schedule check           a button that reports on the selected activity
  - ribbon.context:Activity tools/Activity/Float
                                            a button on the contextual tab the host shows
                                            while an activity is selected
  - menu:gantt.context                      the same check on the context menu }
unit floatcheck.impl;

{$mode Delphi}{$H+}
{$INTERFACES COM}

interface

uses
  Classes, SysUtils, ohs.plugin.api, ohs.plugin.helpers;

type
  TFloatCheckPlugin = class(TOhsPlugin)
  private
    FNearCritical: Integer;
    procedure CheckFloat(Sender: TOhsCommand; const aContext: IOhsContext);
    function FloatStatus(const aRow: IOhsContext; const aField: string): string;
  protected
    procedure DoInitialize; override;
  public
    constructor Create;
  end;

function OhsPluginEntry(aApiVersion: Integer; out aPlugin: IOhsPlugin): Integer; stdcall;

implementation

{$I ..\common\demoglyphs.inc}

function OhsPluginEntry(aApiVersion: Integer; out aPlugin: IOhsPlugin): Integer; stdcall;
begin
  aPlugin:=nil;
  if aApiVersion<>OHS_PLUGIN_API_VERSION then
    Exit(OHS_E_API_VERSION);
  aPlugin:=TFloatCheckPlugin.Create;
  Result:=OHS_OK;
end;

constructor TFloatCheckPlugin.Create;
begin
  inherited Create('com.owlhat.demo.floatcheck','Float check','1.0');
  SetInfo(OHS_INFO_DESCRIPTION,'Marks critical and near critical activities.');
  FNearCritical:=5;
end;

procedure TFloatCheckPlugin.DoInitialize;
var
  lCheck, lFlag: TOhsCommand;
begin
  lCheck:=TOhsCommand.Create('float.check','Check float',CheckFloat);
  lCheck.Hint:='Reports how much float the selected activity has';
  lCheck.SetGlyphPNG(cGlyph_float);
  AddCommand('ribbon:Plugins/Schedule check',lCheck,OHS_SIZE_LARGE);
  AddCommand('menu:gantt.context',lCheck);

  lFlag:=TOhsCommand.Create('float.flag','Float',CheckFloat);
  lFlag.SetGlyphPNG(cGlyph_flag);
  AddCommand('ribbon.context:Activity tools/Activity/Float',lFlag,OHS_SIZE_LARGE);

  AddColumn('gantt:main','Float status','floatstatus',90,FloatStatus);
end;

function TFloatCheckPlugin.FloatStatus(const aRow: IOhsContext; const aField: string): string;
var
  lFloat: Integer;
begin
  Result:='';
  if OhsContextValue(aRow,OHS_CTX_ACTIVITY_CODE)='' then
    Exit;
  lFloat:=StrToIntDef(OhsContextValue(aRow,'activity.totalfloat'),MaxInt);
  if OhsContextValue(aRow,'activity.critical')='true' then
    Result:='critical'
  else if lFloat<=FNearCritical then
    Result:='near critical'
  else
    Result:='ok';
end;

procedure TFloatCheckPlugin.CheckFloat(Sender: TOhsCommand; const aContext: IOhsContext);
var
  lCode: string;
begin
  lCode:=OhsContextValue(aContext,OHS_CTX_ACTIVITY_CODE);
  if lCode='' then
  begin
    ShowMessage('Select an activity to check its float',OHS_MSG_WARNING);
    Exit;
  end;
  ShowMessage(Format('%s %s: %s days total float, %s',[lCode,
    OhsContextValue(aContext,OHS_CTX_ACTIVITY_NAME),
    OhsContextValue(aContext,'activity.totalfloat'),
    FloatStatus(aContext,'')]));
end;

end.
