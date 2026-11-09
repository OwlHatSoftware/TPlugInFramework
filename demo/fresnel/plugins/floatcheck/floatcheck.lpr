library floatcheck;

{ An ohsPluginFramework plugin. The host loads it and calls OhsPluginEntry. }

{$mode Delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  floatcheck.impl;

exports
  OhsPluginEntry name 'OhsPluginEntry';

begin
end.
