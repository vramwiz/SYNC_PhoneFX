
unit SYNC_PhoneFX_Renderer;

// 同じオブジェクト時刻と設定から、同じ透過スマホ画面を生成する。

interface

uses
  System.Types, Winapi.GDIPAPI, Winapi.GDIPOBJ, SYNC_PhoneFX_Timeline;

type
  TPhoneFont = (pfSmall, pfLabel, pfBody, pfTitle, pfNumber, pfClock);
  TPhoneGlyph = (pgCall, pgEnd, pgMic, pgCamera, pgSpeaker, pgBell, pgLock, pgBolt,
    pgChat, pgMail, pgPhoto, pgMusic, pgGrid, pgClock, pgSettings, pgPerson);

  TPhoneRenderer = class
  private
    FSurface: TGPBitmap;
    FFonts: array[TPhoneFont] of TGPFont;
    FTarget: TGPGraphics; // Render が所有し、描画中だけ有効。
    FSettings: TPhoneSettings;
    FTimeline: TPhoneTimeline;
    FTime, FSeconds, FEffectSeconds, FTapAge: Double;
    FTap: TPhoneTap;
    FHasTap: Boolean;
    FWallpaper, FAppIcon, FCallFace, FNoticeFace: TGPBitmap;
    FWallpaperKey, FAppKey, FCallKey, FNoticeKey: string;
    FText, FMuted, FPanel, FBackground: ARGB;
    procedure Palette(Dark: Boolean);
    procedure TextAt(const Text: string; Font: TPhoneFont; X, Y, W, H: Single;
      Color: ARGB; Alignment: TStringAlignment = StringAlignmentNear;
      Wrap: Boolean = False);
    procedure Glyph(Kind: TPhoneGlyph; X, Y, Size: Single; Color: ARGB; Disabled: Boolean = False);
    procedure Button(const Position: TPointF; Radius: Single; Color: ARGB; Icon: TPhoneGlyph;
      const Caption: string; Enabled: Boolean = True);
    function Press(const Position: TPointF): Single;
    procedure DrawTap;
    procedure DrawStatus(Color: ARGB);
    procedure DrawWallpaper;
    procedure DrawLock(Amount: Double = 1);
    procedure DrawHome;
    procedure DrawApp(Index: Integer; const Position: TPointF; Radius: Single);
    procedure DrawLaunch;
    procedure DrawDial(ShowFullNumber: Boolean = False);
    procedure DrawCall(Style: TPhoneStyle);
    procedure DrawVideo;
    procedure DrawNotification;
    procedure DrawAlarm;
    procedure DrawPower;
  public
    constructor Create;
    destructor Destroy; override;
    // 返す画像は描画器が所有し、次の Render まで有効。
    function Render(const Settings: TPhoneSettings; const Timeline: TPhoneTimeline;
      Seconds: Double; const CallFaceFile, NoticeFaceFile: string): TGPBitmap;
  end;

implementation

uses System.Math, System.SysUtils, SYNC_PhoneFX_Graphics;

const
  White = $FFFFFFFF;
  Green = $FF158450;
  Red = $FFD5364D;
  Blue = $FF2468D9;
  AppNames: array[0..7] of string = (MINE_APP_NAME, 'カメラ', '電話', '写真', 'メール', '時計', '音楽', '設定');
  AppGlyphs: array[0..8] of TPhoneGlyph = (pgChat, pgCamera, pgCall, pgPhoto,
    pgMail, pgClock, pgMusic, pgSettings, pgGrid);
  LowBatteryPercent = 20;
  HomeBackground = $FF08090B;
  HomeDock = $CC1D1F24;
  LaunchBackground = $FF101217;
  AppColors: array[0..8] of ARGB = ($FF1DD661, $FFF3F6FC, $FF0C69F4, $FFFFD317,
    $FFE92D39, $FF6638F2, $FFE22A88, $FFD4DFEE, $FFFF9018);
  AppGlyphColors: array[0..8] of ARGB = ($FF10251C, $FF1B2940, White, $FF282307,
    White, White, White, $FF25364B, $FF332006);
  HousingColors: array[0..2] of ARGB = ($FF202428, $FFA5ADB6, $FF364C6B);

procedure LoadSlot(var Image: TGPBitmap; var OldKey: string; const Key: string);
var
  NewImage: TGPBitmap;
begin
  if OldKey = Key then Exit;
  NewImage := LoadPhonePicture(Key);
  Image.Free;
  Image := NewImage;
  OldKey := Key;
end;

constructor TPhoneRenderer.Create;
const
  Sizes: array[TPhoneFont] of Single = (14, 17, 21, 28, 36, 72);
var
  Font: TPhoneFont;
  FontStyle: Integer;
begin
  inherited;
  FSurface := TGPBitmap.Create(PHONE_WIDTH, PHONE_HEIGHT, PixelFormat32bppARGB);
  for Font := Low(TPhoneFont) to High(TPhoneFont) do
  begin
    FontStyle := FontStyleRegular;
    if Font >= pfTitle then FontStyle := FontStyleBold;
    FFonts[Font] := TGPFont.Create('Yu Gothic UI', Sizes[Font], FontStyle, UnitPixel);
  end;
end;

destructor TPhoneRenderer.Destroy;
var
  Font: TPhoneFont;
begin
  FNoticeFace.Free;
  FCallFace.Free;
  FAppIcon.Free;
  FWallpaper.Free;
  for Font := Low(TPhoneFont) to High(TPhoneFont) do FFonts[Font].Free;
  FSurface.Free;
  inherited;
end;

procedure TPhoneRenderer.Palette(Dark: Boolean);
begin
  if Dark then
  begin
    FText := White;
    FMuted := $FFB9C7DE;
    FPanel := $FF24334D;
    FBackground := $FF101C30;
  end
  else
  begin
    FText := $FF102239;
    FMuted := $FF475D78;
    FPanel := $FFF7FAFF;
    FBackground := $FFE2EAF6;
  end;
end;

procedure TPhoneRenderer.TextAt(const Text: string; Font: TPhoneFont; X, Y, W, H: Single;
  Color: ARGB; Alignment: TStringAlignment; Wrap: Boolean);
var
  Brush: TGPSolidBrush;
  Format: TGPStringFormat;
begin
  if Text = '' then Exit;
  Brush := TGPSolidBrush.Create(Color);
  Format := TGPStringFormat.Create;
  try
    Format.SetAlignment(Alignment);
    Format.SetLineAlignment(StringAlignmentCenter);
    Format.SetTrimming(StringTrimmingEllipsisCharacter);
    if not Wrap then Format.SetFormatFlags(StringFormatFlagsNoWrap);
    FTarget.DrawString(Text, Length(Text), FFonts[Font], MakeRect(X, Y, W, H), Format, Brush);
  finally
    Format.Free;
    Brush.Free;
  end;
end;

procedure TPhoneRenderer.Glyph(Kind: TPhoneGlyph; X, Y, Size: Single; Color: ARGB;
  Disabled: Boolean);
var
  State: GraphicsState;
  Pen: TGPPen;
  Path: TGPGraphicsPath;

  procedure Segment(X1, Y1, X2, Y2: Single);
  begin
    FTarget.DrawLine(Pen, X1, Y1, X2, Y2);
  end;

  procedure Circle(CX, CY, R: Single);
  begin
    FTarget.DrawEllipse(Pen, CX - R, CY - R, 2 * R, 2 * R);
  end;

  procedure Box(L, T, W, H, R: Single);
  begin
    Path := RoundPath(L, T, W, H, R);
    try
      FTarget.DrawPath(Pen, Path);
    finally
      Path.Free;
    end;
  end;

begin
  State := FTarget.Save;
  Pen := TGPPen.Create(Color, 1.75);
  try
    Pen.SetLineCap(LineCapRound, LineCapRound, DashCapRound);
    Pen.SetLineJoin(LineJoinRound);
    FTarget.TranslateTransform(X, Y);
    FTarget.ScaleTransform(Size / 24, Size / 24);
    case Kind of
      pgCall, pgEnd:
        begin
          if Kind = pgEnd then FTarget.RotateTransform(135);
          FTarget.DrawBezier(Pen, -8.0, -8.0, -11.0, -1.0, 1.0, 11.0, 8.0, 8.0);
          Segment(-8, -8, -5, -9); Segment(-5, -9, -2, -4); Segment(-2, -4, -5, -2);
          FTarget.DrawBezier(Pen, -5.0, -2.0, -4.0, 0.0, 0.0, 4.0, 2.0, 5.0);
          Segment(2, 5, 4, 2); Segment(4, 2, 9, 5); Segment(9, 5, 8, 8);
        end;
      pgMic:
        begin
          Box(-3, -10, 6, 13, 3);
          FTarget.DrawArc(Pen, -6.0, -5.0, 12.0, 12.0, 0.0, 180.0);
          Segment(0, 7, 0, 10); Segment(-3, 10, 3, 10);
        end;
      pgCamera:
        begin
          Box(-10, -6, 13, 12, 2);
          Segment(3, -2, 9, -6); Segment(9, -6, 9, 6); Segment(9, 6, 3, 2);
        end;
      pgSpeaker:
        begin
          Segment(-8, -3, -4, -3); Segment(-4, -3, 1, -8); Segment(1, -8, 1, 8);
          Segment(1, 8, -4, 3); Segment(-4, 3, -8, 3); Segment(-8, 3, -8, -3);
          FTarget.DrawArc(Pen, 0.0, -5.0, 9.0, 10.0, -65.0, 130.0);
          FTarget.DrawArc(Pen, 1.0, -8.0, 14.0, 16.0, -59.0, 118.0);
        end;
      pgBell:
        begin
          FTarget.DrawArc(Pen, -6.0, -8.0, 12.0, 12.0, 180.0, 180.0);
          Segment(-6, -2, -7, 4); Segment(6, -2, 7, 4); Segment(-8, 4, 8, 4);
          FTarget.DrawArc(Pen, -3.0, 4.0, 6.0, 6.0, 0.0, 180.0);
        end;
      pgLock:
        begin
          Box(-8, -1, 16, 11, 3);
          FTarget.DrawArc(Pen, -4.0, -9.0, 8.0, 10.0, 180.0, 180.0);
          Segment(-4, -4, -4, -1); Segment(4, -4, 4, -1);
        end;
      pgBolt:
        begin
          Segment(1, -10, -6, 1); Segment(-6, 1, -1, 1); Segment(-1, 1, -2, 10);
          Segment(-2, 10, 6, -2); Segment(6, -2, 1, -2); Segment(1, -2, 1, -10);
        end;
      pgChat:
        begin
          Box(-10, -7, 20, 13, 5); Segment(-4, 6, -7, 10); Segment(-7, 10, 0, 6);
          Segment(-5, -1, 5, -1);
        end;
      pgMail:
        begin
          Box(-10, -7, 20, 14, 2); Segment(-9, -6, 0, 1); Segment(0, 1, 9, -6);
        end;
      pgPhoto:
        begin
          Box(-10, -8, 20, 16, 2); Circle(4, -3, 1.5);
          Segment(-9, 6, -3, 0); Segment(-3, 0, 4, 7);
        end;
      pgMusic:
        begin
          Circle(-4, 6, 3); Segment(-1, 6, -1, -8); Segment(-1, -8, 7, -6);
          Segment(7, -6, 7, -2); Segment(7, -2, -1, -4);
        end;
      pgGrid:
        begin
          Box(-8, -8, 6, 6, 1); Box(2, -8, 6, 6, 1);
          Box(-8, 2, 6, 6, 1); Box(2, 2, 6, 6, 1);
        end;
      pgClock:
        begin
          Circle(0, 0, 8); Segment(0, -5, 0, 0); Segment(0, 0, 4, 2);
        end;
      pgSettings:
        begin
          Circle(0, 0, 3); Circle(0, 0, 8);
          Segment(0, -10, 0, -8); Segment(0, 8, 0, 10);
          Segment(-10, 0, -8, 0); Segment(8, 0, 10, 0);
          Segment(-7, -7, -5.5, -5.5); Segment(7, 7, 5.5, 5.5);
          Segment(7, -7, 5.5, -5.5); Segment(-7, 7, -5.5, 5.5);
        end;
      pgPerson:
        begin
          Circle(0, -4, 3.2);
          FTarget.DrawArc(Pen, -7.0, 1.5, 14.0, 11.0, 180.0, 180.0);
        end;
    end;
    if Disabled then Segment(-10, -10, 10, 10);
  finally
    Pen.Free;
    FTarget.Restore(State);
  end;
end;

function TPhoneRenderer.Press(const Position: TPointF): Single;
begin
  Result := 0;
  if FHasTap and (FTap.Position = Position) and (FTapAge < 0.19) then
    Result := Sin(Pi * FTapAge / 0.19);
end;

procedure TPhoneRenderer.Button(const Position: TPointF; Radius: Single; Color: ARGB;
  Icon: TPhoneGlyph; const Caption: string; Enabled: Boolean);
var
  Push: Single;
begin
  Push := Press(Position);
  Radius := Radius * (1 - 0.11 * Push);
  FillRound(FTarget, Position.X - Radius, Position.Y - Radius, Radius * 2,
    Radius * 2, Radius, Color);
  if Push > 0 then
    FillRound(FTarget, Position.X - Radius, Position.Y - Radius, Radius * 2,
      Radius * 2, Radius, OpacityColor(White, 0.18 * Push));
  Glyph(Icon, Position.X, Position.Y, Radius * 1.05, White, not Enabled);
  TextAt(Caption, pfSmall, Position.X - 61, Position.Y + 40, 122, 27, FText, StringAlignmentCenter);
end;

procedure TPhoneRenderer.DrawTap;
var
  Progress, Radius: Single;
  Pen: TGPPen;
begin
  if not FHasTap then Exit;
  Progress := FTapAge / TAP_DURATION;
  Radius := (8 + 34 * Ease(Progress, 0, 1)) * FSettings.TapSize / 100;
  Pen := TGPPen.Create(OpacityColor(FSettings.TapColor, 0.83 * Sqr(1 - Progress)), 3);
  try
    FTarget.DrawEllipse(Pen, FTap.Position.X - Radius, FTap.Position.Y - Radius, 2 * Radius, 2 * Radius);
  finally
    Pen.Free;
  end;
end;

procedure TPhoneRenderer.DrawStatus(Color: ARGB);
var
  I: Integer;
  X, H, BatteryWidth: Single;
  IsCharging: Boolean;
  BatteryColor, LowColor, ChargeColor: ARGB;
  Pen: TGPPen;
  Path: TGPGraphicsPath;
begin
  TextAt(PhoneClock(FSettings.Clock, FSeconds), pfSmall, 35, 25, 78, 23, Color);
  for I := 0 to 3 do
  begin
    X := 317 + I * 5;
    H := 4 + I * 2;
    if I < FSettings.Signal then
      FillRound(FTarget, X, 40 - H, 3, H, 1.4, Color)
    else
      FillRound(FTarget, X, 40 - H, 3, H, 1.4, OpacityColor(Color, 0.33));
  end;
  IsCharging := FSettings.Charging or ((FSettings.Style = psCharge) and (FTime >= NOTICE_AT));
  if Color = White then
  begin
    LowColor := $FFFF6571;
    ChargeColor := $FF57E795;
  end
  else
  begin
    LowColor := $FFB82034;
    ChargeColor := $FF087243;
  end;
  BatteryColor := Color;
  if FSettings.Battery <= LowBatteryPercent then BatteryColor := LowColor
  else if IsCharging then BatteryColor := ChargeColor;
  Path := RoundPath(343, 29, 29, 12, 3);
  Pen := TGPPen.Create(BatteryColor, 1);
  try
    FTarget.DrawPath(Pen, Path);
  finally
    Pen.Free;
    Path.Free;
  end;
  FillRound(FTarget, 374, 32, 2, 6, 1, BatteryColor);
  BatteryWidth := 25 * FSettings.Battery / 100;
  if BatteryWidth > 0 then
    FillRound(FTarget, 345, 31, BatteryWidth, 8, 2, BatteryColor);
  if IsCharging then Glyph(pgBolt, 387, 35, 15, ChargeColor);
end;

procedure TPhoneRenderer.DrawWallpaper;
var
  Brush: TGPLinearGradientBrush;
  ColorA, ColorB: ARGB;
begin
  if FSettings.Dark then
  begin
    ColorA := $FF142346;
    ColorB := $FF254553;
  end
  else
  begin
    ColorA := $FF25497B;
    ColorB := $FF387388;
  end;
  Brush := TGPLinearGradientBrush.Create(MakePoint(14, 18), MakePoint(406, 802), ColorA, ColorB);
  try
    FTarget.FillRectangle(Brush, 14, 18, 392, 784);
  finally
    Brush.Free;
  end;
  if FWallpaper <> nil then
    DrawCoverPicture(FTarget, FWallpaper, MakeRect(Single(14), Single(18), Single(392), Single(784)))
  else
  begin
    FillRound(FTarget, 128, 238, 498, 498, 249, $385BAEC0);
    FillRound(FTarget, -264, 545, 731, 338, 169, $3D7FBCD2);
    FillRound(FTarget, -114, 641, 697, 398, 199, $434165B5);
  end;
  // 壁紙上の白いラベルと時刻を読みやすくする。
  FillRound(FTarget, 14, 18, 392, 784, 0.5, $34081429);
end;

procedure TPhoneRenderer.DrawLock(Amount: Double);
var
  State: GraphicsState;
  Push, Scale: Single;
begin
  if Amount <= 0 then Exit;
  State := FTarget.Save;
  try
    FTarget.TranslateTransform(0, -70 * (1 - Amount));
    TextAt(PhoneClock(FSettings.Clock, FSeconds), pfClock, 25, 114, 370, 112,
      OpacityColor(White, Amount), StringAlignmentCenter);
    Glyph(pgLock, 210, 113, 21, OpacityColor(White, Amount));
    Push := Press(PointF(210, 726));
    Scale := 1 - 0.1 * Push;
    FillRound(FTarget, 210 - 84 * Scale, 726 - 22 * Scale, 168 * Scale, 44 * Scale,
      22 * Scale, OpacityColor($42506A85, Amount));
    if Push > 0 then
      FillRound(FTarget, 210 - 84 * Scale, 726 - 22 * Scale, 168 * Scale, 44 * Scale,
        22 * Scale, OpacityColor(White, 0.18 * Push * Amount));
    TextAt('ロック解除', pfLabel, 128, 704, 164, 44, OpacityColor(White, Amount), StringAlignmentCenter);
  finally
    FTarget.Restore(State);
  end;
end;

procedure TPhoneRenderer.DrawApp(Index: Integer; const Position: TPointF; Radius: Single);
begin
  if Index = 8 then
    DrawPhoneIcon(FTarget, FAppIcon, MakeRect(Position.X - Radius, Position.Y - Radius,
      Radius * 2, Radius * 2), FSettings.IconScale, FSettings.IconX, FSettings.IconY,
      255, AppColors[Index] and $FFFFFF)
  else
    FillRound(FTarget, Position.X - Radius, Position.Y - Radius, 2 * Radius, 2 * Radius,
      Radius * 0.45, AppColors[Index]);
  if (Index <> 8) or (FAppIcon = nil) then
    Glyph(AppGlyphs[Index], Position.X, Position.Y, Radius, AppGlyphColors[Index]);
end;

procedure TPhoneRenderer.DrawHome;
var
  Index: Integer;
  Position: TPointF;
  Name: string;
  Radius, Push: Single;
begin
  FillRound(FTarget, SCREEN_X, SCREEN_Y, SCREEN_W, SCREEN_H, 1, HomeBackground);
  if FWallpaper <> nil then
  begin
    DrawCoverPicture(FTarget, FWallpaper, MakeRect(Single(SCREEN_X), Single(SCREEN_Y),
      Single(SCREEN_W), Single(SCREEN_H)));
    FillRound(FTarget, SCREEN_X, SCREEN_Y, SCREEN_W, SCREEN_H, 1, $40000000);
  end;
  TextAt(PhoneClock(FSettings.Clock, FSeconds), pfNumber, 34, 92, 352, 60, White);
  for Index := 0 to High(AppColors) do
  begin
    Position := AppCenter(Index);
    Push := Press(Position);
    if Index = 8 then Name := FSettings.AppName else Name := AppNames[Index];
    Radius := 33 * (1 - Push * 0.12);
    DrawApp(Index, Position, Radius);
    if Push > 0 then
      FillRound(FTarget, Position.X - Radius, Position.Y - Radius, Radius * 2, Radius * 2, Radius,
        OpacityColor(White, 0.15 * Push));
    TextAt(Name, pfSmall, Position.X - 51, Position.Y + 36, 102, 24, White, StringAlignmentCenter);
  end;
  FillRound(FTarget, 49, 677, 322, 87, 34, HomeDock);
  DrawApp(2, PointF(103, 720), 28);
  DrawApp(0, PointF(210, 720), 28);
  DrawApp(1, PointF(317, 720), 28);
end;

procedure TPhoneRenderer.DrawLaunch;
var
  Index: Integer;
  Progress, Radius, HalfW, HalfH: Single;
  Position, Origin: TPointF;
  Name: string;
begin
  Progress := Ease(FTime, ACTION_AT + 0.12, 0.46);
  if Progress < 1 then DrawHome;
  if Progress <= 0 then Exit;
  Index := TargetApp(FSettings.Style);
  Origin := AppCenter(Index);
  Position := PointF(Origin.X + (210 - Origin.X) * Progress,
    Origin.Y + (376 - Origin.Y) * Progress);
  HalfW := 33 + 390 * Progress;
  HalfH := 33 + 770 * Progress;
  Radius := 18 + 20 * Progress;
  FillRound(FTarget, Position.X - HalfW, Position.Y - HalfH, HalfW * 2, HalfH * 2,
    Radius, LaunchBackground);
  FillRound(FTarget, Position.X - HalfW, Position.Y - HalfH, HalfW * 2, HalfH * 2,
    Radius, OpacityColor(AppColors[Index], 0.08 + 0.92 * Sqr(1 - Progress)));
  DrawApp(Index, Position, 29 + 29 * Progress);
  if Index = 8 then Name := FSettings.AppName else Name := AppNames[Index];
  TextAt(Name, pfTitle, 35, 453, 350, 50, OpacityColor(White, Progress), StringAlignmentCenter);
end;

procedure TPhoneRenderer.DrawDial(ShowFullNumber: Boolean);
const
  Keys = '123456789*0#';
  Letters: array[1..12] of string = ('', 'ABC', 'DEF', 'GHI', 'JKL', 'MNO',
    'PQRS', 'TUV', 'WXYZ', '', '+', '');
var
  Index: Integer;
  Position: TPointF;
  Radius, Push: Single;
  Number: string;
begin
  FillRound(FTarget, 14, 18, 392, 784, 1, FBackground);
  TextAt('電話', pfLabel, 36, 80, 348, 37, FMuted, StringAlignmentCenter);
  if ShowFullNumber then Number := FSettings.NumberText
  else Number := FTimeline.DialPrefix(FTime);
  TextAt(Number, pfNumber, 31, 128, 358, 76, FText, StringAlignmentCenter);
  for Index := 1 to Length(Keys) do
  begin
    Position := KeyCenter(Keys[Index]);
    Push := Press(Position);
    Radius := 35 * (1 - 0.11 * Push);
    FillRound(FTarget, Position.X - Radius, Position.Y - Radius, 2 * Radius, 2 * Radius,
      Radius, FPanel);
    if Push > 0 then
      FillRound(FTarget, Position.X - Radius, Position.Y - Radius, 2 * Radius, 2 * Radius,
        Radius, OpacityColor(Blue, Push * 0.27));
    TextAt(Keys[Index], pfTitle, Position.X - 29, Position.Y - 23, 58, 37, FText, StringAlignmentCenter);
    TextAt(Letters[Index], pfSmall, Position.X - 29, Position.Y + 12, 58, 20, FMuted, StringAlignmentCenter);
  end;
  Button(PointF(210, 686), 36, Green, pgCall, '');
end;

procedure TPhoneRenderer.DrawCall(Style: TPhoneStyle);
var
  Tag: string;
  Ring: Double;
  Pen: TGPPen;
  Radius: Single;
begin
  FillRound(FTarget, 14, 18, 392, 784, 1, FBackground);
  FillRound(FTarget, 50, 141, 320, 361, 64, FPanel);
  case Style of
    psIncoming: Tag := '着信中';
    psOutgoing: Tag := '呼び出し中…';
    psVoice: Tag := CallClock(FSettings.CallOffset + FEffectSeconds);
    psAnswer: Tag := CallClock(FSettings.CallOffset + Max(0.0, FEffectSeconds - ACTION_SWITCH / FTimeline.Speed));
    psBusy: Tag := '話し中';
    psReject: Tag := '着信を拒否しました';
  else
    Tag := '通話を終了しました';
  end;
  if Style = psIncoming then
  begin
    Ring := Frac(FTime / 1.5);
    Radius := 57 + 25 * Ring;
    Pen := TGPPen.Create(OpacityColor(Green, 0.6 * (1 - Ring)), 2.3);
    try
      FTarget.DrawEllipse(Pen, 210 - Radius, 262 - Radius, Radius * 2, Radius * 2);
    finally
      Pen.Free;
    end;
  end;
  DrawPhoneIcon(FTarget, FCallFace, MakeRect(156.0, 208.0, 108.0, 108.0), 100, 0, 0);
  if FCallFace = nil then Glyph(pgPerson, 210, 261, 61, $FF425A74);
  TextAt(FSettings.Caller, pfTitle, 65, 336, 290, 51, FText, StringAlignmentCenter);
  TextAt(FSettings.NumberText, pfBody, 63, 391, 294, 33, FMuted, StringAlignmentCenter);
  TextAt(Tag, pfLabel, 65, 437, 290, 30, FText, StringAlignmentCenter);
  case Style of
    psIncoming:
      begin
        Button(PointF(132, 686), 36, Red, pgEnd, '拒否');
        Button(PointF(288, 686), 36, Green, pgCall, '応答');
      end;
    psVoice, psAnswer:
      begin
        Button(PointF(153, 571), 29, $FF405675, pgMic, 'マイク', FSettings.Mic);
        Button(PointF(267, 571), 29, $FF405675, pgSpeaker, 'スピーカー', FSettings.Speaker);
        Button(PointF(210, 686), 36, Red, pgEnd, '終了');
      end;
    psOutgoing, psBusy: Button(PointF(210, 686), 36, Red, pgEnd, '終了');
  end;
end;

procedure TPhoneRenderer.DrawVideo;
begin
  // 上下の情報とボタンの領域だけを描き、映像を置く中央は透明のままにする。
  FText := White;
  FillRound(FTarget, 23, 20, 374, 36, 18, $B818263C);
  FillRound(FTarget, 48, 72, 324, 78, 22, $B818263C);
  TextAt(FSettings.Caller, pfBody, 57, 79, 306, 37, White, StringAlignmentCenter);
  TextAt(CallClock(FSettings.CallOffset + FEffectSeconds), pfLabel, 57, 114, 306, 26, White, StringAlignmentCenter);
  Button(PointF(86, 727), 28, $D92C405F, pgMic, '', FSettings.Mic);
  Button(PointF(168, 727), 28, $D92C405F, pgCamera, '', FSettings.Camera);
  Button(PointF(252, 727), 28, $D92C405F, pgSpeaker, '', FSettings.Speaker);
  Button(PointF(334, 727), 29, Red, pgEnd, '');
end;

procedure TPhoneRenderer.DrawNotification;
var
  Y, Progress: Single;
  App, Sender, Body: string;
begin
  DrawWallpaper;
  DrawLock;
  Progress := Ease(FTime, NOTICE_AT, 0.32);
  if Progress <= 0 then Exit;
  Y := 244 - 61 * (1 - Progress);
  App := FSettings.NoticeApp;
  Sender := FSettings.Sender;
  Body := FSettings.MessageText;
  if FSettings.Style = psMissed then
  begin
    App := '電話';
    Sender := FSettings.Caller;
    Body := '不在着信　' + FSettings.NumberText;
  end;
  FillRound(FTarget, 36, Y + 4, 348, 145, 25, OpacityColor($660D172C, Progress));
  FillRound(FTarget, 36, Y, 348, 145, 25, OpacityColor(FPanel, Progress));
  if (FNoticeFace <> nil) or (FSettings.Style = psSocial) then
  begin
    DrawPhoneIcon(FTarget, FNoticeFace, MakeRect(50.0, Y + 18, 47.0, 47.0), 100,
      0, 0, Round(255 * Progress));
    if FNoticeFace = nil then Glyph(pgChat, 73.5, Y + 41, 25, OpacityColor(Green, Progress));
  end
  else if FSettings.Style = psMissed then Glyph(pgCall, 73, Y + 41, 25, OpacityColor(Red, Progress))
  else Glyph(pgBell, 73, Y + 41, 28, OpacityColor(FMuted, Progress));
  TextAt(App, pfSmall, 109, Y + 11, 259, 25, OpacityColor(FMuted, Progress));
  TextAt(Sender, pfBody, 109, Y + 34, 259, 30, OpacityColor(FText, Progress));
  TextAt(Body, pfLabel, 51, Y + 66, 317, 67, OpacityColor(FText, Progress),
    StringAlignmentNear, True);
end;

procedure TPhoneRenderer.DrawAlarm;
var
  Ring: Double;
begin
  DrawWallpaper;
  if (FSettings.Style = psAlarmStop) and (FTime >= ACTION_SWITCH) then
  begin
    DrawLock;
    Exit;
  end;
  Ring := 0;
  if FSettings.Style = psAlarm then Ring := Sin(2 * Pi * FTime / 1.65);
  FillRound(FTarget, 44, 164, 332, 341, 39, $C31A2B47);
  Glyph(pgBell, 210 + 3 * Ring, 217, 40, White);
  TextAt(FSettings.AlarmTime, pfClock, 51, 242, 318, 105, White, StringAlignmentCenter);
  TextAt(FSettings.AlarmName, pfTitle, 57, 359, 306, 49, White, StringAlignmentCenter);
  FText := White;
  Button(PointF(210, 684), 36, $FF375E92, pgBell, '停止');
end;

procedure TPhoneRenderer.DrawPower;
var
  Progress: Double;
  BarWidth: Single;
  Accent: ARGB;
  Title: string;
begin
  DrawWallpaper;
  DrawLock;
  Progress := Ease(FTime, NOTICE_AT, 0.27);
  if Progress <= 0 then Exit;
  if FSettings.Style = psCharge then
  begin
    Accent := Green;
    Title := '充電中';
  end
  else
  begin
    Accent := Red;
    Title := 'バッテリー残量が低下';
  end;
  FillRound(FTarget, 43, 273, 334, 184, 29, OpacityColor(FPanel, Progress));
  FillRound(FTarget, 157, 304, 102, 42, 12, OpacityColor(Accent, Progress));
  FillRound(FTarget, 262, 315, 6, 20, 3, OpacityColor(Accent, Progress));
  FillRound(FTarget, 160, 307, 96, 36, 9, OpacityColor(FPanel, Progress));
  BarWidth := 90 * FSettings.Battery / 100;
  if BarWidth > 0 then
    FillRound(FTarget, 163, 310, BarWidth, 30, 7, OpacityColor(Accent, Progress));
  if FSettings.Style = psCharge then Glyph(pgBolt, 210, 325, 25, OpacityColor(FText, Progress));
  TextAt(Format('%d%%', [FSettings.Battery]), pfBody, 50, 357, 320, 35,
    OpacityColor(FText, Progress), StringAlignmentCenter);
  TextAt(Title, pfLabel, 50, 397, 320, 31, OpacityColor(FMuted, Progress), StringAlignmentCenter);
end;

function TPhoneRenderer.Render(const Settings: TPhoneSettings; const Timeline: TPhoneTimeline;
  Seconds: Double; const CallFaceFile, NoticeFaceFile: string): TGPBitmap;
var
  Screen: TGPGraphicsPath;
  Shake, Light, Reveal: Single;
  StatusColor: ARGB;
  Style: TPhoneStyle;
  Transition: GraphicsState;
  Off, Waiting: Boolean;
begin
  FSettings := Settings;
  FTimeline := Timeline;
  FSeconds := Max(0.0, Seconds);
  Waiting := FSeconds < Settings.StartDelay;
  FEffectSeconds := Max(0.0, FSeconds - Settings.StartDelay);
  FTime := FEffectSeconds * FTimeline.Speed;
  FHasTap := FSettings.TapEffect and FTimeline.LastTap(FTime, FTap, FTapAge);
  Palette(Settings.Dark);
  LoadSlot(FWallpaper, FWallpaperKey, Settings.Wallpaper);
  LoadSlot(FAppIcon, FAppKey, Settings.AppIcon);
  LoadSlot(FCallFace, FCallKey, CallFaceFile);
  LoadSlot(FNoticeFace, FNoticeKey, NoticeFaceFile);
  Style := Settings.Style;
  FTarget := TGPGraphics.Create(FSurface);
  try
    FTarget.Clear(0);
    FTarget.SetSmoothingMode(SmoothingModeAntiAlias);
    FTarget.SetPixelOffsetMode(PixelOffsetModeHalf);
    FTarget.SetTextRenderingHint(TextRenderingHintAntiAliasGridFit);
    FTarget.SetInterpolationMode(InterpolationModeHighQualityBicubic);
    if FSettings.Vibrate then
    begin
      Shake := VibrationOffset(Style, FTime);
      if Abs(Shake) > 0.01 then
      begin
        FTarget.TranslateTransform(Shake + Abs(Shake), 0);
        FTarget.ScaleTransform(1 - 2 * Abs(Shake) / PHONE_WIDTH, 1);
      end;
    end;
    if FSettings.Body then DrawHousing(FTarget, HousingColors[Settings.Design]);
    Screen := ScreenPath;
    try
      FTarget.SetClip(Screen, CombineModeIntersect);
    finally
      Screen.Free;
    end;
    StatusColor := White;
    Off := False;
    Light := 1;
    if Waiting and (Style in [psIncoming, psAlarm]) then
    begin
      DrawWallpaper;
      DrawLock;
    end
    else case Style of
      psHome: DrawHome;
      psWake, psSleep:
        begin
          Light := Ease(FTime, 0.04, 0.34);
          if Style = psSleep then Light := 1 - Light;
          Off := Light <= 0;
          if not Off then
          begin
            DrawWallpaper;
            DrawLock;
          end;
        end;
      psUnlock:
        begin
          Reveal := Ease(FTime, ACTION_AT + 0.1, 0.42);
          if Reveal = 0 then
          begin
            DrawWallpaper;
            DrawLock;
          end
          else
          begin
            DrawHome;
            if Reveal < 1 then
            begin
              Transition := FTarget.Save;
              try
                FTarget.TranslateTransform(0, -SCREEN_H * Reveal);
                FillRound(FTarget, SCREEN_X, SCREEN_Y, SCREEN_W, SCREEN_H, SCREEN_RADIUS, FBackground);
                DrawWallpaper;
                DrawLock;
              finally
                FTarget.Restore(Transition);
              end;
            end;
          end;
        end;
      psDial:
        begin
          DrawDial;
          StatusColor := FText;
        end;
      psOutgoing, psIncoming, psAnswer, psVoice, psBusy, psReject, psHangup:
        begin
          if (Style = psOutgoing) and (FTime < ACTION_SWITCH) then
          begin
            // 発信オブジェクトの冒頭を番号入力の最終状態へ接続する。
            DrawDial(True);
          end
          else if (Style in [psAnswer, psReject]) and (FTime < ACTION_SWITCH) then DrawCall(psIncoming)
          else if (Style = psHangup) and (FTime < ACTION_SWITCH) then DrawCall(psVoice)
          else if (Style = psBusy) and Waiting then DrawCall(psOutgoing)
          else DrawCall(Style);
          StatusColor := FText;
        end;
      psVideo: DrawVideo;
      psSocial, psNotification, psMissed: DrawNotification;
      psLaunchMine, psLaunchCamera, psLaunchApp: DrawLaunch;
      psAlarm, psAlarmStop: DrawAlarm;
      psCharge, psBattery: DrawPower;
    end;
    if not Off then
    begin
      DrawStatus(StatusColor);
      if Style <> psVideo then
        FillRound(FTarget, 156, 789, 108, 4, 2, OpacityColor(StatusColor, 0.86));
      DrawTap;
    end;
    if Light < 1 then FillRound(FTarget, 14, 18, 392, 784, 0.5,
      OpacityColor($FF080C13, 1 - Light));
    if FSettings.Body then DrawCameraCutout(FTarget);
    Result := FSurface;
  finally
    FTarget.Free;
    FTarget := nil;
  end;
end;

end.
