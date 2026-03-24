//+------------------------------------------------------------------+
//| OrderBlockZone2.mq5                                              |
//| MT5 port of Order Block Indicator (zones 2.0) — Clean Marker,    |
//| Multi Clean Marker, mitigation, HTF zone-touch alerts.         |
//| General Marker + Break Marker pipelines match Pine in            |
//| Order Block Indicator(zone2.0)_14.txt — extend OnCalculate       |
//| from that file for full parity.                                 |
//+------------------------------------------------------------------+
#property copyright "OB zones port"
#property version   "1.42"
#property indicator_chart_window
#property indicator_plots 0

input bool   InpUseCleanMarker      = true;
input bool   InpUseMultiCleanMarker = true;
input bool   InpEnableDistance      = true;
input double InpMaxDistancePips     = 100.0;
input int    InpMarkerLookback      = 80;
input bool   InpUseWickRule         = true;
input int    InpMaxTrackedOBs       = 80;
input bool   InpDeleteMitigated     = false;
input bool   InpFadeMitigated       = true;
input color  InpBullFill            = C'30,30,200';
input color  InpBearFill            = C'200,30,30';
input color  InpBullBorder         = clrBlue;
input color  InpBearBorder         = clrRed;
input color  InpMitBorder          = clrGreen;
input bool   InpAlertZoneTouchHTF  = false;
input ENUM_TIMEFRAMES InpZoneTouchTF = PERIOD_M15;

#define MAX_OB 400

struct ObZone
  {
   datetime tLeft;
   datetime tRight;
   double   top;
   double   bot;
   int      dir;
   string   objName;
   bool     mitigated;
  };

ObZone g_ob[];
int    g_obCount = 0;
double g_pipSize = 0.0;
double g_maxDistance = 0.0;

enum CleanState { C_IDLE=0, C_SCAN=1, C_WAIT=2 };

CleanState g_cmState[2], g_mcmState[2];
double g_cmExtreme[2],g_cmZoneLow[2],g_cmZoneHigh[2],g_cmBreakRef[2],g_cmImpulse[2];
double g_mcmExtreme[2],g_mcmZoneLow[2],g_mcmZoneHigh[2],g_mcmBreakRef[2],g_mcmImpulse[2];
int    g_cmIdxLeft[2], g_mcmIdxLeft[2];
long   g_cmPineLeft[2], g_mcmPineLeft[2];
bool   g_cmExtremeTaken[2], g_mcmExtremeTaken[2];

double g_lastBearHigh=0,g_lastBearLow=0,g_lastBearOpen=0;
long   g_lastBearBar=-1;
double g_lastBullHigh=0,g_lastBullLow=0,g_lastBullOpen=0;
long   g_lastBullBar=-1;

//+------------------------------------------------------------------+
int OnInit()
  {
   ArrayResize(g_ob, MAX_OB);
   g_obCount = 0;
   g_pipSize = ComputePipSize();
   g_maxDistance = InpMaxDistancePips * g_pipSize;
   for(int d=0;d<2;d++)
     {
      g_cmState[d]=g_mcmState[d]=C_IDLE;
      g_cmIdxLeft[d]=g_mcmIdxLeft[d]=-1;
      g_cmPineLeft[d]=g_mcmPineLeft[d]=-1;
      g_cmExtremeTaken[d]=g_mcmExtremeTaken[d]=false;
     }
   g_lastBearBar=g_lastBullBar=-1;
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   for(int i=0;i<g_obCount;i++)
      ObjectDelete(0, g_ob[i].objName);
  }

//+------------------------------------------------------------------+
double ComputePipSize()
  {
   string s = _Symbol;
   double tick = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(StringFind(s,"JPY")>=0) return tick*10;
   int dg = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   if(dg==5 || dg==3) return tick*10;
   if(StringFind(s,"XAU")>=0 || StringFind(s,"GOLD")>=0) return 0.1;
   return tick;
  }

bool IsBull(const double c,const double o) { return c>=o; }
bool IsBear(const double c,const double o) { return c<o; }
bool IsStrictBull(const double c,const double o) { return c>o; }
bool IsStrictBear(const double c,const double o) { return c<o; }

bool DistanceOk(const int dir,const double zoneRef,const double impulseExt)
  {
   if(!InpEnableDistance) return true;
   return MathAbs(zoneRef - impulseExt) <= g_maxDistance;
  }

void ApplyWickRule(const int dir,const double refH,const double refL,const double refO,
                   const double nextH,const double nextL,const bool useWick,
                   double &zTop,double &zBot)
  {
   zTop=refH;
   zBot=refL;
   if(!useWick) return;
   if(dir==1 && refH>nextH) zTop=refO;
   if(dir==-1 && refL<nextL) zBot=refO;
  }

bool BoxLeftTimeExists(const datetime tLeft)
  {
   for(int i=0;i<g_obCount;i++)
      if(g_ob[i].tLeft==tLeft) return true;
   return false;
  }

bool AllImpulseBarsSince(const int dir,const int idxOpp,const int idxCur,
                         const double &open[],const double &close[],const int total)
  {
   if(idxOpp<0 || idxCur<0 || idxOpp>=total || idxCur>=total) return false;
   for(int j=idxOpp-1; j>=idxCur; j--)
     {
      if(j<0 || j>=total) return false;
      if(dir==1 && !IsBull(close[j],open[j])) return false;
      if(dir==-1 && close[j]>open[j]) return false;
     }
   return true;
  }

int FindMultiStraightOffset(const int dir,const int idxOpp,const int idxCur,const int total,
                            const double &high[],const double &low[],
                            const double &open[],const double &close[])
  {
   if(idxOpp<0 || !AllImpulseBarsSince(dir,idxOpp,idxCur,open,close,total)) return -1;
   int maxMo = (int)MathMin(InpMarkerLookback, idxOpp - idxCur - 1);
   maxMo = (int)MathMin(maxMo, total - 1 - idxCur);
   if(maxMo<1) return -1;
   for(int j=0;j<maxMo;j++)
     {
      int mo = maxMo - j;
      if(idxCur + mo >= total) continue;
      if(idxOpp <= idxCur + mo) continue;
      int im = idxCur + mo;
      int im1 = im + 1;
      int im_1 = im - 1;
      if(im1>=total || im_1<0) continue;
      bool pat=false;
      if(dir==1)
         pat = high[im]>high[im1] && high[im]>high[im_1]
               && IsStrictBull(close[im],open[im]) && IsStrictBull(close[im1],open[im1]) && IsStrictBull(close[im_1],open[im_1]);
      else
         pat = low[im]<low[im1] && low[im]<low[im_1]
               && IsStrictBear(close[im],open[im]) && IsStrictBear(close[im1],open[im1]) && IsStrictBear(close[im_1],open[im_1]);
      if(pat) return mo;
     }
   return -1;
  }

int FindLastOppositeIdx(const int dir,const int idxCur,const double &open[],const double &close[],const int total)
  {
   for(int k=1;k<=InpMarkerLookback;k++)
     {
      int ix = idxCur + k;
      if(ix>=total) break;
      if(dir==1 && IsBear(close[ix],open[ix])) return ix;
      if(dir==-1 && IsBull(close[ix],open[ix])) return ix;
     }
   return -1;
  }

bool SameDirTouch(const int dir,const double top,const double bot,const long pineLeft,const long pineCur,
                  const bool isCleanWait,const double hi,const double lo,const double op,const double cl,
                  const int idx,const double &high[],const double &low[],const double &open[],const double &close[],const int total)
  {
   bool bullC = IsBull(cl,op);
   bool bearC = IsBear(cl,op);
   bool sameDir = (dir==1 && bearC) || (dir==-1 && bullC);
   bool contained = hi<=top && lo>=bot;
   bool bullTouch = dir==1 && ((lo<=top && hi>top) || (lo<bot && hi<=top));
   bool bearTouch = dir==-1 && ((hi>=bot && lo<bot) || (hi>=top && lo>=bot));
   bool ov = hi>top && lo<bot;
   bool bullJump = dir==1 && lo<bot && hi<bot;
   bool bearJump = dir==-1 && lo>top && hi>top;
   if(sameDir)
      return contained || bullTouch || bearTouch || ov || bullJump || bearJump;
   if(pineLeft>=0 && pineLeft < pineCur - 2)
     {
      if(isCleanWait)
         return contained || bullTouch || bearTouch || ov || bullJump || bearJump;
      int oppCount=0;
      for(long pb=pineLeft+2; pb<=pineCur-1; pb++)
        {
         int off = (int)(pineCur - pb);
         int ix = idx + off;
         if(ix>=total || ix<0) continue;
         if(dir==1 ? IsBear(close[ix],open[ix]) : IsBull(close[ix],open[ix]))
            oppCount++;
        }
      if(oppCount>1)
         return contained || bullTouch || bearTouch || ov || bullJump || bearJump;
     }
   return false;
  }

void PushOb(const datetime tLeft,const datetime tRight,const double top,const double bot,const int dir)
  {
   if(g_obCount>=InpMaxTrackedOBs)
     {
      ObjectDelete(0, g_ob[0].objName);
      for(int j=1;j<g_obCount;j++) g_ob[j-1]=g_ob[j];
      g_obCount--;
     }
   string nm = StringFormat("OBZ_%I64d", (long)tLeft);
   int dup=0;
   while(ObjectFind(0,nm)>=0)
      nm = StringFormat("OBZ_%I64d_%d", (long)tLeft, dup++);
   if(!ObjectCreate(0, nm, OBJ_RECTANGLE, 0, tLeft, top, tRight, bot))
      return;
   ObjectSetInteger(0, nm, OBJPROP_COLOR, dir==1 ? InpBullBorder : InpBearBorder);
   ObjectSetInteger(0, nm, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, nm, OBJPROP_BACK, true);
   ObjectSetInteger(0, nm, OBJPROP_FILL, true);
   ObjectSetInteger(0, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, nm, OBJPROP_BGCOLOR, dir==1 ? InpBullFill : InpBearFill);

   g_ob[g_obCount].tLeft=tLeft;
   g_ob[g_obCount].tRight=tRight;
   g_ob[g_obCount].top=top;
   g_ob[g_obCount].bot=bot;
   g_ob[g_obCount].dir=dir;
   g_ob[g_obCount].objName=nm;
   g_ob[g_obCount].mitigated=false;
   g_obCount++;
  }

void RefreshObRightEdges(const datetime tRight)
  {
   for(int i=0;i<g_obCount;i++)
     {
      if(InpDeleteMitigated && g_ob[i].mitigated) continue;
      g_ob[i].tRight = tRight;
      ObjectMove(0, g_ob[i].objName, 1, tRight, g_ob[i].top);
      ObjectMove(0, g_ob[i].objName, 1, tRight, g_ob[i].bot);
     }
  }

void MitigateZones(const double H,const double L)
  {
   for(int z=g_obCount-1; z>=0; z--)
     {
      double top=g_ob[z].top, bot=g_ob[z].bot;
      bool touch = MathMax(H,L)>=bot && MathMin(H,L)<=top;
      if(!touch) continue;
      if(InpDeleteMitigated)
        {
         ObjectDelete(0,g_ob[z].objName);
         for(int j=z;j<g_obCount-1;j++) g_ob[j]=g_ob[j+1];
         g_obCount--;
        }
      else if(InpFadeMitigated)
        {
         g_ob[z].mitigated=true;
         ObjectSetInteger(0,g_ob[z].objName,OBJPROP_COLOR,InpMitBorder);
        }
     }
  }

bool HtfBarCompletedOverlap()
  {
   static datetime s_lastTfBar = 0;
   if(!InpAlertZoneTouchHTF || g_obCount<=0) return false;
   datetime htBar = iTime(_Symbol, InpZoneTouchTF, 0);
   if(htBar==0) return false;
   if(htBar==s_lastTfBar) return false;
   s_lastTfBar = htBar;
   double htfH = iHigh(_Symbol, InpZoneTouchTF, 1);
   double htfL = iLow(_Symbol, InpZoneTouchTF, 1);
   if(htfH<=0 || htfL<=0) return false;
   for(int z=0;z<g_obCount;z++)
     {
      if(MathMax(htfH,htfL)>=g_ob[z].bot && MathMin(htfH,htfL)<=g_ob[z].top)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total<10) return 0;
   ArraySetAsSeries(time,true);
   ArraySetAsSeries(open,true);
   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);
   ArraySetAsSeries(close,true);

   for(int i=0;i<g_obCount;i++) ObjectDelete(0,g_ob[i].objName);
   g_obCount=0;
   for(int d=0;d<2;d++)
     {
      g_cmState[d]=g_mcmState[d]=C_IDLE;
      g_cmIdxLeft[d]=g_mcmIdxLeft[d]=-1;
      g_cmPineLeft[d]=g_mcmPineLeft[d]=-1;
      g_cmExtremeTaken[d]=g_mcmExtremeTaken[d]=false;
     }
   g_lastBearBar=g_lastBullBar=-1;
   g_lastBearHigh=g_lastBearLow=g_lastBearOpen=0;
   g_lastBullHigh=g_lastBullLow=g_lastBullOpen=0;

   for(int idx = rates_total - 1; idx >= 0; idx--)
     {
      long pineBar = (long)(rates_total - 1 - idx);

      double O=open[idx], H=high[idx], L=low[idx], C=close[idx];
      datetime T=time[idx];

      bool isBull = IsBull(C,O);
      bool isBear = IsBear(C,O);
      bool isNeutral = (C==O);

      if(isBear)
        { g_lastBearHigh=H; g_lastBearLow=L; g_lastBearOpen=O; g_lastBearBar=pineBar; }
      if(isBull || isNeutral)
        { g_lastBullHigh=H; g_lastBullLow=L; g_lastBullOpen=O; g_lastBullBar=pineBar; }

      double adjBH=g_lastBearHigh, adjBL=g_lastBearLow;
      double adjBullL=g_lastBullLow;
      ApplyWickRule(1,g_lastBearHigh,g_lastBearLow,g_lastBearOpen,H,L,InpUseWickRule,adjBH,adjBL);
      double dummyTop;
      ApplyWickRule(-1,g_lastBullHigh,g_lastBullLow,g_lastBullOpen,H,L,InpUseWickRule,dummyTop,adjBullL);

      bool bullBreak = (g_lastBearBar>=0) && C>adjBH;
      bool bearBreak = (g_lastBullBar>=0) && C<adjBullL;

      for(int d=0;d<2;d++)
        {
         int dir = d==0 ? 1 : -1;
         bool startCtx = (dir==1 && bullBreak) || (dir==-1 && bearBreak);
         if(startCtx && g_cmState[d]==C_IDLE) g_cmState[d]=C_SCAN;

         int ioppD = FindLastOppositeIdx(dir, idx, open, close, rates_total);

         if(g_cmState[d]==C_SCAN)
           {
            bool opp = (dir==1)?isBear:isBull;
            if(opp) g_cmState[d]=C_IDLE;
            else if(pineBar>=2 && idx+2<rates_total)
              {
               int i2=idx+2,i1=idx+1,i0=idx;
               bool cleanStraight = (dir==1)
                  ? (IsStrictBull(close[i2],open[i2])&&IsStrictBull(close[i1],open[i1])&&IsStrictBull(close[i0],open[i0])
                     && high[i1]>high[i2] && high[i1]>high[i0])
                  : (IsStrictBear(close[i2],open[i2])&&IsStrictBear(close[i1],open[i1])&&IsStrictBear(close[i0],open[i0])
                     && low[i1]<low[i2] && low[i1]<low[i0]);
               bool cleanSegOk = AllImpulseBarsSince(dir,ioppD,idx,open,close,rates_total);
               if(cleanStraight && ioppD>=0 && cleanSegOk)
                 {
                  int iop = ioppD;
                  if(iop<rates_total && iop-1>=0)
                    {
                     double rH=high[iop], rL=low[iop], rO=open[iop];
                     double nH=high[iop-1], nL=low[iop-1];
                     double zt,zb;
                     ApplyWickRule(dir,rH,rL,rO,nH,nL,InpUseWickRule,zt,zb);
                     if(dir==1){ g_cmExtreme[d]=zt; g_cmZoneLow[d]=zb; g_cmBreakRef[d]=high[i1]; g_cmImpulse[d]=low[i1]; }
                     else { g_cmExtreme[d]=zb; g_cmZoneHigh[d]=zt; g_cmBreakRef[d]=low[i1]; g_cmImpulse[d]=high[i1]; }
                     g_cmIdxLeft[d]=iop;
                     g_cmPineLeft[d]=pineBar - (iop - idx);
                     g_cmExtremeTaken[d]=false;
                     g_cmState[d]=C_WAIT;
                    }
                 }
              }
           }

         if(g_cmState[d]==C_WAIT)
           {
            bool opp = (dir==1)?isBear:isBull;
            if(opp){ g_cmState[d]=C_IDLE; continue; }
            double zoneHigh = dir==1?g_cmExtreme[d]:g_cmZoneHigh[d];
            double zoneLow  = dir==1?g_cmZoneLow[d]:g_cmExtreme[d];
            if(SameDirTouch(dir,zoneHigh,zoneLow,g_cmPineLeft[d],pineBar,true,H,L,O,C,idx,high,low,open,close,rates_total))
              { g_cmState[d]=C_IDLE; continue; }

            if(dir==1) g_cmImpulse[d]=MathMin(g_cmImpulse[d], L);
            else       g_cmImpulse[d]=MathMax(g_cmImpulse[d], H);

            bool extTaken=g_cmExtremeTaken[d];
            if(!extTaken){ if(dir==1&&H>g_cmExtreme[d])extTaken=true; if(dir==-1&&L<g_cmExtreme[d])extTaken=true; }
            g_cmExtremeTaken[d]=extTaken;

            // Clean: straight high/low taken by close (closed bar)
            bool cleanBreak = (dir==1)? (C>g_cmBreakRef[d]) : (C<g_cmBreakRef[d]);
            if(extTaken && cleanBreak)
              {
               double rawTop = dir==1?g_cmExtreme[d]:g_cmZoneHigh[d];
               double rawBot = dir==1?g_cmZoneLow[d]:g_cmExtreme[d];
               double fh,fl;
               ApplyWickRule(dir,rawTop,rawBot,O,H,L,InpUseWickRule,fh,fl);
               datetime tL = time[g_cmIdxLeft[d]];
               if(DistanceOk(dir, dir==1?fh:fl, g_cmImpulse[d]) && InpUseCleanMarker && !BoxLeftTimeExists(tL))
                  PushOb(tL, T, fh, fl, dir);
               g_cmState[d]=C_IDLE;
              }
           }
        }

      for(int d=0;d<2;d++)
        {
         int dir = d==0?1:-1;
         bool startCtx = (dir==1 && bullBreak) || (dir==-1 && bearBreak);
         if(startCtx && g_mcmState[d]==C_IDLE) g_mcmState[d]=C_SCAN;
         int ioppM = FindLastOppositeIdx(dir, idx, open, close, rates_total);
         if(g_mcmState[d]==C_SCAN)
           {
            bool opp = (dir==1)?isBear:isBull;
            if(opp) g_mcmState[d]=C_IDLE;
            else
              {
               int mo = FindMultiStraightOffset(dir, ioppM, idx, rates_total, high, low, open, close);
               if(mo>=0 && ioppM>=0)
                 {
                  int im = idx + mo;
                  int iop = ioppM;
                  if(iop<rates_total && iop-1>=0)
                    {
                     if(dir==1){ g_mcmBreakRef[d]=high[im]; g_mcmImpulse[d]=low[im]; }
                     else { g_mcmBreakRef[d]=low[im]; g_mcmImpulse[d]=high[im]; }
                     double rH=high[iop], rL=low[iop], rO=open[iop];
                     double zt,zb;
                     ApplyWickRule(dir,rH,rL,rO,high[iop-1],low[iop-1],InpUseWickRule,zt,zb);
                     if(dir==1){ g_mcmExtreme[d]=zt; g_mcmZoneLow[d]=zb; }
                     else { g_mcmExtreme[d]=zb; g_mcmZoneHigh[d]=zt; }
                     g_mcmIdxLeft[d]=iop;
                     g_mcmPineLeft[d]=pineBar - (iop - idx);
                     g_mcmExtremeTaken[d]=false;
                     g_mcmState[d]=C_WAIT;
                    }
                 }
              }
           }
         if(g_mcmState[d]==C_WAIT)
           {
            bool opp = (dir==1)?isBear:isBull;
            if(opp){ g_mcmState[d]=C_IDLE; continue; }
            double zoneHigh = dir==1?g_mcmExtreme[d]:g_mcmZoneHigh[d];
            double zoneLow  = dir==1?g_mcmZoneLow[d]:g_mcmExtreme[d];
            if(SameDirTouch(dir,zoneHigh,zoneLow,g_mcmPineLeft[d],pineBar,true,H,L,O,C,idx,high,low,open,close,rates_total))
              { g_mcmState[d]=C_IDLE; continue; }
            if(dir==1) g_mcmImpulse[d]=MathMin(g_mcmImpulse[d], L);
            else       g_mcmImpulse[d]=MathMax(g_mcmImpulse[d], H);
            bool extTaken=g_mcmExtremeTaken[d];
            if(!extTaken){ if(dir==1&&H>g_mcmExtreme[d])extTaken=true; if(dir==-1&&L<g_mcmExtreme[d])extTaken=true; }
            g_mcmExtremeTaken[d]=extTaken;
            // Multi clean: straight level taken by close (closed candle), not wick-only
            bool mcbreak=(dir==1)?(C>g_mcmBreakRef[d]):(C<g_mcmBreakRef[d]);
            if(extTaken && mcbreak)
              {
               double rawTop=dir==1?g_mcmExtreme[d]:g_mcmZoneHigh[d];
               double rawBot=dir==1?g_mcmZoneLow[d]:g_mcmExtreme[d];
               double fh,fl;
               ApplyWickRule(dir,rawTop,rawBot,O,H,L,InpUseWickRule,fh,fl);
               datetime tL = time[g_mcmIdxLeft[d]];
               if(DistanceOk(dir,dir==1?fh:fl,g_mcmImpulse[d]) && InpUseMultiCleanMarker && !BoxLeftTimeExists(tL))
                  PushOb(tL, T, fh, fl, dir);
               g_mcmState[d]=C_IDLE;
              }
           }
        }

      MitigateZones(H,L);
      RefreshObRightEdges(T);

      if(idx==0 && HtfBarCompletedOverlap())
         Alert("OB zone touched on HTF candle (" + EnumToString(InpZoneTouchTF) + ")");

     }

   return rates_total;
  }
//+------------------------------------------------------------------+
