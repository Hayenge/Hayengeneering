"""
EMA Trend-Follow Backtest — Optimized (Slide 6)
BTC/USDT 1D | EMA 18/50 + ADX(14) + ATR(10) trailing stop

Usage:
    pip install ccxt pandas numpy matplotlib
    python strategy_a_backtest.py
"""

import ccxt
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from datetime import datetime, timedelta

# ── Config ───────────────────────────────────────────────────────────────────
SYMBOL        = "BTC/USDT"
TIMEFRAME     = "1d"
SINCE_DAYS    = 3650        # ~10 years
CAPITAL       = 10_000.0
RISK_PCT      = 0.015       # 1.5% risk per trade
EMA_FAST      = 18
EMA_SLOW      = 50
EMA_LONG      = 200
ATR_PERIOD    = 10
ADX_PERIOD    = 14
ADX_MIN       = 25.0
RSI_PERIOD    = 14
VOL_AVG_PERIOD = 20
VOL_MULT      = 1.2         # volume must be >= 1.2x average
ATR_STOP_MULT = 1.2         # stop = entry - 1.2*ATR
ATR_BE_MULT   = 1.5         # move stop to BE after +1.5*ATR
ATR_TRAIL_MULT = 1.0        # trail at 1*ATR below close
VOL_SKIP_PCT  = 0.06        # skip if ATR/close > 6%
# ─────────────────────────────────────────────────────────────────────────────


def fetch_ohlcv(symbol: str, timeframe: str, since_days: int) -> pd.DataFrame:
    exchange = ccxt.binance({"enableRateLimit": True})
    since_ts = exchange.parse8601(
        (datetime.utcnow() - timedelta(days=since_days)).strftime("%Y-%m-%dT%H:%M:%SZ")
    )
    all_bars = []
    while True:
        bars = exchange.fetch_ohlcv(symbol, timeframe, since=since_ts, limit=1000)
        if not bars:
            break
        all_bars.extend(bars)
        since_ts = bars[-1][0] + 1
        if len(bars) < 1000:
            break

    df = pd.DataFrame(all_bars, columns=["ts", "open", "high", "low", "close", "volume"])
    df["ts"] = pd.to_datetime(df["ts"], unit="ms", utc=True).dt.tz_localize(None)
    df.set_index("ts", inplace=True)
    df = df[~df.index.duplicated(keep="last")]
    return df.sort_index()


def add_indicators(df: pd.DataFrame) -> pd.DataFrame:
    d = df.copy()

    # EMAs
    d["ema_f"]   = d["close"].ewm(span=EMA_FAST, adjust=False).mean()
    d["ema_s"]   = d["close"].ewm(span=EMA_SLOW, adjust=False).mean()
    d["ema_200"] = d["close"].ewm(span=EMA_LONG, adjust=False).mean()
    d["ema_slope"] = d["ema_200"].diff(5)

    # ATR
    prev_close = d["close"].shift(1)
    tr = pd.concat([
        d["high"] - d["low"],
        (d["high"] - prev_close).abs(),
        (d["low"]  - prev_close).abs(),
    ], axis=1).max(axis=1)
    d["atr"] = tr.ewm(span=ATR_PERIOD, adjust=False).mean()

    # ADX
    up   = d["high"].diff()
    down = -d["low"].diff()
    pdm  = np.where((up > down) & (up > 0), up,   0.0)
    ndm  = np.where((down > up) & (down > 0), down, 0.0)
    atr_s = tr.ewm(span=ADX_PERIOD, adjust=False).mean()
    pdi   = 100 * pd.Series(pdm, index=d.index).ewm(span=ADX_PERIOD, adjust=False).mean() / (atr_s + 1e-9)
    ndi   = 100 * pd.Series(ndm, index=d.index).ewm(span=ADX_PERIOD, adjust=False).mean() / (atr_s + 1e-9)
    dx    = 100 * (pdi - ndi).abs() / (pdi + ndi + 1e-9)
    d["adx"] = dx.ewm(span=ADX_PERIOD, adjust=False).mean()

    # RSI
    delta = d["close"].diff()
    gain  = delta.clip(lower=0).ewm(span=RSI_PERIOD, adjust=False).mean()
    loss  = (-delta.clip(upper=0)).ewm(span=RSI_PERIOD, adjust=False).mean()
    d["rsi"] = 100 - 100 / (1 + gain / (loss + 1e-9))

    # Volume MA & 10-bar high (shift 1 so it's known at entry)
    d["vol_ma"]  = d["volume"].rolling(VOL_AVG_PERIOD).mean()
    d["high_10"] = d["high"].rolling(10).max().shift(1)

    return d.dropna()


def position_mult(adx: float, vol_ratio: float, consecutive_losses: int) -> float:
    """Dynamic sizing multiplier from Slide 10 matrix."""
    m = 1.25 if adx > 35 else 1.0
    if vol_ratio > 0.05:
        m *= 0.75
    if consecutive_losses >= 3:
        m *= 0.25
    elif consecutive_losses >= 2:
        m *= 0.50
    return m


def run_backtest(df: pd.DataFrame):
    trades = []
    equity = CAPITAL
    pos = None          # open position state
    streak = 0          # consecutive losses (for sizing)

    rows = list(df.itertuples())

    for idx, row in enumerate(rows[1:], start=1):
        prev = rows[idx - 1]

        # ── Manage open position ─────────────────────────────────────
        if pos:
            # Promote stop to break-even
            if not pos["be_done"] and row.high >= pos["be_price"]:
                pos["stop"]    = pos["entry"]
                pos["be_done"] = True

            # Trail stop upward
            trail = row.close - ATR_TRAIL_MULT * row.atr
            if trail > pos["stop"]:
                pos["stop"] = trail

            # Check stop hit
            if row.low <= pos["stop"]:
                exit_px = pos["stop"]
                pnl     = (exit_px - pos["entry"]) * pos["size"]
                equity += pnl
                streak  = 0 if pnl > 0 else streak + 1
                trades.append({
                    "entry_date": pos["date"],
                    "exit_date":  row.Index,
                    "entry_px":   pos["entry"],
                    "exit_px":    exit_px,
                    "size":       pos["size"],
                    "pnl":        pnl,
                    "win":        pnl > 0,
                    "equity":     equity,
                })
                pos = None

        # ── Check entry ──────────────────────────────────────────────
        if pos is None:
            ema_cross_now  = prev.ema_f >  prev.ema_s
            ema_cross_prev = rows[idx - 2].ema_f <= rows[idx - 2].ema_s if idx >= 2 else False
            crossover = ema_cross_now and ema_cross_prev

            if crossover:
                vol_ratio = row.atr / row.close
                filters_pass = (
                    row.adx        >= ADX_MIN
                    and 40 <= row.rsi <= 70
                    and row.close   >  row.ema_200
                    and row.ema_slope > 0
                    and row.volume  >= VOL_MULT * row.vol_ma
                    and vol_ratio   <= VOL_SKIP_PCT
                    and row.close   >  row.high_10
                )
                if filters_pass:
                    entry_px  = row.open
                    stop_px   = entry_px - ATR_STOP_MULT * row.atr
                    be_px     = entry_px + ATR_BE_MULT   * row.atr
                    mult      = position_mult(row.adx, vol_ratio, streak)
                    risk_$    = equity * RISK_PCT * mult
                    size      = risk_$ / (ATR_STOP_MULT * row.atr)
                    pos = {
                        "date":    row.Index,
                        "entry":   entry_px,
                        "stop":    stop_px,
                        "be_price": be_px,
                        "be_done": False,
                        "size":    size,
                    }

    # Close any open position at last bar
    if pos and trades == [] or (pos and rows):
        last = rows[-1]
        pnl  = (last.close - pos["entry"]) * pos["size"]
        equity += pnl
        trades.append({
            "entry_date": pos["date"],
            "exit_date":  last.Index,
            "entry_px":   pos["entry"],
            "exit_px":    last.close,
            "size":       pos["size"],
            "pnl":        pnl,
            "win":        pnl > 0,
            "equity":     equity,
        })

    return pd.DataFrame(trades), equity


def print_stats(trades: pd.DataFrame, final_equity: float) -> None:
    if trades.empty:
        print("No trades generated — check filters or data range.")
        return

    wins   = trades[trades["win"]]
    losses = trades[~trades["win"]]
    wr     = len(wins) / len(trades) * 100
    pf     = wins["pnl"].sum() / losses["pnl"].abs().sum() if not losses.empty else float("inf")

    peak   = trades["equity"].cummax()
    dd     = (trades["equity"] - peak) / peak * 100
    mdd    = dd.min()
    total  = (final_equity - CAPITAL) / CAPITAL * 100

    # Approx Sharpe: annual return / annual vol of trade P&Ls
    pnl_pct   = trades["pnl"] / CAPITAL
    sharpe    = (pnl_pct.mean() * len(trades)) / (pnl_pct.std() * np.sqrt(len(trades)) + 1e-9)

    print("\n" + "=" * 52)
    print("  BACKTEST RESULTS — EMA Trend-Follow (Optimized)")
    print("=" * 52)
    print(f"  Trades          {len(trades)}")
    print(f"  Win rate        {wr:.1f}%")
    print(f"  Avg win         ${wins['pnl'].mean():,.2f}")
    print(f"  Avg loss        ${losses['pnl'].mean():,.2f}")
    print(f"  Profit factor   {pf:.2f}")
    print(f"  Sharpe (approx) {sharpe:.2f}")
    print(f"  Max drawdown    {mdd:.1f}%")
    print(f"  Total return    {total:.1f}%")
    print(f"  Final equity    ${final_equity:,.2f}")
    print("=" * 52)


def save_chart(trades: pd.DataFrame) -> None:
    fig, axes = plt.subplots(2, 1, figsize=(13, 7), facecolor="#0d0d0d")

    ax1, ax2 = axes
    for ax in axes:
        ax.set_facecolor("#0d0d0d")
        ax.tick_params(colors="#aaa")
        for spine in ax.spines.values():
            spine.set_edgecolor("#333")

    # Equity curve
    ax1.plot(trades["exit_date"], trades["equity"], color="#00c897", linewidth=2)
    ax1.axhline(CAPITAL, color="#555", linestyle="--", linewidth=1)
    ax1.set_title("Equity Curve", color="white", fontsize=12)
    ax1.set_ylabel("Portfolio ($)", color="#aaa")
    ax1.fill_between(trades["exit_date"], CAPITAL, trades["equity"],
                     where=trades["equity"] >= CAPITAL, alpha=0.12, color="#00c897")
    ax1.fill_between(trades["exit_date"], CAPITAL, trades["equity"],
                     where=trades["equity"] < CAPITAL,  alpha=0.12, color="red")

    # Drawdown
    peak = trades["equity"].cummax()
    dd   = (trades["equity"] - peak) / peak * 100
    ax2.fill_between(trades["exit_date"], 0, dd, color="red", alpha=0.5)
    ax2.set_title("Drawdown (%)", color="white", fontsize=12)
    ax2.set_ylabel("Drawdown %", color="#aaa")
    ax2.set_xlabel("Date", color="#aaa")

    plt.tight_layout()
    plt.savefig("equity_curve.png", dpi=150, facecolor="#0d0d0d")
    plt.close()
    print("  Saved: equity_curve.png")


def main():
    print(f"Fetching {SYMBOL} {TIMEFRAME} ({SINCE_DAYS} days)...")
    df = fetch_ohlcv(SYMBOL, TIMEFRAME, SINCE_DAYS)
    print(f"  {len(df)} bars  ({df.index[0].date()} → {df.index[-1].date()})")

    print("Computing indicators...")
    df = add_indicators(df)

    print("Running backtest...")
    trades, final_equity = run_backtest(df)

    print_stats(trades, final_equity)

    if not trades.empty:
        save_chart(trades)
        trades.to_csv("trades.csv", index=False)
        print("  Saved: trades.csv")


if __name__ == "__main__":
    main()
