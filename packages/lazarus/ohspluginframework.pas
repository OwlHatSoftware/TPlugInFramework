{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit ohspluginframework;

{$warn 5023 off : no warning about unused units}
interface

uses
  ohs.plugin.api, ohs.plugin.helpers, ohs.plugin.registry, ohs.plugin.manager, 
  LazarusPackageIntf;

implementation

procedure Register;
begin
end;

initialization
  RegisterPackage('ohspluginframework', @Register);
end.
