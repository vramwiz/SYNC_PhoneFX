
unit SYNC_PhoneFX_Audio;

// AviUtl2 の要求サンプル範囲から合成音を直接求める。素材ファイルは不要。

interface

uses SYNC_PhoneFX_Timeline;

// 出力はモノラル。呼び出し側が必要なチャンネルへ同じ音を渡す。
procedure RenderPhoneAudio(const Settings: TPhoneSettings; const Timeline: TPhoneTimeline;
  StartSample: Int64; Count, SampleRate: Integer; var Samples: TArray<Single>);

implementation

uses System.Math;

type
  TPhoneSound = (soTap, soDTMF, soDial, soCalling, soRinging, soBusy, soAnswer,
    soEnd, soNotice, soAlarm, soUnlock, soCharge, soVibration);

function Tone(Time, Frequency, Duration, Level: Double; Decay: Double = 0;
  Sweep: Double = 0): Double;
begin
  if (Time <= 0) or (Time >= Duration) then Exit(0);
  Result := Level * Sin(2 * Pi * Time * (Frequency + 0.5 * Sweep * Time)) *
    Min(1.0, Time / 0.005) * Min(1.0, (Duration - Time) / 0.014);
  if Decay > 0 then Result := Result * Exp(-Decay * Time);
end;

function SoundAt(Sound: TPhoneSound; Time: Double; Key: Char; RingTone: Integer): Double;
const
  Keys = '123456789*0#';
  DTMFRows: array[0..3] of Integer = (697, 770, 852, 941);
  DTMFColumns: array[0..2] of Integer = (1209, 1336, 1477);
var
  Index: Integer;
begin
  case Sound of
    soTap: Result := Tone(Time, 335, 0.039, 0.31, 65, -2350) +
      Tone(Time, 1300, 0.018, 0.13, 100);
    soDTMF:
      begin
        Index := Pos(Key, Keys) - 1;
        if Index < 0 then Exit(0);
        Result := Tone(Time, DTMFRows[Index div 3], 0.082, 0.17) +
          Tone(Time, DTMFColumns[Index mod 3], 0.082, 0.16);
      end;
    soDial: Result := Tone(Time, 400, 0.16, 0.18) + Tone(Time, 440, 0.16, 0.12);
    soCalling: Result := Tone(Time, 400, 0.79, 0.27) + Tone(Time, 450, 0.79, 0.13);
    soRinging:
      case RingTone of
        1: Result := Tone(Time, 625, 0.17, 0.33, 9) +
          Tone(Time - 0.18, 825, 0.19, 0.31, 9) + Tone(Time - 0.37, 1090, 0.27, 0.29, 10);
        2: Result := Tone(Time, 510, 0.71, 0.29, 0) * (0.63 + 0.37 * Cos(2 * Pi * 8 * Time)) +
          Tone(Time, 1020, 0.67, 0.075, 0);
      else
        Result := Tone(Time, 710, 0.24, 0.35, 11) + Tone(Time, 1420, 0.15, 0.08, 21) +
          Tone(Time - 0.24, 940, 0.25, 0.34, 9) + Tone(Time - 0.24, 1880, 0.16, 0.08, 21);
      end;
    soBusy: Result := Tone(Time, 400, 0.33, 0.38);
    soAnswer: Result := Tone(Time, 590, 0.13, 0.30, 11, 1500) +
      Tone(Time - 0.08, 890, 0.18, 0.26, 10);
    soEnd: Result := Tone(Time, 670, 0.11, 0.31, 10) +
      Tone(Time - 0.10, 440, 0.18, 0.28, 11);
    soNotice: Result := Tone(Time, 790, 0.15, 0.32, 11) +
      Tone(Time - 0.10, 1160, 0.27, 0.33, 10) + Tone(Time - 0.10, 2320, 0.15, 0.06, 24);
    soAlarm: Result := Tone(Time, 880, 0.19, 0.36) + Tone(Time - 0.23, 880, 0.19, 0.36) +
      Tone(Time - 0.46, 1120, 0.24, 0.33);
    soUnlock: Result := Tone(Time, 480, 0.18, 0.26, 14, 2150);
    soCharge: Result := Tone(Time, 440, 0.17, 0.30, 11) +
      Tone(Time - 0.12, 670, 0.19, 0.28, 9) + Tone(Time - 0.24, 910, 0.26, 0.26, 10);
    soVibration: Result := Tone(Time, 80, 0.31, 0.19, 4) + Tone(Time, 145, 0.27, 0.07, 6);
  else
    Result := 0;
  end;
end;

procedure RenderPhoneAudio(const Settings: TPhoneSettings; const Timeline: TPhoneTimeline;
  StartSample: Int64; Count, SampleRate: Integer; var Samples: TArray<Single>);
var
  I: Integer;
  EffectStartSample: Int64;
  Tap: TPhoneTap;
  RawTime, Time, Gain, Value, Delay, Age: Double;
begin
  SetLength(Samples, Count);
  if Count = 0 then Exit;
  FillChar(Samples[0], Count * SizeOf(Single), 0);
  if Settings.Volume <= 0 then Exit;
  if Settings.Style in [psHome, psWake, psSleep, psVoice, psVideo] then Exit;
  // speed は演出時刻に適用する。待ち時間はオブジェクト上の実時間。
  EffectStartSample := StartSample - Round(Settings.StartDelay * SampleRate);
  if EffectStartSample + Count <= 0 then Exit;
  Gain := Settings.Volume / 100;
  for I := 0 to Count - 1 do
  begin
    RawTime := (EffectStartSample + I) / SampleRate;
    if RawTime < 0 then Continue;
    Time := RawTime * Timeline.Speed;
    Value := 0;
    if Timeline.LastTap(Time, Tap, Age) then
    begin
      Age := Age / Timeline.Speed;
      if Tap.Key <> #0 then Value := SoundAt(soDTMF, Age, Tap.Key, 0);
      if Settings.TapSound then Value := Value + SoundAt(soTap, Age, #0, 0);
    end;

    Delay := ACTION_SWITCH;
    case Settings.Style of
      psOutgoing:
        begin
          Value := Value + SoundAt(soDial, (Time - ACTION_AT) / Timeline.Speed, #0, 0);
          Delay := Time - 0.48;
          if Delay >= 0 then
            Value := Value + SoundAt(soCalling,
              (Delay - Floor(Delay / 2.75) * 2.75) / Timeline.Speed, #0, 0);
        end;
      psIncoming:
        begin
          Delay := Time - NOTICE_AT;
          if Delay >= 0 then
            Value := Value + SoundAt(soRinging, (Delay - Floor(Delay / 2) * 2) /
              Timeline.Speed, #0, Settings.RingTone);
        end;
      psBusy: Value := Value + SoundAt(soBusy, (Time - Floor(Time / 0.68) * 0.68) /
        Timeline.Speed, #0, 0);
      psAnswer: Value := Value + SoundAt(soAnswer, (Time - Delay) / Timeline.Speed, #0, 0);
      psReject, psHangup: Value := Value + SoundAt(soEnd, (Time - Delay) / Timeline.Speed, #0, 0);
      psUnlock: Value := Value + SoundAt(soUnlock, (Time - Delay) / Timeline.Speed, #0, 0);
      psSocial, psNotification, psMissed, psBattery:
        Value := Value + SoundAt(soNotice, (Time - NOTICE_AT) / Timeline.Speed, #0, 0);
      psCharge:
        Value := Value + SoundAt(soCharge, (Time - NOTICE_AT) / Timeline.Speed, #0, 0);
      psAlarm:
        begin
          Delay := Time - NOTICE_AT;
          if Delay >= 0 then
            Value := Value + SoundAt(soAlarm, (Delay - Floor(Delay / 1.65) * 1.65) /
              Timeline.Speed, #0, 0);
        end;
      psAlarmStop:
        if Time < ACTION_SWITCH then Value := Value +
          SoundAt(soAlarm, (Time - NOTICE_AT) / Timeline.Speed, #0, 0) *
          (1 - Ease(Time, ACTION_AT + 0.10, 0.08));
    end;
    if Settings.Vibrate then
      Value := Value + SoundAt(soVibration, VibrationAge(Settings.Style, Time) / Timeline.Speed, #0, 0);
    Samples[I] := EnsureRange(Value, -1.0, 1.0) * Gain;
  end;
end;

end.
