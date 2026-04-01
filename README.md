# Order Block Indicator (Zone 2.0)

TradingView **Pine Script v5** indicator and related **MT5** reference code for drawing and managing order-block style zones after breaks of structure (BOS).

## What this indicator does

The script marks **supply/demand-style zones** on the chart when price **closes through** the last opposite candle’s wick-adjusted level (**BOS**). Several **independent pipelines** can each draw rectangles (and optional labels):

| Piece | Meaning |
|--------|--------|
| **BOS** | **Break of structure**: confirmed close beyond the wick-adjusted high (bullish) or low (bearish) of the **most recent opposite-color** candle. This is what **starts** the clean/multi-clean marker scans. |
| **General OB** | Uses the **last opposite** candle’s zone → confirm → sweep / partial break → “General OB” box. |
| **Clean marker** | Fractal pivot + **take** = close through the pivot’s **wick reference**; optional **invalid-candle** rule (first bar after the 3-bar pattern must not be the wrong color). Wick rule can **cap** the zone to the body when the pivot wick clears the next bar. |
| **Multi clean** | Same fractal idea as Clean but searches a **wider pivot offset** (`mo`). Optional: **prefer the pivot whose take level is crossed first in time** (not only the nearest fractal). **Separate from Break marker** — it still needs a **BOS** in that direction to arm. Optional **skip INV filter** for Multi clean only (matches more manual setups). |
| **Break marker** | Own pipeline: after a BOS **slot**, stack **opposite** wicks → impulse breaks the reference cluster → “Break marker” box. **Not** the same as Multi clean. |
| **Mitigation** | Price **touches** a stored zone → optional mitigated alert; box can be faded or deleted. |
| **HTF touch** | Optional alert when a **completed higher-timeframe** candle’s range overlaps any stored zone. |

**Wick rules:** Zones can be trimmed when a wick **clears the next bar**; pivot candles use a **body-edge** cap when the rule applies.

**Display:** By default, **region guide**, **box name labels**, and **A–D map letters** are off so **boxes stay visible**. Turn them on in settings if you want the legend or Multi clean A/B/C/D mapping.

## Files in this repo

| Path | Description |
|------|-------------|
| `Order Block Indicator(zone2.0)_14.txt` | Pine v5 source — paste into TradingView **Pine Editor** → **Add to chart**. Current title line shows the version (e.g. V1.4.26). |
| `mt5/OrderBlockZone2.mq5` | MetaTrader 5 EA/indicator port (same concept family; not auto-synced with Pine). |
| `img/chart.PNG` | Optional screenshot for documentation. |

## How to use (TradingView)

1. Open **Pine Editor** → create indicator → paste contents of `Order Block Indicator(zone2.0)_14.txt`.
2. **Save** / **Add to chart**.
3. Adjust **inputs** (marker modes, distance in pips, Multi clean options, mitigation, HTF alerts).

## Requirements

- TradingView plan that supports the script’s **max boxes / labels / bars back** (see `indicator(...)` in the Pine file).

## License

Use and modify as needed for your own trading; no warranty is implied.
