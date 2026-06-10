//+------------------------------------------------------------------+
//|                                                   TrendFlowEA.mq5 |
//|   EA ACTIVO de cruce de EMAs con FLIP automatico + gestion ATR.   |
//|                                                                  |
//|   POR QUE ESTE EA (problema de la v3: 1 trade y se congelo):     |
//|   - Eliminados los frenos globales que podian bloquear el EA      |
//|     permanentemente (la guarda de drawdown de v3 entraba en        |
//|     deadlock). Aqui el unico bloqueo es el limite DIARIO, que se   |
//|     resetea cada dia -> NUNCA se queda congelado.                 |
//|   - Senal simple y frecuente: cruce de EMA rapida/lenta. Sobre     |
//|     varios anos genera cientos de operaciones (turnover asegurado).|
//|   - FLIP: al aparecer senal contraria cierra la posicion y abre la |
//|     opuesta -> la posicion "cicla", no se queda atascada.          |
//|   - Filtros OPCIONALES (tendencia TF superior, RSI, ADX) por si    |
//|     quieres subir calidad; por defecto en modo activo.            |
//|                                                                  |
//|   NOTA: optimiza y valida walk-forward con costes reales.         |
//+------------------------------------------------------------------+
#property copyright "TrendFlowEA"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>

//============================ INPUTS ================================
input group "=== General ==="
input long     InpMagic            = 20260611;     // Numero magico
input string   InpComment          = "TrendFlow";  // Comentario de las ordenes
input int      InpMaxSpreadPoints  = 40;           // Spread maximo (puntos)
input bool     InpOnePerBar        = true;         // Una evaluacion por vela
input ENUM_TIMEFRAMES InpEntryTF    = PERIOD_M30;  // TF operativo

input group "=== Senal: Cruce de EMAs ==="
input int      InpEmaFast          = 12;           // EMA rapida
input int      InpEmaSlow          = 26;           // EMA lenta
input bool     InpUseSignalEma     = true;         // Confirmar con EMA filtro (precio del lado correcto)
input int      InpFilterEma        = 100;          // EMA de filtro (precio por encima=compras)

input group "=== Filtros OPCIONALES (calidad) ==="
input bool     InpUseHTFTrend      = false;        // Filtrar por tendencia de TF superior
input ENUM_TIMEFRAMES InpTrendTF    = PERIOD_H4;   // TF superior
input int      InpHTFEma           = 200;          // EMA del TF superior
input bool     InpUseRsiFilter     = false;        // Filtro RSI de momentum
input int      InpRsiPeriod        = 14;           // Periodo RSI
input double   InpRsiBuyMin        = 50.0;         // RSI minimo para comprar
input double   InpRsiSellMax       = 50.0;         // RSI maximo para vender
input bool     InpUseAdxFilter     = false;        // Filtro de fuerza ADX
input int      InpAdxPeriod        = 14;           // Periodo ADX
input double   InpAdxMin           = 18.0;         // ADX minimo

input group "=== Gestion de Riesgo (ATR) ==="
input int      InpAtrPeriod        = 14;           // Periodo ATR
input double   InpSlAtrMult        = 1.5;          // SL = mult * ATR
input double   InpTpRR             = 2.0;          // TP = RR * (distancia del SL)
input bool     InpUseRiskPercent   = true;         // Sizing por % de riesgo
input double   InpRiskPercent      = 1.0;          // Riesgo por operacion (%)
input double   InpFixedLot         = 0.10;         // Lote fijo (si no se usa % riesgo)

input group "=== Comportamiento ==="
input bool     InpFlipOnReverse    = true;         // Cerrar y abrir en sentido contrario al revertir
input bool     InpCloseOnReverse   = true;         // Cerrar la posicion al cruce contrario (aunque no abra)

input group "=== Salidas: Parcial + Trailing ==="
input bool     InpUsePartial       = true;         // Cerrar parte en el primer objetivo
input double   InpPartialAtR        = 1.0;         // Tomar parcial a >= R
input double   InpPartialPercent    = 50.0;        // % del volumen a cerrar
input bool     InpBEAfterPartial    = true;        // Break-even tras el parcial
input double   InpBreakEvenLockPts  = 5.0;         // Puntos asegurados en BE
input bool     InpUseTrailing       = true;        // Trailing stop
input double   InpTrailAtrMult      = 2.0;         // Distancia trailing = mult * ATR
input double   InpTrailStartAtR     = 1.0;         // Iniciar trailing a >= R

input group "=== Limites diarios (se resetean cada dia) ==="
input bool     InpUseDailyLossLimit = true;        // Limite de perdida diaria
input double   InpDailyLossPercent  = 5.0;         // Perdida diaria maxima (%)
input int      InpMaxTradesPerDay   = 10;          // Max operaciones por dia (0 = sin limite)

//============================ GLOBALS ==============================
CTrade   trade;

int hEmaFast, hEmaSlow, hFilterEma, hHTF, hRsi, hAdx, hAtr;

double g_point;
int    g_digits;

datetime g_lastBarTime = 0;
datetime g_dayStart    = 0;
double   g_dayStartEquity = 0.0;
int      g_tradesToday  = 0;
bool     g_tradingBlockedToday = false;

struct PosState
{
   ulong  ticket;
   double openPrice;
   double riskDist;
   double initialVolume;
   bool   partialDone;
};
PosState g_pos[];

//+------------------------------------------------------------------+
int OnInit()
{
   g_point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();

   hEmaFast   = iMA(_Symbol, InpEntryTF, InpEmaFast,  0, MODE_EMA, PRICE_CLOSE);
   hEmaSlow   = iMA(_Symbol, InpEntryTF, InpEmaSlow,  0, MODE_EMA, PRICE_CLOSE);
   hFilterEma = iMA(_Symbol, InpEntryTF, InpFilterEma,0, MODE_EMA, PRICE_CLOSE);
   hHTF       = iMA(_Symbol, InpTrendTF, InpHTFEma,   0, MODE_EMA, PRICE_CLOSE);
   hRsi       = iRSI(_Symbol, InpEntryTF, InpRsiPeriod, PRICE_CLOSE);
   hAdx       = iADX(_Symbol, InpEntryTF, InpAdxPeriod);
   hAtr       = iATR(_Symbol, InpEntryTF, InpAtrPeriod);

   if(hEmaFast==INVALID_HANDLE || hEmaSlow==INVALID_HANDLE || hFilterEma==INVALID_HANDLE ||
      hHTF==INVALID_HANDLE || hRsi==INVALID_HANDLE || hAdx==INVALID_HANDLE || hAtr==INVALID_HANDLE)
   {
      Print("Error creando handles de indicadores.");
      return(INIT_FAILED);
   }

   ResetDailyCounters();
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   IndicatorRelease(hEmaFast);
   IndicatorRelease(hEmaSlow);
   IndicatorRelease(hFilterEma);
   IndicatorRelease(hHTF);
   IndicatorRelease(hRsi);
   IndicatorRelease(hAdx);
   IndicatorRelease(hAtr);
}

//+------------------------------------------------------------------+
void OnTick()
{
   HandleNewDay();
   SyncPositionStates();
   ManageOpenPositions();

   datetime curBar = (datetime)SeriesInfoInteger(_Symbol, InpEntryTF, SERIES_LASTBAR_DATE);
   bool newBar = (curBar != g_lastBarTime);
   if(newBar) g_lastBarTime = curBar;
   if(InpOnePerBar && !newBar) return;

   int signal = GetSignal(); // +1 compra, -1 venta, 0 nada
   if(signal == 0) return;

   // ---- FLIP / cierre al revertir ----
   int dir = OwnPositionDirection(); // +1, -1, 0
   if(dir != 0 && dir != signal)
   {
      if(InpCloseOnReverse || InpFlipOnReverse)
         CloseOwnPositions();
      dir = 0;
   }

   // Limites/spread solo afectan a NUEVAS aperturas (no al cierre defensivo)
   if(!PassGlobalFilters()) return;

   // Abrir si no hay posicion en esa direccion
   if(dir == 0)
      OpenTrade(signal);
}

//+------------------------------------------------------------------+
bool PassGlobalFilters()
{
   if(g_tradingBlockedToday) return(false);
   if(InpMaxTradesPerDay > 0 && g_tradesToday >= InpMaxTradesPerDay) return(false);

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPoints) return(false);

   return(true);
}

//+------------------------------------------------------------------+
//| Senal: cruce de EMAs + filtros opcionales                        |
//+------------------------------------------------------------------+
int GetSignal()
{
   double ef[], es[];
   ArraySetAsSeries(ef, true);
   ArraySetAsSeries(es, true);
   if(CopyBuffer(hEmaFast, 0, 0, 3, ef) < 3) return(0);
   if(CopyBuffer(hEmaSlow, 0, 0, 3, es) < 3) return(0);

   bool buyCross  = (ef[2] <= es[2] && ef[1] > es[1]);
   bool sellCross = (ef[2] >= es[2] && ef[1] < es[1]);
   if(!buyCross && !sellCross) return(0);

   double close1 = iClose(_Symbol, InpEntryTF, 1);
   if(close1 == 0.0) return(0);

   // Filtro EMA de tendencia local (precio del lado correcto)
   if(InpUseSignalEma)
   {
      double fe[];
      ArraySetAsSeries(fe, true);
      if(CopyBuffer(hFilterEma, 0, 0, 2, fe) < 2) return(0);
      if(buyCross  && close1 < fe[1]) return(0);
      if(sellCross && close1 > fe[1]) return(0);
   }

   // Filtro de tendencia TF superior
   if(InpUseHTFTrend)
   {
      double htf[];
      ArraySetAsSeries(htf, true);
      if(CopyBuffer(hHTF, 0, 0, 2, htf) < 2) return(0);
      double htfClose = iClose(_Symbol, InpTrendTF, 1);
      if(htfClose == 0.0) return(0);
      if(buyCross  && htfClose < htf[1]) return(0);
      if(sellCross && htfClose > htf[1]) return(0);
   }

   // Filtro RSI de momentum
   if(InpUseRsiFilter)
   {
      double rsi[];
      ArraySetAsSeries(rsi, true);
      if(CopyBuffer(hRsi, 0, 0, 2, rsi) < 2) return(0);
      if(buyCross  && rsi[1] < InpRsiBuyMin)  return(0);
      if(sellCross && rsi[1] > InpRsiSellMax) return(0);
   }

   // Filtro ADX de fuerza
   if(InpUseAdxFilter)
   {
      double adx[];
      ArraySetAsSeries(adx, true);
      if(CopyBuffer(hAdx, 0, 0, 2, adx) < 2) return(0);
      if(adx[1] < InpAdxMin) return(0);
   }

   return(buyCross ? +1 : -1);
}

//+------------------------------------------------------------------+
void OpenTrade(int signal)
{
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(hAtr, 0, 0, 2, atr) < 2) return;
   double atrVal = atr[1];
   if(atrVal <= 0) return;

   double slDistance = InpSlAtrMult * atrVal;
   double tpDistance = InpTpRR * slDistance;

   double minStop = (double)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point;
   if(slDistance < minStop) slDistance = minStop * 1.5;
   if(tpDistance < minStop) tpDistance = minStop * 1.5;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double price, sl, tp;
   if(signal > 0)
   {
      price = ask;
      sl    = NormalizeDouble(price - slDistance, g_digits);
      tp    = NormalizeDouble(price + tpDistance, g_digits);
   }
   else
   {
      price = bid;
      sl    = NormalizeDouble(price + slDistance, g_digits);
      tp    = NormalizeDouble(price - tpDistance, g_digits);
   }

   double lots = CalcLotSize(slDistance);
   if(lots <= 0) return;

   bool ok = (signal > 0) ? trade.Buy(lots, _Symbol, price, sl, tp, InpComment)
                          : trade.Sell(lots, _Symbol, price, sl, tp, InpComment);
   if(ok)
      g_tradesToday++;
   else
      PrintFormat("Fallo al abrir orden. retcode=%d (%s)", trade.ResultRetcode(), trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
double CalcLotSize(double slDistancePrice)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(!InpUseRiskPercent)
      return(NormalizeLot(InpFixedLot, lotStep, minLot, maxLot));

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0 || tickValue <= 0)
      return(NormalizeLot(InpFixedLot, lotStep, minLot, maxLot));

   double lossPerLot = (slDistancePrice / tickSize) * tickValue;
   if(lossPerLot <= 0)
      return(NormalizeLot(InpFixedLot, lotStep, minLot, maxLot));

   double lots = riskMoney / lossPerLot;
   lots = NormalizeLot(lots, lotStep, minLot, maxLot);

   double marginReq = 0.0;
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lots, ask, marginReq))
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      while(lots > minLot && marginReq > freeMargin * 0.9)
      {
         lots = NormalizeLot(lots - lotStep, lotStep, minLot, maxLot);
         if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, lots, ask, marginReq))
            break;
      }
   }
   return(lots);
}

double NormalizeLot(double lots, double step, double minLot, double maxLot)
{
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step) * step;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   int lotDigits = (int)MathRound(-MathLog10(step));
   if(lotDigits < 0) lotDigits = 2;
   return(NormalizeDouble(lots, lotDigits));
}

double NormalizeClose(double vol)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return(NormalizeLot(vol, lotStep, minLot, maxLot));
}

//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   double atr[];
   ArraySetAsSeries(atr, true);
   bool atrOk = (CopyBuffer(hAtr, 0, 0, 2, atr) >= 2 && atr[1] > 0);
   double atrVal = atrOk ? atr[1] : 0.0;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      int idx = FindPosState(ticket);
      if(idx < 0) continue;

      long   type  = PositionGetInteger(POSITION_TYPE);
      double openP = g_pos[idx].openPrice;
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      double riskDist = g_pos[idx].riskDist;
      if(riskDist <= 0) continue;

      double profitDist = (type == POSITION_TYPE_BUY) ? (bid - openP) : (openP - ask);
      double rMultiple  = profitDist / riskDist;

      if(InpUsePartial && !g_pos[idx].partialDone && rMultiple >= InpPartialAtR)
      {
         double closeVol  = NormalizeClose(g_pos[idx].initialVolume * (InpPartialPercent/100.0));
         double remaining = PositionGetDouble(POSITION_VOLUME) - closeVol;
         double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(closeVol >= minLot && remaining >= minLot)
         {
            if(trade.PositionClosePartial(ticket, closeVol))
               g_pos[idx].partialDone = true;
         }
         else
            g_pos[idx].partialDone = true;
      }

      double newSL = curSL;

      if(type == POSITION_TYPE_BUY)
      {
         if(InpBEAfterPartial && g_pos[idx].partialDone)
         {
            double be = NormalizeDouble(openP + InpBreakEvenLockPts * g_point, g_digits);
            if(be > newSL) newSL = be;
         }
         if(InpUseTrailing && atrOk && rMultiple >= InpTrailStartAtR)
         {
            double trail = NormalizeDouble(bid - InpTrailAtrMult * atrVal, g_digits);
            if(trail > newSL) newSL = trail;
         }
         if(newSL > curSL && newSL < bid)
            trade.PositionModify(ticket, newSL, curTP);
      }
      else
      {
         if(InpBEAfterPartial && g_pos[idx].partialDone)
         {
            double be = NormalizeDouble(openP - InpBreakEvenLockPts * g_point, g_digits);
            if(curSL == 0.0 || be < newSL) newSL = be;
         }
         if(InpUseTrailing && atrOk && rMultiple >= InpTrailStartAtR)
         {
            double trail = NormalizeDouble(ask + InpTrailAtrMult * atrVal, g_digits);
            if(curSL == 0.0 || trail < newSL) newSL = trail;
         }
         if((curSL == 0.0 || newSL < curSL) && newSL > ask)
            trade.PositionModify(ticket, newSL, curTP);
      }
   }
}

//+------------------------------------------------------------------+
//| Direccion de la posicion propia: +1 buy, -1 sell, 0 ninguna      |
//+------------------------------------------------------------------+
int OwnPositionDirection()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      return(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? +1 : -1);
   }
   return(0);
}

void CloseOwnPositions()
{
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      trade.PositionClose(ticket);
   }
}

//+------------------------------------------------------------------+
void SyncPositionStates()
{
   for(int i = ArraySize(g_pos)-1; i >= 0; i--)
      if(!PositionSelectByTicket(g_pos[i].ticket))
         RemovePosStateAt(i);

   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(FindPosState(ticket) >= 0) continue;

      double openP = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl    = PositionGetDouble(POSITION_SL);
      double vol   = PositionGetDouble(POSITION_VOLUME);
      double risk  = (sl > 0.0) ? MathAbs(openP - sl) : 0.0;

      int n = ArraySize(g_pos);
      ArrayResize(g_pos, n+1);
      g_pos[n].ticket        = ticket;
      g_pos[n].openPrice     = openP;
      g_pos[n].riskDist      = risk;
      g_pos[n].initialVolume = vol;
      g_pos[n].partialDone   = false;
   }
}

int FindPosState(ulong ticket)
{
   for(int i = 0; i < ArraySize(g_pos); i++)
      if(g_pos[i].ticket == ticket) return(i);
   return(-1);
}

void RemovePosStateAt(int idx)
{
   int n = ArraySize(g_pos);
   if(idx < 0 || idx >= n) return;
   for(int i = idx; i < n-1; i++) g_pos[i] = g_pos[i+1];
   ArrayResize(g_pos, n-1);
}

//+------------------------------------------------------------------+
void HandleNewDay()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   datetime today = StringToTime(StringFormat("%04d.%02d.%02d", dt.year, dt.mon, dt.day));

   if(today != g_dayStart)
   {
      g_dayStart = today;
      ResetDailyCounters();
   }

   if(InpUseDailyLossLimit && !g_tradingBlockedToday)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double dayLoss = g_dayStartEquity - equity;
      double maxLoss = g_dayStartEquity * (InpDailyLossPercent / 100.0);
      if(maxLoss > 0 && dayLoss >= maxLoss)
         g_tradingBlockedToday = true;
   }
}

void ResetDailyCounters()
{
   g_dayStartEquity      = AccountInfoDouble(ACCOUNT_EQUITY);
   g_tradesToday         = 0;
   g_tradingBlockedToday = false;
}
//+------------------------------------------------------------------+
