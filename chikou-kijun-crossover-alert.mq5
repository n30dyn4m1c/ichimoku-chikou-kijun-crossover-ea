//+------------------------------------------------------------------+
//|  Simple Ichimoku Alert EA: Chikou crossing historical Kijun (MT5)
//|  Closed-bar confirmation only (alerts fire after candle close)
//|  Author: Neo Malesa  |  https://www.x.com/n30dyn4m1c
//|  Reviewer fix: Code Copilot (Chikou×Kijun alignment)
//+------------------------------------------------------------------+
#property copyright "Neo Malesa"
#property link      "https://www.x.com/n30dyn4m1c"
#property version   "1.11"
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
int      g_ichimokuHandle = INVALID_HANDLE;
datetime g_lastAlertBarTime = 0; // once-per-bar throttle

//================ Lifecycle =====================//
int OnInit()
{
   g_ichimokuHandle = iIchimoku(_Symbol, Timeframe, Tenkan, Kijun, Senkou);
   if (g_ichimokuHandle == INVALID_HANDLE)
   {
      Alert("[Ichimoku EA] Failed to create handle for ", _Symbol, ", TF=", TimeframeToString(Timeframe));
      return INIT_FAILED;
   }
   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if (g_ichimokuHandle != INVALID_HANDLE)
      IndicatorRelease(g_ichimokuHandle);
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

//================ Core ==========================//
bool GetBufValue(const int handle, const int buffer, const int shift, double &val)
{
   double tmp[1];
   int copied = CopyBuffer(handle, buffer, shift, 1, tmp);
   if (copied != 1) return false;
   val = tmp[0];
   return true;
}

void OnTick()
{
   // Only proceed at new bar open to confirm last candle is closed
   if (!IsNewBar())
      return;

   if (!EnoughBars())
      return;

   double chikou_prev, chikou_now, kijun_prev, kijun_now;
   if (!GetBufValue(g_ichimokuHandle, 4, Kijun + 2, chikou_prev)) return;
   if (!GetBufValue(g_ichimokuHandle, 4, Kijun + 1, chikou_now )) return;
   if (!GetBufValue(g_ichimokuHandle, 1, Kijun + 2, kijun_prev )) return;
   if (!GetBufValue(g_ichimokuHandle, 1, Kijun + 1, kijun_now  )) return;

   if (chikou_now == EMPTY_VALUE || chikou_prev == EMPTY_VALUE ||
       kijun_now  == EMPTY_VALUE || kijun_prev  == EMPTY_VALUE)
      return;

   const double eps    = _Point * 0.5;
   const double d_prev = chikou_prev - kijun_prev;
   const double d_now  = chikou_now  - kijun_now;

   bool bull_core = (d_prev <= +eps) && (d_now > +eps);
   bool bear_core = (d_prev >= -eps) && (d_now < -eps);

   const bool crossed_bullish = InvertSignals ? bear_core : bull_core;
   const bool crossed_bearish = InvertSignals ? bull_core : bear_core;

   const datetime closedBarTime = iTime(_Symbol, Timeframe, 1);
   if (closedBarTime == g_lastAlertBarTime)
      return;

   if ((crossed_bullish || crossed_bearish) && EnableAlerts)
   {
      g_lastAlertBarTime = closedBarTime;
      const double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      const string tf = TimeframeToString(Timeframe);
      const string dir = crossed_bullish ? "Bullish" : "Bearish";
      Alert(_Symbol, " ", dir, " Chikou-Kijun Crossover on ", tf,
            " at ", DoubleToString(price, _Digits));
   }
}
//+------------------------------------------------------------------+
