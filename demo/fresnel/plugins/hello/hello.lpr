library hello;

{ An ohsPluginFramework plugin. The host loads it and calls OhsPluginEntry. }

{$mode Delphi}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  hello.impl;

exports
  OhsPluginEntry name 'OhsPluginEntry';

begin
end.
