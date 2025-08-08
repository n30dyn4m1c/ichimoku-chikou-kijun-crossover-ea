//+------------------------------------------------------------------+
//|  Simple Ichimoku Alert EA: Chikou crossing historical Kijun (MT5)
//|  Fires only after candle close (no intrabar alerts)
//|  Author: Neo Malesa  |  https://www.x.com/n30dyn4m1c
//+------------------------------------------------------------------+
#property copyright "Neo Malesa"
#property link      "https://www.x.com/n30dyn4m1c"
#property version   "1.04"
#property strict

//==================== Inputs ====================//
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT; // evaluation timeframe
input ulong  MagicNumber   = 20250717;            // not used for trading; kept for consistency
input bool   EnableAlerts  = true;                // platform alerts
input bool   DebugLog      = false;               // print diagnostics

// Ichimoku parameters
input int Tenkan = 9;
input int Kijun  = 26; // also the Chikou offset
input int Senkou = 52;

//================ Utility =======================//
string TimeframeToString(ENUM_TIMEFRAMES tf)
{
    switch(tf)
    {
        case PERIOD_M1:  return "M1";
        case PERIOD_M2:  return "M2";
        case PERIOD_M3:  return "M3";
        case PERIOD_M4:  return "M4";
        case PERIOD_M5:  return "M5";
        case PERIOD_M6:  return "M6";
        case PERIOD_M10: return "M10";
        case PERIOD_M12: return "M12";
        case PERIOD_M15: return "M15";
        case PERIOD_M20: return "M20";
        case PERIOD_M30: return "M30";
        case PERIOD_H1:  return "H1";
        case PERIOD_H2:  return "H2";
        case PERIOD_H3:  return "H3";
        case PERIOD_H4:  return "H4";
        case PERIOD_H6:  return "H6";
        case PERIOD_H8:  return "H8";
        case PERIOD_H12: return "H12";
        case PERIOD_D1:  return "D1";
        case PERIOD_W1:  return "W1";
        case PERIOD_MN1: return "MN1";
        default:         return "Custom";
    }
}

//================ Globals =======================//
int      g_ichimokuHandle = INVALID_HANDLE;
datetime g_lastAlertBarTime = 0; // prevents duplicate alerts per bar

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

// New bar detector (on selected Timeframe)
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

// Ensure we can reference 26-27 bars back with closed-bar confirmation
bool EnoughBars()
{
    int bars = Bars(_Symbol, Timeframe);
    return (bars >= (Kijun + 2));
}

//================ Core ==========================//
void OnTick()
{
    // Evaluate only once per new bar → previous bar is closed
    if (!IsNewBar())
        return;

    if (!EnoughBars())
        return;

    // Alignments (closed-bar confirmation):
    // - Chikou buffer index 4 at shifts [0,1] → plotted points for the just-closed bar and its previous.
    //   These correspond to price bars [26,27] back.
    // - Kijun buffer index 1 at shifts [26,27] → values from those same historical price bars.
    double chikouAtClosedBar[2];     // [0]=closed bar, [1]=prev (plotted 26/27 back in price time)
    double kijunAtSameHistorical[2]; // [0]=Kijun@26 back, [1]=Kijun@27 back

    if (CopyBuffer(g_ichimokuHandle, 4, 0, 2, chikouAtClosedBar) < 2)
    {
        if (DebugLog) Print("[Ichimoku EA] CopyBuffer Chikou failed: ", GetLastError());
        return;
    }
    if (CopyBuffer(g_ichimokuHandle, 1, Kijun, 2, kijunAtSameHistorical) < 2)
    {
        if (DebugLog) Print("[Ichimoku EA] CopyBuffer Kijun failed: ", GetLastError());
        return;
    }

    double chikou_closed   = chikouAtClosedBar[0];
    double chikou_previous = chikouAtClosedBar[1];
    double kijun_closed    = kijunAtSameHistorical[0];
    double kijun_previous  = kijunAtSameHistorical[1];

    // Ignore if indicator hasn't enough history at those points
    if (chikou_closed == EMPTY_VALUE || chikou_previous == EMPTY_VALUE ||
        kijun_closed == EMPTY_VALUE  || kijun_previous  == EMPTY_VALUE)
    {
        if (DebugLog) Print("[Ichimoku EA] EMPTY_VALUE encountered — waiting for more history");
        return;
    }

    // Cross detection on the historical timeline
    bool crossed_bullish = (chikou_previous <= kijun_previous) && (chikou_closed > kijun_closed);
    bool crossed_bearish = (chikou_previous >= kijun_previous) && (chikou_closed < kijun_closed);

    if (DebugLog)
    {
        PrintFormat("[Ichimoku EA] ChikouPrev=%.5f ChikouNow=%.5f | KijunPrev=%.5f KijunNow=%.5f | Bull=%s Bear=%s",
                    chikou_previous, chikou_closed, kijun_previous, kijun_closed,
                    crossed_bullish?"T":"F", crossed_bearish?"T":"F");
    }

    // Use closed bar time to throttle once-per-bar
    datetime closedBarTime = iTime(_Symbol, Timeframe, 1);
    if (closedBarTime == g_lastAlertBarTime)
        return;

    if ((crossed_bullish || crossed_bearish) && EnableAlerts)
    {
        g_lastAlertBarTime = closedBarTime;
        double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        string tf = TimeframeToString(Timeframe);
        string dir = crossed_bullish ? "Bullish" : "Bearish";
        Alert(_Symbol, " ", dir, " Chikou x historical Kijun (closed) on ", tf,
              " at ", DoubleToString(price, _Digits));
    }
}

//+------------------------------------------------------------------+
