object Form1: TForm1
  Left = 0
  Top = 0
  Caption = 'Simple plugin demo'
  ClientHeight = 441
  ClientWidth = 624
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnDestroy = FormDestroy
  OnShow = FormShow
  TextHeight = 15
  object Label1: TLabel
    Left = 40
    Top = 48
    Width = 265
    Height = 15
    Caption = 'Very simple plugin framework based on interfaces.'
  end
  object Label2: TLabel
    Left = 40
    Top = 69
    Width = 252
    Height = 15
    Caption = 'The plugin works boths sides: HostApp and DLL'
  end
  object Memo1: TMemo
    Left = 24
    Top = 104
    Width = 577
    Height = 313
    TabOrder = 0
  end
  object ToolBar1: TToolBar
    Left = 0
    Top = 0
    Width = 624
    Height = 29
    Caption = 'ToolBar1'
    ShowCaptions = True
    TabOrder = 1
    ExplicitWidth = 618
  end
end
