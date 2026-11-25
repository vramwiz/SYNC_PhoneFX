
unit SYNC_PhoneFX_Graphics;

// MINE の筐体、角丸、画像読み込み、円形トリミングを流用する。

interface

uses Winapi.GDIPAPI, Winapi.GDIPOBJ;

const
  PHONE_WIDTH = 420;
  PHONE_HEIGHT = 820;
  SCREEN_X = 14;
  SCREEN_Y = 18;
  SCREEN_W = 392;
  SCREEN_H = 784;
  SCREEN_RADIUS = 29;
  DEFAULT_FACE_BACKGROUND = $E2E8ED;

function StartPhoneGraphics: Boolean;
procedure StopPhoneGraphics;
function RoundPath(X, Y, W, H, Radius: Single): TGPGraphicsPath;
function ScreenPath: TGPGraphicsPath;
procedure FillRound(Target: TGPGraphics; X, Y, W, H, Radius: Single; Color: ARGB);
procedure DrawHousing(Target: TGPGraphics; Color: ARGB);
procedure DrawCameraCutout(Target: TGPGraphics);
function LoadPhonePicture(const FileName: string): TGPBitmap;
procedure DrawPicture(Target: TGPGraphics; Image: TGPBitmap; const Bounds: TGPRectF;
  Opacity: Byte = 255);
procedure DrawPhoneIcon(Target: TGPGraphics; Image: TGPBitmap; const Bounds: TGPRectF;
  Scale, X, Y: Double; Opacity: Byte = 255; Background: Cardinal = DEFAULT_FACE_BACKGROUND);
procedure DrawCoverPicture(Target: TGPGraphics; Image: TGPBitmap; const Bounds: TGPRectF);
function OpacityColor(Color: ARGB; Opacity: Double): ARGB;

implementation

uses System.Math, System.SysUtils, Winapi.Windows;

var
  GraphicsToken: ULONG_PTR;

function StartPhoneGraphics: Boolean;
var
  Input: TGdiplusStartupInput;
begin
  if GraphicsToken <> 0 then Exit(True);
  Input := Default(TGdiplusStartupInput);
  Input.GdiplusVersion := 1;
  Result := GdiplusStartup(GraphicsToken, @Input, nil) = Ok;
end;

procedure StopPhoneGraphics;
begin
  if GraphicsToken = 0 then Exit;
  GdiplusShutdown(GraphicsToken);
  GraphicsToken := 0;
end;

function LoadPhonePicture(const FileName: string): TGPBitmap;
var
  Source: TGPBitmap;
  Target: TGPGraphics;
  Ratio: Double;
  W, H: Integer;
begin
  Result := nil;
  if (FileName = '') or not FileExists(FileName) then Exit;
  Source := TGPBitmap.Create(FileName);
  try
    if Source.GetLastStatus <> Ok then Exit;
    W := Source.GetWidth;
    H := Source.GetHeight;
    if (W < 1) or (H < 1) or (Int64(W) * H > 33554432) then Exit;
    Ratio := Min(1.0, 1024.0 / Max(W, H));
    Result := TGPBitmap.Create(Max(1, Round(W * Ratio)), Max(1, Round(H * Ratio)),
      PixelFormat32bppPARGB);
    Target := TGPGraphics.Create(Result);
    try
      Target.Clear(0);
      Target.SetInterpolationMode(InterpolationModeHighQualityBicubic);
      Target.DrawImage(Source, 0, 0, Integer(Result.GetWidth), Integer(Result.GetHeight));
    finally
      Target.Free;
    end;
  finally
    Source.Free;
  end;
end;

function RoundPath(X, Y, W, H, Radius: Single): TGPGraphicsPath;
begin
  Result := TGPGraphicsPath.Create;
  Radius := Min(Radius, Min(W, H) / 2) * 2;
  Result.AddArc(X, Y, Radius, Radius, 180, 90);
  Result.AddArc(X + W - Radius, Y, Radius, Radius, 270, 90);
  Result.AddArc(X + W - Radius, Y + H - Radius, Radius, Radius, 0, 90);
  Result.AddArc(X, Y + H - Radius, Radius, Radius, 90, 90);
  Result.CloseFigure;
end;

procedure FillRound(Target: TGPGraphics; X, Y, W, H, Radius: Single; Color: ARGB);
var
  Path: TGPGraphicsPath;
  Brush: TGPSolidBrush;
begin
  Path := RoundPath(X, Y, W, H, Radius);
  Brush := TGPSolidBrush.Create(Color);
  try
    Target.FillPath(Brush, Path);
  finally
    Brush.Free;
    Path.Free;
  end;
end;

procedure DrawPicture(Target: TGPGraphics; Image: TGPBitmap; const Bounds: TGPRectF;
  Opacity: Byte);
var
  Attributes: TGPImageAttributes;
  Matrix: TColorMatrix;
  I: Integer;
begin
  if Image = nil then Exit;
  Attributes := TGPImageAttributes.Create;
  try
    Matrix := Default(TColorMatrix);
    for I := 0 to 4 do Matrix[I, I] := 1;
    Matrix[3, 3] := Opacity / 255;
    Attributes.SetColorMatrix(Matrix);
    Target.DrawImage(Image, Bounds, 0, 0, Image.GetWidth, Image.GetHeight, UnitPixel, Attributes);
  finally
    Attributes.Free;
  end;
end;

procedure DrawPhoneIcon(Target: TGPGraphics; Image: TGPBitmap; const Bounds: TGPRectF;
  Scale, X, Y: Double; Opacity: Byte; Background: Cardinal);
var
  Path: TGPGraphicsPath;
  State: GraphicsState;
  Ratio, W, H: Double;
begin
  FillRound(Target, Bounds.X, Bounds.Y, Bounds.Width, Bounds.Height, Bounds.Width / 2,
    (Cardinal(Opacity) shl 24) or (Background and $FFFFFF));
  if Image = nil then Exit;
  Path := TGPGraphicsPath.Create;
  State := Target.Save;
  try
    Path.AddEllipse(Bounds);
    Target.SetClip(Path, CombineModeIntersect);
    Ratio := Max(Bounds.Width / Image.GetWidth, Bounds.Height / Image.GetHeight) * Scale / 100;
    W := Image.GetWidth * Ratio;
    H := Image.GetHeight * Ratio;
    DrawPicture(Target, Image, MakeRect(Single(Bounds.X + (Bounds.Width - W) / 2 + X * Bounds.Width / 100),
      Single(Bounds.Y + (Bounds.Height - H) / 2 + Y * Bounds.Height / 100), Single(W), Single(H)), Opacity);
  finally
    Target.Restore(State);
    Path.Free;
  end;
end;

function ScreenPath: TGPGraphicsPath;
begin
  Result := RoundPath(SCREEN_X, SCREEN_Y, SCREEN_W, SCREEN_H, SCREEN_RADIUS);
end;

procedure DrawHousing(Target: TGPGraphics; Color: ARGB);
var
  Path: TGPGraphicsPath;
  Opening: TGPGraphicsPath;
  Brush: TGPSolidBrush;
begin
  // 開口を引いたパスを描くので、ビデオ通話では背面の映像が透過する。
  Opening := ScreenPath;
  try
    Path := RoundPath(1, 1, PHONE_WIDTH - 2, PHONE_HEIGHT - 2, 42);
    Brush := TGPSolidBrush.Create($FF101418);
    try
      Path.AddPath(Opening, False);
      Target.FillPath(Brush, Path);
    finally
      Brush.Free;
      Path.Free;
    end;
    Path := RoundPath(3, 3, PHONE_WIDTH - 6, PHONE_HEIGHT - 6, 40);
    Brush := TGPSolidBrush.Create(Color or $FF000000);
    try
      Path.AddPath(Opening, False);
      Target.FillPath(Brush, Path);
    finally
      Brush.Free;
      Path.Free;
    end;
  finally
    Opening.Free;
  end;
end;

procedure DrawCameraCutout(Target: TGPGraphics);
begin
  FillRound(Target, PHONE_WIDTH / 2 - 42, 26, 84, 16, 8, $FF101418);
end;

procedure DrawCoverPicture(Target: TGPGraphics; Image: TGPBitmap; const Bounds: TGPRectF);
var
  Scale, W, H: Single;
begin
  if Image = nil then Exit;
  Scale := Max(Bounds.Width / Image.GetWidth, Bounds.Height / Image.GetHeight);
  W := Image.GetWidth * Scale;
  H := Image.GetHeight * Scale;
  DrawPicture(Target, Image, MakeRect(Bounds.X + (Bounds.Width - W) / 2,
    Bounds.Y + (Bounds.Height - H) / 2, W, H));
end;

function OpacityColor(Color: ARGB; Opacity: Double): ARGB;
begin
  Result := (Color and $FFFFFF) or
    (Cardinal(Round((Color shr 24) * EnsureRange(Opacity, 0.0, 1.0))) shl 24);
end;

end.
