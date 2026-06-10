//+------------------------------------------------------------------+
//|                                                 ProfitEdgeEA.mq5  |
//|   v3.0 - Sistema de SCORING tunable (pullback + breakout) con     |
//|   control de drawdown agresivo y R:R mejorado.                    |
//|                                                                  |
//|   POR QUE v3 (corrige el backtest real de v1 y v2):              |
//|   - v1: PF 1.23, drawdown 57%, R:R real ~1.1 -> ganaba pero con   |
//|     riesgo brutal y el trailing cortaba ganadores muy pronto.     |
//|   - v2: demasiados filtros AND -> ~1 operacion/mes.               |
//|                                                                  |
//|   IDEAS CLAVE v3:                                                 |
//|   1) ENTRADAS POR PUNTAJE: cada confirmacion suma puntos; entras  |
//|      si el puntaje >= umbral. La FRECUENCIA se controla con UN     |
//|      solo dial (InpMinScore) -> resuelve v1 (muy laxo) y v2.       |
//|   2) PULLBACK + BREAKOUT: captura retrocesos Y arranques de        |
//|      tendencia (ventaja desde que inicia el movimiento).          |
//|   3) CONTROL DE DRAWDOWN: guarda de DD por equity, sizing          |
//|      defensivo tras rachas perdedoras y filtro de curva de equity. |
//|   4) R:R real mejor: parciales + runner con trailing mas holgado   |
//|      y TP amplio para dejar correr ganadores.                      |
//|                                                                  |
//|   NOTA: Ningun sistema es el "santo grial". Esto maximiza el edge  |
//|   y minimiza el riesgo de ruina. Optimiza walk-forward con costes. |
//+------------------------------------------------------------------+
#property copyright "ProfitEdgeEA"
#property version   "3.00"
#property strict

#include <Trade/Trade.mqh>

//============================ INPUTS ================================
input group "=== General ==="
input long     InpMagic            = 20260610;     // Numero magico
input string   InpComment          = "ProfitEdge3";// Comentario de las ordenes
input int      InpMaxSpreadPoints  = 30;           // Spread maximo (puntos)
input int      InpMaxPositions     = 1;            // Posiciones simultaneas maximas
input bool     InpOnePerBar        = true;         // Maximo una entrada por vela

input group "=== Timeframes ==="
input ENUM_TIMEFRAMES InpTrendTF    = PERIOD_H4;   // TF de tendencia (superior)
input ENUM_TIMEFRAMES InpEntryTF    = PERIOD_H1;   // TF de entrada (operativo)

input group "=== Tendencia (TF superior) - GATE direccional ==="
input int      InpEmaFast          = 50;           // EMA rapida
input int      InpEmaSlow          = 200;          // EMA lenta
input bool     InpUseSlopeFilter   = true;         // Exigir pendiente de la EMA rapida
input int      InpSlopeLookback    = 3;            // Velas para medir pendiente

input group "=== SCORING de entrada (TF operativo) ==="
input double   InpMinScore         = 2.5;          // DIAL DE FRECUENCIA: puntaje minimo para entrar
input int      InpAdxPeriod        = 14;           // Periodo ADX (fuerza de tendencia)
input double   InpAdxMin           = 20.0;         // ADX minimo para sumar su punto
input double   InpWAdx             = 1.0;          // Peso: tendencia fuerte (ADX)
input int      InpRsiPeriod        = 14;           // Periodo RSI
input double   InpRsiBuyPullback   = 45.0;         // RSI < esto = pullback alcista
input double   InpRsiSellPullback  = 55.0;         // RSI > esto = pullback bajista
input double   InpWPullback        = 1.0;          // Peso: pullback (RSI en zona)
input int      InpPullbackEmaPeriod= 20;           // EMA dinamica del pullback
input double   InpEntryProxATR     = 0.60;         // Proximidad a la EMA (mult. ATR)
input double   InpWEmaTouch        = 1.0;          // Peso: precio toco la EMA dinamica
input int      InpBreakoutBars     = 20;           // Velas para el maximo/minimo (breakout)
input double   InpWBreakout        = 2.0;          // Peso: ruptura (arranque de tendencia)
input double   InpCandleBodyFrac   = 0.50;         // Cierre en parte alta/baja del rango
input double   InpWCandle          = 1.0;          // Peso: vela de momentum con cuerpo fuerte
input double   InpWRsiTurn         = 0.5;          // Peso: RSI girando a favor

input group "=== Filtros de Regimen (GATES) ==="
input bool     InpUseVolRegime     = true;         // Filtro de volatilidad (ATR vs media)
input int      InpAtrAvgPeriod     = 50;           // Periodo de la media de ATR
input double   InpAtrMinFactor     = 0.60;         // ATR >= factor*media (evita mercado muerto)
input double   InpAtrMaxFactor     = 3.00;         // ATR <= factor*media (evita caos)
input bool     InpUseOverextension = true;         // Evitar perseguir lejos de la EMA
input double   InpMaxExtensionATR  = 2.5;          // Distancia maxima precio-EMA (mult. ATR)

input group "=== Riesgo (ATR) ==="
input int      InpAtrPeriod        = 14;           // Periodo ATR
input double   InpSlAtrMult        = 2.0;          // SL = mult * ATR
input double   InpTpRR             = 4.0;          // TP del runner = RR * riesgo (amplio)
input bool     InpUseRiskPercent   = true;         // Sizing por % de riesgo
input double   InpRiskPercent      = 1.0;          // Riesgo base por operacion (%)
input double   InpFixedLot         = 0.10;         // Lote fijo (si no se usa % riesgo)

input group "=== Salidas: Parciales + Runner ==="
input bool     InpUsePartial       = true;         // Cerrar parte en el primer objetivo
input double   InpPartialAtR        = 1.5;         // Tomar parcial a >= R (multiplos de riesgo)
input double   InpPartialPercent    = 50.0;        // % del volumen a cerrar en el parcial
input bool     InpBEAfterPartial    = true;        // Mover a break-even tras el parcial
input double   InpBreakEvenLockPts  = 5.0;         // Puntos asegurados en break-even
input bool     InpUseTrailing       = true;        // Trailing stop tras el parcial
input double   InpTrailAtrMult      = 3.0;         // Distancia del trailing = mult * ATR (holgado)
input double   InpTrailStartAtR     = 1.5;         // Iniciar trailing a >= R
input int      InpMaxBarsInTrade     = 0;          // Salida por tiempo (0 = off) en velas del TF

input group "=== CONTROL DE DRAWDOWN ==="
input bool     InpUseDDGuard        = true;        // Guarda de drawdown por equity
input double   InpMaxDDPercent       = 20.0;       // DD maximo desde el pico (%) -> pausa
input double   InpDDResumeFactor     = 0.5;        // Reanuda cuando DD <= maxDD*factor
input double   InpLossRiskDecay      = 0.80;       // Sizing defensivo: riesgo *= decay^rachaPerdedora
input int      InpMaxDecaySteps      = 4;          // Maximos pasos de reduccion de riesgo
input bool     InpUseEquityFilter    = false;      // Operar solo si la curva de equity esta "en forma"
input int      InpEqMaPeriod         = 10;         // Trades para la media de la curva de equity

input group "=== Sesion (GMT) y Limites ==="
input bool     InpUseSession        = false;       // Filtrar por sesiones (GMT)
input int      InpBrokerGMTOffset   = 2;           // Offset del servidor respecto a GMT
input bool     InpTradeLondon       = true;        // Londres (07-16 GMT)
input bool     InpTradeNewYork      = true;        // Nueva York (12-21 GMT)
input bool     InpTradeAsia         = false;       // Asia (23-08 GMT)
input bool     InpAvoidFridayLate   = true;        // No abrir viernes a ultima hora
input int      InpFridayStopHourGMT = 20;          // Hora GMT de corte el viernes
input bool     InpUseDailyLossLimit = true;        // Limite de perdida diaria
input double   InpDailyLossPercent  = 4.0;         // Perdida diaria maxima (%)
input int      InpMaxTradesPerDay   = 6;           // Max operaciones por dia (0 = sin limite)

//============================ GLOBALS ==============================
CTrade   trade;

int hEmaFastT, hEmaSlowT, hAdxT;          // handles TF tendencia
int hRsiE, hEmaPullE, hAtrE;              // handles TF entrada

double g_point;
int    g_digits;

datetime g_lastBarTime = 0;
datetime g_dayStart    = 0;
double   g_dayStartEquity = 0.0;
int      g_tradesToday  = 0;
bool     g_tradingBlockedToday = false;

double   g_peakEquity    = 0.0;
bool     g_ddHalted      = false;
int      g_consecLosses  = 0;
double   g_eqCurve[];     // balance realizado tras cada cierre

struct PosState
{
   ulong    ticket;
   double   openPrice;
   double   riskDist;
   double   initialVolume;
   datetime openTime;
   bool     partialDone;
   bool     beDone;
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

   g_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   ResetDailyCounters();
   return(INIT_SUCCEEDED);
}

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
   UpdateDrawdownState();
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
//| Drawdown guard: pausa el trading si el DD desde el pico es alto  |
//+------------------------------------------------------------------+
void UpdateDrawdownState()
{
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_peakEquity)
      g_peakEquity = eq;

   if(!InpUseDDGuard || g_peakEquity <= 0)
      return;

   double dd = (g_peakEquity - eq) / g_peakEquity * 100.0;

   if(!g_ddHalted && dd >= InpMaxDDPercent)
      g_ddHalted = true;                                   // pausa
   else if(g_ddHalted && dd <= InpMaxDDPercent * InpDDResumeFactor)
      g_ddHalted = false;                                  // reanuda al recuperar
}

//+------------------------------------------------------------------+
bool PassGlobalFilters()
{
   if(g_tradingBlockedToday) return(false);
   if(g_ddHalted)            return(false);

   if(InpMaxTradesPerDay > 0 && g_tradesToday >= InpMaxTradesPerDay)
      return(false);

   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > InpMaxSpreadPoints)
      return(false);

   if(!PassSessionFilter())
      return(false);

   if(InpUseEquityFilter && !EquityCurveInForm())
      return(false);

   return(true);
}

//+------------------------------------------------------------------+
//| Filtro de curva de equity: opera solo si va por encima de su MA  |
//+------------------------------------------------------------------+
bool EquityCurveInForm()
{
   int n = ArraySize(g_eqCurve);
   if(n < InpEqMaPeriod) return(true); // sin datos suficientes, permitir
   double sum = 0.0;
   for(int i = n - InpEqMaPeriod; i < n; i++)
      sum += g_eqCurve[i];
   double ma = sum / InpEqMaPeriod;
   return(g_eqCurve[n-1] >= ma);
}

//+------------------------------------------------------------------+
bool PassSessionFilter()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   int gmtHour = (dt.hour - InpBrokerGMTOffset + 24) % 24;

   if(InpAvoidFridayLate && dt.day_of_week == 5 && gmtHour >= InpFridayStopHourGMT)
      return(false);

   if(!InpUseSession) return(true);

   bool inSession = false;
   if(InpTradeLondon  && InHourRange(gmtHour, 7, 16))  inSession = true;
   if(InpTradeNewYork && InHourRange(gmtHour, 12, 21)) inSession = true;
   if(InpTradeAsia    && InHourRange(gmtHour, 23, 8))  inSession = true;
   return(inSession);
}

bool InHourRange(int hour, int startH, int endH)
{
   if(startH <= endH) return(hour >= startH && hour < endH);
   return(hour >= startH || hour < endH);
}

double HighestHigh(int startShift, int count)
{
   double m = -DBL_MAX;
   for(int i = 0; i < count; i++)
   {
      double h = iHigh(_Symbol, InpEntryTF, startShift + i);
      if(h > m) m = h;
   }
   return(m);
}

double LowestLow(int startShift, int count)
{
   double m = DBL_MAX;
   for(int i = 0; i < count; i++)
   {
      double l = iLow(_Symbol, InpEntryTF, startShift + i);
      if(l < m) m = l;
   }
   return(m);
}

//+------------------------------------------------------------------+
//| Senal por SCORING: GATES direccionales + suma de confirmaciones  |
//+------------------------------------------------------------------+
int GetSignal()
{
   // Serie temporal: 0 = vela en formacion, 1 = ultima cerrada, 2 = previa.

   // ---- ATR + regimen de volatilidad (GATE) ----
   int atrNeed = MathMax(2, InpAtrAvgPeriod + 2);
   double atr[];
   ArraySetAsSeries(atr, true);
   if(CopyBuffer(hAtrE, 0, 0, atrNeed, atr) < atrNeed) return(0);
   double atrVal = atr[1];
   if(atrVal <= 0) return(0);

   if(InpUseVolRegime)
   {
      double sum = 0.0;
      for(int i = 1; i <= InpAtrAvgPeriod; i++) sum += atr[i];
      double atrAvg = sum / InpAtrAvgPeriod;
      if(atrAvg > 0)
      {
         if(atrVal < InpAtrMinFactor * atrAvg) return(0);
         if(atrVal > InpAtrMaxFactor * atrAvg) return(0);
      }
   }

   // ---- Tendencia TF superior (GATE direccional) ----
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
   if(!upTrend && !downTrend) return(0);

   // ---- ADX (fuerza) ----
   double adx[];
   ArraySetAsSeries(adx, true);
   if(CopyBuffer(hAdxT, 0, 0, 2, adx) < 2) return(0);
   bool adxStrong = (adx[1] >= InpAdxMin);

   // ---- Datos TF operativo ----
   double rsi[];
   ArraySetAsSeries(rsi, true);
   if(CopyBuffer(hRsiE, 0, 0, 3, rsi) < 3) return(0);

   double emaPull[];
   ArraySetAsSeries(emaPull, true);
   if(CopyBuffer(hEmaPullE, 0, 0, 2, emaPull) < 2) return(0);

   double open1  = iOpen(_Symbol,  InpEntryTF, 1);
   double close1 = iClose(_Symbol, InpEntryTF, 1);
   double close2 = iClose(_Symbol, InpEntryTF, 2);
   double low1   = iLow(_Symbol,   InpEntryTF, 1);
   double high1  = iHigh(_Symbol,  InpEntryTF, 1);
   if(close1==0.0 || close2==0.0 || high1<=low1) return(0);
   double range = high1 - low1;

   // ============ COMPRA ============
   if(upTrend)
   {
      // GATE: no perseguir si esta sobre-extendido
      if(InpUseOverextension && (close1 - emaPull[1]) > InpMaxExtensionATR * atrVal)
         return(0);

      double score = 0.0;
      if(adxStrong)                                              score += InpWAdx;
      if(rsi[1] < InpRsiBuyPullback)                             score += InpWPullback;
      if(low1 <= emaPull[1] + InpEntryProxATR * atrVal)          score += InpWEmaTouch;
      if(close1 > HighestHigh(2, InpBreakoutBars))               score += InpWBreakout; // ruptura
      if(close1 > open1 && (close1 - low1) >= InpCandleBodyFrac*range) score += InpWCandle;
      if(rsi[1] > rsi[2])                                        score += InpWRsiTurn;

      // Trigger minimo: la vela de senal debe ser alcista (evita comprar velas rojas)
      bool trigger = (close1 > open1) || (close1 > close2);
      if(score >= InpMinScore && trigger)
         return(+1);
   }
   // ============ VENTA ============
   else if(downTrend)
   {
      if(InpUseOverextension && (emaPull[1] - close1) > InpMaxExtensionATR * atrVal)
         return(0);

      double score = 0.0;
      if(adxStrong)                                              score += InpWAdx;
      if(rsi[1] > InpRsiSellPullback)                            score += InpWPullback;
      if(high1 >= emaPull[1] - InpEntryProxATR * atrVal)         score += InpWEmaTouch;
      if(close1 < LowestLow(2, InpBreakoutBars))                 score += InpWBreakout;
      if(close1 < open1 && (high1 - close1) >= InpCandleBodyFrac*range) score += InpWCandle;
      if(rsi[1] < rsi[2])                                        score += InpWRsiTurn;

      bool trigger = (close1 < open1) || (close1 < close2);
      if(score >= InpMinScore && trigger)
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

   double riskPct = EffectiveRiskPercent();
   double lots = CalcLotSize(slDistance, riskPct);
   if(lots <= 0) return;

   bool ok = (signal > 0) ? trade.Buy(lots, _Symbol, price, sl, tp, InpComment)
                          : trade.Sell(lots, _Symbol, price, sl, tp, InpComment);

   if(ok)
      g_tradesToday++;
   else
      PrintFormat("Fallo al abrir orden. retcode=%d (%s)", trade.ResultRetcode(), trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Sizing defensivo: reduce el riesgo tras rachas perdedoras        |
//+------------------------------------------------------------------+
double EffectiveRiskPercent()
{
   double r = InpRiskPercent;
   if(InpLossRiskDecay < 1.0 && g_consecLosses > 0)
   {
      int steps = MathMin(g_consecLosses, InpMaxDecaySteps);
      r *= MathPow(InpLossRiskDecay, steps);
   }
   return(r);
}

double CalcLotSize(double slDistancePrice, double riskPct)
{
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(!InpUseRiskPercent)
      return(NormalizeLot(InpFixedLot, lotStep, minLot, maxLot));

   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (riskPct / 100.0);

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
//| Gestion: parciales, BE, trailing y salida por tiempo             |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   double atr[];
   ArraySetAsSeries(atr, true);
   bool atrOk = (CopyBuffer(hAtrE, 0, 0, 2, atr) >= 2 && atr[1] > 0);
   double atrVal = atrOk ? atr[1] : 0.0;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   int barSec = PeriodSeconds(InpEntryTF);

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

      // ---- Salida por tiempo (trades estancados) ----
      if(InpMaxBarsInTrade > 0 && barSec > 0)
      {
         long barsOpen = (long)((TimeCurrent() - g_pos[idx].openTime) / barSec);
         if(barsOpen >= InpMaxBarsInTrade && rMultiple < InpPartialAtR)
         {
            trade.PositionClose(ticket);
            continue;
         }
      }

      // ---- Parcial ----
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
         bool wantBE = (InpBEAfterPartial && g_pos[idx].partialDone);
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
         bool wantBE = (InpBEAfterPartial && g_pos[idx].partialDone);
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
      g_pos[n].openTime      = (datetime)PositionGetInteger(POSITION_TIME);
      g_pos[n].partialDone   = false;
      g_pos[n].beDone        = false;
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
//| Deteccion de cierres: actualiza racha perdedora y curva de equity|
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD) return;
   if(!HistoryDealSelect(trans.deal)) return;

   long   magic = (long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   string sym   = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   long   entry = (long)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(magic != InpMagic || sym != _Symbol) return;
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY) return;

   double pnl = HistoryDealGetDouble(trans.deal, DEAL_PROFIT)
              + HistoryDealGetDouble(trans.deal, DEAL_SWAP)
              + HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);

   if(pnl < 0.0) g_consecLosses++;
   else if(pnl > 0.0) g_consecLosses = 0;

   int n = ArraySize(g_eqCurve);
   ArrayResize(g_eqCurve, n+1);
   g_eqCurve[n] = AccountInfoDouble(ACCOUNT_BALANCE);
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
