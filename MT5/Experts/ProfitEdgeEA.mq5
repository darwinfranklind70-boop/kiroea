//+------------------------------------------------------------------+
//|                                                 ProfitEdgeEA.mq5  |
//|   v2.0 - Multi-Timeframe Trend + Pullback con confluencia,        |
//|   salidas parciales (runner), filtros de regimen y sesion GMT.    |
//|                                                                  |
//|   MEJORAS v2.0 respecto a v1:                                    |
//|   - Entradas por CONFLUENCIA (varias confirmaciones obligatorias)|
//|     en lugar de un OR laxo -> menos senales, mejor calidad.       |
//|   - Salidas PARCIALES: cierra parte en 1R, mueve a break-even y   |
//|     deja correr el resto con trailing (ganancias que corren).     |
//|   - Filtro de REGIMEN de volatilidad (ATR vs su media).           |
//|   - Filtro de SOBRE-EXTENSION (no perseguir precio lejos de EMA). |
//|   - SESIONES normalizadas a GMT + guarda de viernes.              |
//|   - Sizing por % de riesgo mas robusto (validaciones de margen).  |
//|                                                                  |
//|   NOTA: Ningun sistema garantiza rentabilidad. Optimiza y valida  |
//|   walk-forward con costes reales por par y periodo.               |
//+------------------------------------------------------------------+
#property copyright "ProfitEdgeEA"
#property version   "2.00"
#property strict

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include <Trade/SymbolInfo.mqh>

//============================ INPUTS ================================
input group "=== General ==="
input long     InpMagic            = 20260610;     // Numero magico (identifica este EA)
input string   InpComment          = "ProfitEdge"; // Comentario de las ordenes
input int      InpMaxSpreadPoints  = 25;           // Spread maximo permitido (puntos)
input int      InpMaxPositions     = 1;            // Posiciones simultaneas maximas
input bool     InpOnePerBar        = true;         // Maximo una entrada por vela del TF operativo

input group "=== Timeframes ==="
input ENUM_TIMEFRAMES InpTrendTF    = PERIOD_H4;   // Timeframe de tendencia (superior)
input ENUM_TIMEFRAMES InpEntryTF    = PERIOD_H1;   // Timeframe de entrada (operativo)

input group "=== Filtro de Tendencia (TF superior) ==="
input int      InpEmaFast          = 50;           // EMA rapida (tendencia)
input int      InpEmaSlow          = 200;          // EMA lenta (tendencia)
input bool     InpUseSlopeFilter   = true;         // Exigir pendiente de la EMA rapida
input int      InpSlopeLookback    = 3;            // Velas para medir pendiente
input bool     InpUseAdxFilter     = true;         // Usar filtro de fuerza ADX
input int      InpAdxPeriod        = 14;           // Periodo ADX
input double   InpAdxMin           = 22.0;         // ADX minimo para operar

input group "=== Entrada por Confluencia (TF operativo) ==="
input int      InpRsiPeriod        = 14;           // Periodo RSI
input double   InpRsiBuyPullback   = 45.0;         // RSI por debajo de esto = pullback en alza
input double   InpRsiSellPullback  = 55.0;         // RSI por encima de esto = pullback en baja
input int      InpPullbackEmaPeriod= 20;           // EMA dinamica del pullback (TF operativo)
input double   InpEntryProxATR     = 0.50;         // Proximidad a la EMA dinamica (mult. de ATR)
input bool     InpUseCandleFilter  = true;         // Exigir vela de confirmacion con cuerpo fuerte
input double   InpCandleBodyFrac   = 0.50;         // Cierre en el % superior/inferior del rango

input group "=== Filtro de Regimen / Volatilidad ==="
input bool     InpUseVolRegime     = true;         // Filtrar por regimen de volatilidad (ATR vs media)
input int      InpAtrAvgPeriod     = 50;           // Periodo de la media de ATR
input double   InpAtrMinFactor     = 0.70;         // ATR debe ser >= factor * media (evita mercado muerto)
input double   InpAtrMaxFactor     = 2.50;         // ATR debe ser <= factor * media (evita caos)
input bool     InpUseOverextension = true;         // Evitar perseguir precio lejos de la EMA dinamica
input double   InpMaxExtensionATR  = 2.0;          // Distancia maxima precio-EMA (mult. de ATR)

input group "=== Gestion de Riesgo (ATR) ==="
input int      InpAtrPeriod        = 14;           // Periodo ATR (TF operativo)
input double   InpSlAtrMult        = 1.8;          // SL = mult * ATR
input double   InpTpRR             = 3.0;          // TP del runner = RR * (distancia del SL)
input bool     InpUseRiskPercent   = true;         // Sizing por % de riesgo
input double   InpRiskPercent      = 1.0;          // Riesgo por operacion (% del balance)
input double   InpFixedLot         = 0.10;         // Lote fijo (si no se usa % de riesgo)

input group "=== Salidas Parciales + Runner ==="
input bool     InpUsePartial       = true;         // Cerrar parte de la posicion en el primer objetivo
input double   InpPartialAtR       = 1.0;          // Tomar parcial cuando profit >= R (multiplos de riesgo)
input double   InpPartialPercent   = 50.0;         // % del volumen a cerrar en el parcial
input bool     InpBEAfterPartial   = true;         // Mover a break-even tras el parcial

input group "=== Break-even y Trailing ==="
input bool     InpUseBreakEven     = true;         // Activar break-even
input double   InpBreakEvenAtR     = 1.0;          // Mover a BE cuando profit >= R
input double   InpBreakEvenLockPts = 5.0;          // Puntos asegurados al hacer BE
input bool     InpUseTrailing      = true;         // Activar trailing stop
input double   InpTrailAtrMult     = 2.0;          // Distancia del trailing = mult * ATR
input double   InpTrailStartAtR    = 1.2;          // Iniciar trailing cuando profit >= R

input group "=== Sesion (GMT) y Limites ==="
input bool     InpUseSession       = false;        // Filtrar por sesiones (horas GMT)
input int      InpBrokerGMTOffset  = 2;            // Offset del servidor respecto a GMT (ej. GMT+2 -> 2)
input bool     InpTradeLondon      = true;         // Operar sesion de Londres (07-16 GMT)
input bool     InpTradeNewYork     = true;         // Operar sesion de Nueva York (12-21 GMT)
input bool     InpTradeAsia        = false;        // Operar sesion asiatica (23-08 GMT)
input bool     InpAvoidFridayLate  = true;         // Evitar abrir el viernes a ultima hora
input int      InpFridayStopHourGMT= 20;           // Hora GMT a partir de la cual no abrir el viernes
input bool     InpUseDailyLossLimit= true;         // Limite de perdida diaria
input double   InpDailyLossPercent = 3.0;          // Perdida diaria maxima (% del balance)
input int      InpMaxTradesPerDay  = 5;            // Operaciones maximas por dia (0 = sin limite)

//============================ GLOBALS ==============================
CTrade         trade;

int hEmaFastT, hEmaSlowT, hAdxT;          // handles TF tendencia
int hRsiE, hEmaPullE, hAtrE;              // handles TF entrada

double g_point;
int    g_digits;

datetime g_lastBarTime = 0;
datetime g_dayStart    = 0;
double   g_dayStartEquity = 0.0;
int      g_tradesToday  = 0;
bool     g_tradingBlockedToday = false;

// Estado por posicion (para parciales/BE/trailing con referencia de riesgo estable)
struct PosState
{
   ulong  ticket;
   double openPrice;
   double riskDist;       // distancia de riesgo inicial (open -> SL inicial)
   double initialVolume;  // volumen original al abrir
   bool   partialDone;
   bool   beDone;
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

   hEmaFastT = iMA(_Symbol, InpTrendTF, InpEmaFast, 0, MODE_EMA, PRICE_CLOSE);
   hEmaSlowT = iMA(_Symbol, InpTrendTF, InpEmaSlow, 0, MODE_EMA, PRICE_CLOSE);
   hAdxT     = iADX(_Symbol, InpTrendTF, InpAdxPeriod);

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
void OnTick()
{
   HandleNewDay();
   SyncPositionStates();
   ManageOpenPositions();

   datetime curBar = (datetime)SeriesInfoInteger(_Symbol, InpEntryTF, SERIES_LASTBAR_DATE);
   bool newBar = (curBar != g_lastBarTime);
   if(newBar)
      g_lastBarTime = curBar;

   if(InpOnePerBar && !newBar)
      return;

   if(!PassGlobalFilters())
      return;

   if(CountOwnPositions() >= InpMaxPositions)
      return;

   int signal = GetSignal();
   if(signal == 0)
      return;

   OpenTrade(signal);
}

//+------------------------------------------------------------------+
//| Filtros globales: spread, sesion GMT, viernes, limites diarios   |
//+------------------------------------------------------------------+
bool PassGlobalFilters()
{
   if(g_tradingBlockedToday)
      return(false);

   if(InpMaxTradesPerDay > 0 && g_tradesToday >= InpMaxTradesPerDay)
      return(false);

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPoints)
      return(false);

   if(!PassSessionFilter())
      return(false);

   return(true);
}

//+------------------------------------------------------------------+
//| Sesiones en GMT + guarda de viernes                              |
//+------------------------------------------------------------------+
bool PassSessionFilter()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);

   // Hora GMT = hora del servidor - offset del servidor respecto a GMT
   int gmtHour = (dt.hour - InpBrokerGMTOffset + 24) % 24;

   // Guarda de viernes a ultima hora (dia 5 = viernes)
   if(InpAvoidFridayLate && dt.day_of_week == 5 && gmtHour >= InpFridayStopHourGMT)
      return(false);

   if(!InpUseSession)
      return(true);

   bool inSession = false;
   if(InpTradeLondon  && InHourRange(gmtHour, 7, 16))  inSession = true;
   if(InpTradeNewYork && InHourRange(gmtHour, 12, 21)) inSession = true;
   if(InpTradeAsia    && InHourRange(gmtHour, 23, 8))  inSession = true; // cruza medianoche

   return(inSession);
}

bool InHourRange(int hour, int startH, int endH)
{
   if(startH <= endH)
      return(hour >= startH && hour < endH);
   // rango que cruza medianoche (ej. 23 -> 8)
   return(hour >= startH || hour < endH);
}

//+------------------------------------------------------------------+
//| Senal por confluencia: tendencia + regimen + pullback + trigger  |
//+------------------------------------------------------------------+
int GetSignal()
{
   // Indexacion en serie temporal: 0 = vela en formacion, 1 = ultima cerrada, 2 = previa.

   // ---- ATR (TF operativo) ----
   int atrNeed = MathMax(2, InpAtrAvgPeriod + 2);
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(hAtrE, 0, 0, atrNeed, atr) < atrNeed) return(0);
   double atrVal = atr[1];
   if(atrVal <= 0) return(0);

   // ---- Filtro de regimen de volatilidad ----
   if(InpUseVolRegime)
   {
      double sum = 0.0;
      for(int i = 1; i <= InpAtrAvgPeriod; i++)
         sum += atr[i];
      double atrAvg = sum / InpAtrAvgPeriod;
      if(atrAvg > 0)
      {
         if(atrVal < InpAtrMinFactor * atrAvg) return(0); // mercado demasiado plano
         if(atrVal > InpAtrMaxFactor * atrAvg) return(0); // volatilidad extrema/caotica
      }
   }

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
      if(adx[1] < InpAdxMin) return(0);
   }

   if(!upTrend && !downTrend)
      return(0);

   // ---- Datos del TF operativo ----
   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(hRsiE, 0, 0, 3, rsi) < 3) return(0);

   double emaPull[];
   ArraySetAsSeries(emaPull, true);
   if(CopyBuffer(hEmaPullE, 0, 0, 2, emaPull) < 2) return(0);

   double open1  = iOpen(_Symbol, InpEntryTF, 1);
   double close1 = iClose(_Symbol, InpEntryTF, 1);
   double close2 = iClose(_Symbol, InpEntryTF, 2);
   double low1   = iLow(_Symbol, InpEntryTF, 1);
   double high1  = iHigh(_Symbol, InpEntryTF, 1);
   if(close1==0.0 || close2==0.0 || high1<=low1) return(0);

   double range = high1 - low1;

   // ---- CONFLUENCIA de compra ----
   if(upTrend)
   {
      // 1) Pullback real: RSI en zona de retroceso
      bool cPullback = (rsi[1] < InpRsiBuyPullback);
      // 2) Proximidad: el minimo se acerco a la EMA dinamica (dentro de X*ATR)
      bool cProximity = (low1 <= emaPull[1] + InpEntryProxATR * atrVal);
      // 3) No sobre-extension: el cierre no esta demasiado lejos de la EMA
      bool cExtension = (!InpUseOverextension) || ((close1 - emaPull[1]) <= InpMaxExtensionATR * atrVal);
      // 4) Trigger de momentum: vela alcista y RSI girando al alza
      bool cMomentum = (close1 > open1) && (close1 > close2) && (rsi[1] > rsi[2]);
      // 5) Cuerpo fuerte: cierre en la parte alta del rango
      bool cCandle = (!InpUseCandleFilter) || ((close1 - low1) >= InpCandleBodyFrac * range);

      if(cPullback && cProximity && cExtension && cMomentum && cCandle)
         return(+1);
   }
   // ---- CONFLUENCIA de venta ----
   else if(downTrend)
   {
      bool cPullback  = (rsi[1] > InpRsiSellPullback);
      bool cProximity = (high1 >= emaPull[1] - InpEntryProxATR * atrVal);
      bool cExtension = (!InpUseOverextension) || ((emaPull[1] - close1) <= InpMaxExtensionATR * atrVal);
      bool cMomentum  = (close1 < open1) && (close1 < close2) && (rsi[1] < rsi[2]);
      bool cCandle    = (!InpUseCandleFilter) || ((high1 - close1) >= InpCandleBodyFrac * range);

      if(cPullback && cProximity && cExtension && cMomentum && cCandle)
         return(-1);
   }

   return(0);
}

//+------------------------------------------------------------------+
void OpenTrade(int signal)
{
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(hAtrE, 0, 0, 2, atr) < 2) return;
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

   // Validacion de margen: reduce el lote si no hay margen suficiente
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

//+------------------------------------------------------------------+
//| Gestion: parciales, break-even y trailing usando riesgo estable  |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   if(!InpUsePartial && !InpUseBreakEven && !InpUseTrailing)
      return;

   double atr[];
   ArraySetAsSeries(atr, true);
   bool atrOk = (CopyBuffer(hAtrE, 0, 0, 2, atr) >= 2 && atr[1] > 0);
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
      if(idx < 0) continue; // se registra en SyncPositionStates

      long   type  = PositionGetInteger(POSITION_TYPE);
      double openP = g_pos[idx].openPrice;
      double curSL = PositionGetDouble(POSITION_SL);
      double curTP = PositionGetDouble(POSITION_TP);
      double riskDist = g_pos[idx].riskDist;
      if(riskDist <= 0) continue;

      double profitDist = (type == POSITION_TYPE_BUY) ? (bid - openP) : (openP - ask);
      double rMultiple  = profitDist / riskDist;

      // ----- Salida parcial -----
      if(InpUsePartial && !g_pos[idx].partialDone && rMultiple >= InpPartialAtR)
      {
         double closeVol = NormalizeClose(g_pos[idx].initialVolume * (InpPartialPercent/100.0));
         double remaining = PositionGetDouble(POSITION_VOLUME) - closeVol;
         double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
         if(closeVol >= minLot && remaining >= minLot)
         {
            if(trade.PositionClosePartial(ticket, closeVol))
               g_pos[idx].partialDone = true;
         }
         else
         {
            g_pos[idx].partialDone = true; // no se puede partir mas; marcamos hecho
         }
      }

      // Recalcular SL deseado
      double newSL = curSL;

      if(type == POSITION_TYPE_BUY)
      {
         bool wantBE = (InpUseBreakEven && rMultiple >= InpBreakEvenAtR) ||
                       (InpBEAfterPartial && g_pos[idx].partialDone);
         if(wantBE)
         {
            double be = NormalizeDouble(openP + InpBreakEvenLockPts * g_point, g_digits);
            if(be > newSL) newSL = be;
            g_pos[idx].beDone = true;
         }
         if(InpUseTrailing && atrOk && rMultiple >= InpTrailStartAtR)
         {
            double trail = NormalizeDouble(bid - InpTrailAtrMult * atrVal, g_digits);
            if(trail > newSL) newSL = trail;
         }
         if(newSL > curSL && newSL < bid)
            trade.PositionModify(ticket, newSL, curTP);
      }
      else // SELL
      {
         bool wantBE = (InpUseBreakEven && rMultiple >= InpBreakEvenAtR) ||
                       (InpBEAfterPartial && g_pos[idx].partialDone);
         if(wantBE)
         {
            double be = NormalizeDouble(openP - InpBreakEvenLockPts * g_point, g_digits);
            if(curSL == 0.0 || be < newSL) newSL = be;
            g_pos[idx].beDone = true;
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

double NormalizeClose(double vol)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   return(NormalizeLot(vol, lotStep, minLot, maxLot));
}

//+------------------------------------------------------------------+
//| Sincroniza el estado por posicion (registra nuevas, limpia viejas)|
//+------------------------------------------------------------------+
void SyncPositionStates()
{
   // Eliminar estados de posiciones que ya no existen
   for(int i = ArraySize(g_pos)-1; i >= 0; i--)
   {
      if(!PositionSelectByTicket(g_pos[i].ticket))
         RemovePosStateAt(i);
   }

   // Registrar posiciones propias nuevas
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
      g_pos[n].beDone        = false;
   }
}

int FindPosState(ulong ticket)
{
   for(int i = 0; i < ArraySize(g_pos); i++)
      if(g_pos[i].ticket == ticket)
         return(i);
   return(-1);
}

void RemovePosStateAt(int idx)
{
   int n = ArraySize(g_pos);
   if(idx < 0 || idx >= n) return;
   for(int i = idx; i < n-1; i++)
      g_pos[i] = g_pos[i+1];
   ArrayResize(g_pos, n-1);
}

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
      {
         g_tradingBlockedToday = true;
         PrintFormat("Limite de perdida diaria alcanzado (%.2f). Trading bloqueado hoy.", dayLoss);
      }
   }
}

void ResetDailyCounters()
{
   g_dayStartEquity      = AccountInfoDouble(ACCOUNT_EQUITY);
   g_tradesToday         = 0;
   g_tradingBlockedToday = false;
}
//+------------------------------------------------------------------+
