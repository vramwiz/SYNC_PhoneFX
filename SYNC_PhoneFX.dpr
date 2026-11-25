
library SYNC_PhoneFX;

// AviUtl2 のプラグイン読み込みと GDI+ の生存期間を管理する。

{$ALIGN 8}

uses
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  PluginFilterTable in 'Source\Lib\FilterTable\PluginFilterTable.pas',
  RTTIPersistent in 'Source\Lib\RTTIPersistent\RTTIPersistent.pas',
  RTTIPersistentIni in 'Source\Lib\RTTIPersistent\RTTIPersistentIni.pas',
  RTTISectionPersistent in 'Source\Lib\RTTIPersistent\RTTISectionPersistent.pas',
  SectionFileManager in 'Source\Lib\SectionFileManager\SectionFileManager.pas',
  VectorRendererData in 'Source\Lib\VectorRenderer\VectorRendererData.pas',
  VectorRenderer in 'Source\Lib\VectorRenderer\VectorRenderer.pas',
  VectorRendererImageList in 'Source\Lib\VectorRenderer\VectorRendererImageList.pas',
  SYNC_PhoneFX_CharacterIcons in 'Source\Common\Images\SYNC_PhoneFX_CharacterIcons.pas',
  SYNC_PhoneFX_Timeline in 'Source\Common\Effects\SYNC_PhoneFX_Timeline.pas',
  SYNC_PhoneFX_Graphics in 'Source\Common\Render\SYNC_PhoneFX_Graphics.pas',
  SYNC_PhoneFX_Renderer in 'Source\Common\Render\SYNC_PhoneFX_Renderer.pas',
  SYNC_PhoneFX_Audio in 'Source\Common\Render\SYNC_PhoneFX_Audio.pas',
  SYNC_PhoneFX_FilterPlugin in 'Source\Plugin\Filter\SYNC_PhoneFX_FilterPlugin.pas';

{$R *.res}
{$R 'Source\Lib\CharacterResources\SerifCharaVectorResource.RES'}

function InitializePlugin(Version: Cardinal): Byte; cdecl;
begin
  Result := 0;
  try
    if (Version < PHONE_REQUIRED_VERSION) or not StartPhoneGraphics then Exit;
    GetPhoneFilterTable;
    Result := 1;
  except
    StopPhoneGraphics;
  end;
end;

procedure UninitializePlugin; cdecl;
begin
  StopPhoneGraphics;
end;

function RequiredVersion: Cardinal; cdecl;
begin
  Result := PHONE_REQUIRED_VERSION;
end;

function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin
  Result := nil;
  try
    Result := GetPhoneFilterTable;
  except
    // Delphi の例外を SDK の C 境界へ渡さない。
  end;
end;

exports
  RequiredVersion name 'RequiredVersion',
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable';

begin
  System.IsMultiThread := True;
end.
