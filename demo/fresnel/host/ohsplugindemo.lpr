program ohsplugindemo;

{ The ohsPluginFramework demo host. Plugins are loaded from the plugins folder
  next to the program. See hostform for the command line switches. }

{$mode objfpc}{$H+}
{$apptype console}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Fresnel, // initializes the widgetset
  Fresnel.App, hostform;

begin
  FresnelApplication.Initialize;
  FresnelApplication.CreateFormNew(TMainForm,MainForm);
  FresnelApplication.Run;
end.
