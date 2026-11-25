
unit SYNC_PhoneFX_FilterPlugin;

// AviUtl2 のパラメータを読み取り、映像と効果音をメディアオブジェクトへ渡す。

interface

uses AviUtl2FilterTypes;

const PHONE_REQUIRED_VERSION = 2011600;

function GetPhoneFilterTable: PFILTER_PLUGIN_TABLE;

implementation

uses
  System.Classes, System.Math, System.SyncObjs, Winapi.GDIPAPI, Winapi.GDIPOBJ,
  PluginFilterTable, SYNC_PhoneFX_Timeline, SYNC_PhoneFX_CharacterIcons,
  SYNC_PhoneFX_Renderer, SYNC_PhoneFX_Audio;

type
  TPhoneSession = class
  private
    FVideoLock, FAudioLock: TCriticalSection;
    FRenderer: TPhoneRenderer;
    FVideoTimeline, FAudioTimeline: TPhoneTimeline;
    FVideoStyle, FAudioStyle: TPhoneStyle;
    FVideoSpeed, FAudioSpeed: Double;
    FVideoNumber, FAudioNumber: string;
    FCallFaceIndex, FNoticeFaceIndex: Integer;
    FCallFaceFile, FNoticeFaceFile: string;
    FPixels: TArray<TPIXEL_RGBA>;
    FSamples: TArray<Single>;
  public
    constructor Create;
    destructor Destroy; override;
    function RenderVideo(Video: PFILTER_PROC_VIDEO): Byte;
    function RenderAudio(Audio: PFILTER_PROC_AUDIO): Byte;
  end;

var
  Initialized: Boolean;
  StyleItem, DesignItem, CallFace, NoticeFace, RingTone: TFILTER_ITEM_SELECT;
  Body, Dark, Charging, Mic, Camera, Speaker, TapEffect, TapSound, Vibrate: TFILTER_ITEM_CHECK;
  Speed, StartDelay, CallOffset, Signal, Battery, IconX, IconY, IconScale, TapSize, Volume:
    TFILTER_ITEM_TRACK;
  TapColor: TFILTER_ITEM_COLOR;
  NumberText, Caller, NoticeApp, Sender, MessageText, AlarmTime, AlarmName, AppName, Clock:
    TFILTER_ITEM_STRING;
  CallImage, NoticeImage, AppIcon, Wallpaper: TFILTER_ITEM_FILE;
  Groups: array[0..7] of TFILTER_ITEM_GROUP;
  StyleOptions: array[0..Ord(High(TPhoneStyle)) + 1] of TFILTER_ITEM_SELECT_ITEM;
  FaceOptions: TArray<TFILTER_ITEM_SELECT_ITEM>;
  FaceNames: TArray<string>;
  DesignOptions: array[0..3] of TFILTER_ITEM_SELECT_ITEM;
  RingOptions: array[0..3] of TFILTER_ITEM_SELECT_ITEM;

procedure UpdateTimeline(const Settings: TPhoneSettings; var Timeline: TPhoneTimeline;
  var CachedStyle: TPhoneStyle; var CachedSpeed: Double; var CachedNumber: string);
begin
  if (CachedStyle = Settings.Style) and (CachedSpeed = Settings.Speed) and
    (CachedNumber = Settings.NumberText) then Exit;
  Timeline.Prepare(Settings.Style, Settings.NumberText, Settings.Speed);
  CachedStyle := Settings.Style;
  CachedSpeed := Settings.Speed;
  CachedNumber := Settings.NumberText;
end;

function ReadCommon: TPhoneSettings;
begin
  Result := Default(TPhoneSettings);
  Result.Style := TPhoneStyle(EnsureRange(StyleItem.Value, 0, Ord(High(TPhoneStyle))));
  Result.NumberText := string(NumberText.Value);
  Result.Speed := EnsureRange(Speed.Value, 25.0, 200.0);
  Result.StartDelay := EnsureRange(StartDelay.Value, 0.0, 60.0);
  Result.Vibrate := Vibrate.Value <> 0;
end;

function ReadVideo: TPhoneSettings;
begin
  Result := ReadCommon;
  Result.Design := EnsureRange(DesignItem.Value, 0, 2);
  Result.Body := Body.Value <> 0;
  Result.Dark := Dark.Value <> 0;
  Result.Caller := string(Caller.Value);
  Result.CallFace := CallFace.Value;
  Result.CallImage := string(CallImage.Value);
  Result.CallOffset := Max(0.0, CallOffset.Value);
  Result.Mic := Mic.Value <> 0;
  Result.Camera := Camera.Value <> 0;
  Result.Speaker := Speaker.Value <> 0;
  Result.NoticeApp := string(NoticeApp.Value);
  Result.Sender := string(Sender.Value);
  Result.NoticeFace := NoticeFace.Value;
  Result.NoticeImage := string(NoticeImage.Value);
  Result.MessageText := string(MessageText.Value);
  Result.AlarmTime := string(AlarmTime.Value);
  Result.AlarmName := string(AlarmName.Value);
  Result.AppIcon := string(AppIcon.Value);
  Result.AppName := string(AppName.Value);
  Result.IconX := IconX.Value;
  Result.IconY := IconY.Value;
  Result.IconScale := IconScale.Value;
  Result.Clock := string(Clock.Value);
  Result.Signal := EnsureRange(Round(Signal.Value), 0, 4);
  Result.Battery := EnsureRange(Round(Battery.Value), 0, 100);
  Result.Charging := Charging.Value <> 0;
  Result.Wallpaper := string(Wallpaper.Value);
  Result.TapEffect := TapEffect.Value <> 0;
  Result.TapSize := TapSize.Value;
  Result.TapColor := $FF000000 or (Cardinal(TapColor.R) shl 16) or (Cardinal(TapColor.G) shl 8) or
    TapColor.B;
end;

function ReadAudio: TPhoneSettings;
begin
  Result := ReadCommon;
  Result.TapSound := TapSound.Value <> 0;
  Result.Volume := EnsureRange(Volume.Value, 0.0, 100.0);
  Result.RingTone := RingTone.Value;
end;

function FaceFile(Selection: Integer; const Image: string; var LastSelection: Integer;
  var CachedFile: string): string;
begin
  if Image <> '' then Exit(Image);
  if (Selection < 1) or (Selection > Length(FaceNames)) then Exit('');
  if Selection <> LastSelection then
  begin
    try
      CachedFile := PhoneCharacterIconFile(FaceNames[Selection - 1]);
    except
      // Documents が読み取り専用でも、既定のアイコンで描画を続ける。
      CachedFile := '';
    end;
    LastSelection := Selection;
  end;
  Result := CachedFile;
end;

constructor TPhoneSession.Create;
begin
  inherited;
  FVideoLock := TCriticalSection.Create;
  FAudioLock := TCriticalSection.Create;
end;

destructor TPhoneSession.Destroy;
begin
  FRenderer.Free;
  FAudioLock.Free;
  FVideoLock.Free;
  inherited;
end;

function TPhoneSession.RenderVideo(Video: PFILTER_PROC_VIDEO): Byte;
var
  Settings: TPhoneSettings;
  BitmapData: TBitmapData;
  Source: PByte;
  Target: PPIXEL_RGBA;
  X, Y, Width, Height: Integer;
  Image: TGPBitmap;
  CallFile, NoticeFile: string;
begin
  Result := 0;
  if not Assigned(Video^.SetImageData) then Exit;
  FVideoLock.Acquire;
  try
    Settings := ReadVideo;
    UpdateTimeline(Settings, FVideoTimeline, FVideoStyle, FVideoSpeed, FVideoNumber);
    CallFile := '';
    NoticeFile := '';
    if Settings.Style in [psOutgoing, psIncoming, psAnswer, psVoice, psBusy, psReject, psHangup] then
      CallFile := FaceFile(Settings.CallFace, Settings.CallImage, FCallFaceIndex, FCallFaceFile);
    if Settings.Style in [psSocial, psNotification, psMissed] then
      NoticeFile := FaceFile(Settings.NoticeFace, Settings.NoticeImage, FNoticeFaceIndex, FNoticeFaceFile);
    if FRenderer = nil then FRenderer := TPhoneRenderer.Create;
    Image := FRenderer.Render(Settings, FVideoTimeline, Video^.Object_^.Time, CallFile, NoticeFile);
    Width := Image.GetWidth;
    Height := Image.GetHeight;
    SetLength(FPixels, Width * Height);
    // GDI+ の straight BGRA から、SDK の straight RGBA へ変換する。
    if Image.LockBits(MakeRect(0, 0, Width, Height), ImageLockModeRead,
      PixelFormat32bppARGB, BitmapData) <> Ok then Exit;
    try
      for Y := 0 to Height - 1 do
      begin
        Source := PByte(NativeInt(BitmapData.Scan0) + NativeInt(Y) * BitmapData.Stride);
        Target := @FPixels[Y * Width];
        for X := 0 to Width - 1 do
        begin
          Target^.R := Source[2];
          Target^.G := Source[1];
          Target^.B := Source[0];
          Target^.A := Source[3];
          Inc(Source, 4);
          Inc(Target);
        end;
      end;
    finally
      Image.UnlockBits(BitmapData);
    end;
    Video^.SetImageData(@FPixels[0], Width, Height);
    Result := 1;
  finally
    FVideoLock.Release;
  end;
end;

function TPhoneSession.RenderAudio(Audio: PFILTER_PROC_AUDIO): Byte;
var
  Settings: TPhoneSettings;
  Count, Channel, SampleRate: Integer;
begin
  Result := 0;
  if (Audio^.Scene = nil) or not Assigned(Audio^.SetSampleData) then Exit;
  Count := Audio^.Object_^.SampleNum;
  SampleRate := Audio^.Scene^.SampleRate;
  if (Count < 0) or (Count > 16777216) or (SampleRate < 8000) or (SampleRate > 384000) or
    (Audio^.Object_^.ChannelNum < 1) or (Audio^.Object_^.ChannelNum > 32) then Exit;
  if Count = 0 then Exit(1);
  FAudioLock.Acquire;
  try
    Settings := ReadAudio;
    UpdateTimeline(Settings, FAudioTimeline, FAudioStyle, FAudioSpeed, FAudioNumber);
    RenderPhoneAudio(Settings, FAudioTimeline, Audio^.Object_^.SampleIndex, Count, SampleRate, FSamples);
    for Channel := 0 to Audio^.Object_^.ChannelNum - 1 do
      Audio^.SetSampleData(@FSamples[0], Channel);
    Result := 1;
  finally
    FAudioLock.Release;
  end;
end;

function ProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
begin
  Result := 0;
  try
    if (Video = nil) or (Video^.Object_ = nil) or (Video^.UserData = nil) then Exit;
    Result := TPhoneSession(Video^.UserData).RenderVideo(Video);
  except
  end;
end;

function ProcAudio(Audio: PFILTER_PROC_AUDIO): Byte; cdecl;
begin
  Result := 0;
  try
    if (Audio = nil) or (Audio^.Object_ = nil) or (Audio^.UserData = nil) then Exit;
    Result := TPhoneSession(Audio^.UserData).RenderAudio(Audio);
  except
  end;
end;

function CreateSession(EffectID: Int64): Pointer; cdecl;
begin
  Result := nil;
  try
    Result := TPhoneSession.Create;
  except
  end;
end;

procedure DestroySession(EffectID: Int64; UserData: Pointer); cdecl;
begin
  try
    TPhoneSession(UserData).Free;
  except
  end;
end;

procedure PrepareLists;
const
  Designs: array[0..2] of PWideChar = ('チャコール', 'シルバー', 'ネイビー');
  Tones: array[0..2] of PWideChar = ('ベル', '上昇チャイム', 'パルス');
var
  Names: TStringList;
  Style: TPhoneStyle;
  I: Integer;
begin
  for Style := Low(TPhoneStyle) to High(TPhoneStyle) do
  begin
    StyleOptions[Ord(Style)].Name := STYLE_NAMES[Style];
    StyleOptions[Ord(Style)].Value := Ord(Style);
  end;
  for I := 0 to High(Designs) do
  begin
    DesignOptions[I].Name := Designs[I];
    DesignOptions[I].Value := I;
    RingOptions[I].Name := Tones[I];
    RingOptions[I].Value := I;
  end;
  Names := TStringList.Create;
  try
    PhoneCharacterNames(Names);
    SetLength(FaceNames, Names.Count);
    SetLength(FaceOptions, Names.Count + 2);
    FaceOptions[0].Name := '標準';
    for I := 0 to Names.Count - 1 do
    begin
      FaceNames[I] := Names[I];
      FaceOptions[I + 1].Name := PWideChar(FaceNames[I]);
      FaceOptions[I + 1].Value := I + 1;
    end;
  finally
    Names.Free;
  end;
end;

function GetPhoneFilterTable: PFILTER_PLUGIN_TABLE;
const
  ImageFilter = '画像ファイル (*.png;*.jpg;*.jpeg;*.bmp;*.gif)'#0'*.png;*.jpg;*.jpeg;*.bmp;*.gif'#0#0;
begin
  if not Initialized then
  begin
    PrepareLists;
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_AUDIO or FILTER_FLAG_INPUT or FILTER_FLAG_USERDATA,
      'スマホ演出', 'SYNC', 'スマートフォン画面と同期した効果音を生成します', ProcVideo, ProcAudio);
    AddSelect(StyleItem, '演出スタイル', Ord(psIncoming), @StyleOptions[0]);

    AddGroup(Groups[0], 'スマホ設定', 0);
    AddSelect(DesignItem, 'スマートフォンデザイン', 0, @DesignOptions[0]);
    AddCheck(Body, 'スマートフォン本体表示', 1);
    AddTrack(Speed, '演出速度', 100, 25, 200, 1);
    AddTrack(StartDelay, '演出開始までの待ち時間 (秒)', 0.50, 0, 60, 0.01);

    AddGroup(Groups[1], '電話', 0);
    AddString(NumberText, '電話番号', DEFAULT_NUMBER);
    AddString(Caller, '相手の名前', '連絡先');
    AddSelect(CallFace, '電話の顔アイコン', 0, @FaceOptions[0]);
    AddFile(CallImage, '電話の顔アイコン画像', '', ImageFilter);
    AddTrack(CallOffset, '通話開始時の経過時間 (秒)', 0, 0, 86400, 0.01);
    AddCheck(Mic, 'マイク', 1);
    AddCheck(Camera, 'カメラ', 1);
    AddCheck(Speaker, 'スピーカー', 0);

    AddGroup(Groups[2], '通知', 0);
    AddString(NoticeApp, '通知のアプリ名', MINE_APP_NAME);
    AddString(Sender, '送信者名', '連絡先');
    AddSelect(NoticeFace, '通知の顔アイコン', 0, @FaceOptions[0]);
    AddFile(NoticeImage, '通知の顔アイコン画像', '', ImageFilter);
    AddString(MessageText, 'メッセージ本文', '新しいメッセージがあります');
    MessageText.ItemType := 'text'; // SDK の text は string と同じ配置で、改行を保持する。

    AddGroup(Groups[3], 'アラーム', 0);
    AddString(AlarmTime, 'アラーム時刻', DEFAULT_ALARM);
    AddString(AlarmName, 'アラーム名', 'アラーム');

    AddGroup(Groups[4], 'アプリ起動', 0);
    AddFile(AppIcon, 'アプリアイコン画像ファイル', '', ImageFilter);
    AddString(AppName, '起動するアプリ名', 'マイアプリ');
    AddTrack(IconX, 'アイコン画像X', 0, -100, 100, 0.01);
    AddTrack(IconY, 'アイコン画像Y', 0, -100, 100, 0.01);
    AddTrack(IconScale, 'アイコン画像拡大率', 100, 10, 400, 0.01);

    AddGroup(Groups[5], '画面', 0);
    AddString(Clock, '表示時刻', DEFAULT_CLOCK);
    AddTrack(Signal, '電波強度', 4, 0, 4, 1);
    AddTrack(Battery, 'バッテリー残量', 78, 0, 100, 1);
    AddCheck(Charging, '充電中', 0);
    AddFile(Wallpaper, '壁紙画像', '', ImageFilter);
    AddCheck(Dark, 'ダークモード', 0);

    AddGroup(Groups[6], 'タップエフェクト', 0);
    AddCheck(TapEffect, 'タップエフェクトを表示', 1);
    AddColor(TapColor, 'タップエフェクトの色', $FF, $A8, $30);
    AddTrack(TapSize, 'タップエフェクトの大きさ', 100, 25, 300, 1);
    AddCheck(TapSound, 'タップ音', 1);

    AddGroup(Groups[7], '効果音', 0);
    AddTrack(Volume, '効果音の音量', 50, 0, 100, 0.01);
    AddSelect(RingTone, '着信音の種類', 0, @RingOptions[0]);
    AddCheck(Vibrate, 'バイブレーション', 1);

    GetPluginTable^.Func_Create := CreateSession;
    GetPluginTable^.Func_Destroy := DestroySession;
    Initialized := True;
  end;
  Result := GetPluginTable;
end;

end.
