//+------------------------------------------------------------------+
//| Ichimoku EA – CK-sequenced entries + DI exits (uniform alerts)   |
// Logic summary//
// Runs on selected timeframe. On new CK cross: if opposite to current position, close; then start that side’s sequence.
// Filter: require CP (Chikou beyond High/Low 26 bars back).
// Entry: when DI agrees on the last closed bar or a DI cross occurs (bear: -DI>+DI; bull: +DI>-DI).
// Exit: on opposite DI cross; also close long if -DI>+DI, short if +DI>-DI.
// Any opposite CK during trade closes and restarts.
// Alerts deduped with P/L; advisory PK/PT/Kumo alerts; only manages its MagicNumber.
//+------------------------------------------------------------------+
#property version   "1.71"
#property strict
#include <Trade/Trade.mqh>

//==================== Inputs ====================//
input ENUM_TIMEFRAMES Timeframe = PERIOD_CURRENT;
input ulong  MagicNumber=20250717;
input bool   EnableAlerts=true, InvertSignals=false;
input int    Tenkan=9, Kijun=26, Senkou=52;
input bool   AlertTenkanClose=true, AlertKijunClose=true, AlertPriceCloudCross=true, AlertChikouCloudCross=true;
input bool   ShowCountdown=true; input color CountdownColor=clrLime; input int CountdownFontPx=20, CountdownPadY=10;
input double Lots=0.10; input int DeviationPts=20;
input double EpsPoints=0.5;
input int    AlertCooldownSec=5;

//==================== Globals ===================//
CTrade trade;
int g_iCh=INVALID_HANDLE, g_iADX=INVALID_HANDLE;
datetime g_lastCK=0,g_lastPX=0,g_lastCX=0,g_lastTK=0,g_lastKJ=0,g_lastTwoMinTarget=0;
string g_lastMsg=""; datetime g_lastAlert=0;

// State
enum SeqState{IDLE, WAIT_CHI_BEAR, WAIT_DI_BEAR, SHORT_OPEN, WAIT_CHI_BULL, WAIT_DI_BULL, LONG_OPEN};
SeqState g_st=IDLE;

//==================== Utils =====================//
string TF(ENUM_TIMEFRAMES tf){ if(tf==PERIOD_CURRENT) tf=(ENUM_TIMEFRAMES)Period();
 switch(tf){case PERIOD_M1:return"M1";case PERIOD_M5:return"M5";case PERIOD_M15:return"M15";
 case PERIOD_M30:return"M30";case PERIOD_H1:return"H1";case PERIOD_H4:return"H4";
 case PERIOD_D1:return"D1";case PERIOD_W1:return"W1";case PERIOD_MN1:return"MN1";default:return"TF";}}
bool GetBuf(const int h,const int buf,const int sh,double &v){ double t[1]; if(CopyBuffer(h,buf,sh,1,t)!=1) return false; v=t[0]; return true; }
bool NewBar(){ static datetime lt=0; datetime t=iTime(_Symbol,Timeframe,0); if(t!=lt){lt=t; return true;} return false; }
bool EnoughBars(){ return Bars(_Symbol,Timeframe) >= (Kijun+Senkou+10); }
void AlertOnce(const string msg){ if(!EnableAlerts) return; datetime now=TimeCurrent(); if(msg!=g_lastMsg || (now-g_lastAlert)>AlertCooldownSec){ g_lastMsg=msg; g_lastAlert=now; Alert(msg);} }
void Fire(const datetime bt, datetime &gate, const string msg){ if(!EnableAlerts) return; if(bt!=gate){ gate=bt; AlertOnce(msg);} }
void ResetSeq(){ g_st=IDLE; }

//==================== ADX / DI ==================//
const int BUF_ADX=0, BUF_PDI=1, BUF_MDI=2;
bool GetDI(const int sh,double &p,double &m){
  if(g_iADX==INVALID_HANDLE) return false;
  double a[1],b[1];
  if(CopyBuffer(g_iADX,BUF_PDI,sh,1,a)!=1) return false;
  if(CopyBuffer(g_iADX,BUF_MDI,sh,1,b)!=1) return false;
  p=a[0]; m=b[0]; return (p!=EMPTY_VALUE && m!=EMPTY_VALUE);
}
bool DIIsBull(){ double p,m; return GetDI(1,p,m)&&p>m; }
bool DIIsBear(){ double p,m; return GetDI(1,p,m)&&m>p; }
bool DIXBull(){ double p1,m1,p2,m2; if(!GetDI(1,p1,m1)||!GetDI(2,p2,m2)) return false; return (p2-m2)<=0 && (p1-m1)>0; }
bool DIXBear(){ double p1,m1,p2,m2; if(!GetDI(1,p1,m1)||!GetDI(2,p2,m2)) return false; return (p2-m2)>=0 && (p1-m1)<0; }

//==================== Trading helpers ===========//
bool HasOurPosition(){ if(!PositionSelect(_Symbol)) return false; return (ulong)PositionGetInteger(POSITION_MAGIC)==MagicNumber; }
int  OpenDir(){ if(!HasOurPosition()) return 0; return PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?+1:-1; }
bool CloseIfAny(){
  if(!HasOurPosition()) return true;
  string side=OpenDir()>0?"BUY":"SELL";
  if(!trade.PositionClose(_Symbol)){ AlertOnce(StringFormat("%s [%s] %s close FAILED (%s)",_Symbol,TF(Timeframe),side,trade.ResultRetcodeDescription())); return false; }
  double pl=0; ulong d=trade.ResultDeal(); if(d>0 && HistoryDealSelect(d)) pl=HistoryDealGetDouble(d,DEAL_PROFIT);
  AlertOnce(StringFormat("%s [%s] %s CLOSE @ %.*f | P/L = %.2f %s | %s",
    _Symbol,TF(Timeframe),side,_Digits,trade.ResultPrice(),pl,AccountInfoString(ACCOUNT_CURRENCY),trade.ResultRetcodeDescription()));
  return true;
}
bool OpenDirIfValid(const int dir){
  trade.SetExpertMagicNumber(MagicNumber); trade.SetDeviationInPoints(DeviationPts);
  bool ok=(dir>0)?trade.Buy(Lots,_Symbol):trade.Sell(Lots,_Symbol);
  string side=(dir>0)?"BUY":"SELL";
  if(ok) AlertOnce(StringFormat("%s [%s] %s OPEN @ %.*f | %s",_Symbol,TF(Timeframe),side,_Digits,trade.ResultPrice(),trade.ResultRetcodeDescription()));
  else   AlertOnce(StringFormat("%s [%s] %s open FAILED (%s)",_Symbol,TF(Timeframe),side,trade.ResultRetcodeDescription()));
  return ok;
}

//==================== UI: Countdown =============//
#define COUNT_NAME "EA_NextHourCountdown"
void MakeCountdown(){ ObjectDelete(0,COUNT_NAME);
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
  if(rem<=120 && g_lastTwoMinTarget!=next){ g_lastTwoMinTarget=next; AlertOnce(StringFormat("%s 2 minutes to new hour (%s)",_Symbol,TF(Timeframe))); }
}

//==================== Lifecycle =================//
int OnInit(){
  g_iCh = iIchimoku(_Symbol,Timeframe,Tenkan,Kijun,Senkou);
  if(g_iCh==INVALID_HANDLE){ AlertOnce("Ichimoku handle failed"); return INIT_FAILED; }
  g_iADX = iADX(_Symbol,Timeframe,14);
  if(g_iADX==INVALID_HANDLE){ AlertOnce("ADX handle failed"); return INIT_FAILED; }
  trade.SetExpertMagicNumber(MagicNumber); trade.SetDeviationInPoints(DeviationPts);
  if(ShowCountdown){ EventSetTimer(1); MakeCountdown(); UpdateCountdown(); }
  return INIT_SUCCEEDED;
}
void OnDeinit(const int reason){
  if(g_iCh!=INVALID_HANDLE) IndicatorRelease(g_iCh);
  if(g_iADX!=INVALID_HANDLE) IndicatorRelease(g_iADX);
  if(ShowCountdown){ EventKillTimer(); ObjectDelete(0,COUNT_NAME); }
}
void OnTimer(){ if(ShowCountdown) UpdateCountdown(); }

//==================== Main logic =================//
void OnTick(){
  if(!NewBar() || !EnoughBars()) return;

  const datetime barTime=iTime(_Symbol,Timeframe,1);
  const double eps=_Point*EpsPoints;

  //--- CK cross detection (Chikou buf=4, Kijun buf=1)
  double ck_p,ck_n,kj_p,kj_n;
  bool ok = GetBuf(g_iCh,4,Kijun+2,ck_p) && GetBuf(g_iCh,4,Kijun+1,ck_n) &&
            GetBuf(g_iCh,1,Kijun+2,kj_p) && GetBuf(g_iCh,1,Kijun+1,kj_n);
  bool bull=false, bear=false;
  if(ok){
    double d_p=ck_p-kj_p, d_n=ck_n-kj_n;
    bull=(d_p<=+eps)&&(d_n>+eps);
    bear=(d_p>=-eps)&&(d_n<-eps);
    if(InvertSignals){ bool t=bull; bull=bear; bear=t; }
  }

  // Immediate DI relation exits on closed bar
  int dir=OpenDir(); double p,m;
  if(GetDI(1,p,m)){
    if(dir>0 && m>p){ if(CloseIfAny()){ AlertOnce(StringFormat("%s [%s] BUY exit: Bearish DI (-DI>+DI)",_Symbol,TF(Timeframe))); ResetSeq(); } }
    if(dir<0 && p>m){ if(CloseIfAny()){ AlertOnce(StringFormat("%s [%s] SELL exit: Bullish DI (+DI>-DI)",_Symbol,TF(Timeframe))); ResetSeq(); } }
  }

// Fresh CK cross → only close on opposite CK
if(bull||bear){
  int dir=OpenDir();
  bool oppCK = (dir>0 && bear) || (dir<0 && bull);
  bool sameCK= (dir>0 && bull) || (dir<0 && bear);

  if(oppCK){
    AlertOnce(StringFormat("%s [%s] Forced close: Opposite CK",_Symbol,TF(Timeframe)));
    CloseIfAny();
  }

  if(dir==0 || oppCK){
    g_st = bear ? WAIT_CHI_BEAR : WAIT_CHI_BULL;
    AlertOnce(StringFormat("%s [%s] Sequence start: %s CK",_Symbol,TF(Timeframe),(bear?"Bearish":"Bullish")));
    Fire(barTime,g_lastCK,StringFormat("%s %s CK cross on %s",_Symbol,(bear?"Bearish":"Bullish"),TF(Timeframe)));
  } else if(sameCK){
    AlertOnce(StringFormat("%s [%s] CK same-direction; holding",_Symbol,TF(Timeframe)));
  }
}



  // Step 2: CP requirement (Chikou beyond price 26-back)
  double refH=iHigh(_Symbol,Timeframe,Kijun+1);
  double refL=iLow (_Symbol,Timeframe,Kijun+1);
  if(ok){
    if(g_st==WAIT_CHI_BEAR && ck_n < refL - eps){
      g_st=WAIT_DI_BEAR; AlertOnce(StringFormat("%s [%s] Bearish CP cross confirmed: Chikou < Low(26)",_Symbol,TF(Timeframe)));
    }
    if(g_st==WAIT_CHI_BULL && ck_n > refH + eps){
      g_st=WAIT_DI_BULL; AlertOnce(StringFormat("%s [%s] Bullish CP cross confirmed: Chikou > High(26)",_Symbol,TF(Timeframe)));
    }
  }

  // Step 3: DI gate to enter
  if(g_st==WAIT_DI_BEAR && (DIIsBear() || DIXBear())){
    if(OpenDirIfValid(-1)) g_st=SHORT_OPEN;
  }
  if(g_st==WAIT_DI_BULL && (DIIsBull() || DIXBull())){
    if(OpenDirIfValid(+1)) g_st=LONG_OPEN;
  }

  // Step 4: hold until opposite DI cross (CK cross handled above)
  if(g_st==SHORT_OPEN){ if(DIXBull()){ if(CloseIfAny()) ResetSeq(); } }
  if(g_st==LONG_OPEN ){ if(DIXBear()){ if(CloseIfAny()) ResetSeq(); } }

  // Advisory alerts with uniform terms where applicable
  const double peps=eps;
  if(AlertTenkanClose){
    double tk_p,tk_n; if(GetBuf(g_iCh,0,2,tk_p)&&GetBuf(g_iCh,0,1,tk_n)){
      double c_p=iClose(_Symbol,Timeframe,2), c_n=iClose(_Symbol,Timeframe,1);
      bool up=(c_p<=tk_p+peps)&&(c_n>tk_n+peps), dn=(c_p>=tk_p-peps)&&(c_n<tk_n-peps);
      if(up) Fire(barTime,g_lastTK,StringFormat("%s Bullish PT cross on %s",_Symbol,TF(Timeframe)));
      if(dn) Fire(barTime,g_lastTK,StringFormat("%s Bearish PT cross on %s",_Symbol,TF(Timeframe)));
    }
  }
  if(AlertKijunClose){
    double kjp,kjn; if(GetBuf(g_iCh,1,2,kjp)&&GetBuf(g_iCh,1,1,kjn)){
      double c_p=iClose(_Symbol,Timeframe,2), c_n=iClose(_Symbol,Timeframe,1);
      bool up=(c_p<=kjp+peps)&&(c_n>kjn+peps), dn=(c_p>=kjp-peps)&&(c_n<kjn-peps);
      if(up) Fire(barTime,g_lastKJ,StringFormat("%s Bullish PK cross on %s",_Symbol,TF(Timeframe)));
      if(dn) Fire(barTime,g_lastKJ,StringFormat("%s Bearish PK cross on %s",_Symbol,TF(Timeframe)));
    }
  }
  if(AlertPriceCloudCross){
    const int s_now=1, s_prev=2;
    double ssa_n,ssb_n,ssa_p,ssb_p;
    if(GetBuf(g_iCh,2,s_now,ssa_n)&&GetBuf(g_iCh,3,s_now,ssb_n)&&GetBuf(g_iCh,2,s_prev,ssa_p)&&GetBuf(g_iCh,3,s_prev,ssb_p)){
      double c_p=iClose(_Symbol,Timeframe,2), c_n=iClose(_Symbol,Timeframe,1);
      double top_p=MathMax(ssa_p,ssb_p), bot_p=MathMin(ssa_p,ssb_p);
      double top_n=MathMax(ssa_n,ssb_n), bot_n=MathMin(ssa_n,ssb_n);
      bool was_above=c_p>top_p+peps, was_below=c_p<bot_p-peps, was_in=!(was_above||was_below);
      bool is_above=c_n>top_n+peps,  is_below=c_n<bot_n-peps,  is_in=!(is_above||is_below);
      bool px_in=(was_above||was_below)&&is_in, px_above=was_in&&is_above, px_below=was_in&&is_below;
      bool px_jump_up=was_below&&is_above, px_jump_dn=was_above&&is_below;
      if(px_in)      Fire(barTime,g_lastPX,StringFormat("%s Price closed INSIDE Kumo on %s",_Symbol,TF(Timeframe)));
      if(px_above)   Fire(barTime,g_lastPX,StringFormat("%s Price closed ABOVE Kumo on %s",_Symbol,TF(Timeframe)));
      if(px_below)   Fire(barTime,g_lastPX,StringFormat("%s Price closed BELOW Kumo on %s",_Symbol,TF(Timeframe)));
      if(px_jump_up) Fire(barTime,g_lastPX,StringFormat("%s Price jumped ABOVE Kumo on %s",_Symbol,TF(Timeframe)));
      if(px_jump_dn) Fire(barTime,g_lastPX,StringFormat("%s Price dropped BELOW Kumo on %s",_Symbol,TF(Timeframe)));
    }
  }
  if(AlertChikouCloudCross){
    const int sc_now=1, sc_prev=2;
    double chi_n,chi_p, ssa_n,ssb_n, ssa_p,ssb_p;
    if(GetBuf(g_iCh,4,sc_now,chi_n)&&GetBuf(g_iCh,4,sc_prev,chi_p) &&
       GetBuf(g_iCh,2,sc_now+2*Kijun,ssa_n)&&GetBuf(g_iCh,3,sc_now+2*Kijun,ssb_n) &&
       GetBuf(g_iCh,2,sc_prev+2*Kijun,ssa_p)&&GetBuf(g_iCh,3,sc_prev+2*Kijun,ssb_p))
    {
      double top_p=MathMax(ssa_p,ssb_p), bot_p=MathMin(ssa_p,ssb_p);
      double top_n=MathMax(ssa_n,ssb_n), bot_n=MathMin(ssa_n,ssb_n);
      bool was_above=chi_p>top_p+peps, was_below=chi_p<bot_p-peps, was_in=!(was_above||was_below);
      bool is_above =chi_n>top_n+peps,  is_below =chi_n<bot_n-peps,  is_in=!(is_above||is_below);
      if(is_in && (was_above||was_below)) Fire(barTime,g_lastCX,StringFormat("%s Chikou closed INSIDE Kumo on %s",_Symbol,TF(Timeframe)));
      if(was_in && is_above)              Fire(barTime,g_lastCX,StringFormat("%s Chikou closed ABOVE Kumo on %s",_Symbol,TF(Timeframe)));
      if(was_in && is_below)              Fire(barTime,g_lastCX,StringFormat("%s Chikou closed BELOW Kumo on %s",_Symbol,TF(Timeframe)));
    }
  }
}
