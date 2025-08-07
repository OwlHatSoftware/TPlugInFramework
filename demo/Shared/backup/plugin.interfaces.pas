
unit plugin.interfaces;

interface

type
  IPlugin = interface
    ['{9D765E88-6B29-4D5D-8F3E-7787F6C31234}']
    function GetName: PChar; stdcall;
    function Execute(const Input: PChar): PChar; stdcall;
  end;

  IHost = interface
    ['{AB5F2D85-B346-45EA-9B3C-4CB4182694DE}']
    procedure SetSpeedButton(AName: PChar); stdcall;
  end;

implementation

end.
