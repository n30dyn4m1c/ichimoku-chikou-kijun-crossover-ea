# 🌥️📈 Ichimoku Chikou-Kijun Cross Alert EA for MT5

A lightweight MetaTrader 5 Expert Advisor that detects Chikou Span (Lagging Line) crossovers against the Kijun-sen line using the Ichimoku indicator. Designed for discretionary or semi-automated traders who want timely alerts of potential momentum shifts across any timeframe or instrument.

---

## 🧰 Tech Stack

- **Platform**: MetaTrader 5  
- **Language**: MQL5  
- **Alert System**: Terminal-based popup alerts  
- **Signal Logic**: Ichimoku-based crossover  
- **Symbol Coverage**: Any MT5 instrument  
- **Timeframes**: All MT5-supported timeframes (M1–MN1)

---

## 🚀 Key Features

- ✅ Detects Chikou Span crossovers over Kijun-sen  
- ✅ Bullish and Bearish alerts  
- ✅ Timeframe-selectable input (multi-timeframe support)  
- ✅ Minimal performance overhead — runs from a single chart  
- ✅ Simple and clean codebase (for learning or extension)  
- 🔜 Optional push/email notifications  
- 🔜 Chart markers and logging to file

---

## 📊 Signal Logic

This EA checks for Ichimoku crossovers as follows:

### 🔼 Bullish Signal
- Chikou Span crosses **above** Kijun-sen from below

### 🔽 Bearish Signal
- Chikou Span crosses **below** Kijun-sen from above

Both are checked on each new candle close of the selected timeframe.

---

## 🗂 Included Files

| File                         | Description                                |
|------------------------------|--------------------------------------------|
| `chikou-kijun-crossover-alert.mq5` | Main EA file with alert-only functionality |

---

## 🛠️ Setup Instructions

1. Launch MetaTrader 5  
2. Press `F4` to open MetaEditor  
3. Copy `chikou-kijun-crossover-alert.mq5` into `MQL5/Experts`  
4. Compile (`Right-click → Compile`)  
5. Open a chart, drag the EA from Navigator  
6. Select your desired timeframe and enable alerts  
7. Enable **Algo Trading**

---

## ⏰ When to Use

- Ideal for scalping or intraday momentum breakouts  
- Works best with volatile pairs (XAUUSD, NAS100, US30 BTCUSD, etc.)  
- Can be used for confirmation alongside other strategies

---

## 📸 Screenshot

To be added.

---

## 🎓 Lessons Learned

- Chikou-Kijun crossovers can be high probability trade signals
- For M1 trades, get bias from M30
- M30 is ideal for swing trading
- Chikou-Kijun crossover is an entry signal.
- Freedom of Chikou to move is important. If the kumo cloud is near, there may be a rejection first. Do not just open a trade at a crossover. Have a checklist to see if the Chikou is free to move.  
- Exit signals:
- Exit option 1: For M1 scalping, 30 pips TP for Gold if in Tokyo or London or trading against the bias. For example, M30 is bearish but the entry signal is bullish on m1. Then just aim for 30 pips TP.
- Exit option 2: price closes beyond Kijun. This is the most ideal exit. In a ranging market, this closure gives time for you to wait for the next crossover, which will be your next trade entry. But note that for trending markets, sometimes there will be two touches to kijun before the real reversal. Check the angle of the cloud, if it is 45 degrees then you are in a trending market.
- Exit option 3: price closes beyond Tenkan. This is for large spikes, where there will be an extreme pullback.
- Exit option 4: Chikou crosses the Kijun again. This is the most lagging exit signal. Potential profits may be lost with this exit. 
- Arbitrary stop losses will need to be placed depending on risk. M30 swings can have a larger SL until at a few hours later.

---

## 🎯 Future Improvements

- 🧠 Add Kumo (cloud) filter for stronger signal confirmation  
- 📩 Push/mobile/email notifications  
- 🎯 Chart arrows on crossover bars  
- 🗃️ Signal logging to `.csv` for journaling  
- 📊 Visual dashboard of crossover status per pair

---

## 📝 License & Acknowledgments

- © 2025 **Neo Malesa** – [@n30dyn4m1c on X](https://www.x.com/n30dyn4m1c)  
- Made for MT5 technical traders  
- Strategy inspired by classic Ichimoku theory
- Recommended reading: 'Trading with Ichimoku - A Practical Guide', by Karen Péloille 

---
