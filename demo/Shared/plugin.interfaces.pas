unit plugin.interfaces;

interface

{$IFDEF FPC}
{$MODE delphi}
{$ENDIF}

type
  IPlugin1 = interface
    ['{9D765E88-6B29-4D5D-8F3E-7787F6C31234}']
    function GetName: PChar; stdcall;
    function Execute(const Input: PChar): PChar; stdcall;
  end;

  IPlugin2 = interface
    ['{48762EA4-4CAA-4B9D-A273-C0CC03B6CD19}']
    function GetName: PChar; stdcall;
    function Execute(const Input: PChar): PChar; stdcall;
  end;

  IHost = interface
    ['{AB5F2D85-B346-45EA-9B3C-4CB4182694DE}']
    procedure SetSpeedButton(Source: integer; AName: PChar); stdcall;
  end;

implementation

end.
