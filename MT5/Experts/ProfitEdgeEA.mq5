//+------------------------------------------------------------------+
//|                                                 ProfitEdgeEA.mq5  |
//|   Multi-Timeframe Trend + Pullback EA con gestion de riesgo ATR   |
//|                                                                  |
//|   Metodologia:                                                   |
//|   1) Tendencia en timeframe superior (EMA rapida vs lenta +      |
//|      pendiente + filtro de fuerza ADX).                          |
//|   2) Entrada en timeframe operativo por pullback (RSI) con       |
//|      confirmacion de momentum y alineacion con la tendencia.     |
//|   3) Riesgo definido por ATR: SL = k*ATR, TP = RR*SL.            |
//|   4) Sizing por % de riesgo, break-even, trailing y limites      |
//|      diarios de perdida / numero de operaciones.                 |
//|                                                                  |
//|   NOTA: Ningun sistema garantiza rentabilidad. Este EA aporta    |
//|   un edge estadistico configurable + control estricto de riesgo. |
//|   Optimiza y valida con backtests largos y walk-forward.         |
//+------------------------------------------------------------------+
#property copyright "ProfitEdgeEA"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>

//============================ INPUTS ================================
input group "=== General ==="
input long     InpMagic            = 20260610;   // Numero magico (identifica este EA)
input string   InpComment          = "ProfitEdge"; // Comentario de las ordenes
input int      InpMaxSpreadPoints  = 30;          // Spread maximo permitido (puntos)
input int      InpMaxPositions     = 1;           // Posiciones simultaneas maximas

input group "=== Timeframes ==="
input ENUM_TIMEFRAMES InpTrendTF    = PERIOD_H4;  // Timeframe de tendencia (superior)
input ENUM_TIMEFRAMES InpEntryTF    = PERIOD_H1;  // Timeframe de entrada (operativo)

input group "=== Filtro de Tendencia (TF superior) ==="
input int      InpEmaFast          = 50;          // EMA rapida (tendencia)
input int      InpEmaSlow          = 200;         // EMA lenta (tendencia)
input bool     InpUseSlopeFilter   = true;        // Exigir pendiente de la EMA rapida
input int      InpSlopeLookback    = 3;           // Velas para medir pendiente
input bool     InpUseAdxFilter     = true;        // Usar filtro de fuerza ADX
input int      InpAdxPeriod        = 14;          // Periodo ADX
input double   InpAdxMin           = 22.0;        // ADX minimo para operar

input group "=== Entrada (TF operativo) ==="
input int      InpRsiPeriod        = 14;          // Periodo RSI
input double   InpRsiBuyPullback   = 45.0;        // RSI por debajo de esto = pullback en alza
input double   InpRsiSellPullback  = 55.0;        // RSI por encima de esto = pullback en baja
input int      InpPullbackEmaPeriod= 20;          // EMA dinamica del pullback (TF operativo)
input bool     InpRequireMomentum  = true;        // Exigir vela de confirmacion de momentum

input group "=== Gestion de Riesgo (ATR) ==="
input int      InpAtrPeriod        = 14;          // Periodo ATR (TF operativo)
input double   InpSlAtrMult        = 1.8;         // SL = mult * ATR
input double   InpTpRR             = 2.2;         // TP = RR * (distancia del SL)
input bool     InpUseRiskPercent   = true;        // Sizing por % de riesgo
input double   InpRiskPercent      = 1.0;         // Riesgo por operacion (% del balance)
input double   InpFixedLot         = 0.10;        // Lote fijo (si no se usa % de riesgo)

input group "=== Gestion de la Posicion ==="
input bool     InpUseBreakEven     = true;        // Activar break-even
input double   InpBreakEvenAtR     = 1.0;         // Mover a BE cuando profit >= R (multiplos de riesgo)
input double   InpBreakEvenLockPts = 5.0;         // Puntos asegurados al hacer BE
input bool     InpUseTrailing      = true;        // Activar trailing stop
input double   InpTrailAtrMult     = 2.0;         // Distancia del trailing = mult * ATR
input double   InpTrailStartAtR    = 1.2;         // Iniciar trailing cuando profit >= R

input group "=== Filtros de Sesion y Limites ==="
input bool     InpUseTimeFilter    = false;       // Filtrar por horas (hora del servidor)
input int      InpStartHour        = 7;           // Hora inicio (incl.)
input int      InpEndHour          = 20;          // Hora fin (excl.)
input bool     InpUseDailyLossLimit= true;        // Limite de perdida diaria
input double   InpDailyLossPercent = 3.0;         // Perdida diaria maxima (% del balance)
input int      InpMaxTradesPerDay  = 5;           // Operaciones maximas por dia (0 = sin limite)
input bool     InpOnePerBar        = true;        // Maximo una entrada por vela del TF operativo

//============================ GLOBALS ==============================
CTrade         trade;
CPositionInfo  posInfo;
CSymbolInfo    symInfo;

int hEmaFastT, hEmaSlowT, hAdxT;          // handles TF tendencia
int hRsiE, hEmaPullE, hAtrE;              // handles TF entrada

double g_point;
int    g_digits;

datetime g_lastBarTime = 0;               // control "una por vela"
datetime g_dayStart    = 0;               // inicio del dia actual
double   g_dayStartEquity = 0.0;          // equity al inicio del dia
int      g_tradesToday  = 0;              // operaciones abiertas hoy
bool     g_tradingBlockedToday = false;   // bloqueo por limite diario

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   if(!symInfo.Name(_Symbol))
   {
      Print("Error: no se pudo inicializar el simbolo.");
      return(INIT_FAILED);
   }

   g_point  = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(20);
   trade.SetTypeFillingBySymbol(_Symbol);
   trade.SetMarginMode();

   // Handles TF tendencia
   hEmaFastT = iMA(_Symbol, InpTrendTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hEmaSlowT = iMA(_Symbol, InpTrendTF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   hAdxT     = iADX(_Symbol, InpTrendTF, InpAdxPeriod);

   // Handles TF entrada
   hRsiE     = iRSI(_Symbol, InpEntryTF, InpRsiPeriod, PRICE_CLOSE);
   hEmaPullE = iMA(_Symbol, InpEntryTF, InpPullbackEmaPeriod, 0, MODE_EMA, PRICE_CLOSE);
   hAtrE     = iATR(_Symbol, InpEntryTF, InpAtrPeriod);

   if(hEmaFastT==INVALID_HANDLE || hEmaSlowT==INVALID_HANDLE || hAdxT==INVALID_HANDLE ||
      hRsiE==INVALID_HANDLE || hEmaPullE==INVALID_HANDLE || hAtrE==INVALID_HANDLE)
   {
      Print("Error creando handles de indicadores.");
      return(INIT_FAILED);
   }

   ResetDailyCounters();

   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(hEmaFastT);
   IndicatorRelease(hEmaSlowT);
   IndicatorRelease(hAdxT);
   IndicatorRelease(hRsiE);
   IndicatorRelease(hEmaPullE);
   IndicatorRelease(hAtrE);
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void OnTick()
{
   // Control de cambio de dia (resetea contadores y equity de referencia)
   HandleNewDay();

   // Gestion de posiciones abiertas (BE / trailing) en cada tick
   ManageOpenPositions();

   // Solo evaluamos entradas en el cierre de una vela del TF operativo
   datetime curBar = (datetime)SeriesInfoInteger(_Symbol, InpEntryTF, SERIES_LASTBAR_DATE);
   bool newBar = (curBar != g_lastBarTime);
   if(newBar)
      g_lastBarTime = curBar;

   if(InpOnePerBar && !newBar)
      return;

   // Verificaciones previas (filtros globales)
   if(!PassGlobalFilters())
      return;

   // Si ya hay el maximo de posiciones, no abrimos mas
   if(CountOwnPositions() >= InpMaxPositions)
      return;

   // Senal
   int signal = GetSignal(); // +1 compra, -1 venta, 0 nada
   if(signal == 0)
      return;

   OpenTrade(signal);
}

//+------------------------------------------------------------------+
//| Filtros globales (spread, sesion, limite diario)                 |
//+------------------------------------------------------------------+
bool PassGlobalFilters()
{
   if(g_tradingBlockedToday)
      return(false);

   // Limite de operaciones por dia
   if(InpMaxTradesPerDay > 0 && g_tradesToday >= InpMaxTradesPerDay)
      return(false);

   // Spread
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPoints)
      return(false);

   // Filtro horario
   if(InpUseTimeFilter)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      if(InpStartHour <= InpEndHour)
      {
         if(dt.hour < InpStartHour || dt.hour >= InpEndHour)
            return(false);
      }
      else // ventana que cruza medianoche
      {
         if(dt.hour < InpStartHour && dt.hour >= InpEndHour)
            return(false);
      }
   }

   return(true);
}

//+------------------------------------------------------------------+
//| Determina la senal combinando tendencia + pullback + momentum    |
//+------------------------------------------------------------------+
int GetSignal()
{
   // NOTA de indexacion: usamos arrays como serie temporal (ArraySetAsSeries),
   // por lo que el indice 0 = vela en formacion, 1 = ultima vela CERRADA, 2 = previa.
   // La barra de senal es la ultima cerrada (indice 1), coherente con iClose(.,1).

   // ---- Tendencia (TF superior) ----
   int needT = MathMax(2, InpSlopeLookback + 2);
   double emaFast[], emaSlow[];
   ArraySetAsSeries(emaFast, true);
   ArraySetAsSeries(emaSlow, true);
   if(CopyBuffer(hEmaFastT, 0, 0, needT, emaFast) < needT) return(0);
   if(CopyBuffer(hEmaSlowT, 0, 0, needT, emaSlow) < needT) return(0);

   bool upTrend   = (emaFast[1] > emaSlow[1]);
   bool downTrend = (emaFast[1] < emaSlow[1]);

   if(InpUseSlopeFilter)
   {
      double slope = emaFast[1] - emaFast[1 + InpSlopeLookback];
      upTrend   = upTrend   && (slope > 0);
      downTrend = downTrend && (slope < 0);
   }

   if(InpUseAdxFilter)
   {
      double adx[];
      ArraySetAsSeries(adx, true);
      if(CopyBuffer(hAdxT, 0, 0, 2, adx) < 2) return(0);
      if(adx[1] < InpAdxMin)
         return(0);
   }

   if(!upTrend && !downTrend)
      return(0);

   // ---- Pullback + momentum (TF operativo) ----
   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(hRsiE, 0, 0, 3, rsi) < 3) return(0);

   double emaPull[];
   ArraySetAsSeries(emaPull, true);
   if(CopyBuffer(hEmaPullE, 0, 0, 2, emaPull) < 2) return(0);

   // Precios: indice 1 = ultima vela cerrada, indice 2 = previa
   double close1 = iClose(_Symbol, InpEntryTF, 1);
   double close2 = iClose(_Symbol, InpEntryTF, 2);
   double low1   = iLow(_Symbol, InpEntryTF, 1);
   double high1  = iHigh(_Symbol, InpEntryTF, 1);
   if(close1==0.0 || close2==0.0) return(0);

   if(upTrend)
   {
      // Hubo pullback: RSI bajo en la vela de senal o el minimo toco la EMA dinamica
      bool pullback = (rsi[1] < InpRsiBuyPullback) || (low1 <= emaPull[1]);
      // Confirmacion de momentum: vela de senal alcista y RSI girando al alza
      bool momentum = (!InpRequireMomentum) || (close1 > close2 && rsi[1] > rsi[2]);
      if(pullback && momentum)
         return(+1);
   }
   else if(downTrend)
   {
      bool pullback = (rsi[1] > InpRsiSellPullback) || (high1 >= emaPull[1]);
      bool momentum = (!InpRequireMomentum) || (close1 < close2 && rsi[1] < rsi[2]);
      if(pullback && momentum)
         return(-1);
   }

   return(0);
}

//+------------------------------------------------------------------+
//| Abre una operacion con SL/TP por ATR y sizing por riesgo         |
//+------------------------------------------------------------------+
void OpenTrade(int signal)
{
   double atr[1];
   if(CopyBuffer(hAtrE, 0, 0, 1, atr) < 1) return;
   double atrVal = atr[0];
   if(atrVal <= 0) return;

   double slDistance = InpSlAtrMult * atrVal;        // distancia del SL en precio
   double tpDistance = InpTpRR * slDistance;          // TP por ratio riesgo/beneficio

   // Respetar distancia minima del broker (stops level)
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

   bool ok = false;
   if(signal > 0)
      ok = trade.Buy(lots, _Symbol, price, sl, tp, InpComment);
   else
      ok = trade.Sell(lots, _Symbol, price, sl, tp, InpComment);

   if(ok)
   {
      g_tradesToday++;
   }
   else
   {
      PrintFormat("Fallo al abrir orden. retcode=%d (%s)", trade.ResultRetcode(), trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Calculo del tamano de lote segun riesgo % y distancia de SL      |
//+------------------------------------------------------------------+
double CalcLotSize(double slDistancePrice)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(!InpUseRiskPercent)
   {
      double lot = InpFixedLot;
      lot = MathMax(minLot, MathMin(maxLot, lot));
      return(NormalizeLot(lot, lotStep, minLot, maxLot));
   }

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (InpRiskPercent / 100.0);

   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0 || tickValue <= 0)
      return(NormalizeLot(InpFixedLot, lotStep, minLot, maxLot));

   // Perdida por lote si se toca el SL
   double lossPerLot = (slDistancePrice / tickSize) * tickValue;
   if(lossPerLot <= 0)
      return(NormalizeLot(InpFixedLot, lotStep, minLot, maxLot));

   double lots = riskMoney / lossPerLot;
   return(NormalizeLot(lots, lotStep, minLot, maxLot));
}

double NormalizeLot(double lots, double step, double minLot, double maxLot)
{
   if(step <= 0) step = 0.01;
   lots = MathFloor(lots / step) * step;
   lots = MathMax(minLot, MathMin(maxLot, lots));
   // redondeo a la precision del step
   int lotDigits = (int)MathRound(-MathLog10(step));
   if(lotDigits < 0) lotDigits = 2;
   return(NormalizeDouble(lots, lotDigits));
}

//+------------------------------------------------------------------+
//| Gestion de posiciones abiertas: break-even y trailing            |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   if(!InpUseBreakEven && !InpUseTrailing)
      return;

   double atr[1];
   bool atrOk = (CopyBuffer(hAtrE, 0, 0, 1, atr) >= 1 && atr[0] > 0);

   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;

      long   type     = PositionGetInteger(POSITION_TYPE);
      double openP    = PositionGetDouble(POSITION_PRICE_OPEN);
      double curSL    = PositionGetDouble(POSITION_SL);
      double curTP    = PositionGetDouble(POSITION_TP);
      double bid      = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      double ask      = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      // Distancia de riesgo inicial (open -> SL). Si no hay SL usamos ATR.
      double riskDist = MathAbs(openP - curSL);
      if(riskDist <= 0 && atrOk)
         riskDist = InpSlAtrMult * atr[0];
      if(riskDist <= 0) continue;

      double newSL = curSL;

      if(type == POSITION_TYPE_BUY)
      {
         double profitDist = bid - openP;
         double rMultiple  = profitDist / riskDist;

         // Break-even
         if(InpUseBreakEven && rMultiple >= InpBreakEvenAtR)
         {
            double be = NormalizeDouble(openP + InpBreakEvenLockPts * g_point, g_digits);
            if(be > newSL) newSL = be;
         }
         // Trailing
         if(InpUseTrailing && atrOk && rMultiple >= InpTrailStartAtR)
         {
            double trail = NormalizeDouble(bid - InpTrailAtrMult * atr[0], g_digits);
            if(trail > newSL) newSL = trail;
         }

         if(newSL > curSL && newSL < bid)
            trade.PositionModify(ticket, newSL, curTP);
      }
      else if(type == POSITION_TYPE_SELL)
      {
         double profitDist = openP - ask;
         double rMultiple  = profitDist / riskDist;

         if(InpUseBreakEven && rMultiple >= InpBreakEvenAtR)
         {
            double be = NormalizeDouble(openP - InpBreakEvenLockPts * g_point, g_digits);
            if(curSL == 0 || be < newSL) newSL = be;
         }
         if(InpUseTrailing && atrOk && rMultiple >= InpTrailStartAtR)
         {
            double trail = NormalizeDouble(ask + InpTrailAtrMult * atr[0], g_digits);
            if(curSL == 0 || trail < newSL) newSL = trail;
         }

         if((curSL == 0 || newSL < curSL) && newSL > ask)
            trade.PositionModify(ticket, newSL, curTP);
      }
   }
}

//+------------------------------------------------------------------+
//| Cuenta posiciones propias (mismo magic y simbolo)                |
//+------------------------------------------------------------------+
int CountOwnPositions()
{
   int count = 0;
   for(int i = PositionsTotal()-1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      if(PositionGetInteger(POSITION_MAGIC) == InpMagic &&
         PositionGetString(POSITION_SYMBOL) == _Symbol)
         count++;
   }
   return(count);
}

//+------------------------------------------------------------------+
//| Control de cambio de dia y limite de perdida diaria              |
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

   // Evaluar limite de perdida diaria
   if(InpUseDailyLossLimit && !g_tradingBlockedToday)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double dayLoss = g_dayStartEquity - equity;
      double maxLoss = g_dayStartEquity * (InpDailyLossPercent / 100.0);
      if(dayLoss >= maxLoss && maxLoss > 0)
      {
         g_tradingBlockedToday = true;
         PrintFormat("Limite de perdida diaria alcanzado (%.2f). Trading bloqueado hoy.", dayLoss);
      }
   }
}

void ResetDailyCounters()
{
   g_dayStartEquity        = AccountInfoDouble(ACCOUNT_EQUITY);
   g_tradesToday           = 0;
   g_tradingBlockedToday   = false;
}
//+------------------------------------------------------------------+
