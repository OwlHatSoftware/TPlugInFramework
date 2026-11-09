{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit ohspluginframework_fresnel;

{$warn 5023 off : no warning about unused units}
interface

uses
  ohs.plugin.fresnel.common, ohs.plugin.fresnel.panels, LazarusPackageIntf;

implementation

procedure Register;
begin
end;

initialization
  RegisterPackage('ohspluginframework_fresnel', @Register);
end.
