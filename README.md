# ProfitEdgeEA — Expert Advisor para MT5 (MQL5)

EA de **seguimiento de tendencia multi-timeframe con entradas por pullback** y
**gestión de riesgo estricta basada en ATR**. Diseñado para ser optimizado y
validado en el Strategy Tester de MetaTrader 5 sobre periodos largos.

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

2. **Entrada por pullback (timeframe operativo, p. ej. H1/M15)**
   - Espera un **retroceso** (RSI en zona de pullback o toque de una EMA dinámica)
     *a favor de la tendencia* — comprar barato en alza, vender caro en baja.
   - Confirmación de **momentum** (vela que reanuda la dirección + RSI girando).
   - Esto evita "perseguir" el precio y mejora el ratio riesgo/beneficio.

3. **Riesgo y gestión (ATR)**
   - **SL = k × ATR** → el stop se adapta a la volatilidad real del mercado.
   - **TP = RR × distancia del SL** → ratio riesgo/beneficio positivo (p. ej. 2.2:1),
     clave matemática para que un acierto compense varias pérdidas.
   - **Sizing por % de riesgo**: cada operación arriesga un % fijo del balance,
     calculando el lote a partir de la distancia del SL (riesgo monetario constante).
   - **Break-even** y **trailing stop** para proteger ganancias.
   - **Límite de pérdida diaria** y **máximo de operaciones por día** para evitar
     rachas destructivas.

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
| | `InpPullbackEmaPeriod` | EMA dinámica del retroceso |
| | `InpRequireMomentum` | Exigir confirmación de momentum |
| Riesgo | `InpSlAtrMult` | SL = mult × ATR |
| | `InpTpRR` | TP = RR × distancia del SL |
| | `InpUseRiskPercent` / `InpRiskPercent` | Riesgo % por operación |
| | `InpFixedLot` | Lote fijo (si no se usa % de riesgo) |
| Gestión | `InpUseBreakEven` / `InpBreakEvenAtR` | Mover a break-even |
| | `InpUseTrailing` / `InpTrailAtrMult` / `InpTrailStartAtR` | Trailing stop |
| Límites | `InpUseDailyLossLimit` / `InpDailyLossPercent` | Stop diario |
| | `InpMaxTradesPerDay` | Máx. operaciones por día |
| | `InpUseTimeFilter` / `InpStartHour` / `InpEndHour` | Filtro de sesión |

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
