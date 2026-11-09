# ohsPluginFramework

Plugins in libraries (`.dll`, `.so`) for Free Pascal and Lazarus applications built on
[Fresnel](https://gitlab.com/freepascal.org/lazarus/fresnel). A plugin can add:

- buttons with glyphs to an **ohsRibbon**: in groups, on contextual tabs and in the quick access toolbar
- buttons, toggles and separators to a **toolbar**
- items to a **menu** or context menu
- **panels of controls** (label, button, edit, memo, check box, combo box, groups and rows) to an area of the host
- **columns** to an **ohsMultiGrid** or to the table of an **ohsGantt** chart

It hears about the selection, and every command it runs gets the context of the moment, such as the
selected activity.

It builds with FPC 3.2.2 for Windows (i386-win32) and Linux (x86_64-linux); macOS is prepared but
untested (see [Platforms](#platforms)). Fresnel, ohsRibbon, ohsMultiGrid and
ohsGanttComponents are expected next to this repository, with the Fresnel changes those packages need.

## How it works

A plugin never creates a host control. Host and plugin each have their own RTL, memory manager and
class types, so a Fresnel object cannot safely cross the library boundary. Instead the plugin
**describes** what it wants through COM-style interfaces in `ohs.plugin.api`, and the host **builds**
the real controls:

```
 plugin library                         host program
 ─────────────────                      ──────────────────────────────────────────────────
 TOhsPlugin  ── IOhsPlugin ──────────►  TOhsPluginManager   loads libraries, life cycle
 TOhsCommand ── IOhsCommand ────────►   TOhsUIRegistry      keeps every contribution
             ◄── IOhsHost / IOhsUI ──   TOhsPluginSite      one per plugin, tags what it adds
             ◄── IOhsPanel/IOhsControl  adapters            build the controls:
                                          TOhsRibbonAdapter      ribbon:…  ribbon.quick:  ribbon.context:…
                                          TOhsToolBarAdapter     toolbar:<id>
                                          TOhsMenuAdapter        menu:<id>
                                          TOhsPanelAdapter       panel:<id>
                                          TOhsMultiGridAdapter   grid:<id>
                                          TOhsGanttAdapter       gantt:<id>
```

What crosses the boundary: interfaces with `stdcall` methods, UTF-8 `PAnsiChar` strings, `Integer`
and `LongBool`. Each object is freed by the module that made it. No exception crosses: the helpers
and the registry catch them.

A plugin built on `ohs.plugin.api` and `ohs.plugin.helpers` links only the FCL. The demo plugins are
about 450 KB.

### Locations

Where a contribution goes is a string, `'<kind>:<target>[/<path>]'`. The host decides which exist by
registering adapters.

| Location | Adapter | What appears |
| --- | --- | --- |
| `ribbon:<Tab>/<Group>` | `TOhsRibbonAdapter` | A ribbon button; tab and group are made when missing |
| `ribbon.quick:` | `TOhsRibbonAdapter` | A button in the quick access toolbar |
| `ribbon.context:<Context>/<Tab>/<Group>` | `TOhsRibbonAdapter` | A button on a contextual tab; the host shows it with `SetContextVisible` |
| `toolbar:<id>` | `TOhsToolBarAdapter` | A `TButton` (or separator) in a container `TDiv` |
| `menu:<id>` | `TOhsMenuAdapter` | A `TMenuItem` under a menu item, such as the `Items` of a `TPopupMenu` |
| `panel:<id>` | `TOhsPanelAdapter` | A `TGroupBox` of controls in a container |
| `grid:<id>` | `TOhsMultiGridAdapter` | A column on a `TohsMultiGrid` |
| `gantt:<id>` | `TOhsGanttAdapter` | A column on the table of a `TohsGanttChart` |

Commands and columns for a location that does not exist yet are kept and appear when the host
registers its adapter, for example when it builds a second grid later. A panel needs its location
now. `IOhsUI.HasLocation` tells a plugin what the host offers.

Contributions to one place are sorted by the `aOrder` the plugins give, then by arrival. Separate
plugins that sort the same way stay in a fixed order, because libraries load in file name order.

### Context and events

When a command runs, the registry builds an `IOhsContext`: `location`, plus what every adapter knows.
The Gantt adapter adds the selected activity (`activity.code`, `activity.name`, `activity.duration`,
`activity.start`, `activity.finish`, `activity.totalfloat`, `activity.critical`,
`activity.milestone`); the grid adapter adds `grid` and `row`. Hosts can add their own keys with
`TOhsUIRegistry.OnGetContext`, `TOhsMultiGridAdapter.OnRowContext` or
`TOhsGanttAdapter.OnActivityContext`.

A column's cell provider gets the same keys for its row. Plugins subscribe to `selection`, which the
grid and Gantt adapters publish, or to any event a host publishes with `TOhsUIRegistry.Publish`.

## Host

Add the packages you need: `ohspluginframework_fresnel` and, as needed, `_ribbon`, `_multigrid`
and `_gantt` (each pulls in the core package `ohspluginframework`).

```pascal
uses ohs.plugin.api, ohs.plugin.registry, ohs.plugin.manager,
  ohs.plugin.fresnel.common, ohs.plugin.fresnel.panels, ohs.plugin.fresnel.ribbon,
  ohs.plugin.fresnel.gantt;

Stylesheet.Text := MyCSS + cOhsPluginCSS;      // default look of toolbars and panels

Registry := TOhsUIRegistry.Create;
Registry.Info.Values[OHS_HOST_NAME] := 'My planner';
Registry.OnMessage := PluginMessage;           // IOhsHost.ShowMessage

Registry.RegisterAdapter(TOhsRibbonAdapter.Create(Ribbon));
Registry.RegisterAdapter(TOhsToolBarAdapter.Create('main', ToolBarDiv));
Registry.RegisterAdapter(TOhsMenuAdapter.Create('gantt.context', GanttPopup.Items));
Registry.RegisterAdapter(TOhsPanelAdapter.Create('side', SideDiv));
Registry.RegisterAdapter(TOhsGanttAdapter.Create('main', Chart));  // after setting Chart's own events

Plugins := TOhsPluginManager.Create(Registry);
Plugins.LoadFromDirectory(ExtractFilePath(ParamStr(0)) + 'plugins');
```

On closing: free the manager first (it unloads the plugins while their controls still exist), then
the adapters, then the registry, then let the form free its controls. `TOhsPluginManager.AddPlugin`
adds a plugin compiled into the host, which goes through the same steps without a library.

## Plugin

A library that requires only the package `ohspluginframework`:

```pascal
library myplugin;
{$mode Delphi}{$H+}
uses ohs.plugin.api, ohs.plugin.helpers, SysUtils;

type
  TMyPlugin = class(TOhsPlugin)
  private
    procedure Report(Sender: TOhsCommand; const aContext: IOhsContext);
    function Status(const aRow: IOhsContext; const aField: string): string;
  protected
    procedure DoInitialize; override;
  end;

procedure TMyPlugin.DoInitialize;
var
  lCmd: TOhsCommand;
begin
  lCmd := TOhsCommand.Create('my.report', 'Report', Report);
  lCmd.LoadGlyphPNG(IncludeTrailingPathDelimiter(OhsStr(Host.GetInfo(OHS_HOST_PLUGINDIR))) + 'report.png');
  AddCommand('ribbon:Plugins/My tools', lCmd, OHS_SIZE_LARGE);
  AddCommand('toolbar:main', lCmd);
  AddColumn('gantt:main', 'Status', 'status', 80, Status);
end;

procedure TMyPlugin.Report(Sender: TOhsCommand; const aContext: IOhsContext);
begin
  ShowMessage('Selected: ' + OhsContextValue(aContext, OHS_CTX_ACTIVITY_CODE));
end;

function TMyPlugin.Status(const aRow: IOhsContext; const aField: string): string;
begin
  Result := OhsContextValue(aRow, 'activity.critical');
end;

function OhsPluginEntry(aApiVersion: Integer; out aPlugin: IOhsPlugin): Integer; stdcall;
begin
  aPlugin := nil;
  if aApiVersion <> OHS_PLUGIN_API_VERSION then
    Exit(OHS_E_API_VERSION);
  aPlugin := TMyPlugin.Create('com.example.my', 'My plugin', '1.0');
  Result := OHS_OK;
end;

exports OhsPluginEntry name 'OhsPluginEntry';
begin
end.
```

- `TOhsCommand` kinds: `OHS_CMD_BUTTON`, `OHS_CMD_TOGGLE` (flips `Checked` before `OnExecute`) and
  `OHS_CMD_SEPARATOR`. After changing `Caption`, `Enabled`, `Checked`, `Visible` or the glyph, call
  `Changed`.
- Glyphs are PNG bytes: `SetGlyphPNG` from a constant array (see `demo\fresnel\icons\make-icons.ps1`,
  which writes them as an include file) or `LoadGlyphPNG` from a file. 32×32 works for every size.
- Panels: `AddPanel('panel:side', 'Caption', Panel)`, then `Panel.AddControl(OHS_CTRL_EDIT, 'id', 'placeholder')`.
  `OHS_CTRL_GROUP` and `OHS_CTRL_ROW` return a control whose `AsPanel` takes more controls.
  `Panel.SetEvents` gets clicks and changes of all of them.
- `DoFinalize`: let go of every host interface you keep (panels, controls). The host removes what
  you added.

## Demo

`demo\fresnel` has a host with a ribbon, a toolbar, a Gantt chart with a context menu, and a side
area, and two plugins:

- `hello`: a button on the ribbon, quick access toolbar and toolbar; a toggle that shows and hides a
  column; a context menu item; a side panel that follows the selected activity and stores notes,
  shown in a Note column.
- `floatcheck`: a Float status column, a ribbon button, a context menu item and a button on the
  contextual tab *Activity tools*, which the host shows while an activity is selected.

The Home tab of the demo unloads and loads the plugins again.

## Build

On Windows:

```powershell
.\build.ps1
```

On Linux and macOS:

```bash
./build.sh
```

Both build the five packages, the plugins, the demo and the tests, run `test/testframework` and the
demo's `--selftest`, and must end with `BUILD OK, TESTS PASSED`. They register the packages in a
Lazarus configuration of their own under `out/`, not in the one of the IDE (`build.ps1` takes
`-LazarusConfig` to use yours). The demo is `demo/fresnel/out/<cpu>-<os>/ohsplugindemo`, with the
plugins in `plugins/` beside it: `hello.dll` on Windows, `libhello.so` on Linux, `libhello.dylib` on
macOS. The manager loads whatever has the platform's library extension.

`build.sh` expects the libraries in `../../lazarus_libraries` as on Windows; set `LIBS_DIR` (or
`FRESNEL_DIR`, `RIBBON_DIR`, `MULTIGRID_DIR`, `GANTT_DIR`) when they are elsewhere. Without a
display it skips the demo self test.

`ohsplugindemo --capture=shot.png --tab=Plugins` writes a screenshot.

### Platforms

| Target | Status |
| --- | --- |
| i386-win32 | Built and tested: FPC 3.2.2, Lazarus 4.8 |
| x86_64-linux | Built and tested: FPC 3.2.2, Lazarus 4.4, GTK3, in WSL with WSLg |
| macOS (x86_64, aarch64) | Not built or tested yet. Fresnel uses Cocoa with Skia there and does not ship `libsk4d.dylib`: build one and point `SKIA_LIB` at it |

## Limits

- ohsRibbon cannot remove items, groups or tabs. When a plugin is unloaded its ribbon buttons are
  hidden and disconnected, and groups and tabs the adapter made are hidden once empty; loading the
  plugin again reuses them. A `RemoveItem`/`RemoveGroup` in ohsRibbon would let the adapter free them.
- Fresnel has no toolbar control and cannot insert a child at a position, so the toolbar is a `TDiv`
  styled by `cOhsPluginCSS`, and plugin buttons keep their order by being moved to the end.
- Plugins and host must use the same `OHS_PLUGIN_API_VERSION`.
- All calls happen on the UI thread.
- macOS is untested, see Platforms. The framework itself has no platform-specific code: libraries
  load through `dynlibs`, and the plugin API is the same on every platform.
- Delphi is no longer supported: the previous `TPlugInFramework` demos for Delphi were removed.
