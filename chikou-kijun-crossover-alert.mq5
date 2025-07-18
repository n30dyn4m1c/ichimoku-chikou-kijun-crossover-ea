//+------------------------------------------------------------------+
//|                  Simple Ichimoku Alert EA: Chikou crossing Kijun |
//|                                                       Neo Malesa |
//|                                     https://www.x.com/n30dyn4m1c |
//+------------------------------------------------------------------+

#property copyright "Neo Malesa"
#property link      "https://www.x.com/n30dyn4m1c"
#property version   "1.00"
#property strict

input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;
input ulong  MagicNumber   = 20250717;
input bool   EnableAlerts  = true;

string TimeframeToString(ENUM_TIMEFRAMES tf)
{
    switch(tf)
    {
        case PERIOD_M1: return "M1";
        case PERIOD_M5: return "M5";
        case PERIOD_M15: return "M15";
        case PERIOD_M30: return "M30";
        case PERIOD_H1: return "H1";
        case PERIOD_H4: return "H4";
        case PERIOD_D1: return "D1";
        case PERIOD_W1: return "W1";
        case PERIOD_MN1: return "MN1";
        default: return "Custom";
    }
}

int ichimokuHandle;
datetime lastBarTime = 0;

int OnInit()
{
    ichimokuHandle = iIchimoku(_Symbol, Timeframe, 9, 26, 52);
    if (ichimokuHandle == INVALID_HANDLE)
    {
        Alert("Failed to create Ichimoku handle for ", _Symbol);
        return INIT_FAILED;
    }
    return INIT_SUCCEEDED;
}

bool IsNewBar()
{
    static datetime lastTime = 0;
    datetime currentTime = iTime(_Symbol, Timeframe, 0);
    if (currentTime != lastTime)
    {
        lastTime = currentTime;
        return true;
    }
    return false;
}

void OnTick()
{
    if (!IsNewBar())
        return;

    double chikou26[2], kijun26[2];

    if (CopyBuffer(ichimokuHandle, 4, 26, 2, chikou26) < 2 ||
        CopyBuffer(ichimokuHandle, 1, 26, 2, kijun26) < 2)
    {
        Alert("Buffer copy error for ", _Symbol);
        return;
    }

    double chikouPrev = chikou26[1];
    double chikouCurr = chikou26[0];
    double kijunPrev = kijun26[1];
    double kijunCurr = kijun26[0];

    bool bullishCross = (chikouPrev < kijunPrev) && (chikouCurr > kijunCurr);
    bool bearishCross = (chikouPrev > kijunPrev) && (chikouCurr < kijunCurr);

    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if (bullishCross && EnableAlerts)
    {
        Alert(_Symbol, " Bullish Crossover on ", TimeframeToString(Timeframe), " at ", DoubleToString(price, _Digits));
    }
    else if (bearishCross && EnableAlerts)
    {
        Alert(_Symbol, " Bearish Crossover on ", TimeframeToString(Timeframe), " at ", DoubleToString(price, _Digits));
    }
}

//+------------------------------------------------------------------+
