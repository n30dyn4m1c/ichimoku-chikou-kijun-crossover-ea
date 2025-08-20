//+------------------------------------------------------------------+
//| Ichimoku EA with Cloud, Chikou & Cross Alerts (MT5)              |
//| Visual alignments:                                               |
//|  - Price vs Kumo: compare to Kumo shifted BACK 26 (s=1/2)        |
//|  - Chikou vs Kumo: compare to Kumo shifted BACK 52 (s=1+2K/2+2K) |
//| Jump-through detection + per-condition throttles + 2-min alert   |
//+------------------------------------------------------------------+
#property copyright "Neo Malesa"
#property version   "1.39"
#property strict

//==================== Inputs ====================//
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;
input ulong  MagicNumber    = 20250717;
input bool   EnableAlerts   = true;
input bool   DebugLog       = false;
input bool   InvertSignals  = false;
input int Tenkan = 9, Kijun = 26, Senkou = 52;
input bool AlertTenkanClose=true, AlertKijunClose=true, AlertPriceCloudCross=true, AlertChikouCloudCross=true;
// Countdown (UI)
input bool  ShowCountdown=true; input color CountdownColor=clrLime; input int CountdownFontPx=20, CountdownPadY=10;

//==================== Globals ===================//
int g_ichimokuHandle=INVALID_HANDLE;
// independent throttles
datetime g_lastCK=0, g_lastPX=0, g_lastCX=0, g_lastTK=0, g_lastKJ=0;
// 2-minute alert throttle
datetime g_lastTwoMinTarget=0;

//==================== Utils =====================//
string TF(ENUM_TIMEFRAMES tf){ if(tf==PERIOD_CURRENT) tf=(ENUM_TIMEFRAMES)Period();
 switch(tf){case PERIOD_M1:return"M1";case PERIOD_M5:return"M5";case PERIOD_M15:return"M15";
 case PERIOD_M30:return"M30";case PERIOD_H1:return"H1";case PERIOD_H4:return"H4";
 case PERIOD_D1:return"D1";case PERIOD_W1:return"W1";case PERIOD_MN1:return"MN1";default:return"TF";}}
bool GetBuf(const int h,const int b,const int sh,double &v){ double t[1]; int c=CopyBuffer(h,b,sh,1,t); if(c!=1) return false; v=t[0]; return true; }
bool NewBar(){ static datetime lt=0; datetime t=iTime(_Symbol,Timeframe,0); if(t!=lt){ lt=t; return true;} return false; }
bool EnoughBars(){ return Bars(_Symbol,Timeframe) >= (Kijun+Senkou+10); }
void Fire(const datetime barTime, datetime &gate, const string msg){ if(!EnableAlerts) return; if(barTime!=gate) gate=barTime; Alert(msg); }

//==================== UI: Countdown =============//
#define COUNT_NAME "EA_NextHourCountdown"
void MakeCountdown(){
  ObjectDelete(0,COUNT_NAME);
  if(!ObjectCreate(0,COUNT_NAME,OBJ_LABEL,0,0,0)) return;
  ObjectSetInteger(0,COUNT_NAME,OBJPROP_CORNER,CORNER_LEFT_UPPER);
  ObjectSetInteger(0,COUNT_NAME,OBJPROP_ANCHOR,ANCHOR_CENTER);
  long w=ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
  ObjectSetInteger(0,COUNT_NAME,OBJPROP_XDISTANCE,(int)(w/2));
  ObjectSetInteger(0,COUNT_NAME,OBJPROP_YDISTANCE,CountdownPadY);
  ObjectSetInteger(0,COUNT_NAME,OBJPROP_FONTSIZE,CountdownFontPx);
  ObjectSetString (0,COUNT_NAME,OBJPROP_FONT,"Arial Black");
  ObjectSetInteger(0,COUNT_NAME,OBJPROP_COLOR,CountdownColor);
  ObjectSetInteger(0,COUNT_NAME,OBJPROP_BACK,false);
  ObjectSetInteger(0,COUNT_NAME,OBJPROP_HIDDEN,false);
  ObjectSetInteger(0,COUNT_NAME,OBJPROP_SELECTABLE,false);
}
void UpdateCountdown(){
  if(ObjectFind(0,COUNT_NAME)<0) MakeCountdown();
  datetime now=TimeCurrent(), next=(now/3600+1)*3600;
  int rem=(int)(next-now), m=rem/60, s=rem%60;
  ObjectSetString(0,COUNT_NAME,OBJPROP_TEXT,StringFormat("Next hour in %02d:%02d",m,s));
  ObjectSetInteger(0,COUNT_NAME,OBJPROP_COLOR,rem<=10?clrRed:CountdownColor);
  long w=ChartGetInteger(0,CHART_WIDTH_IN_PIXELS);
  ObjectSetInteger(0,COUNT_NAME,OBJPROP_XDISTANCE,(int)(w/2)); ChartRedraw(0);
  if(rem<=120 && g_lastTwoMinTarget!=next){ g_lastTwoMinTarget=next; if(EnableAlerts) Alert(_Symbol," 2 minutes to new hour (",TF(Timeframe),")"); }
}

//==================== Lifecycle =================//
int OnInit(){
  g_ichimokuHandle=iIchimoku(_Symbol,Timeframe,Tenkan,Kijun,Senkou);
  if(g_ichimokuHandle==INVALID_HANDLE){ Alert("Ichimoku handle failed"); return INIT_FAILED; }
  if(ShowCountdown){ EventSetTimer(1); MakeCountdown(); UpdateCountdown(); }
  return INIT_SUCCEEDED;
}
void OnDeinit(const int reason){
  if(g_ichimokuHandle!=INVALID_HANDLE) IndicatorRelease(g_ichimokuHandle);
  if(ShowCountdown){ EventKillTimer(); ObjectDelete(0,COUNT_NAME); }
}
void OnTimer(){ if(ShowCountdown) UpdateCountdown(); }

//==================== Logic =====================//
void OnTick(){
  if(!NewBar() || !EnoughBars()) return;
  const datetime barTime=iTime(_Symbol,Timeframe,1);
  const double eps=_Point*0.5;

  // --- Chikou × Kijun crossover (historical) ---
  double ck_p,ck_n,kj_p,kj_n;
  if(GetBuf(g_ichimokuHandle,4,Kijun+2,ck_p)&&GetBuf(g_ichimokuHandle,4,Kijun+1,ck_n)&&
     GetBuf(g_ichimokuHandle,1,Kijun+2,kj_p)&&GetBuf(g_ichimokuHandle,1,Kijun+1,kj_n))
  {
    if(ck_p!=EMPTY_VALUE&&ck_n!=EMPTY_VALUE&&kj_p!=EMPTY_VALUE&&kj_n!=EMPTY_VALUE){
      double d_p=ck_p-kj_p, d_n=ck_n-kj_n;
      bool bull=(d_p<=+eps)&&(d_n>+eps), bear=(d_p>=-eps)&&(d_n<-eps);
      if(InvertSignals){ bool t=bull; bull=bear; bear=t; }
      if(bull||bear) Fire(barTime,g_lastCK,_Symbol+" "+(bull?"Bullish":"Bearish")+" Chikou-Kijun Crossover on "+TF(Timeframe));
    }
  }

  // --- Close crosses Tenkan / Kijun ---
  if(AlertTenkanClose){
    double tk_p,tk_n; if(GetBuf(g_ichimokuHandle,0,2,tk_p)&&GetBuf(g_ichimokuHandle,0,1,tk_n)){
      double c_p=iClose(_Symbol,Timeframe,2), c_n=iClose(_Symbol,Timeframe,1);
      bool up=(c_p<=tk_p+eps)&&(c_n>tk_n+eps), dn=(c_p>=tk_p-eps)&&(c_n<tk_n-eps);
      if(up||dn) Fire(barTime,g_lastTK,_Symbol+(up?" Price closed ABOVE Tenkan":" Price closed BELOW Tenkan")+" on "+TF(Timeframe));
    }
  }
  if(AlertKijunClose){
    double kjp,kjn; if(GetBuf(g_ichimokuHandle,1,2,kjp)&&GetBuf(g_ichimokuHandle,1,1,kjn)){
      double c_p=iClose(_Symbol,Timeframe,2), c_n=iClose(_Symbol,Timeframe,1);
      bool up=(c_p<=kjp+eps)&&(c_n>kjn+eps), dn=(c_p>=kjp-eps)&&(c_n<kjn-eps);
      if(up||dn) Fire(barTime,g_lastKJ,_Symbol+(up?" Price closed ABOVE Kijun":" Price closed BELOW Kijun")+" on "+TF(Timeframe));
    }
  }

  // --- Price vs Kumo (Kumo shifted BACK 26; s=1/2) ---
  if(AlertPriceCloudCross){
    const int s_now=1, s_prev=2; // pull cloud back 26 to where price is visually now
    double ssa_n,ssb_n,ssa_p,ssb_p;
    if(GetBuf(g_ichimokuHandle,2,s_now,ssa_n)&&GetBuf(g_ichimokuHandle,3,s_now,ssb_n)&&
       GetBuf(g_ichimokuHandle,2,s_prev,ssa_p)&&GetBuf(g_ichimokuHandle,3,s_prev,ssb_p))
    {
      double c_p=iClose(_Symbol,Timeframe,2), c_n=iClose(_Symbol,Timeframe,1);
      double top_p=MathMax(ssa_p,ssb_p), bot_p=MathMin(ssa_p,ssb_p);
      double top_n=MathMax(ssa_n,ssb_n), bot_n=MathMin(ssa_n,ssb_n);

      bool was_above=c_p>top_p+eps, was_below=c_p<bot_p-eps, was_in=!(was_above||was_below);
      bool is_above=c_n>top_n+eps,  is_below=c_n<bot_n-eps,  is_in=!(is_above||is_below);

      bool px_in=(was_above||was_below)&&is_in;
      bool px_above=was_in&&is_above, px_below=was_in&&is_below;
      bool px_jump_up=was_below&&is_above, px_jump_dn=was_above&&is_below;

      if(px_in)        Fire(barTime,g_lastPX,_Symbol+" Price closed INSIDE Kumo on "+TF(Timeframe));
      if(px_above)     Fire(barTime,g_lastPX,_Symbol+" Price closed ABOVE Kumo on "+TF(Timeframe));
      if(px_below)     Fire(barTime,g_lastPX,_Symbol+" Price closed BELOW Kumo on "+TF(Timeframe));
      if(px_jump_up)   Fire(barTime,g_lastPX,_Symbol+" Price jumped ABOVE Kumo on "+TF(Timeframe));
      if(px_jump_dn)   Fire(barTime,g_lastPX,_Symbol+" Price dropped BELOW Kumo on "+TF(Timeframe));
    }
  }

  // --- Chikou vs Kumo (Kumo shifted BACK 52; s=1+2K / 2+2K) ---
  if(AlertChikouCloudCross){
    const int sc_now=1, sc_prev=2;                 // evaluate plotted Chikou at bars 1/2
    double chi_n,chi_p, ssa_n,ssb_n, ssa_p,ssb_p;
    if(GetBuf(g_ichimokuHandle,4,sc_now,chi_n)&&GetBuf(g_ichimokuHandle,4,sc_prev,chi_p) &&
       GetBuf(g_ichimokuHandle,2,sc_now+2*Kijun,ssa_n)&&GetBuf(g_ichimokuHandle,3,sc_now+2*Kijun,ssb_n) &&
       GetBuf(g_ichimokuHandle,2,sc_prev+2*Kijun,ssa_p)&&GetBuf(g_ichimokuHandle,3,sc_prev+2*Kijun,ssb_p))
    {
      double top_p=MathMax(ssa_p,ssb_p), bot_p=MathMin(ssa_p,ssb_p);
      double top_n=MathMax(ssa_n,ssb_n), bot_n=MathMin(ssa_n,ssb_n);

      bool was_above=chi_p>top_p+eps, was_below=chi_p<bot_p-eps, was_in=!(was_above||was_below);
      bool is_above =chi_n>top_n+eps,  is_below =chi_n<bot_n-eps,  is_in=!(is_above||is_below);

      bool cx_in=(was_above||was_below)&&is_in;
      bool cx_above=was_in&&is_above, cx_below=was_in&&is_below;
      bool cx_jump_up=was_below&&is_above, cx_jump_dn=was_above&&is_below;

      if(cx_in)       Fire(barTime,g_lastCX,_Symbol+" Chikou closed INSIDE Kumo on "+TF(Timeframe));
      if(cx_above)    Fire(barTime,g_lastCX,_Symbol+" Chikou closed ABOVE Kumo on "+TF(Timeframe));
      if(cx_below)    Fire(barTime,g_lastCX,_Symbol+" Chikou closed BELOW Kumo on "+TF(Timeframe));
      if(cx_jump_up)  Fire(barTime,g_lastCX,_Symbol+" Chikou jumped ABOVE Kumo on "+TF(Timeframe));
      if(cx_jump_dn)  Fire(barTime,g_lastCX,_Symbol+" Chikou dropped BELOW Kumo on "+TF(Timeframe));
    }
  }
}
