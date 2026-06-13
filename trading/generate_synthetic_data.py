"""
Synthetic BTC/USDT daily OHLCV generator.
Uses GBM with BTC-calibrated parameters + realistic halving cycles.
Outputs: btc_synthetic.csv
"""

import numpy as np
import pandas as pd
from datetime import datetime, timedelta

np.random.seed(42)

START_DATE   = datetime(2015, 1, 1)
END_DATE     = datetime(2025, 6, 1)
START_PRICE  = 250.0

# BTC halving dates (approx) and post-halving regime shifts
HALVING_DATES = [
    datetime(2016, 7, 9),
    datetime(2020, 5, 11),
    datetime(2024, 4, 19),
]

def generate_ohlcv(start: datetime, end: datetime, start_price: float) -> pd.DataFrame:
    dates = pd.date_range(start, end, freq="D")
    n     = len(dates)

    # Daily drift/vol that shifts by regime (bull/bear cycles)
    base_drift = 0.0015     # ~70% annual in bull
    base_vol   = 0.035      # daily vol
    bear_drift = -0.003
    bear_vol   = 0.05

    # Regimes: rough bear years for BTC
    bear_periods = [
        (datetime(2018, 1, 1), datetime(2018, 12, 31)),
        (datetime(2022, 1, 1), datetime(2022, 12, 31)),
    ]

    prices = [start_price]
    for i, d in enumerate(dates[1:], 1):
        in_bear = any(bs <= d <= be for bs, be in bear_periods)
        mu  = bear_drift if in_bear else base_drift
        sig = bear_vol   if in_bear else base_vol
        # Extra vol around halving dates
        near_halving = any(abs((d - h).days) < 60 for h in HALVING_DATES)
        if near_halving:
            sig *= 1.4
        ret = np.random.normal(mu, sig)
        prices.append(max(prices[-1] * np.exp(ret), 1.0))

    prices = np.array(prices)

    # Generate OHLC from close prices
    daily_range = np.random.uniform(0.01, 0.06, n) * prices   # daily range
    high  = prices + daily_range * np.random.uniform(0.3, 0.9, n)
    low   = prices - daily_range * np.random.uniform(0.3, 0.9, n)
    low   = np.maximum(low, prices * 0.5)  # floor
    open_ = prices * (1 + np.random.normal(0, 0.008, n))
    open_ = np.clip(open_, low, high)

    volume = np.random.lognormal(10, 0.8, n) * (1 + 0.5 * (prices / prices.mean()))

    df = pd.DataFrame({
        "ts":     dates,
        "open":   np.round(open_, 2),
        "high":   np.round(high,  2),
        "low":    np.round(low,   2),
        "close":  np.round(prices, 2),
        "volume": np.round(volume, 2),
    })
    df.set_index("ts", inplace=True)
    return df


if __name__ == "__main__":
    df = generate_ohlcv(START_DATE, END_DATE, START_PRICE)
    df.to_csv("btc_synthetic.csv")
    print(f"Generated {len(df)} daily bars  ({df.index[0].date()} → {df.index[-1].date()})")
    print(f"  Price range: ${df['close'].min():,.0f} → ${df['close'].max():,.0f}")
    print("  Saved: btc_synthetic.csv")
