//+------------------------------------------------------------------+
//|              EURUSD_Scalper_Pro.mq5                              |
//|              Dynamic Lot + Dynamic SL/TP Scalping Robot          |
//+------------------------------------------------------------------+
#property copyright "EURUSD Scalper Pro"
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Indicators\Trend.mqh>

//--- Input Parameters
input group "=== RISK MANAGEMENT ==="
input double   RiskPercent        = 1.5;      // Risk % per trade
input double   MinLotSize         = 0.01;     // Minimum lot size
input double   MaxLotSize         = 1.00;     // Maximum lot size
input double   StrongTrendBoost   = 2.5;      // Lot multiplier on strong trend
input int      MaxOpenTrades      = 3;        // Max simultaneous trades

input group "=== STRATEGY SETTINGS ==="
input int      EMA_Fast           = 8;        // Fast EMA period
input int      EMA_Slow           = 21;       // Slow EMA period
input int      EMA_Trend          = 50;       // Trend EMA period
input int      RSI_Period         = 14;       // RSI period
input int      ATR_Period         = 14;       // ATR period (for SL/TP)
input double   ATR_SL_Mult        = 1.5;      // ATR multiplier for Stop Loss
input double   ATR_TP_Mult        = 2.2;      // ATR multiplier for Take Profit
input int      BB_Period          = 20;       // Bollinger Band period
input double   BB_Dev             = 2.0;      // Bollinger Band deviation
input int      MACD_Fast          = 12;       // MACD fast
input int      MACD_Slow          = 26;       // MACD slow
input int      MACD_Signal        = 9;        // MACD signal

input group "=== FILTERS ==="
input int      MinSignalScore     = 4;        // Min signals to open trade (max 7)
input double   MinATR_Pips        = 3.0;      // Minimum ATR in pips to trade
input int      TradingStartHour   = 7;        // London open
input int      TradingEndHour     = 20;       // NY close
input bool     UseNewsFilter      = false;    // Pause near news (manual)

input group "=== TRAILING STOP ==="
input bool     UseTrailingStop    = true;     // Enable trailing stop
input double   TrailingATR_Mult   = 1.0;      // Trailing stop ATR multiplier

//--- Global variables
CTrade         trade;
CPositionInfo  pos;

int    handleEMA_Fast, handleEMA_Slow, handleEMA_Trend;
int    handleRSI, handleATR, handleBB, handleMACD, handleStoch;

double atrValue, emaFast[], emaSlow[], emaTrend[];
double rsiVal[], bbUpper[], bbLower[], bbMiddle[];
double macdMain[], macdSignal[];
double stochMain[], stochSignal[];

datetime lastBarTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(202401);
   trade.SetDeviationInPoints(10);
   trade.SetTypeFilling(ORDER_FILLING_FOK);

   handleEMA_Fast  = iMA(_Symbol, PERIOD_M5, EMA_Fast,  0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Slow  = iMA(_Symbol, PERIOD_M5, EMA_Slow,  0, MODE_EMA, PRICE_CLOSE);
   handleEMA_Trend = iMA(_Symbol, PERIOD_M5, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI       = iRSI(_Symbol, PERIOD_M5, RSI_Period, PRICE_CLOSE);
   handleATR       = iATR(_Symbol, PERIOD_M5, ATR_Period);
   handleBB        = iBands(_Symbol, PERIOD_M5, BB_Period, 0, BB_Dev, PRICE_CLOSE);
   handleMACD      = iMACD(_Symbol, PERIOD_M5, MACD_Fast, MACD_Slow, MACD_Signal, PRICE_CLOSE);
   handleStoch     = iStochastic(_Symbol, PERIOD_M5, 5, 3, 3, MODE_SMA, STO_LOWHIGH);

   ArraySetAsSeries(emaFast,    true);
   ArraySetAsSeries(emaSlow,    true);
   ArraySetAsSeries(emaTrend,   true);
   ArraySetAsSeries(rsiVal,     true);
   ArraySetAsSeries(bbUpper,    true);
   ArraySetAsSeries(bbLower,    true);
   ArraySetAsSeries(bbMiddle,   true);
   ArraySetAsSeries(macdMain,   true);
   ArraySetAsSeries(macdSignal, true);
   ArraySetAsSeries(stochMain,  true);
   ArraySetAsSeries(stochSignal,true);

   if(handleEMA_Fast == INVALID_HANDLE || handleEMA_Slow == INVALID_HANDLE ||
      handleRSI == INVALID_HANDLE || handleATR == INVALID_HANDLE)
   {
      Print("ERROR: Failed to create indicator handles!");
      return INIT_FAILED;
   }

   Print("EURUSD Scalper Pro initialized successfully.");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   IndicatorRelease(handleEMA_Fast);
   IndicatorRelease(handleEMA_Slow);
   IndicatorRelease(handleEMA_Trend);
   IndicatorRelease(handleRSI);
   IndicatorRelease(handleATR);
   IndicatorRelease(handleBB);
   IndicatorRelease(handleMACD);
   IndicatorRelease(handleStoch);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   // Only run on new M5 bar
   datetime currentBar = iTime(_Symbol, PERIOD_M5, 0);
   if(currentBar == lastBarTime) return;
   lastBarTime = currentBar;

   // Time filter
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   if(dt.hour < TradingStartHour || dt.hour >= TradingEndHour) return;

   // Load indicator values
   if(!LoadIndicators()) return;

   // Manage existing trades (trailing stop)
   if(UseTrailingStop) ManageTrailingStop();

   // Check max trades
   if(CountOpenTrades() >= MaxOpenTrades) return;

   // ATR filter - avoid low volatility
   double atrPips = atrValue / _Point / 10.0;
   if(atrPips < MinATR_Pips) return;

   // Score signals
   int buyScore  = 0;
   int sellScore = 0;
   bool strongTrend = false;

   ScoreSignals(buyScore, sellScore, strongTrend);

   // Execute trades
   if(buyScore >= MinSignalScore && sellScore < MinSignalScore)
      OpenTrade(ORDER_TYPE_BUY, strongTrend);
   else if(sellScore >= MinSignalScore && buyScore < MinSignalScore)
      OpenTrade(ORDER_TYPE_SELL, strongTrend);
}

//+------------------------------------------------------------------+
//| Load all indicator buffers                                        |
//+------------------------------------------------------------------+
bool LoadIndicators()
{
   double atrBuf[1];
   if(CopyBuffer(handleATR,       0, 0, 3, atrBuf)     < 1) return false;
   if(CopyBuffer(handleEMA_Fast,  0, 0, 3, emaFast)    < 1) return false;
   if(CopyBuffer(handleEMA_Slow,  0, 0, 3, emaSlow)    < 1) return false;
   if(CopyBuffer(handleEMA_Trend, 0, 0, 3, emaTrend)   < 1) return false;
   if(CopyBuffer(handleRSI,       0, 0, 3, rsiVal)     < 1) return false;
   if(CopyBuffer(handleBB,        1, 0, 3, bbUpper)    < 1) return false;
   if(CopyBuffer(handleBB,        2, 0, 3, bbLower)    < 1) return false;
   if(CopyBuffer(handleBB,        0, 0, 3, bbMiddle)   < 1) return false;
   if(CopyBuffer(handleMACD,      0, 0, 3, macdMain)   < 1) return false;
   if(CopyBuffer(handleMACD,      1, 0, 3, macdSignal) < 1) return false;
   if(CopyBuffer(handleStoch,     0, 0, 3, stochMain)  < 1) return false;
   if(CopyBuffer(handleStoch,     1, 0, 3, stochSignal)< 1) return false;

   atrValue = atrBuf[0];
   return true;
}

//+------------------------------------------------------------------+
//| Score buy/sell signals across multiple confluences                |
//+------------------------------------------------------------------+
void ScoreSignals(int &buyScore, int &sellScore, bool &strongTrend)
{
   double close = iClose(_Symbol, PERIOD_M5, 1);

   // 1. EMA Cross (Fast > Slow)
   if(emaFast[1] > emaSlow[1] && emaFast[2] <= emaSlow[2]) buyScore++;
   if(emaFast[1] < emaSlow[1] && emaFast[2] >= emaSlow[2]) sellScore++;

   // 2. EMA Trend Filter (price vs EMA50)
   if(close > emaTrend[1] && emaFast[1] > emaSlow[1]) buyScore++;
   if(close < emaTrend[1] && emaFast[1] < emaSlow[1]) sellScore++;

   // 3. RSI
   if(rsiVal[1] > 50 && rsiVal[1] < 70) buyScore++;
   if(rsiVal[1] < 50 && rsiVal[1] > 30) sellScore++;

   // 4. MACD
   if(macdMain[1] > macdSignal[1] && macdMain[1] > 0) buyScore++;
   if(macdMain[1] < macdSignal[1] && macdMain[1] < 0) sellScore++;

   // 5. Bollinger Band (price near lower = buy, near upper = sell)
   double bbRange = bbUpper[1] - bbLower[1];
   if(bbRange > 0)
   {
      double posInBand = (close - bbLower[1]) / bbRange;
      if(posInBand < 0.35) buyScore++;
      if(posInBand > 0.65) sellScore++;
   }

   // 6. Stochastic
   if(stochMain[1] < 30 && stochMain[1] > stochSignal[1]) buyScore++;
   if(stochMain[1] > 70 && stochMain[1] < stochSignal[1]) sellScore++;

   // 7. Momentum (price movement)
   double prevClose = iClose(_Symbol, PERIOD_M5, 2);
   if(close > prevClose && emaFast[1] > emaSlow[1]) buyScore++;
   if(close < prevClose && emaFast[1] < emaSlow[1]) sellScore++;

   // Strong trend: high score AND EMA50 aligned
   strongTrend = (buyScore >= 6 || sellScore >= 6);
}

//+------------------------------------------------------------------+
//| Calculate dynamic lot size                                        |
//+------------------------------------------------------------------+
double CalcLotSize(bool isStrongTrend)
{
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * (RiskPercent / 100.0);
   double slPips    = (atrValue * ATR_SL_Mult) / _Point / 10.0;
   if(slPips <= 0) slPips = 10.0;

   double tickVal   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double minLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);

   if(tickVal == 0 || tickSize == 0) return MinLotSize;

   double pipValue  = (tickVal / tickSize) * _Point * 10;
   double lots      = riskMoney / (slPips * pipValue);

   if(isStrongTrend)
      lots *= StrongTrendBoost;

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(lots, MathMax(minLot, MinLotSize));
   lots = MathMin(lots, MathMin(maxLot, MaxLotSize));

   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Open a trade with dynamic SL/TP                                   |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type, bool strongTrend)
{
   double lot = CalcLotSize(strongTrend);
   double sl, tp, price;
   double slDist = atrValue * ATR_SL_Mult;
   double tpDist = atrValue * ATR_TP_Mult;

   if(type == ORDER_TYPE_BUY)
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      sl    = price - slDist;
      tp    = price + tpDist;
      trade.Buy(lot, _Symbol, price, sl, tp,
                StringFormat("Scalper BUY Lot:%.2f %s", lot, strongTrend ? "[STRONG]" : ""));
   }
   else
   {
      price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl    = price + slDist;
      tp    = price - tpDist;
      trade.Sell(lot, _Symbol, price, sl, tp,
                 StringFormat("Scalper SELL Lot:%.2f %s", lot, strongTrend ? "[STRONG]" : ""));
   }

   if(trade.ResultRetcode() == TRADE_RETCODE_DONE)
      Print(StringFormat("Trade opened: %s Lot:%.2f SL:%.5f TP:%.5f StrongTrend:%s",
            (type == ORDER_TYPE_BUY ? "BUY" : "SELL"), lot, sl, tp,
            (strongTrend ? "YES" : "NO")));
   else
      Print("Trade failed: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Manage trailing stop on open positions                            |
//+------------------------------------------------------------------+
void ManageTrailingStop()
{
   double trailDist = atrValue * TrailingATR_Mult;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Symbol() != _Symbol) continue;
      if(pos.Magic() != 202401) continue;

      double newSL = 0;
      if(pos.PositionType() == POSITION_TYPE_BUY)
      {
         newSL = SymbolInfoDouble(_Symbol, SYMBOL_BID) - trailDist;
         if(newSL > pos.StopLoss() + _Point)
            trade.PositionModify(pos.Ticket(), newSL, pos.TakeProfit());
      }
      else if(pos.PositionType() == POSITION_TYPE_SELL)
      {
         newSL = SymbolInfoDouble(_Symbol, SYMBOL_ASK) + trailDist;
         if(newSL < pos.StopLoss() - _Point || pos.StopLoss() == 0)
            trade.PositionModify(pos.Ticket(), newSL, pos.TakeProfit());
      }
   }
}

//+------------------------------------------------------------------+
//| Count open trades by magic number                                 |
//+------------------------------------------------------------------+
int CountOpenTrades()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(pos.SelectByIndex(i) && pos.Symbol() == _Symbol && pos.Magic() == 202401)
         count++;
   }
   return count;
}
//+------------------------------------------------------------------+
