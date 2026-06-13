"""
Multi-Factor Scoring Model — Slide 5
Factors: Momentum (30%) | Value (20%) | Volatility (25%) | Trend (25%)

Fetches live BTC/USDT daily data, scores today, and prints last 30 days.

Usage:
    pip install ccxt pandas numpy
    python multi_factor.py
    python multi_factor.py --symbol ETH/USDT
    python multi_factor.py --csv                  # export full history to CSV
"""

import argparse
import ccxt
import numpy as np
import pandas as pd
from datetime import datetime, timedelta

# ── Config ───────────────────────────────────────────────────────────────────
DEFAULT_SYMBOL   = "BTC/USDT"
TIMEFRAME        = "1d"
LOOKBACK_DAYS    = 730          # 2 years for percentile normalisation
MOMENTUM_PERIOD  = 90
ATR_PERIOD       = 14
EMA_SHORT        = 21
EMA_MED          = 55
EMA_LONG         = 200

WEIGHTS = {
    "momentum":   0.30,
    "value":      0.20,
    "volatility": 0.25,
    "trend":      0.25,
}

SIGNAL_THRESHOLDS = {
    "FULL": 0.65,
    "HALF": 0.50,
}
# ─────────────────────────────────────────────────────────────────────────────


def fetch_ohlcv(symbol: str, days: int) -> pd.DataFrame:
    exchange = ccxt.binance({"enableRateLimit": True})
    # Fetch extra bars so normalisation window is fully populated
    since_ts = exchange.parse8601(
        (datetime.utcnow() - timedelta(days=days + 250)).strftime("%Y-%m-%dT%H:%M:%SZ")
    )
    all_bars = []
    while True:
        bars = exchange.fetch_ohlcv(symbol, TIMEFRAME, since=since_ts, limit=1000)
        if not bars:
            break
        all_bars.extend(bars)
        since_ts = bars[-1][0] + 1
        if len(bars) < 1000:
            break

    df = pd.DataFrame(all_bars, columns=["ts", "open", "high", "low", "close", "volume"])
    df["ts"] = pd.to_datetime(df["ts"], unit="ms", utc=True).dt.tz_localize(None)
    df.set_index("ts", inplace=True)
    return df[~df.index.duplicated(keep="last")].sort_index()


# ── Factor functions (each returns a 0–1 Series) ─────────────────────────────

def factor_momentum(df: pd.DataFrame) -> pd.Series:
    """90-day ROC percentile-ranked within a rolling 2-year window."""
    roc = df["close"].pct_change(MOMENTUM_PERIOD)
    return roc.rolling(LOOKBACK_DAYS).apply(
        lambda x: float(pd.Series(x).rank(pct=True).iloc[-1]), raw=False
    ).clip(0, 1)


def factor_value(df: pd.DataFrame) -> pd.Series:
    """
    MVRV proxy: score based on price deviation from 200-EMA.
    Deeply discounted (< -10%) = high score; extreme premium (> 50%) = 0.
    """
    ema200 = df["close"].ewm(span=EMA_LONG, adjust=False).mean()
    dev    = (df["close"] - ema200) / ema200
    score  = np.where(dev < -0.10, 1.0,
             np.where(dev <  0.10, 0.6,
             np.where(dev <  0.30, 0.4,
             np.where(dev <  0.50, 0.2, 0.0))))
    return pd.Series(score, index=df.index)


def factor_volatility(df: pd.DataFrame) -> pd.Series:
    """
    Inverse normalised ATR/Close.
    Lower volatility = higher score (safer entry, tighter regime).
    """
    prev  = df["close"].shift(1)
    tr    = pd.concat([
        df["high"] - df["low"],
        (df["high"] - prev).abs(),
        (df["low"]  - prev).abs(),
    ], axis=1).max(axis=1)
    atr       = tr.ewm(span=ATR_PERIOD, adjust=False).mean()
    vol_ratio = atr / df["close"]
    inv_vol   = 1.0 / (vol_ratio + 1e-9)
    lo        = inv_vol.rolling(LOOKBACK_DAYS).min()
    hi        = inv_vol.rolling(LOOKBACK_DAYS).max()
    return ((inv_vol - lo) / (hi - lo + 1e-9)).clip(0, 1)


def factor_trend(df: pd.DataFrame) -> pd.Series:
    """
    EMA alignment:
      EMA21 > EMA55 > EMA200  → 1.0 (full bull)
      Partial alignment        → 0.5
      All inverted             → 0.0
    """
    ema_s = df["close"].ewm(span=EMA_SHORT, adjust=False).mean()
    ema_m = df["close"].ewm(span=EMA_MED,   adjust=False).mean()
    ema_l = df["close"].ewm(span=EMA_LONG,  adjust=False).mean()

    full_bull = (ema_s > ema_m) & (ema_m > ema_l)
    partial   = ((ema_s > ema_m) & (ema_m <= ema_l)) | \
                ((ema_s <= ema_m) & (ema_m > ema_l))

    score = np.where(full_bull, 1.0, np.where(partial, 0.5, 0.0))
    return pd.Series(score, index=df.index)


# ── Composite ─────────────────────────────────────────────────────────────────

def compute_all(df: pd.DataFrame) -> pd.DataFrame:
    d = df.copy()
    d["f_momentum"]   = factor_momentum(d)
    d["f_value"]      = factor_value(d)
    d["f_volatility"] = factor_volatility(d)
    d["f_trend"]      = factor_trend(d)

    d["composite"] = (
        WEIGHTS["momentum"]   * d["f_momentum"]   +
        WEIGHTS["value"]      * d["f_value"]       +
        WEIGHTS["volatility"] * d["f_volatility"]  +
        WEIGHTS["trend"]      * d["f_trend"]
    )

    d["signal"] = np.where(
        d["composite"] >= SIGNAL_THRESHOLDS["FULL"], "FULL",
        np.where(d["composite"] >= SIGNAL_THRESHOLDS["HALF"], "HALF", "CASH")
    )
    return d.dropna()


# ── Output ────────────────────────────────────────────────────────────────────

def print_latest(df: pd.DataFrame, symbol: str) -> None:
    row = df.iloc[-1]
    date = df.index[-1].date()

    signal_color = {
        "FULL": "\033[92m",   # green
        "HALF": "\033[93m",   # yellow
        "CASH": "\033[91m",   # red
    }
    reset = "\033[0m"
    c     = signal_color.get(row["signal"], "")

    print(f"\n{'='*52}")
    print(f"  Multi-Factor Score — {symbol}  [{date}]")
    print(f"{'='*52}")
    print(f"  Momentum   (30%)  {row['f_momentum']:.3f}")
    print(f"  Value      (20%)  {row['f_value']:.3f}")
    print(f"  Volatility (25%)  {row['f_volatility']:.3f}")
    print(f"  Trend      (25%)  {row['f_trend']:.3f}")
    print(f"  {'─'*30}")
    print(f"  COMPOSITE         {row['composite']:.3f}")
    print(f"  SIGNAL      →  {c}{row['signal']}{reset}")
    print(f"{'='*52}")

    allocation = {
        "FULL": "Deploy 100% of allocated capital",
        "HALF": "Deploy 50% of allocated capital",
        "CASH": "Stay in cash — no new longs",
    }
    print(f"\n  Action: {allocation[row['signal']]}")


def print_history(df: pd.DataFrame, n: int = 30) -> None:
    cols = ["f_momentum", "f_value", "f_volatility", "f_trend", "composite", "signal"]
    tail = df[cols].tail(n).copy()
    tail.index = tail.index.date
    tail.columns = ["Mom", "Val", "Vol", "Trend", "Score", "Signal"]
    tail = tail.round(3)
    print(f"\n  Last {n} days:\n")
    print(tail.to_string())


def main():
    parser = argparse.ArgumentParser(description="Multi-factor model scorer")
    parser.add_argument("--symbol", default=DEFAULT_SYMBOL, help="e.g. ETH/USDT")
    parser.add_argument("--history", type=int, default=30, help="Days of history to print")
    parser.add_argument("--csv", action="store_true",      help="Export full score history to CSV")
    args = parser.parse_args()

    print(f"Fetching {args.symbol} daily data ({LOOKBACK_DAYS + 250} days)...")
    df = fetch_ohlcv(args.symbol, LOOKBACK_DAYS)
    print(f"  {len(df)} bars  ({df.index[0].date()} → {df.index[-1].date()})")

    print("Computing factor scores...")
    df = compute_all(df)

    print_latest(df, args.symbol)
    print_history(df, args.history)

    if args.csv:
        out = "factor_scores.csv"
        cols = ["f_momentum", "f_value", "f_volatility", "f_trend", "composite", "signal"]
        df[cols].to_csv(out)
        print(f"\n  Saved full history → {out}")


if __name__ == "__main__":
    main()
