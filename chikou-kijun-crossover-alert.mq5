//+------------------------------------------------------------------+
//|                   Simple Ichimoku Alert EA: Chikou crosses Kijun |
//|                                                       Neo Malesa |
//|                                     https://www.x.com/n30dyn4m1c |
//+------------------------------------------------------------------+
#property copyright "Neo Malesa"
#property link      "https://www.x.com/n30dyn4m1c"
#property version   "1.00"
#property strict

input ulong  MagicNumber   = 20250717;
input bool   EnableAlerts  = true;

int ichimokuHandle;
datetime lastBarTime = 0;

int OnInit()
{
    ichimokuHandle = iIchimoku(_Symbol, PERIOD_M1, 9, 26, 52);
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
    datetime currentTime = iTime(_Symbol, PERIOD_M1, 0);
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

    double chikou[2], kijun[2];

    if (CopyBuffer(ichimokuHandle, 4, 26, 2, chikou) < 2 ||
        CopyBuffer(ichimokuHandle, 1, 26, 2, kijun) < 2)
    {
        Alert("Buffer copy error for ", _Symbol);
        return;
    }

    double chikouPrev = chikou[1];
    double chikouCurr = chikou[0];
    double kijunPrev = kijun[1];
    double kijunCurr = kijun[0];

    bool bullishCross = (chikouPrev < kijunPrev) && (chikouCurr > kijunCurr);
    bool bearishCross = (chikouPrev > kijunPrev) && (chikouCurr < kijunCurr);

    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);

    if (bullishCross && EnableAlerts)
    {
        Alert(_Symbol, " Bullish Crossover at ", DoubleToString(price, _Digits));
    }
    else if (bearishCross && EnableAlerts)
    {
        Alert(_Symbol, " Bearish Crossover at ", DoubleToString(price, _Digits));
    }
}

//+------------------------------------------------------------------+
