# Order Block Indicator (Zone 2.0)

TradingView **Pine Script v5** indicator and related **MT5** reference code for drawing and managing order-block style zones after breaks of structure (BOS).

## What this indicator does

The script marks **supply/demand-style zones** on the chart when price **closes through** the last opposite candle’s wick-adjusted level (**BOS**). Several **independent pipelines** can each draw rectangles (and optional labels):

| Piece | Meaning |
|--------|--------|
| **BOS** | **Break of structure**: confirmed close beyond the wick-adjusted high (bullish) or low (bearish) of the **most recent opposite-color** candle. This is what **starts** the clean/multi-clean marker scans. |
| **General OB** | Uses the **last opposite** candle’s zone → confirm → sweep / partial break → “General OB” box. |
| **Clean marker** | **3-bar straight wick pivot** (middle high/low vs neighbors). **All three** candles must be **strict** impulse (bull: `close > open`, bear: `close < open`). From the **last opposite** candle before the pivot through the current bar, the leg must be **impulse-only** (e.g. no bearish bars in a bullish clean leg); if that fails, **no Clean box** — use **Break marker** instead. **Take** = **confirmed** close through the straight level on a **strict** impulse bar. **INV** still applies (first bar after “candle 3” must not be the wrong color). Zone uses **pivot** wick/body rules (body cap when the pivot wick clears the next bar). Impulse bound = min low / max high from the **straight candle** through the current bar (then updated in WAIT). |
| **Multi clean** | Same **wick fractal** idea as before (middle candle **can** be any color), with a **wider pivot** search (`mo`). Optional **impulse-only after last opposite** via input (`requireImpulseAfterOpp` — **Multi clean only**; Clean always enforces the impulse leg). Optional: **prefer the pivot whose take level is crossed first in time**. **Separate from Break marker** — it still needs a **BOS** in that direction to arm. Optional **skip INV filter** for Multi clean only. |
| **Break marker** | Own pipeline: after a BOS **slot**, stack **opposite** wicks → impulse breaks the reference cluster → “Break marker” box. **Not** the same as Multi clean. |
| **Mitigation** | Price **touches** a stored zone → optional mitigated alert; box can be faded or deleted. |
| **HTF touch** | Optional alert when a **completed higher-timeframe** candle’s range overlaps any stored zone. |

**Wick rules:** Zones can be trimmed when a wick **clears the next bar**; pivot candles use a **body-edge** cap when the rule applies.

**Display:** By default, **region guide**, **box name labels**, and **A–D map letters** are off so **boxes stay visible**. Turn them on in settings if you want the legend or Multi clean A/B/C/D mapping.

## Clean marker examples (schematic)

Reference diagrams (not a live chart): **3-bar straight wick pivot**, **strict** impulse on all three candles, **last opposite** before the pivot, **impulse-only** leg through the take, then a **strict** close through the straight high/low.

**Bullish (demand-style zone)**

![Clean marker bullish example — straight pivot, zone, take](img/clean-marker-bullish-example.png)

**Bearish (supply-style zone)**

![Clean marker bearish example — straight pivot, zone, take](img/clean-marker-bearish-example.png)

## Files in this repo

| Path | Description |
|------|-------------|
| `Order Block Indicator(zone2.0)_14.txt` | Pine v5 source — paste into TradingView **Pine Editor** → **Add to chart**. Current title line shows the version (e.g. V1.4.27). |
| `mt5/OrderBlockZone2.mq5` | MetaTrader 5 indicator port; **Clean marker** logic is aligned with Pine (strict3-candle triple, impulse-only leg, pivot wick zone). Other pipelines follow the same concept family; diff details in source comments / `#property version`. |
| `img/clean-marker-bullish-example.png` | Schematic: bullish clean marker (straight pivot, zone, take). |
| `img/clean-marker-bearish-example.png` | Schematic: bearish clean marker (mirror logic). |
| `img/chart.PNG` | Optional live-style screenshot for documentation. |

## How to use (TradingView)

1. Open **Pine Editor** → create indicator → paste contents of `Order Block Indicator(zone2.0)_14.txt`.
2. **Save** / **Add to chart**.
3. Adjust **inputs** (marker modes, distance in pips, Multi clean options, mitigation, HTF alerts).

## Requirements

- TradingView plan that supports the script’s **max boxes / labels / bars back** (see `indicator(...)` in the Pine file).

## License

Use and modify as needed for your own trading; no warranty is implied.
