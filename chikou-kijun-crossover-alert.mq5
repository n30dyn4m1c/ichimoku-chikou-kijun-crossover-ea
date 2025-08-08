//+------------------------------------------------------------------+
//|                  Simple Ichimoku Alert EA: Chikou crossing Kijun |
//|                                                       Neo Malesa |
//|                                     https://www.x.com/n30dyn4m1c |
//+------------------------------------------------------------------+
#property copyright "Neo Malesa"
#property link      "https://www.x.com/n30dyn4m1c"
#property version   "1.03"
#property strict

input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;
input ulong  MagicNumber   = 20250717;
input bool   EnableAlerts  = true;

// --- internal settings
input int Tenkan = 9;
input int Kijun  = 26;
input int Senkou = 52;

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

int      ichimokuHandle = INVALID_HANDLE;
datetime lastAlertBarTime = 0; // avoids duplicate alerts per bar

int OnInit()
{
    ichimokuHandle = iIchimoku(_Symbol, Timeframe, Tenkan, Kijun, Senkou);
    if (ichimokuHandle == INVALID_HANDLE)
    {
        Alert("Failed to create Ichimoku handle for ", _Symbol);
        return INIT_FAILED;
    }
    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    if (ichimokuHandle != INVALID_HANDLE)
        IndicatorRelease(ichimokuHandle);
}

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
    // Need enough history to reference Chikou and Kijun values from 26+ bars back
    int bars = Bars(_Symbol, Timeframe);
    return (bars >= (Kijun + 3));
}

void OnTick()
{
    if (!IsNewBar())
        return;

    if (!EnoughBars())
        return;

    // CLOSED-BAR CONFIRMATION:
    //   Bullish: Chikou crosses ABOVE historical Kijun (both values from same historical bar)
    //   Bearish: Chikou crosses BELOW historical Kijun
    double chikouPlottedAtClosedBar[2]; // Chikou plotted points for closed bar and its previous
    double kijunHistoricalAtClosedBar[2]; // Kijun values from the same historical bars as Chikou

    if (CopyBuffer(ichimokuHandle, 4, 1, 2, chikouPlottedAtClosedBar) < 2)
    {
        Print("CopyBuffer for Chikou failed: ", GetLastError());
        return;
    }

    if (CopyBuffer(ichimokuHandle, 1, Kijun + 1, 2, kijunHistoricalAtClosedBar) < 2)
    {
        Print("CopyBuffer for Kijun failed: ", GetLastError());
        return;
    }

    double chikouClosedBar   = chikouPlottedAtClosedBar[0];
    double chikouPreviousBar = chikouPlottedAtClosedBar[1];
    double kijunClosedBar    = kijunHistoricalAtClosedBar[0];
    double kijunPreviousBar  = kijunHistoricalAtClosedBar[1];

    bool bullish = (chikouPreviousBar <= kijunPreviousBar) && (chikouClosedBar > kijunClosedBar);
    bool bearish = (chikouPreviousBar >= kijunPreviousBar) && (chikouClosedBar < kijunClosedBar);

    datetime closedBarTime = iTime(_Symbol, Timeframe, 1);
    if (closedBarTime == lastAlertBarTime)
        return;

    if ((bullish || bearish) && EnableAlerts)
    {
        lastAlertBarTime = closedBarTime;
        double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
        string tf = TimeframeToString(Timeframe);
        string dir = bullish ? "Bullish" : "Bearish";
        Alert(_Symbol, " ", dir, " Chikou crossed historical Kijun (closed) on ", tf, " at ", DoubleToString(price, _Digits));
    }
}

//+------------------------------------------------------------------+
