"""
Monte Carlo Simulation — Strategy A (Slide 9)
1,000 simulations × 50 trades each
Win rate: 61% | Avg win: 2.3R | Avg loss: 1.0R

Can also accept live stats exported from strategy_a_backtest.py:
    python monte_carlo.py --csv trades.csv

Usage:
    python monte_carlo.py
    python monte_carlo.py --csv trades.csv --sims 5000 --trades 50
"""

import argparse
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt

# ── Defaults (from Slide 9 / optimized strategy) ─────────────────────────────
DEFAULT_WIN_RATE  = 0.61
DEFAULT_AVG_WIN_R = 2.3
DEFAULT_AVG_LOSS_R = 1.0
DEFAULT_CAPITAL   = 10_000.0
DEFAULT_RISK_PCT  = 0.015
DEFAULT_N_TRADES  = 50
DEFAULT_N_SIMS    = 1_000
# ─────────────────────────────────────────────────────────────────────────────


def load_stats_from_csv(path: str):
    """Derive win rate and avg R multiples from a trades.csv output."""
    df = pd.read_csv(path)
    if "win" not in df.columns or "pnl" not in df.columns:
        raise ValueError("CSV must have 'win' and 'pnl' columns.")
    wins   = df[df["win"] == True]
    losses = df[df["win"] == False]
    wr     = len(wins) / len(df)
    avg_w  = wins["pnl"].mean()
    avg_l  = losses["pnl"].abs().mean()
    # Normalise to R
    avg_loss_r = 1.0
    avg_win_r  = avg_w / avg_l if avg_l > 0 else DEFAULT_AVG_WIN_R
    print(f"  Loaded from CSV: WR={wr:.1%}  AvgWin={avg_win_r:.2f}R  AvgLoss=1R  n={len(df)}")
    return wr, avg_win_r, avg_loss_r


def simulate(
    win_rate: float,
    avg_win_r: float,
    avg_loss_r: float,
    n_trades: int,
    n_sims: int,
    capital: float,
    risk_pct: float,
    rng: np.random.Generator,
) -> tuple[np.ndarray, list[np.ndarray]]:
    """Vectorised Monte Carlo — returns (final_equities, equity_curves)."""
    # Shape: (n_sims, n_trades) — True = win
    outcomes = rng.random((n_sims, n_trades)) < win_rate
    r_matrix = np.where(outcomes, avg_win_r, -avg_loss_r)

    # Fixed-fraction compounding: equity[t+1] = equity[t] * (1 + risk_pct * R)
    multipliers = 1 + risk_pct * r_matrix          # (n_sims, n_trades)
    equity_curves = np.cumprod(
        np.hstack([np.ones((n_sims, 1)), multipliers]), axis=1
    ) * capital                                      # (n_sims, n_trades+1)

    return equity_curves[:, -1], equity_curves


def max_drawdown(curve: np.ndarray) -> float:
    peak = np.maximum.accumulate(curve)
    dd   = (curve - peak) / peak
    return dd.min()


def print_report(
    final_eq: np.ndarray,
    curves: np.ndarray,
    capital: float,
    n_trades: int,
) -> None:
    returns = (final_eq - capital) / capital * 100
    pcts    = [5, 10, 25, 50, 75, 90, 95]

    print("\n" + "=" * 58)
    print("  MONTE CARLO  —  Strategy A (Optimized)")
    print("=" * 58)
    for p in pcts:
        v  = np.percentile(final_eq, p)
        r  = np.percentile(returns,  p)
        print(f"  {p:>3}th percentile   {r:>+7.1f}%   (${v:>10,.0f})")
    print(f"  {'Mean':<18}   {returns.mean():>+7.1f}%   (${final_eq.mean():>10,.0f})")
    print(f"  {'Std dev':<18}   {returns.std():>7.1f}%")
    print()
    pct_neg  = (final_eq < capital).mean() * 100
    pct_2x   = (final_eq >= 2 * capital).mean() * 100
    pct_3x   = (final_eq >= 3 * capital).mean() * 100
    print(f"  P(loss)          {pct_neg:>5.1f}%  of simulations end negative")
    print(f"  P(2× capital)    {pct_2x:>5.1f}%")
    print(f"  P(3× capital)    {pct_3x:>5.1f}%")
    print()
    # Max consecutive losses (approximate from a sample)
    sample_outcomes = np.random.default_rng(0).random((10_000, n_trades)) < DEFAULT_WIN_RATE
    max_streaks = []
    for row in sample_outcomes:
        streak = best = 0
        for w in row:
            streak = 0 if w else streak + 1
            best   = max(best, streak)
        max_streaks.append(best)
    print(f"  Avg max loss streak      {np.mean(max_streaks):.1f} trades")
    print(f"  P(≥4 consecutive losses) {(np.array(max_streaks) >= 4).mean()*100:.1f}%")
    print(f"  P(≥6 consecutive losses) {(np.array(max_streaks) >= 6).mean()*100:.1f}%")
    print("=" * 58)

    # Verdict
    median_r = np.percentile(returns, 50)
    worst_5  = np.percentile(returns, 5)
    verdict  = "ROBUST" if worst_5 > 0 else "FRAGILE"
    print(f"\n  Verdict: {verdict}")
    print(f"  Median outcome: {median_r:+.1f}% | Worst 5% floor: {worst_5:+.1f}%")


def save_chart(
    final_eq: np.ndarray,
    curves: np.ndarray,
    capital: float,
) -> None:
    returns = (final_eq - capital) / capital * 100
    n_steps = curves.shape[1]
    xs      = range(n_steps)

    fig, axes = plt.subplots(1, 2, figsize=(14, 6), facecolor="#0d0d0d")

    for ax in axes:
        ax.set_facecolor("#0d0d0d")
        ax.tick_params(colors="#aaa")
        for spine in ax.spines.values():
            spine.set_edgecolor("#333")

    # ── Equity fan ───────────────────────────────────────────────────
    ax = axes[0]
    for curve in curves[::10]:
        ax.plot(xs, curve, alpha=0.06, color="#4a9eff", linewidth=0.7)

    for pct, col, lw, label in [
        (5,  "red",     2, "5th pct"),
        (50, "white",   2, "Median"),
        (95, "#00c897", 2, "95th pct"),
    ]:
        vals = [np.percentile(curves[:, i], pct) for i in xs]
        ax.plot(xs, vals, color=col, linewidth=lw, label=label)

    ax.axhline(capital, color="#555", linestyle="--", linewidth=1)
    ax.set_title("Equity Fan — 1,000 Simulations", color="white")
    ax.set_xlabel("Trade #", color="#aaa")
    ax.set_ylabel("Portfolio Value ($)", color="#aaa")
    ax.legend(facecolor="#1a1a1a", labelcolor="white")

    # ── Return histogram ─────────────────────────────────────────────
    ax = axes[1]
    ax.hist(returns, bins=60, color="#4a9eff", edgecolor="none", alpha=0.85)
    ax.axvline(0,              color="red",    linewidth=2,   label="Break-even")
    ax.axvline(returns.mean(), color="white",  linewidth=1.5, linestyle="--",
               label=f"Mean {returns.mean():.0f}%")
    ax.axvline(np.percentile(returns, 5), color="#ff9900", linewidth=1.5, linestyle=":",
               label=f"5th pct {np.percentile(returns, 5):.0f}%")
    ax.set_title("Return Distribution", color="white")
    ax.set_xlabel("Return (%)", color="#aaa")
    ax.set_ylabel("Frequency",  color="#aaa")
    ax.legend(facecolor="#1a1a1a", labelcolor="white")

    plt.tight_layout()
    plt.savefig("monte_carlo.png", dpi=150, facecolor="#0d0d0d")
    plt.close()
    print("\n  Saved: monte_carlo.png")


def main():
    parser = argparse.ArgumentParser(description="Monte Carlo for Strategy A")
    parser.add_argument("--csv",    default=None,               help="Path to trades.csv from backtest")
    parser.add_argument("--sims",   type=int,   default=DEFAULT_N_SIMS,    help="Number of simulations")
    parser.add_argument("--trades", type=int,   default=DEFAULT_N_TRADES,  help="Trades per simulation")
    parser.add_argument("--capital",type=float, default=DEFAULT_CAPITAL,   help="Starting capital")
    parser.add_argument("--risk",   type=float, default=DEFAULT_RISK_PCT,  help="Risk per trade (0.015 = 1.5%)")
    args = parser.parse_args()

    win_rate  = DEFAULT_WIN_RATE
    avg_win_r = DEFAULT_AVG_WIN_R
    avg_loss_r = DEFAULT_AVG_LOSS_R

    if args.csv:
        win_rate, avg_win_r, avg_loss_r = load_stats_from_csv(args.csv)

    print(f"Running {args.sims:,} simulations × {args.trades} trades...")
    print(f"  Win rate={win_rate:.1%}  AvgWin={avg_win_r:.2f}R  AvgLoss={avg_loss_r:.2f}R")

    rng = np.random.default_rng(42)
    final_eq, curves = simulate(
        win_rate, avg_win_r, avg_loss_r,
        args.trades, args.sims,
        args.capital, args.risk, rng,
    )

    print_report(final_eq, curves, args.capital, args.trades)
    save_chart(final_eq, curves, args.capital)

    pd.DataFrame({
        "sim": range(args.sims),
        "final_equity": final_eq,
        "return_pct":   (final_eq - args.capital) / args.capital * 100,
    }).to_csv("monte_carlo_results.csv", index=False)
    print("  Saved: monte_carlo_results.csv")


if __name__ == "__main__":
    main()
