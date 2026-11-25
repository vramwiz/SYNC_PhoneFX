
unit SYNC_PhoneFX_Timeline;

// フレームと音声でタップ、通知、振動の時刻を共有する。

interface

uses System.Types;

type
  TPhoneStyle = (psHome, psWake, psSleep, psUnlock, psDial, psOutgoing, psIncoming,
    psAnswer, psVoice, psVideo, psBusy, psReject, psHangup, psSocial, psNotification,
    psMissed, psLaunchMine, psLaunchCamera, psLaunchApp, psAlarm, psAlarmStop,
    psCharge, psBattery);

  TPhoneSettings = record
    Style: TPhoneStyle;
    Design, CallFace, NoticeFace, Signal, Battery, RingTone: Integer;
    Body, Dark, Charging, Mic, Camera, Speaker, TapEffect, TapSound, Vibrate: Boolean;
    Speed, StartDelay, CallOffset, IconX, IconY, IconScale, TapSize, Volume: Double;
    TapColor: Cardinal;
    NumberText, Caller, CallImage, NoticeApp, Sender, NoticeImage, MessageText,
      AlarmTime, AlarmName, AppIcon, AppName, Clock, Wallpaper: string;
  end;

  TPhoneTap = record
    AtTime: Double;
    Position: TPointF;
    Key: Char;
  end;

  TPhoneTimeline = record
    Taps: TArray<TPhoneTap>;
    DialText: string;
    DialEnds: TArray<Integer>;
    Speed: Double;
    procedure Prepare(Style: TPhoneStyle; const NumberText: string; SpeedPercent: Double);
    function DialPrefix(Time: Double): string;
    function LastTap(Time: Double; out Tap: TPhoneTap; out Age: Double): Boolean;
  end;

const
  MINE_APP_NAME = 'MINE';
  STYLE_NAMES: array[TPhoneStyle] of PWideChar = (
    'ホーム画面', '画面点灯', '画面消灯', 'ロック解除', '電話番号入力', '電話発信',
    '電話着信', '通話開始', '音声通話中', 'ビデオ通話中', '話し中', '着信拒否',
    '通話終了', MINE_APP_NAME + '・SNS受信通知', '一般アプリ通知', '不在着信通知', MINE_APP_NAME + '起動',
    'カメラ起動', '任意のアプリ起動', 'アラーム', 'アラーム停止', '充電開始',
    'バッテリー残量警告');
  DEFAULT_NUMBER = '090-xxxx-xxxx';
  DEFAULT_CLOCK = '12:00';
  DEFAULT_ALARM = '07:00';
  ACTION_AT = 0.23;
  NOTICE_AT = 0.16;
  FIRST_KEY_AT = 0.23;
  KEY_INTERVAL = 0.19;
  TAP_DURATION = 0.36;
  ACTION_SWITCH = ACTION_AT + 0.18;

function KeyCenter(Key: Char): TPointF;
function AppCenter(Index: Integer): TPointF;
function TargetApp(Style: TPhoneStyle): Integer;
function Ease(Time, Start, Duration: Double): Double;
function VibrationAge(Style: TPhoneStyle; Time: Double): Double;
function VibrationOffset(Style: TPhoneStyle; Time: Double): Single;
function PhoneClock(const Start: string; Seconds: Double): string;
function CallClock(Seconds: Double): string;

implementation

uses System.Math, System.SysUtils, System.Character;

const
  Keys = '123456789*0#';

function KeyCenter(Key: Char): TPointF;
var
  Index: Integer;
begin
  Index := Max(0, Pos(Key, Keys) - 1);
  Result := PointF(103 + 107 * (Index mod 3), 302 + 87 * (Index div 3));
end;

function AppCenter(Index: Integer): TPointF;
begin
  Result := PointF(93 + 117 * (Index mod 3), 222 + 120 * (Index div 3));
end;

function TargetApp(Style: TPhoneStyle): Integer;
begin
  case Style of
    psLaunchMine: Result := 0;
    psLaunchCamera: Result := 1;
  else
    Result := 8;
  end;
end;

procedure TPhoneTimeline.Prepare(Style: TPhoneStyle; const NumberText: string;
  SpeedPercent: Double);
var
  I, N, GlyphLength: Integer;
  Key: Char;

  procedure AddTap(const Position: TPointF; AtTime: Double; DialKey: Char = #0);
  var
    Index: Integer;
  begin
    Index := Length(Taps);
    SetLength(Taps, Index + 1);
    Taps[Index].AtTime := AtTime;
    Taps[Index].Position := Position;
    Taps[Index].Key := DialKey;
  end;

begin
  Speed := EnsureRange(SpeedPercent, 25.0, 200.0) / 100;
  Taps := nil;
  DialEnds := nil;
  DialText := '';
  case Style of
    psDial:
      begin
        DialText := NumberText;
        SetLength(Taps, Length(DialText));
        SetLength(DialEnds, Length(DialText));
        N := 0;
        I := 1;
        while I <= Length(DialText) do
        begin
          GlyphLength := 1;
          if (I < Length(DialText)) and DialText[I].IsHighSurrogate and DialText[I + 1].IsLowSurrogate then
            GlyphLength := 2;
          Key := DialText[I];
          if not CharInSet(Key, ['-', ' ', '(', ')', '+']) then
          begin
            if Pos(Key, Keys) = 0 then Key := Char(Ord('0') + ((N * 7 + 3) mod 10));
            Taps[N].AtTime := FIRST_KEY_AT + N * KEY_INTERVAL;
            Taps[N].Position := KeyCenter(Key);
            Taps[N].Key := Key;
            DialEnds[N] := I + GlyphLength - 1;
            Inc(N);
          end
          else if N > 0 then
            DialEnds[N - 1] := I + GlyphLength - 1;
          Inc(I, GlyphLength);
        end;
        SetLength(Taps, N);
        SetLength(DialEnds, N);
      end;
    psUnlock: AddTap(PointF(210, 726), ACTION_AT);
    psOutgoing, psHangup: AddTap(PointF(210, 686), ACTION_AT);
    psAnswer: AddTap(PointF(288, 686), ACTION_AT);
    psReject: AddTap(PointF(132, 686), ACTION_AT);
    psLaunchMine, psLaunchCamera, psLaunchApp: AddTap(AppCenter(TargetApp(Style)), ACTION_AT);
    psAlarmStop: AddTap(PointF(210, 684), ACTION_AT);
  end;
end;

function TPhoneTimeline.DialPrefix(Time: Double): string;
var
  Index: Integer;
begin
  if Length(DialEnds) = 0 then
  begin
    if Time >= FIRST_KEY_AT then Exit(DialText);
    Exit('');
  end;
  if Time < FIRST_KEY_AT then Exit('');
  Index := Min(High(DialEnds), Floor((Time - FIRST_KEY_AT) / KEY_INTERVAL));
  Result := Copy(DialText, 1, DialEnds[Index]);
end;

function TPhoneTimeline.LastTap(Time: Double; out Tap: TPhoneTap; out Age: Double): Boolean;
var
  Index: Integer;
begin
  if Length(Taps) = 0 then Exit(False);
  Index := 0;
  if Length(Taps) > 1 then
    Index := EnsureRange(Floor((Time - FIRST_KEY_AT) / KEY_INTERVAL), 0, High(Taps));
  Tap := Taps[Index];
  Age := Time - Tap.AtTime;
  Result := (Age >= 0) and (Age < TAP_DURATION);
end;

function Ease(Time, Start, Duration: Double): Double;
var
  T: Double;
begin
  T := EnsureRange((Time - Start) / Duration, 0.0, 1.0);
  Result := T * T * (3 - 2 * T);
end;

function VibrationAge(Style: TPhoneStyle; Time: Double): Double;
begin
  Result := -1;
  case Style of
    psIncoming: Result := Time - Floor(Time / 2.0) * 2.0 - NOTICE_AT;
    psSocial, psNotification, psMissed, psBattery: Result := Time - NOTICE_AT;
    psAlarm: Result := Time - Floor(Time / 1.65) * 1.65 - NOTICE_AT;
  end;
end;

function VibrationOffset(Style: TPhoneStyle; Time: Double): Single;
var
  Age: Double;
begin
  Result := 0;
  Age := VibrationAge(Style, Time);
  if (Age >= 0) and (Age < 0.34) then
    Result := 4 * Sin(Age * 2 * Pi * 15) * (1 - Age / 0.34);
end;

function PhoneClock(const Start: string; Seconds: Double): string;
var
  Split, H, M: Integer;
  Minutes: Int64;
begin
  Split := Pos(':', Start);
  H := StrToIntDef(Copy(Start, 1, Split - 1).Trim, -1);
  M := StrToIntDef(Copy(Start, Split + 1, MaxInt).Trim, -1);
  if (H < 0) or (H > 23) or (M < 0) or (M > 59) then
  begin
    H := 12;
    M := 0;
  end;
  Minutes := (H * 60 + M + Trunc(Max(0.0, Seconds) / 60)) mod 1440;
  Result := Format('%.2d:%.2d', [Minutes div 60, Minutes mod 60]);
end;

function CallClock(Seconds: Double): string;
var
  Whole: Int64;
begin
  Whole := Trunc(Max(0.0, Seconds));
  if Whole >= 3600 then
    Result := Format('%d:%.2d:%.2d', [Whole div 3600, Whole div 60 mod 60, Whole mod 60])
  else
    Result := Format('%.2d:%.2d', [Whole div 60, Whole mod 60]);
end;

end.
