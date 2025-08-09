//+------------------------------------------------------------------+
//|  Simple Ichimoku Alert EA: Chikou crossing historical Kijun (MT5)
//|  Closed-bar confirmation only
//|  Author: Neo Malesa  |  https://www.x.com/n30dyn4m1c
//|  Reviewer fix: Code Copilot (Chikou×Kijun alignment)
//+------------------------------------------------------------------+
#property copyright "Neo Malesa"
#property link      "https://www.x.com/n30dyn4m1c"
#property version   "1.06"
#property strict

//==================== Inputs ====================//
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT; // evaluation timeframe
input ulong  MagicNumber   = 20250717;            // reserved; not used for trading
input bool   EnableAlerts  = true;                // platform alerts
input bool   DebugLog      = false;               // diagnostics

// Ichimoku parameters
input int Tenkan = 9;
input int Kijun  = 26; // also Chikou offset
input int Senkou = 52;

//================ Utility =======================//
string TimeframeToString(ENUM_TIMEFRAMES tf)
{
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

// New bar detector (selected timeframe)
bool IsNewBar()
{
   static datetime lastTime = 0;
   const datetime t = iTime(_Symbol, Timeframe, 0);
   if (t != lastTime) { lastTime = t; return true; }
   return false;
}

// Need to access up to shift (Kijun+2)
bool EnoughBars()
{
   const int bars = Bars(_Symbol, Timeframe);
   return (bars >= (Kijun + 3));
}

//================ Core ==========================//
void OnTick()
{
   if (!IsNewBar())
      return;

   if (!EnoughBars())
      return;

   // *** Alignment choice ***
   // Option A (recommended): read Chikou **where it's drawn** → shifts [Kijun+1, Kijun+2]
   // Option B (previous attempt): read closes via Chikou[1,2] and compare with Kijun[Kijun+1,Kijun+2]
   // Some terminals differ on how the Chikou buffer is filled; A avoids ambiguity.

   // --- Option A: both series sampled at the SAME historical bars ---
   double chikouHist[2];
   if (CopyBuffer(g_ichimokuHandle, 4, Kijun + 1, 2, chikouHist) < 2)
   {
      if (DebugLog) Print("[Ichimoku EA] CopyBuffer Chikou(hist) failed: ", GetLastError());
      return;
   }

   double kijunHist[2];
   if (CopyBuffer(g_ichimokuHandle, 1, Kijun + 1, 2, kijunHist) < 2)
   {
      if (DebugLog) Print("[Ichimoku EA] CopyBuffer Kijun(hist) failed: ", GetLastError());
      return;
   }

   const double chikou_now   = chikouHist[0];
   const double chikou_prev  = chikouHist[1];
   const double kijun_now    = kijunHist[0];
   const double kijun_prev   = kijunHist[1];

   // Guard against missing values
   if (chikou_now == EMPTY_VALUE || chikou_prev == EMPTY_VALUE ||
       kijun_now  == EMPTY_VALUE || kijun_prev  == EMPTY_VALUE)
   {
      if (DebugLog) Print("[Ichimoku EA] EMPTY_VALUE encountered — waiting for more history");
      return;
   }

   // Robust cross with epsilon to avoid flat-line equality issues
   const double eps = _Point * 0.5; // why: guard float equality; 0.5 pip on most symbols
   const bool crossed_bullish = (chikou_prev <= kijun_prev + eps) && (chikou_now > kijun_now + eps);
   const bool crossed_bearish = (chikou_prev >= kijun_prev - eps) && (chikou_now < kijun_now - eps);

   if (DebugLog)
   {
      PrintFormat("[Ichimoku EA] t1 Chikou=%.5f Kijun=%.5f | t2 Chikou=%.5f Kijun=%.5f | Bull=%s Bear=%s",
                  chikou_prev, kijun_prev, chikou_now, kijun_now,
                  crossed_bullish?"T":"F", crossed_bearish?"T":"F");
   }

   // Throttle once per closed bar
   const datetime closedBarTime = iTime(_Symbol, Timeframe, 1);
   if (closedBarTime == g_lastAlertBarTime)
      return;

   if ((crossed_bullish || crossed_bearish) && EnableAlerts)
   {
      g_lastAlertBarTime = closedBarTime;
      const double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      const string tf = TimeframeToString(Timeframe);
      const string dir = crossed_bullish ? "Bullish" : "Bearish";
      Alert(_Symbol, " ", dir, " Chikou × historical Kijun (closed) on ", tf,
            " at ", DoubleToString(price, _Digits));
   }
}
//+------------------------------------------------------------------+
