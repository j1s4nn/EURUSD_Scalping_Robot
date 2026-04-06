# EURUSD Scalper Pro — Setup Guide

## ✅ Your PC is more than capable
AMD Ryzen 7 5800H + RTX 3060 → YES, handles this easily.

---

## 📁 Project Structure

```
EURUSD_Scalping_Robot/
│
├── mt5_ea/
│   └── EURUSD_Scalper_Pro.mq5     ← Upload to MT5 (Step 1)
│
├── python_tools/
│   └── download_data.py           ← Run to download data (Step 3)
│
├── data/                          ← Auto-created when you run downloader
│
├── requirements.txt               ← Python packages (Step 2)
└── README.md                      ← This file
```

---

## 🚀 Installation Order (Follow Exactly)

### STEP 1 — Install the MT5 Expert Advisor
1. Open **MetaTrader 5**
2. Go to **File → Open Data Folder**
3. Navigate to: `MQL5\Experts\`
4. **Copy** `mt5_ea/EURUSD_Scalper_Pro.mq5` into that folder
5. In MT5, open **MetaEditor** (press `F4`)
6. Open `EURUSD_Scalper_Pro.mq5` and press `F7` to compile
7. Fix any errors shown (usually none)

### STEP 2 — Install Python requirements
Open **Command Prompt** or **PowerShell** and run:
```
pip install -r requirements.txt
```

### STEP 3 — Download Historical Data
1. Make sure MT5 is **open and logged into your Exness account**
2. Run:
```
python python_tools/download_data.py
```
3. Data CSVs will be saved in the `data/` folder

### STEP 4 — Attach EA to Chart
1. In MT5, open an **EURUSD M5** chart
2. In the Navigator panel, find `EURUSD_Scalper_Pro` under Expert Advisors
3. Drag it onto the chart
4. A settings window appears — adjust inputs or leave defaults
5. Make sure **"Allow Algo Trading"** is enabled (green robot icon in toolbar)

### STEP 5 — Backtest (Recommended before live)
1. In MT5 go to **View → Strategy Tester** (`Ctrl+R`)
2. Select `EURUSD_Scalper_Pro`
3. Symbol: `EURUSD`, Timeframe: `M5`
4. Date range: last 6–12 months
5. Model: **Every tick based on real ticks** (most accurate)
6. Click **Start**

---

## ⚙️ Key Settings Explained

| Setting | Default | What it does |
|---|---|---|
| RiskPercent | 1.5% | % of balance risked per trade |
| StrongTrendBoost | 2.5x | Multiplies lot on high-confidence signals |
| MinSignalScore | 4 / 7 | How many indicators must agree |
| ATR_SL_Mult | 1.5 | Stop loss = 1.5× ATR (dynamic) |
| ATR_TP_Mult | 2.2 | Take profit = 2.2× ATR (dynamic) |
| MaxOpenTrades | 3 | Never more than 3 trades at once |
| TradingHours | 7–20 | London + New York sessions only |

---

## 📊 Strategy Logic Summary

The EA uses **7 confluence signals** — a trade opens only when ≥4 agree:

1. **EMA 8/21 crossover** — trend direction
2. **EMA 50 filter** — only trade with the major trend
3. **RSI 14** — momentum confirmation
4. **MACD** — histogram direction
5. **Bollinger Bands** — mean-reversion entry zones
6. **Stochastic %K/%D** — overbought/oversold
7. **Price momentum** — recent bar direction

**Strong Trend Mode**: When 6–7 signals agree, lot size is boosted automatically.

---

## ⚠️ Important Notes

- Start with a **demo account** first — always
- Exness allows EA trading on all account types
- Minimum recommended balance: $100 (with 0.01 lot min)
- The EA targets $3–5/day profit on small accounts through controlled compounding
- News events can spike price — consider pausing during major USD/EUR news

---

## 🛠️ Troubleshooting

**EA not trading?**
- Check "Allow Algo Trading" button in MT5 toolbar is GREEN
- Check EA is attached to M5 chart (not M1 or H1)
- Check "AutoTrading" is enabled in Tools → Options → Expert Advisors

**Python script errors?**
- Make sure MT5 terminal is open and logged in first
- Run `pip install MetaTrader5 pandas numpy` manually if needed
