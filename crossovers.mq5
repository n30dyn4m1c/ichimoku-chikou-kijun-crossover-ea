
//+------------------------------------------------------------------+
//| Ichimoku Chikou×Kijun EA + Top-Center Hourly Countdown (MT5)     |
//| Adds alerts: Close crossing Tenkan/Kijun (fresh, closed bar)     |
//+------------------------------------------------------------------+
#property copyright "Neo Malesa"
#property link      "https://www.x.com/n30dyn4m1c"
#property version   "1.21"
#property strict

//==================== Inputs ====================//
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT; // evaluation timeframe
input ulong  MagicNumber   = 20250717;            // reserved; not used for trading
input bool   EnableAlerts  = true;                // platform alerts
input bool   DebugLog      = false;               // diagnostics
input bool   InvertSignals = false;               // flips bull/bear labeling if needed
// Ichimoku parameters
input int Tenkan = 9;
input int Kijun  = 26; // also Chikou offset
input int Senkou = 52;
// Tenkan/Kijun close-cross alerts
input bool AlertTenkanClose = true;
input bool AlertKijunClose  = true;
// Countdown display
input bool  ShowCountdown   = true;
input color CountdownColor  = clrLime;
input int   CountdownFontPx = 20;
input int   CountdownPadY   = 10;

//================ Utility =======================//
string TimeframeToString(ENUM_TIMEFRAMES tf)
{
   if (tf == PERIOD_CURRENT) tf = (ENUM_TIMEFRAMES)Period();
   switch(tf)
   {
      case PERIOD_M1:  return "M1";   case PERIOD_M2:  return "M2";   case PERIOD_M3:  return "M3";
      case PERIOD_M4:  return "M4";   case PERIOD_M5:  return "M5";   case PERIOD_M6:  return "M6";
      case PERIOD_M10: return "M10";  case PERIOD_M12: return "M12";  case PERIOD_M15: return "M15";
      case PERIOD_M20: return "M20";  case PERIOD_M30: return "M30";  case PERIOD_H1:  return "H1";
      case PERIOD_H2:  return "H2";   case PERIOD_H3:  return "H3";   case PERIOD_H4:  return "H4";
      case PERIOD_H6:  return "H6";   case PERIOD_H8:  return "H8";   case PERIOD_H12: return "H12";
      case PERIOD_D1:  return "D1";   case PERIOD_W1:  return "W1";   case PERIOD_MN1: return "MN1";
      default:         return "Custom";
   }
}

//================ Globals =======================//
int      g_ichimokuHandle   = INVALID_HANDLE;
datetime g_lastAlertBarTime = 0; // Chikou×Kijun once-per-bar throttle
datetime g_lastTenkanCloseBar=0, g_lastKijunCloseBar=0; // once-per-bar for close crosses

// Countdown globals
#define COUNT_NAME "EA_NextHourCountdown"
void MakeCountdown();
void UpdateCountdown();

//================ Lifecycle =====================//
int OnInit()
{
   g_ichimokuHandle = iIchimoku(_Symbol, Timeframe, Tenkan, Kijun, Senkou);
   if (g_ichimokuHandle == INVALID_HANDLE)
   {
      Alert("[Ichimoku EA] Failed to create handle for ", _Symbol, ", TF=", TimeframeToString(Timeframe));
      return INIT_FAILED;
   }
   if (ShowCountdown)
   {
      EventSetTimer(1);
      MakeCountdown();
      UpdateCountdown();
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if (g_ichimokuHandle != INVALID_HANDLE)
      IndicatorRelease(g_ichimokuHandle);
   if (ShowCountdown)
   {
      EventKillTimer();
      ObjectDelete(0, COUNT_NAME);
   }
}

// Fires only at the open of a new bar (ensures previous bar is closed)
bool IsNewBar()
{
   static datetime lastTime = 0;
   datetime t = iTime(_Symbol, Timeframe, 0);
   if (t != lastTime)
   {
      lastTime = t;
      return true;
   }
   return false;
}

bool EnoughBars()
{
   int bars = Bars(_Symbol, Timeframe);
   return (bars >= (Kijun + 3));
}

//================ Core helpers ==================//
bool GetBufValue(const int handle, const int buffer, const int shift, double &val)
{
   double tmp[1];
   int copied = CopyBuffer(handle, buffer, shift, 1, tmp);
   if (copied != 1) return false;
   val = tmp[0];
   return true;
}

//================ Signals =======================//
void OnTick()
{
   // Only proceed at new bar open to confirm last candle is closed
   if (!IsNewBar()) return;
   if (!EnoughBars()) return;

   const datetime closedBarTime = iTime(_Symbol, Timeframe, 1);
   const double eps = _Point * 0.5;

   // ----- Chikou × Kijun (historical) crossover detection -----
   double chikou_prev, chikou_now, kijun_prev, kijun_now;
   if (!GetBufValue(g_ichimokuHandle, 4, Kijun + 2, chikou_prev)) return; // Chikou at bar (1) aligned -> shift Kijun+1; need prev too
   if (!GetBufValue(g_ichimokuHandle, 4, Kijun + 1, chikou_now )) return;
   if (!GetBufValue(g_ichimokuHandle, 1, Kijun + 2, kijun_prev )) return; // historical Kijun
   if (!GetBufValue(g_ichimokuHandle, 1, Kijun + 1, kijun_now  )) return;

   if (chikou_now!=EMPTY_VALUE && chikou_prev!=EMPTY_VALUE &&
       kijun_now !=EMPTY_VALUE && kijun_prev !=EMPTY_VALUE)
   {
      const double d_prev = chikou_prev - kijun_prev;
      const double d_now  = chikou_now  - kijun_now;

      bool bull_core = (d_prev <= +eps) && (d_now > +eps);
      bool bear_core = (d_prev >= -eps) && (d_now < -eps);

      const bool crossed_bullish = InvertSignals ? bear_core : bull_core;
      const bool crossed_bearish = InvertSignals ? bull_core : bear_core;

      if (closedBarTime != g_lastAlertBarTime && (crossed_bullish || crossed_bearish) && EnableAlerts)
      {
         g_lastAlertBarTime = closedBarTime;
         const double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         const string tf = TimeframeToString(Timeframe);
         const string dir = crossed_bullish ? "Bullish" : "Bearish";
         Alert(_Symbol, " ", dir, " Chikou-Kijun Crossover on ", tf,
               " at ", DoubleToString(price, _Digits));
      }
   }

   // ----- Close crossing Tenkan (fresh, closed bar) -----
   if (AlertTenkanClose && closedBarTime != g_lastTenkanCloseBar)
   {
      double tk_prev, tk_now;
      if (!GetBufValue(g_ichimokuHandle, 0, 2, tk_prev) || !GetBufValue(g_ichimokuHandle, 0, 1, tk_now))
         return;

      double c_prev = iClose(_Symbol, Timeframe, 2);
      double c_now  = iClose(_Symbol, Timeframe, 1);

      bool up   = (c_prev <= tk_prev + eps) && (c_now > tk_now + eps);
      bool down = (c_prev >= tk_prev - eps) && (c_now < tk_now - eps);

      if ((up || down) && EnableAlerts)
      {
         g_lastTenkanCloseBar = closedBarTime;
         const string tf = TimeframeToString(Timeframe);
         Alert(_Symbol, " ", (up ? "Close>Tenkan" : "Close<Tenkan"), " on ", tf);
      }
      else if (DebugLog)
      {
         PrintFormat("TenkanClose chk up=%d down=%d c_prev=%.5f tk_prev=%.5f c_now=%.5f tk_now=%.5f",
                     up, down, c_prev, tk_prev, c_now, tk_now);
      }
   }

   // ----- Close crossing Kijun (fresh, closed bar) -----
   if (AlertKijunClose && closedBarTime != g_lastKijunCloseBar)
   {
      double kj_prev, kj_now;
      if (!GetBufValue(g_ichimokuHandle, 1, 2, kj_prev) || !GetBufValue(g_ichimokuHandle, 1, 1, kj_now))
         return;

      double c_prev = iClose(_Symbol, Timeframe, 2);
      double c_now  = iClose(_Symbol, Timeframe, 1);

      bool up   = (c_prev <= kj_prev + eps) && (c_now > kj_now + eps);
      bool down = (c_prev >= kj_prev - eps) && (c_now < kj_now - eps);

      if ((up || down) && EnableAlerts)
      {
         g_lastKijunCloseBar = closedBarTime;
         const string tf = TimeframeToString(Timeframe);
         Alert(_Symbol, " ", (up ? "Close>Kijun" : "Close<Kijun"), " on ", tf);
      }
      else if (DebugLog)
      {
         PrintFormat("KijunClose chk up=%d down=%d c_prev=%.5f kj_prev=%.5f c_now=%.5f kj_now=%.5f",
                     up, down, c_prev, kj_prev, c_now, kj_now);
      }
   }
}

//================ Countdown =====================//
void OnTimer()
{
   if (ShowCountdown) UpdateCountdown();
}

void MakeCountdown()
{
   ObjectDelete(0, COUNT_NAME);
   if(!ObjectCreate(0, COUNT_NAME, OBJ_LABEL, 0, 0, 0))
   { Print("Countdown create failed, err=", GetLastError()); return; }

   ObjectSetInteger(0, COUNT_NAME, OBJPROP_CORNER,  CORNER_LEFT_UPPER);
   ObjectSetInteger(0, COUNT_NAME, OBJPROP_ANCHOR,  ANCHOR_CENTER);
   long w = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   ObjectSetInteger(0, COUNT_NAME, OBJPROP_XDISTANCE, (int)(w/2));
   ObjectSetInteger(0, COUNT_NAME, OBJPROP_YDISTANCE, CountdownPadY);
   ObjectSetInteger(0, COUNT_NAME, OBJPROP_FONTSIZE,  CountdownFontPx);
   ObjectSetString (0, COUNT_NAME, OBJPROP_FONT,      "Arial Black");
   ObjectSetInteger(0, COUNT_NAME, OBJPROP_COLOR,     CountdownColor);
   ObjectSetInteger(0, COUNT_NAME, OBJPROP_BACK,      false);
   ObjectSetInteger(0, COUNT_NAME, OBJPROP_HIDDEN,    false);
   ObjectSetInteger(0, COUNT_NAME, OBJPROP_SELECTABLE,false);
}

void UpdateCountdown()
{
   if(ObjectFind(0, COUNT_NAME) < 0) MakeCountdown();
   datetime now  = TimeCurrent();
   datetime next = (now/3600 + 1) * 3600;
   int rem = (int)(next - now), m = rem/60, s = rem%60;
   string txt = StringFormat("Next hour in %02d:%02d", m, s);
   ObjectSetString(0, COUNT_NAME, OBJPROP_TEXT, txt);
   // turn red in last 10s
   ObjectSetInteger(0, COUNT_NAME, OBJPROP_COLOR, rem<=10 ? clrRed : CountdownColor);
   // keep centered on resize
   long w = ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   ObjectSetInteger(0, COUNT_NAME, OBJPROP_XDISTANCE, (int)(w/2));
   ChartRedraw(0);
}
//+------------------------------------------------------------------+

