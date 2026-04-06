"""
EURUSD Scalping Robot - Data Downloader
========================================
Downloads EURUSD historical data from MT5 terminal.
Make sure your MT5 terminal is OPEN and LOGGED IN before running this.

Requirements: See requirements.txt
Usage:        python download_data.py
"""

import MetaTrader5 as mt5
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
import os
import time

# ─── CONFIG ────────────────────────────────────────────────────────────────────
SYMBOL         = "EURUSD"
OUTPUT_DIR     = "data"
TIMEFRAMES = {
    "M1":  mt5.TIMEFRAME_M1,
    "M5":  mt5.TIMEFRAME_M5,
    "M15": mt5.TIMEFRAME_M15,
    "H1":  mt5.TIMEFRAME_H1,
    "H4":  mt5.TIMEFRAME_H4,
    "D1":  mt5.TIMEFRAME_D1,
}
YEARS_BACK     = 2       # How many years of data to download
# ───────────────────────────────────────────────────────────────────────────────


def connect_mt5():
    """Initialize and connect to MT5 terminal."""
    print("Connecting to MetaTrader 5...")
    if not mt5.initialize():
        print(f"  ERROR: MT5 initialize() failed — error code: {mt5.last_error()}")
        print("  Make sure MT5 terminal is open and logged in.")
        return False

    account_info = mt5.account_info()
    if account_info is None:
        print("  ERROR: Cannot get account info. Please log in to MT5.")
        mt5.shutdown()
        return False

    print(f"  Connected! Account: {account_info.login}  Server: {account_info.server}")
    print(f"  Balance: ${account_info.balance:.2f}  Leverage: 1:{account_info.leverage}")
    return True


def ensure_symbol(symbol: str) -> bool:
    """Make sure the symbol is available and visible in MT5."""
    info = mt5.symbol_info(symbol)
    if info is None:
        print(f"  ERROR: Symbol {symbol} not found on this broker.")
        return False
    if not info.visible:
        mt5.symbol_select(symbol, True)
        time.sleep(0.5)
    print(f"  Symbol OK: {symbol}  Spread: {info.spread} pts  Digits: {info.digits}")
    return True


def download_timeframe(symbol: str, tf_name: str, tf_code: int,
                        years: int, output_dir: str) -> pd.DataFrame | None:
    """Download OHLCV bars for one timeframe and save to CSV."""
    date_to   = datetime.now()
    date_from = date_to - timedelta(days=years * 365)

    print(f"\n  [{tf_name}] Downloading {symbol} from {date_from.date()} ...")

    rates = mt5.copy_rates_range(symbol, tf_code, date_from, date_to)
    if rates is None or len(rates) == 0:
        print(f"    WARNING: No data returned for {tf_name}. Error: {mt5.last_error()}")
        return None

    df = pd.DataFrame(rates)
    df["time"] = pd.to_datetime(df["time"], unit="s")
    df.rename(columns={
        "time": "datetime",
        "open": "Open",
        "high": "High",
        "low":  "Low",
        "close":"Close",
        "tick_volume": "Volume"
    }, inplace=True)
    df = df[["datetime", "Open", "High", "Low", "Close", "Volume"]]
    df.set_index("datetime", inplace=True)

    os.makedirs(output_dir, exist_ok=True)
    filepath = os.path.join(output_dir, f"{symbol}_{tf_name}.csv")
    df.to_csv(filepath)

    print(f"    Saved {len(df):,} bars  →  {filepath}")
    return df


def add_indicators(df: pd.DataFrame) -> pd.DataFrame:
    """Add basic technical indicators used by the EA for offline analysis."""
    df = df.copy()
    close = df["Close"]

    # EMAs
    df["EMA_8"]  = close.ewm(span=8,  adjust=False).mean()
    df["EMA_21"] = close.ewm(span=21, adjust=False).mean()
    df["EMA_50"] = close.ewm(span=50, adjust=False).mean()

    # RSI
    delta = close.diff()
    gain  = delta.clip(lower=0)
    loss  = -delta.clip(upper=0)
    avg_gain = gain.ewm(com=13, adjust=False).mean()
    avg_loss = loss.ewm(com=13, adjust=False).mean()
    rs  = avg_gain / avg_loss
    df["RSI"] = 100 - (100 / (1 + rs))

    # ATR
    tr = pd.concat([
        df["High"] - df["Low"],
        (df["High"] - close.shift(1)).abs(),
        (df["Low"]  - close.shift(1)).abs()
    ], axis=1).max(axis=1)
    df["ATR"] = tr.ewm(com=13, adjust=False).mean()

    # Bollinger Bands
    df["BB_Mid"]   = close.rolling(20).mean()
    bb_std         = close.rolling(20).std()
    df["BB_Upper"] = df["BB_Mid"] + 2 * bb_std
    df["BB_Lower"] = df["BB_Mid"] - 2 * bb_std

    # MACD
    ema12 = close.ewm(span=12, adjust=False).mean()
    ema26 = close.ewm(span=26, adjust=False).mean()
    df["MACD"]        = ema12 - ema26
    df["MACD_Signal"] = df["MACD"].ewm(span=9, adjust=False).mean()
    df["MACD_Hist"]   = df["MACD"] - df["MACD_Signal"]

    return df


def show_summary(df: pd.DataFrame, tf: str):
    """Print a brief data quality summary."""
    print(f"\n  ── {tf} Summary ──────────────────────────────")
    print(f"  Rows       : {len(df):,}")
    print(f"  Date range : {df.index[0]}  →  {df.index[-1]}")
    print(f"  Null values: {df.isnull().sum().sum()}")
    pct_change = df["Close"].pct_change()
    print(f"  Max 1-bar move : {pct_change.abs().max()*100:.4f}%")
    print(f"  Avg daily range: {(df['High']-df['Low']).mean()*10000:.1f} pips (approx)")
    print(f"  ─────────────────────────────────────────────")


def main():
    print("=" * 55)
    print("  EURUSD Scalping Robot — Data Downloader")
    print("=" * 55)

    if not connect_mt5():
        return

    if not ensure_symbol(SYMBOL):
        mt5.shutdown()
        return

    results = {}
    for tf_name, tf_code in TIMEFRAMES.items():
        df = download_timeframe(SYMBOL, tf_name, tf_code, YEARS_BACK, OUTPUT_DIR)
        if df is not None:
            results[tf_name] = df

    # Add indicators to M5 (main trading timeframe)
    if "M5" in results:
        print("\nAdding technical indicators to M5 data...")
        df_m5_ind = add_indicators(results["M5"])
        ind_path  = os.path.join(OUTPUT_DIR, f"{SYMBOL}_M5_with_indicators.csv")
        df_m5_ind.to_csv(ind_path)
        print(f"  Saved M5 + indicators  →  {ind_path}")
        show_summary(df_m5_ind, "M5")

    mt5.shutdown()

    print("\n✅  Download complete!")
    print(f"   Files saved in: ./{OUTPUT_DIR}/")
    print("\nNext steps:")
    print("  1. Open MT5 terminal.")
    print("  2. Compile EURUSD_Scalper_Pro.mq5 in MetaEditor (F7).")
    print("  3. Attach the EA to the EURUSD M5 chart.")
    print("  4. Run backtests using Strategy Tester in MT5.")


if __name__ == "__main__":
    main()
