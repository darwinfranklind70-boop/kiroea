# ProfitEdgeEA — Expert Advisor para MT5 (MQL5) — v3.0

EA de tendencia multi-timeframe con **entradas por puntaje (scoring) tunable**,
combinando **pullback + breakout**, y un **control de drawdown agresivo**.
Diseñado para optimizar y validar en el Strategy Tester sobre periodos largos.

## Por qué v3.0 (corrige el backtest real)
El backtest de la v1 mostró: beneficio +690% pero con **drawdown del 57%**,
**profit factor 1.23** y un **R:R real de solo ~1.1** (el trailing cortaba
ganadores demasiado pronto). La v2, al exigir *todas* las confirmaciones a la
vez, operaba ~1 vez al mes. La v3 ataca ambos problemas:

- **Entradas por SCORING:** cada confirmación (ADX, pullback, toque de EMA,
  breakout, vela fuerte, giro de RSI) suma puntos. Entras si el puntaje supera
  `InpMinScore`. **La frecuencia se controla con un solo dial** → ni demasiado
  laxo (v1) ni demasiado restrictivo (v2).
- **Pullback + Breakout:** captura retrocesos *y* arranques de tendencia
  (aprovecha el movimiento desde que inicia).
- **Control de drawdown** (lo que faltaba en v1):
  - **DD Guard:** pausa el trading si el drawdown desde el pico supera un límite,
    y reanuda al recuperarse.
  - **Sizing defensivo:** reduce el riesgo tras rachas perdedoras consecutivas.
  - **Filtro de curva de equity** (opcional): opera solo cuando el sistema está
    "en forma" (su equity por encima de su media).
- **R:R real mejor:** TP amplio (`InpTpRR=4`), parcial a 1.5R y trailing más
  holgado (`InpTrailAtrMult=3`) para dejar correr de verdad a los ganadores.
- **Salida por tiempo** opcional para liberar capital de trades estancados.

> **Aviso honesto:** ningún sistema garantiza rentabilidad en Forex. Este EA
> aporta un *edge* estadístico configurable y un control de riesgo riguroso
> (pérdidas pequeñas y acotadas, ganancias que corren). La rentabilidad real
> depende del par, el periodo, los costes (spread/comisión/swap) y de una buena
> optimización + validación walk-forward. Úsalo primero en cuenta demo.

---

## 1. La metodología (por qué tiene sentido estadístico)

El sistema combina tres capas que filtran el ruido y buscan operar solo cuando
la probabilidad está a favor:

1. **Tendencia (timeframe superior, p. ej. H4/D1)**
   - EMA rápida vs EMA lenta (50 vs 200) define la dirección.
   - Filtro de **pendiente** de la EMA rápida (evita rangos planos).
   - Filtro de **fuerza ADX** (solo opera si hay tendencia real, ADX ≥ umbral).

2. **Entrada por SCORING (timeframe operativo, p. ej. H1/M15)**
   En vez de exigir *todas* las condiciones (v2, muy restrictivo) o solo una
   (v1, muy laxo), cada confirmación **suma puntos** y entras si el total supera
   `InpMinScore`. Confirmaciones (con su peso configurable):
   - **ADX fuerte** (`InpWAdx`): hay tendencia real.
   - **Pullback** (`InpWPullback`): el RSI entró en zona de retroceso.
   - **Toque de EMA** (`InpWEmaTouch`): el precio se acercó a la EMA dinámica.
   - **Breakout** (`InpWBreakout`): ruptura del máx/mín de N velas (arranque).
   - **Vela fuerte** (`InpWCandle`): cierre en la parte alta/baja del rango.
   - **Giro de RSI** (`InpWRsiTurn`): el RSI vuelve a favor de la tendencia.

   **El dial `InpMinScore` controla la frecuencia**: más bajo = más trades,
   más alto = menos pero de mayor calidad. *Gates* obligatorios: dirección de
   la tendencia (TF superior), régimen de volatilidad y no sobre-extensión.

3. **Riesgo, parciales y control de drawdown (ATR)**
   - **SL = k × ATR** y **TP del runner = RR × SL** (RR amplio, ej. 4).
   - **Parcial** a 1.5R + break-even, runner con **trailing holgado** (3×ATR)
     para dejar correr (ataca el R:R real de ~1.1 de la v1).
   - **DD Guard**: pausa el trading si el drawdown desde el pico supera el límite.
   - **Sizing defensivo**: reduce el riesgo tras rachas perdedoras.
   - **Filtro de curva de equity** (opcional), límite diario y máx. trades/día.

### La matemática del edge
Con un ratio riesgo/beneficio `RR` y un porcentaje de acierto `W`, la esperanza
por operación (en múltiplos de riesgo `R`) es:

```
E[R] = W * RR - (1 - W)
```

Ejemplos:
- RR = 2.2, W = 40% → `0.4*2.2 - 0.6 = 0.28R` por trade (positivo).
- RR = 2.0, W = 35% → `0.35*2 - 0.65 = 0.05R` (apenas positivo, frágil).
- RR = 1.0, W = 45% → `0.45 - 0.55 = -0.10R` (negativo).

**Objetivo al optimizar:** maximizar `E[R]` y el *profit factor* manteniendo el
*drawdown* bajo control. Un sistema con menos del 50% de aciertos puede ser muy
rentable si el `RR` es suficientemente alto.

---

## 2. Instalación

1. Copia `MT5/Experts/ProfitEdgeEA.mq5` a la carpeta `MQL5/Experts/` de tu
   instalación de MetaTrader 5 (en MT5: *Archivo → Abrir carpeta de datos →
   MQL5 → Experts*).
2. Abre el archivo en **MetaEditor** y pulsa **Compilar** (F7). Debe compilar sin
   errores y generar `ProfitEdgeEA.ex5`.
3. En MT5, arrastra el EA al gráfico del par deseado o úsalo en el Strategy Tester.

---

## 3. Parámetros principales

| Grupo | Parámetro | Descripción |
|-------|-----------|-------------|
| General | `InpMagic` | Identificador único del EA |
| | `InpMaxSpreadPoints` | No opera si el spread supera este valor |
| | `InpMaxPositions` | Posiciones simultáneas máximas |
| Timeframes | `InpTrendTF` / `InpEntryTF` | TF de tendencia y de entrada |
| Tendencia (gate) | `InpEmaFast` / `InpEmaSlow` | EMAs de tendencia (50 / 200) |
| | `InpUseSlopeFilter` / `InpSlopeLookback` | Pendiente de la EMA rápida |
| **Scoring** | **`InpMinScore`** | **DIAL DE FRECUENCIA: puntaje mínimo para entrar** |
| | `InpAdxMin` / `InpWAdx` | ADX y su peso |
| | `InpRsiBuyPullback` / `InpRsiSellPullback` / `InpWPullback` | Pullback y peso |
| | `InpPullbackEmaPeriod` / `InpEntryProxATR` / `InpWEmaTouch` | Toque de EMA y peso |
| | `InpBreakoutBars` / `InpWBreakout` | Ruptura (Donchian) y peso |
| | `InpCandleBodyFrac` / `InpWCandle` | Vela fuerte y peso |
| | `InpWRsiTurn` | Peso del giro de RSI |
| Régimen (gate) | `InpUseVolRegime` / `InpAtrAvgPeriod` | Filtro de volatilidad (ATR vs media) |
| | `InpAtrMinFactor` / `InpAtrMaxFactor` | Rango de volatilidad permitido |
| | `InpUseOverextension` / `InpMaxExtensionATR` | Evitar perseguir el precio |
| Riesgo | `InpSlAtrMult` / `InpTpRR` | SL = mult×ATR, TP runner = RR×SL |
| | `InpUseRiskPercent` / `InpRiskPercent` / `InpFixedLot` | Tamaño de posición |
| Salidas | `InpUsePartial` / `InpPartialAtR` / `InpPartialPercent` | Parcial (ej. 50% en 1.5R) |
| | `InpBEAfterPartial` / `InpBreakEvenLockPts` | Break-even tras parcial |
| | `InpUseTrailing` / `InpTrailAtrMult` / `InpTrailStartAtR` | Trailing del runner |
| | `InpMaxBarsInTrade` | Salida por tiempo (0 = off) |
| **Drawdown** | **`InpUseDDGuard` / `InpMaxDDPercent` / `InpDDResumeFactor`** | **Pausa por drawdown** |
| | `InpLossRiskDecay` / `InpMaxDecaySteps` | Sizing defensivo tras rachas |
| | `InpUseEquityFilter` / `InpEqMaPeriod` | Filtro de curva de equity |
| Sesión | `InpUseSession` / `InpBrokerGMTOffset` | Sesiones en GMT |
| | `InpTradeLondon` / `InpTradeNewYork` / `InpTradeAsia` | Sesiones activas |
| | `InpAvoidFridayLate` / `InpFridayStopHourGMT` | Guarda de viernes |
| Límites | `InpUseDailyLossLimit` / `InpDailyLossPercent` / `InpMaxTradesPerDay` | Límites diarios |

---

## 4. Backtesting (Strategy Tester de MT5)

1. **Calidad de datos:** usa "Every tick based on real ticks" para resultados
   realistas. Descarga el historial completo del par primero.
2. **Costes reales:** configura **spread real**, comisión y swap de tu bróker.
   Un EA que solo es rentable con spread 0 no sirve.
3. **Periodo largo:** prueba 5–10 años, incluyendo mercados alcistas, bajistas y
   laterales. Los buenos pares para tendencia: EUR/USD, GBP/USD, USD/JPY, XAU/USD.
4. **Métricas a mirar (no solo el beneficio):**
   - *Profit factor* > 1.3 (idealmente > 1.5).
   - *Drawdown* relativo máximo bajo (< 20–25%).
   - Nº de operaciones suficiente (> 100–200) para que sea estadísticamente válido.
   - *Recovery factor* y *Sharpe ratio* altos.
   - Curva de equity estable y creciente, sin saltos por una sola operación.

### Cómo optimizar sin sobre-ajustar (overfitting)
- Optimiza pocos parámetros a la vez (ATR mult, RR, ADX min, RSI pullback).
- Usa **walk-forward**: optimiza en un periodo y valida en otro **no visto**.
- Desconfía de combinaciones que solo brillan en un rango estrecho de valores;
  busca *mesetas* de robustez (zonas amplias donde el sistema sigue siendo rentable).
- Valida en **varios pares** y en **datos out-of-sample**.

### Orden sugerido de optimización (v3)
1. **Primero el dial de frecuencia y el RR** (los de mayor impacto):

| Parámetro | Inicio | Paso | Fin |
|-----------|--------|------|-----|
| `InpMinScore` | 1.5 | 0.5 | 5.0 |
| `InpTpRR` | 2.0 | 0.5 | 6.0 |
| `InpSlAtrMult` | 1.2 | 0.2 | 3.0 |

2. **Luego los pesos y umbrales** del scoring (`InpWBreakout`, `InpWPullback`,
   `InpAdxMin`, `InpRsiBuyPullback`, `InpBreakoutBars`).
3. **Por último el control de drawdown** (`InpMaxDDPercent`, `InpLossRiskDecay`)
   y los parámetros de salida (`InpPartialAtR`, `InpTrailAtrMult`).

> Apunta a **profit factor > 1.4** y **drawdown < 25%** con > 150 operaciones.
> El objetivo es subir el ratio retorno/drawdown (Calmar), no solo el beneficio.

---

## 5. Recomendaciones de gestión
- Empieza con `InpRiskPercent` entre **0.5% y 1%**. Riesgos altos disparan el drawdown.
- Mantén el límite de pérdida diaria activo para sobrevivir a las malas rachas.
- Valida **siempre** en demo antes de operar en real.

---

## 6. Estructura del repositorio
```
MT5/
  Experts/
    ProfitEdgeEA.mq5   <- código fuente del EA (compilar en MetaEditor)
README.md              <- esta guía
```
