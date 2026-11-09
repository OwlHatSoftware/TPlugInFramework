{ ohsPluginFramework - the binary interface between a host and its plugins.

  This is the only unit a plugin and a host must share. Everything that crosses the
  library boundary is declared here, and it is kept to what is safe across two
  separately compiled modules, each with its own RTL and memory manager:

  - COM style interfaces (reference counted; an object is always freed by the module
    that created it), with stdcall methods.
  - Strings are UTF-8 PAnsiChar. A string passed IN is only valid during the call;
    copy it if you need it later. A string RETURNED is owned by the object that
    returned it and stays valid until the next call on that same object.
  - Booleans are LongBool, numbers are Integer.
  - No Pascal classes, no AnsiString or dynamic arrays, no exceptions. An exception
    must never leave a method; the helpers in ohs.plugin.helpers catch them for you.

  A plugin never creates host controls. It describes commands, panels and columns,
  and the host builds them with the controls it uses (Fresnel, ohsRibbon,
  ohsMultiGrid, ohsGantt). That keeps plugins free of any UI library and lets the
  host change its UI without breaking them.

  Locations

  Where a contribution goes is a location string: '<kind>:<target>[/<path>...]'.
  The host decides which locations exist; a plugin can ask with HasLocation.
  The kinds the Fresnel adapters understand:

    ribbon:<Tab>/<Group>        a button in a ribbon group, tab and group made on demand
    ribbon.quick:               a button in the ribbon's quick access toolbar
    ribbon.context:<Context>/<Tab>/<Group>   a group on a contextual tab
    toolbar:<id>                a button on a toolbar the host registered as <id>
    menu:<id>                   an item on a menu (main or popup) the host registered
    panel:<id>                  a panel of controls inside a host area <id>
    grid:<id>                   a column on an ohsMultiGrid the host registered
    gantt:<id>                  a column on the table of an ohsGantt chart

  Unknown kinds are kept by the host and handed to an adapter registered later, so a
  host can add its own kinds without changing this unit. }
unit ohs.plugin.api;

{$IFDEF FPC}
  {$MODE Delphi}{$H+}
  {$INTERFACES COM}
{$ENDIF}

interface

const
  // Raise when a change breaks plugins built for the previous version.
  OHS_PLUGIN_API_VERSION = 1;

  // The name a plugin library exports its entry point under.
  OHS_PLUGIN_ENTRY = 'OhsPluginEntry';

  // Results of the entry point.
  OHS_OK               = 0;
  OHS_E_API_VERSION    = 1; // the plugin does not support the host's API version
  OHS_E_FAILED         = 2;

  // Keys of IOhsPlugin.GetInfo
  OHS_INFO_ID          = 'id';          // unique, for example 'com.owlhat.hello'
  OHS_INFO_NAME        = 'name';
  OHS_INFO_VERSION     = 'version';
  OHS_INFO_AUTHOR      = 'author';
  OHS_INFO_DESCRIPTION = 'description';

  // Keys of IOhsHost.GetInfo
  OHS_HOST_NAME        = 'host.name';
  OHS_HOST_VERSION     = 'host.version';
  OHS_HOST_UI          = 'host.ui';     // 'fresnel' for the Fresnel adapters
  OHS_HOST_PLUGINDIR   = 'host.plugindir';

  // IOhsCommand.GetKind
  OHS_CMD_BUTTON       = 0; // runs Execute
  OHS_CMD_TOGGLE       = 1; // flips its checked state; the plugin reports it in GetState
  OHS_CMD_SEPARATOR    = 2; // a divider in a menu or toolbar; nothing to execute

  // IOhsCommand.GetState, a set of flags; 0 is a normal, enabled, visible command
  OHS_STATE_DISABLED   = 1;
  OHS_STATE_CHECKED    = 2;
  OHS_STATE_HIDDEN     = 4;

  // Size hint for AddCommand; the host may choose another one when space runs out
  OHS_SIZE_DEFAULT     = 0;
  OHS_SIZE_LARGE       = 1; // large ribbon button with the glyph above the caption
  OHS_SIZE_MEDIUM      = 2; // small glyph and caption
  OHS_SIZE_SMALL       = 3; // glyph only

  // Glyph formats of IOhsCommand.GetGlyph
  OHS_GLYPH_NONE       = 0;
  OHS_GLYPH_PNG        = 1; // PNG bytes; 32x32 for large buttons, the host scales

  // Kinds of IOhsPanel.AddControl
  OHS_CTRL_LABEL       = 0;
  OHS_CTRL_BUTTON      = 1;
  OHS_CTRL_EDIT        = 2;
  OHS_CTRL_MEMO        = 3;
  OHS_CTRL_CHECKBOX    = 4;
  OHS_CTRL_COMBOBOX    = 5; // SetItems with lines separated by #10
  OHS_CTRL_GROUP       = 6; // a captioned box; use AsPanel to add controls to it
  OHS_CTRL_ROW         = 7; // a horizontal row; use AsPanel to add controls to it

  // IOhsControlEvents.Event
  OHS_EVT_CLICK        = 1;
  OHS_EVT_CHANGE       = 2;

  // IOhsHost.ShowMessage
  OHS_MSG_INFO         = 0;
  OHS_MSG_WARNING      = 1;
  OHS_MSG_ERROR        = 2;

  // Events a host publishes through IOhsHost.Subscribe. Hosts may add their own.
  OHS_EVENT_SELECTION  = 'selection';  // context: source, and what was selected
  OHS_EVENT_CLOSING    = 'closing';    // the host is about to close

  // Common context keys
  OHS_CTX_LOCATION     = 'location';   // where the command was run from
  OHS_CTX_SOURCE       = 'source';     // the id of the control the event came from
  OHS_CTX_ROW          = 'row';        // a grid row index
  OHS_CTX_ACTIVITY_CODE = 'activity.code';
  OHS_CTX_ACTIVITY_NAME = 'activity.name';

type
  POhsChar = PAnsiChar; // always UTF-8

  { A read only set of values, handed to commands, events and cell providers. }
  IOhsContext = interface
    ['{4E0B3E1A-6F0C-4C1B-9E44-2B7F2C3B8A01}']
    function GetCount: Integer; stdcall;
    function GetKey(aIndex: Integer): POhsChar; stdcall;
    // '' when the key is not there
    function GetValue(aKey: POhsChar): POhsChar; stdcall;
  end;

  { Something a user can run: a ribbon or toolbar button, or a menu item.
    The plugin implements it. The host asks for caption, glyph and state when it
    builds the control, and again after the plugin calls IOhsUI.CommandChanged. }
  IOhsCommand = interface
    ['{7C3D0F52-1B6A-4E9B-8A63-0E5D7F1C2B02}']
    function GetId: POhsChar; stdcall;
    function GetCaption: POhsChar; stdcall;
    function GetHint: POhsChar; stdcall;
    function GetKind: Integer; stdcall;          // OHS_CMD_*
    function GetState: Integer; stdcall;         // OHS_STATE_*
    // aData is owned by the command and valid while it lives
    function GetGlyph(out aData: Pointer; out aSize: Integer): Integer; stdcall; // OHS_GLYPH_*
    procedure Execute(const aContext: IOhsContext); stdcall;
  end;

  IOhsPanel = interface;

  { A control a host built for a plugin's panel. }
  IOhsControl = interface
    ['{2A9E6B13-5D4C-47F0-B1E8-6C3A9D0F4B03}']
    function GetId: POhsChar; stdcall;
    function GetKind: Integer; stdcall;
    function GetText: POhsChar; stdcall;
    procedure SetText(aText: POhsChar); stdcall;
    function GetChecked: LongBool; stdcall;
    procedure SetChecked(aValue: LongBool); stdcall;
    function GetItemIndex: Integer; stdcall;
    procedure SetItemIndex(aValue: Integer); stdcall;
    // Lines separated by #10
    procedure SetItems(aItems: POhsChar); stdcall;
    procedure SetEnabled(aValue: LongBool); stdcall;
    procedure SetVisible(aValue: LongBool); stdcall;
    procedure SetHint(aText: POhsChar); stdcall;
    // nil unless the control is a group or a row
    function AsPanel: IOhsPanel; stdcall;
  end;

  { Implemented by a plugin to hear about its panel controls. }
  IOhsControlEvents = interface
    ['{9F1C2D84-3E7B-4A65-8D29-1B4E7C6A0D04}']
    procedure ControlEvent(const aControl: IOhsControl; aEvent: Integer); stdcall; // OHS_EVT_*
  end;

  { A panel of controls the host built in one of its areas. }
  IOhsPanel = interface
    ['{5B8D4E26-0C9A-4F31-A7D6-3E2B1F8C5A05}']
    function AddControl(aKind: Integer; aId, aCaption: POhsChar): IOhsControl; stdcall;
    // nil when there is no control with that id in this panel or its groups
    function FindControl(aId: POhsChar): IOhsControl; stdcall;
    // One handler for all controls of the panel and its groups; nil to stop
    procedure SetEvents(const aEvents: IOhsControlEvents); stdcall;
    procedure SetCaption(aCaption: POhsChar); stdcall;
    procedure Clear; stdcall;
  end;

  { Implemented by a plugin to fill a column it added to a grid or Gantt table.
    aRow carries what the host knows of the row, such as OHS_CTX_ROW or the
    activity keys. }
  IOhsCellProvider = interface
    ['{C6E2A0B7-8D15-4F9C-9B3A-4D7E0F2C6B06}']
    function GetCellText(const aRow: IOhsContext; aField: POhsChar): POhsChar; stdcall;
  end;

  { Implemented by a plugin to hear about host events. }
  IOhsEventSink = interface
    ['{E1D7B3C8-2F46-4A0E-8C51-7A9F3B2D4E07}']
    procedure HandleEvent(aEvent: POhsChar; const aContext: IOhsContext); stdcall;
  end;

  { What a plugin may add to the user interface. Everything a plugin adds is
    removed again when the plugin is unloaded.
    Commands and columns for a location nobody shows yet are kept, and appear when
    the host adds that location later (a contextual tab, a second grid). A panel
    needs its location to exist now: AddPanel returns 0 and no panel otherwise.
    Handles are never 0; 0 means the call failed. }
  IOhsUI = interface
    ['{0D4F8A39-6B21-4C7E-9E15-8F3A2C7B1D08}']
    function HasLocation(aLocation: POhsChar): LongBool; stdcall;
    // aOrder sorts the contributions of all plugins in one place, lowest first
    function AddCommand(aLocation: POhsChar; const aCommand: IOhsCommand;
      aSize, aOrder: Integer): Integer; stdcall;
    // A panel in a panel location. The panel lives until the plugin removes it.
    function AddPanel(aLocation, aCaption: POhsChar; out aPanel: IOhsPanel): Integer; stdcall;
    // A column in a grid or gantt location. aField is passed back to the provider.
    function AddColumn(aLocation, aTitle, aField: POhsChar; aWidth: Integer;
      const aProvider: IOhsCellProvider): Integer; stdcall;
    procedure Remove(aHandle: Integer); stdcall;
    // Call after the caption, glyph or state of a command changed
    procedure CommandChanged(const aCommand: IOhsCommand); stdcall;
    // Call after the cell texts of a column changed
    procedure ColumnChanged(aHandle: Integer); stdcall;
  end;

  { The host as one plugin sees it. Each plugin gets its own, so the host knows
    whose contributions to remove. }
  IOhsHost = interface
    ['{8A2C5E41-9D37-4B6F-A0C8-5E1D3B7F2A09}']
    function GetApiVersion: Integer; stdcall;
    function GetInfo(aKey: POhsChar): POhsChar; stdcall;
    function UI: IOhsUI; stdcall;
    procedure ShowMessage(aKind: Integer; aText: POhsChar); stdcall;
    procedure Log(aText: POhsChar); stdcall;
    // The context the user is in now, such as the selected activity
    function GetContext: IOhsContext; stdcall;
    function Subscribe(aEvent: POhsChar; const aSink: IOhsEventSink): Integer; stdcall;
    procedure Unsubscribe(aHandle: Integer); stdcall;
  end;

  { The plugin. Initialize is where it adds its commands and panels; Finalize
    must drop every reference it holds to host objects. }
  IOhsPlugin = interface
    ['{B3F9D6E2-4A58-4C1D-8B7E-9C2A5F0D3E10}']
    function GetInfo(aKey: POhsChar): POhsChar; stdcall;
    function Initialize(const aHost: IOhsHost): LongBool; stdcall;
    procedure Finalize; stdcall;
  end;

  { The function each plugin library exports as OHS_PLUGIN_ENTRY. }
  TOhsPluginEntry = function(aApiVersion: Integer; out aPlugin: IOhsPlugin): Integer; stdcall;

implementation

end.
