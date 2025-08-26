//+------------------------------------------------------------------+
//| Ichimoku EA + DI filter + DI-exit + Imminent-DI (MT5)            |
//| On Chikou–Kijun cross: close any trade; open if DI validates     |
//| or DI momentum implies imminent cross. Exit on opposite DI cross |
//+------------------------------------------------------------------+
#property copyright "Neo Malesa"
#property version   "1.47"
#property strict
#include <Trade/Trade.mqh>

//==================== Inputs ====================//
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;
input ulong  MagicNumber    = 20250717;
input bool   EnableAlerts   = true;
input bool   InvertSignals  = false;
input int Tenkan = 9, Kijun = 26, Senkou = 52;
input bool AlertTenkanClose=true, AlertKijunClose=true, AlertPriceCloudCross=true, AlertChikouCloudCross=true;
input bool  ShowCountdown=true; input color CountdownColor=clrLime; input int CountdownFontPx=20, CountdownPadY=10;
input double Lots=0.10; input int DeviationPts=20;
input double DIImminentThresh=4.0; // min |ΔDI| over 1 bar for early validation

CTrade trade;

//==================== Globals ===================//
int g_ichimokuHandle=INVALID_HANDLE, g_adxHandle=INVALID_HANDLE;
datetime g_lastCK=0, g_lastPX=0, g_lastCX=0, g_lastTK=0, g_lastKJ=0, g_lastTwoMinTarget=0;

//==================== Utils =====================//
string TF(ENUM_TIMEFRAMES tf){ if(tf==PERIOD_CURRENT) tf=(ENUM_TIMEFRAMES)Period();
 switch(tf){case PERIOD_M1:return"M1";case PERIOD_M5:return"M5";case PERIOD_M15:return"M15";
 case PERIOD_M30:return"M30";case PERIOD_H1:return"H1";case PERIOD_H4:return"H4";
 case PERIOD_D1:return"D1";case PERIOD_W1:return"W1";case PERIOD_MN1:return"MN1";default:return"TF";}}
bool GetBuf(const int h,const int b,const int sh,double &v){ double t[1]; int c=CopyBuffer(h,b,sh,1,t); if(c!=1) return false; v=t[0]; return true; }
bool NewBar(){ static datetime lt=0; datetime t=iTime(_Symbol,Timeframe,0); if(t!=lt){ lt=t; return true;} return false; }
bool EnoughBars(){ return Bars(_Symbol,Timeframe) >= (Kijun+Senkou+10); }
void Fire(const datetime barTime, datetime &gate, const string msg){ if(!EnableAlerts) return; if(barTime!=gate) gate=barTime; Alert(msg); }

//==================== ADX / DI ==================//
bool GetDI(const int sh,double &plusDI,double &minusDI){
  if(g_adxHandle==INVALID_HANDLE) return false;
  double p[1], m[1];
  if(CopyBuffer(g_adxHandle,1,sh,1,p)!=1) return false;   // +DI
  if(CopyBuffer(g_adxHandle,2,sh,1,m)!=1) return false;   // -DI
  plusDI=p[0]; minusDI=m[0];
  return (plusDI!=EMPTY_VALUE && minusDI!=EMPTY_VALUE);
}
bool DIFilter(const bool bull,double &p,double &m){ if(!GetDI(1,p,m)) return false; return bull ? (p>m) : (m>p); }
bool DIXBull(){ double p1,m1,p2,m2; if(!GetDI(1,p1,m1)||!GetDI(2,p2,m2)) return false; return (p2<=m2 && p1>m1); }
bool DIXBear(){ double p1,m1,p2,m2; if(!GetDI(1,p1,m1)||!GetDI(2,p2,m2)) return false; return (p2>=m2 && p1<m1); }
// Imminent cross: strong 1-bar DI divergence toward desired side
bool DIImminent(const bool bull){
  double p1,m1,p2,m2; if(!GetDI(1,p1,m1)||!GetDI(2,p2,m2)) return false;
  double dP=p1-p2, dM=m1-m2; // recent momentum
  return bull ? (dP>=DIImminentThresh && dM<=-DIImminentThresh)
              : (dM>=DIImminentThresh && dP<=-DIImminentThresh);
}

//==================== Trade notes ===============//
void NoteOpen(const string side){
  Alert(_Symbol," [",TF(Timeframe),"] ",side," OPEN @ ",DoubleToString(trade.ResultPrice(),_Digits),
        " | ",trade.ResultRetcodeDescription());
}
void NoteClose(const string side){
  Alert(_Symbol," [",TF(Timeframe),"] ",side," CLOSE @ ",DoubleToString(trade.ResultPrice(),_Digits),
        " | ",trade.ResultRetcodeDescription());
}

//==================== Trading helpers (netting) ==//
bool HasOurPosition(){ if(!PositionSelect(_Symbol)) return false; return (ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber; }
int  OpenDir(){ if(!HasOurPosition()) return 0; return PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?1:-1; }
bool CloseIfAny(){
  if(!HasOurPosition()) return true;
  string curSide = OpenDir()>0 ? "BUY" : "SELL";
  if(!trade.PositionClose(_Symbol)){ Alert(_Symbol," [",TF(Timeframe),"] ",curSide," close FAILED (",trade.ResultRetcodeDescription(),")"); return false; }
  NoteClose(curSide); return true;
}
bool OpenDirIfValid(const int dir){
  trade.SetExpertMagicNumber(MagicNumber); trade.SetDeviationInPoints(DeviationPts);
  bool ok=(dir>0)?trade.Buy(Lots,_Symbol):trade.Sell(Lots,_Symbol);
  string side=(dir>0)?"BUY":"SELL";
  if(ok) NoteOpen(side); else Alert(_Symbol," [",TF(Timeframe),"] ",side," open FAILED (",trade.ResultRetcodeDescription(),")");
  return ok;
}

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
  g_ichimokuHandle=iIchimoku(_Symbol,Timeframe,Tenkan,Kijun,Senkou); if(g_ichimokuHandle==INVALID_HANDLE){ Alert("Ichimoku handle failed"); return INIT_FAILED; }
  g_adxHandle=iADX(_Symbol,Timeframe,14);                              if(g_adxHandle==INVALID_HANDLE){ Alert("ADX handle failed"); return INIT_FAILED; }
  trade.SetExpertMagicNumber(MagicNumber); trade.SetDeviationInPoints(DeviationPts);
  if(ShowCountdown){ EventSetTimer(1); MakeCountdown(); UpdateCountdown(); }
  return INIT_SUCCEEDED;
}
void OnDeinit(const int reason){
  if(g_ichimokuHandle!=INVALID_HANDLE) IndicatorRelease(g_ichimokuHandle);
  if(g_adxHandle!=INVALID_HANDLE) IndicatorRelease(g_adxHandle);
  if(ShowCountdown){ EventKillTimer(); ObjectDelete(0,COUNT_NAME); }
}
void OnTimer(){ if(ShowCountdown) UpdateCountdown(); }

//==================== Logic =====================//
void OnTick(){
  if(!NewBar() || !EnoughBars()) return;
  const datetime barTime=iTime(_Symbol,Timeframe,1);
  const double eps=_Point*0.5;

  // --- Chikou × Kijun crossover (entry logic) ---
  double ck_p,ck_n,kj_p,kj_n;
  if(GetBuf(g_ichimokuHandle,4,Kijun+2,ck_p)&&GetBuf(g_ichimokuHandle,4,Kijun+1,ck_n)&&
     GetBuf(g_ichimokuHandle,1,Kijun+2,kj_p)&&GetBuf(g_ichimokuHandle,1,Kijun+1,kj_n))
  {
    if(ck_p!=EMPTY_VALUE&&ck_n!=EMPTY_VALUE&&kj_p!=EMPTY_VALUE&&kj_n!=EMPTY_VALUE){
      double d_p=ck_p-kj_p, d_n=ck_n-kj_n;
      bool bull=(d_p<=+eps)&&(d_n>+eps), bear=(d_p>=-eps)&&(d_n<-eps);
      if(InvertSignals){ bool t=bull; bull=bear; bear=t; }

      if(bull||bear){
        string cross=bull?"Bullish":"Bearish";

        // 1) Always close any open trade at crossover
        if(HasOurPosition()) CloseIfAny();

        // 2) Validate with DI or Imminent DI momentum
        double pDI,mDI; bool pass=DIFilter(bull,pDI,mDI);
        if(!pass && DIImminent(bull)){
          Alert(_Symbol," [",TF(Timeframe),"] ",cross," crossover EARLY VALID (DI momentum) ",
                "| +DIΔ/-DIΔ >= ",DoubleToString(DIImminentThresh,1));
          pass=true;
        }

        if(pass){
          Alert(_Symbol," [",TF(Timeframe),"] ",cross," crossover VALID → ",bull?"BUY":"SELL",
                " | +DI=",DoubleToString(pDI,1),"  -DI=",DoubleToString(mDI,1));
          OpenDirIfValid(bull?+1:-1);
        }else{
          Alert(_Symbol," [",TF(Timeframe),"] ",cross," crossover NO-TRADE (DI filter) ",
                "| +DI=",DoubleToString(pDI,1),"  -DI=",DoubleToString(mDI,1));
        }
        Fire(barTime,g_lastCK,_Symbol+" "+cross+" Chikou-Kijun Crossover on "+TF(Timeframe));
      }
    }
  }

  // --- Tenkan/Kijun close alerts only ---
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

  // --- Price vs Kumo alerts only ---
  if(AlertPriceCloudCross){
    const int s_now=1, s_prev=2;
    double ssa_n,ssb_n,ssa_p,ssb_p;
    if(GetBuf(g_ichimokuHandle,2,s_now,ssa_n)&&GetBuf(g_ichimokuHandle,3,s_now,ssb_n)&&
       GetBuf(g_ichimokuHandle,2,s_prev,ssa_p)&&GetBuf(g_ichimokuHandle,3,s_prev,ssb_p))
    {
      double c_p=iClose(_Symbol,Timeframe,2), c_n=iClose(_Symbol,Timeframe,1);
      double top_p=MathMax(ssa_p,ssb_p), bot_p=MathMin(ssa_p,ssb_p);
      double top_n=MathMax(ssa_n,ssb_n), bot_n=MathMin(ssa_n,ssb_n);
      bool was_above=c_p>top_p+eps, was_below=c_p<bot_p-eps, was_in=!(was_above||was_below);
      bool is_above=c_n>top_n+eps,  is_below=c_n<bot_n-eps,  is_in=!(is_above||is_below);
      bool px_in=(was_above||was_below)&&is_in, px_above=was_in&&is_above, px_below=was_in&&is_below;
      bool px_jump_up=was_below&&is_above, px_jump_dn=was_above&&is_below;
      if(px_in) Fire(barTime,g_lastPX,_Symbol+" Price closed INSIDE Kumo on "+TF(Timeframe));
      if(px_above) Fire(barTime,g_lastPX,_Symbol+" Price closed ABOVE Kumo on "+TF(Timeframe));
      if(px_below) Fire(barTime,g_lastPX,_Symbol+" Price closed BELOW Kumo on "+TF(Timeframe));
      if(px_jump_up) Fire(barTime,g_lastPX,_Symbol+" Price jumped ABOVE Kumo on "+TF(Timeframe));
      if(px_jump_dn) Fire(barTime,g_lastPX,_Symbol+" Price dropped BELOW Kumo on "+TF(Timeframe));
    }
  }

  // --- Chikou vs Kumo alerts only ---
  if(AlertChikouCloudCross){
    const int sc_now=1, sc_prev=2;
    double chi_n,chi_p, ssa_n,ssb_n, ssa_p,ssb_p;
    if(GetBuf(g_ichimokuHandle,4,sc_now,chi_n)&&GetBuf(g_ichimokuHandle,4,sc_prev,chi_p) &&
       GetBuf(g_ichimokuHandle,2,sc_now+2*Kijun,ssa_n)&&GetBuf(g_ichimokuHandle,3,sc_now+2*Kijun,ssb_n) &&
       GetBuf(g_ichimokuHandle,2,sc_prev+2*Kijun,ssa_p)&&GetBuf(g_ichimokuHandle,3,sc_prev+2*Kijun,ssb_p))
    {
      double top_p=MathMax(ssa_p,ssb_p), bot_p=MathMin(ssa_p,ssb_p);
      double top_n=MathMax(ssa_n,ssb_n), bot_n=MathMin(ssa_n,ssb_n);
      bool was_above=chi_p>top_p+eps, was_below=chi_p<bot_p-eps, was_in=!(was_above||was_below);
      bool is_above =chi_n>top_n+eps,  is_below =chi_n<bot_n-eps;
      bool is_in=!(is_above||is_below);
      if(is_in && (was_above||was_below)) Fire(barTime,g_lastCX,_Symbol+" Chikou closed INSIDE Kumo on "+TF(Timeframe));
      if(was_in && is_above) Fire(barTime,g_lastCX,_Symbol+" Chikou closed ABOVE Kumo on "+TF(Timeframe));
      if(was_in && is_below) Fire(barTime,g_lastCX,_Symbol+" Chikou closed BELOW Kumo on "+TF(Timeframe));
    }
  }

  // --- DI crossover exits (manage open trade) ---
  int dir=OpenDir();
  if(dir>0 && DIXBear()){ if(CloseIfAny()) Alert(_Symbol," [",TF(Timeframe),"] BUY exited on -DI crossing above +DI"); }
  if(dir<0 && DIXBull()){ if(CloseIfAny()) Alert(_Symbol," [",TF(Timeframe),"] SELL exited on +DI crossing above -DI"); }
}
