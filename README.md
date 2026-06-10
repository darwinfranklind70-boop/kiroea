# ProfitEdgeEA — Expert Advisor para MT5 (MQL5) — v2.0

EA de **seguimiento de tendencia multi-timeframe con entradas por confluencia** y
**gestión de riesgo estricta basada en ATR**. Diseñado para ser optimizado y
validado en el Strategy Tester de MetaTrader 5 sobre periodos largos.

## Novedades v2.0 (potenciado)
- **Entradas por confluencia:** ahora exige varias confirmaciones obligatorias
  (pullback + proximidad a EMA + momentum + vela con cuerpo fuerte + no
  sobre-extensión) en vez del OR laxo de la v1 → menos señales, mejor calidad.
- **Salidas parciales + runner:** cierra una parte (ej. 50%) en 1R, mueve a
  break-even y deja correr el resto con trailing → *ganancias que corren,
  pérdidas pequeñas*, justo el objetivo del sistema.
- **Filtro de régimen de volatilidad:** compara el ATR con su media para evitar
  mercados muertos o caóticos.
- **Filtro de sobre-extensión:** no persigue el precio cuando ya está lejos de la EMA.
- **Sesiones normalizadas a GMT** (Londres / NY / Asia) + **guarda de viernes**.
- **Sizing por riesgo más robusto** con validación de margen libre.

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

2. **Entrada por CONFLUENCIA (timeframe operativo, p. ej. H1/M15)**
   Para entrar a favor de la tendencia exige **todas** estas condiciones (v2.0):
   - **Pullback**: el RSI entró en zona de retroceso.
   - **Proximidad**: el precio se acercó a la EMA dinámica (dentro de X·ATR).
   - **No sobre-extensión**: el cierre no está demasiado lejos de la EMA.
   - **Momentum**: vela que reanuda la dirección + RSI girando a favor.
   - **Cuerpo fuerte**: el cierre queda en la parte alta/baja del rango de la vela.

   Exigir varias confirmaciones a la vez reduce las señales de baja calidad.

3. **Riesgo, parciales y gestión (ATR)**
   - **SL = k × ATR** → el stop se adapta a la volatilidad real del mercado.
   - **TP del runner = RR × distancia del SL** → ratio riesgo/beneficio amplio.
   - **Salida parcial**: cierra un % en 1R y pasa el resto a break-even.
   - **Sizing por % de riesgo** con validación de margen libre.
   - **Break-even** y **trailing stop** (ATR) para proteger y dejar correr.
   - **Régimen de volatilidad**, **límite de pérdida diaria** y **máx. trades/día**.

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
| Tendencia | `InpEmaFast` / `InpEmaSlow` | EMAs de tendencia (50 / 200) |
| | `InpUseAdxFilter` / `InpAdxMin` | Filtro de fuerza de tendencia |
| Entrada | `InpRsiPeriod` / `InpRsiBuyPullback` / `InpRsiSellPullback` | Zona de pullback |
| | `InpPullbackEmaPeriod` / `InpEntryProxATR` | EMA dinámica y proximidad (×ATR) |
| | `InpUseCandleFilter` / `InpCandleBodyFrac` | Vela de confirmación con cuerpo fuerte |
| Régimen | `InpUseVolRegime` / `InpAtrAvgPeriod` | Filtro de volatilidad (ATR vs media) |
| | `InpAtrMinFactor` / `InpAtrMaxFactor` | Rango de volatilidad permitido |
| | `InpUseOverextension` / `InpMaxExtensionATR` | Evitar perseguir el precio |
| Riesgo | `InpSlAtrMult` | SL = mult × ATR |
| | `InpTpRR` | TP del runner = RR × distancia del SL |
| | `InpUseRiskPercent` / `InpRiskPercent` | Riesgo % por operación |
| | `InpFixedLot` | Lote fijo (si no se usa % de riesgo) |
| Parciales | `InpUsePartial` / `InpPartialAtR` / `InpPartialPercent` | Salida parcial en 1R |
| | `InpBEAfterPartial` | Pasar a break-even tras el parcial |
| Gestión | `InpUseBreakEven` / `InpBreakEvenAtR` | Mover a break-even |
| | `InpUseTrailing` / `InpTrailAtrMult` / `InpTrailStartAtR` | Trailing stop |
| Sesión | `InpUseSession` / `InpBrokerGMTOffset` | Sesiones en GMT |
| | `InpTradeLondon` / `InpTradeNewYork` / `InpTradeAsia` | Sesiones activas |
| | `InpAvoidFridayLate` / `InpFridayStopHourGMT` | Guarda de viernes |
| Límites | `InpUseDailyLossLimit` / `InpDailyLossPercent` | Stop diario |
| | `InpMaxTradesPerDay` | Máx. operaciones por día |

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

### Sugerencia de rangos de optimización
| Parámetro | Inicio | Paso | Fin |
|-----------|--------|------|-----|
| `InpSlAtrMult` | 1.0 | 0.2 | 3.0 |
| `InpTpRR` | 1.5 | 0.2 | 3.5 |
| `InpAdxMin` | 15 | 2 | 30 |
| `InpRsiBuyPullback` | 35 | 5 | 50 |
| `InpEmaFast` | 20 | 10 | 60 |

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
