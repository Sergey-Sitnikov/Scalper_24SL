//+------------------------------------------------------------------+
//|                                                   Scalper_24.mq5 |
//|                                                              SSV |
//|                                                   821654@mail.ru |
//+------------------------------------------------------------------+
#property copyright "SSV"
#property link      "821654@mail.ru"
#property version   "1.00"

#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Expert\Money\MoneyFixedRisk.mqh>
//#include <Expert\Money\MoneyFixedMargin.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\OrderInfo.mqh>

CPositionInfo     m_position;                   // trade position object
CTrade            m_trade;                      // trading object
CSymbolInfo       m_symbol;                     // symbol info object
CAccountInfo      m_account;                    // account info wrapper
CDealInfo         m_deal;
//CMoneyFixedMargin m_money;
CMoneyFixedRisk m_money;
COrderInfo        m_orders;
//---
input bool Allow_trading = true;
//input bool Open_BUY = false;
//input bool Open_SELL = false;
//input int STOP=50;
input int   step_position = 250;
input int   TP = 2000;
input int   SL = 100;
input double   volum = 0.01;
input double   ratio = 2.0;
//input double   risk = 1;
input int      max_pos = 5;
input int      per_K = 5;
input int      per_D = 3;
input int      slow = 3;
input ENUM_TIMEFRAMES    time_stoh = PERIOD_M5;
int      periodMACDfast = 12;
int      periodMACDslow = 9;
int      periodMACDsignal = 26;
input ENUM_TIMEFRAMES    time_macd_fast = PERIOD_M5;
input ENUM_TIMEFRAMES    time_macd = PERIOD_D1;
//input int      время_таймера = 1;
ulong          m_magic = 555;             // magic number
int            handle_iStochastic;      // variable for storing the handle of the iStochastic indicator
int            handle_iMACD;
int            handle_iMACD_fast;

ENUM_ACCOUNT_MARGIN_MODE m_margin_mode;
datetime Time_Old = 0;
MqlTradeResult resultat;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
// EventSetTimer(время_таймера);
   SetMarginMode();
   if(!IsHedging())
     {
      Print("Hedging only!");
      return(INIT_FAILED);
     }
//---
   m_symbol.Name(Symbol());                  // sets symbol name
   if(!m_symbol.RefreshRates())
     {
      Print("Error RefreshRates. Bid=", DoubleToString(m_symbol.Bid(), Digits()),
            ", Ask=", DoubleToString(m_symbol.Ask(), Digits()));
      return(INIT_FAILED);
     }
//---
   m_trade.SetExpertMagicNumber(m_magic);    // sets magic number
//--- tuning for 3 or 5 digits
//int digits_adjust = 1;
//if(m_symbol.Digits() == 3 || m_symbol.Digits() == 5)
//   digits_adjust = 10;

//   ExtStep=InpStep*digits_adjust;
//   ExtProfitFactor= InpProfitFactor * digits_adjust;
//ExtTrailingStop= InpTrailingStop * digits_adjust;

//--- create handle of the indicator iStochastic
   handle_iStochastic = iStochastic(Symbol(), time_stoh, per_K, per_D, slow, MODE_LWMA, STO_CLOSECLOSE);
//--- if the handle is not created
   if(handle_iStochastic == INVALID_HANDLE)
     {
      PrintFormat("Failed to create handle of the iStochastic indicator for the symbol %s/%s, error code %d",
                  Symbol(),
                  EnumToString(Period()),
                  GetLastError());
      //--- the indicator is stopped early
      return(INIT_FAILED);
     }

   handle_iMACD = iMACD(NULL, time_macd, periodMACDfast, periodMACDslow, periodMACDsignal, PRICE_CLOSE);
//--- if the handle is not created
   if(handle_iMACD == INVALID_HANDLE)
     {
      //--- tell about the failure and output the error code
      PrintFormat("Failed to create handle of the iStochastic indicator for the symbol %s/%s, error code %d",
                  Symbol(),
                  EnumToString(Period()),
                  GetLastError());
      //--- the indicator is stopped early
      return(INIT_FAILED);
     }
     
       handle_iMACD_fast = iMACD(NULL, time_macd_fast, periodMACDfast, periodMACDslow, periodMACDsignal, PRICE_CLOSE);
//--- if the handle is not created
   if(handle_iMACD == INVALID_HANDLE)
     {
      //--- tell about the failure and output the error code
      PrintFormat("Failed to create handle of the iStochastic indicator for the symbol %s/%s, error code %d",
                  Symbol(),
                  EnumToString(Period()),
                  GetLastError());
      //--- the indicator is stopped early
      return(INIT_FAILED);
     }

//---

   m_money.Init(GetPointer(m_symbol), _Period, _Point);
// m_money.Percent(risk);

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
//void OnTimer()
void OnTick()
  {
//string comment = "position lock";
//for(int i = max_pos - 1; i >= 0; --i)
//  {
//   comment += "\n" + IntegerToString(MSOP[i].pos) + " " + IntegerToString(MSOP[i].lock_);
//  }
//Comment(comment);

   /*  datetime Time[];
      CopyTime(_Symbol,_Period,0,100,Time);
      ArraySetAsSeries(Time,true);
       if(Time[0]!=Time_Old)
        {
         Time_Old=Time[0];*/

   static datetime prev_time = 0;
   datetime time_0 = iTime(0);
   if(prev_time == time_0)
      return;
   prev_time = time_0;

   ResetLastError();

   if(!RefreshRates())
      return;
   bool allow_step_buy = true;
   bool allow_step_sell = true;
   bool allow_step = false;
   string signal_MACD = SignalMACD(handle_iMACD);
   string signal_MACD_fast = SignalMACD(handle_iMACD_fast);
   string signal_Stohastic = SignalStohastic();

   int count = 0;

   for(int j = PositionsTotal() - 1; j >= 0; --j)
     {
      m_position.SelectByIndex(j);
      if(m_position.Magic() != m_magic || m_position.Symbol() != Symbol())
         continue;
      ++count;

      if(m_position.PositionType() == POSITION_TYPE_BUY)
        {
         if(allow_step_buy == true)
            if(m_symbol.Ask() < m_position.PriceOpen() + step_position * _Point &&
               m_symbol.Ask() > m_position.PriceOpen() - step_position * _Point)
               allow_step_buy = false;
         //   Print("buy ", allow_step_buy);
         double tp = m_position.PriceOpen() + TP * _Point;
         if(m_position.Profit() > 0)
           {
            if(SignalStohastic() == "sell" && m_symbol.Bid() > tp)
              {
               m_trade.PositionClose(m_position.Ticket());
               continue;
              }
           }
         else
           {
            double sl = m_position.PriceOpen() - SL * _Point;
            if(m_symbol.Ask() < sl)
              {
               double v = m_position.Volume();
               m_trade.PositionClose(m_position.Ticket());
               if(signal_MACD == "sell")
                  m_trade.Sell(v * ratio);
               else
                  m_trade.Buy(v * ratio);
               continue;
              }
           }
        }

      if(m_position.PositionType() == POSITION_TYPE_SELL)
        {
         if(allow_step_sell == true)
            if(m_symbol.Bid() < m_position.PriceOpen() + step_position * _Point &&
               m_symbol.Bid() > m_position.PriceOpen() - step_position * _Point)
               allow_step_sell = false;
         double tp = m_position.PriceOpen() - TP * _Point;
         if(m_position.Profit() > 0)
           {
            if(SignalStohastic() == "buy" && m_symbol.Ask() < tp)
              {
               m_trade.PositionClose(m_position.Ticket());
               continue;
              }
           }
         else
           {
            double sl = m_position.PriceOpen() + SL * _Point;
            if(m_symbol.Bid() > sl)
              {
               double v = m_position.Volume();
               m_trade.PositionClose(m_position.Ticket());
               if(signal_MACD == "buy")
                  m_trade.Buy(v * ratio);
               else
                  m_trade.Sell(v * ratio);
               continue;
              }
           }
        }
     }
   if(count < max_pos)
      allow_step = true;

   if(Allow_trading && allow_step)
     {
   //   if(signal_MACD == "buy" && SignalStohastic() == "buy" && allow_step_buy)
      if(signal_MACD == "buy" && signal_MACD_fast == "buy" && allow_step_buy)
        {
         // Print("buy");
         if(!m_trade.Buy(volum))//, NULL, 0, m_symbol.Bid() - SL * _Point, m_symbol.Ask() + TP * _Point))
            PrintFormat("Buy не открыт %d", m_trade.ResultRetcode());
         else
           {
            m_trade.Result(resultat);
            if(resultat.retcode == 10009 && resultat.volume > 0)
              {

              }
           }
        }

      // if(Open_SELL == true && SignalStohastic() == "sell")
      //if(signal_MACD == "sell" && SignalStohastic() == "sell" && allow_step_sell)
      if(signal_MACD == "sell" && signal_MACD_fast == "sell" && allow_step_sell)
        {
         //  string ts = bool
         if(!m_trade.Sell(volum))//, NULL, 0, m_symbol.Ask() + SL * _Point, m_symbol.Bid() - TP * _Point))
            PrintFormat("Sell не открыт %d", m_trade.ResultRetcode());
         else
           {
            m_trade.Result(resultat);
            if(resultat.retcode == 10009 && resultat.volume > 0)
              {

              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Refreshes the symbol quotes data                                 |
//+------------------------------------------------------------------+
bool RefreshRates()
  {
//--- refresh rates
   if(!m_symbol.RefreshRates())
      return(false);
//--- protection against the return value of "zero"
   if(m_symbol.Ask() == 0 || m_symbol.Bid() == 0)
      return(false);
//---
   return(true);
  }

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void SetMarginMode(void)
  {
   m_margin_mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool IsHedging(void)
  {
   return(m_margin_mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
  }
//+------------------------------------------------------------------+
//| Get Time for specified bar index                                 |
//+------------------------------------------------------------------+
datetime iTime(const int index, string symbol = NULL, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT)
  {
   if(symbol == NULL)
      symbol = Symbol();
   if(timeframe == 0)
      timeframe = Period();
   datetime Time[];
   datetime time = 0;
   ArraySetAsSeries(Time, true);
   int copied = CopyTime(symbol, timeframe, index, 1, Time);
   if(copied > 0)
      time = Time[0];
   return(time);
  }
//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
string SignalStohastic()
  {
   double Stochastic_main[];
   double Stochastic_signal[];
   ArraySetAsSeries(Stochastic_main, true);
   ArraySetAsSeries(Stochastic_signal, true);
//--- reset error code
   ResetLastError();
//--- fill a part of the iStochasticBuffer array with values from the indicator buffer that has 0 index
   if(CopyBuffer(handle_iStochastic, 0, 0, 4, Stochastic_main) < 0)
     {
      //--- if the copying fails, tell the error code
      PrintFormat("Failed to copy data from the Stochastic_main, error code %d", GetLastError());
      //--- quit with zero result - it means that the indicator is considered as not calculated
      return("error");
     }

   if(CopyBuffer(handle_iStochastic, 1, 0, 4, Stochastic_signal) < 0)
     {
      //--- if the copying fails, tell the error code
      PrintFormat("Failed to copy data from the Stochastic_signal, error code %d", GetLastError());
      //--- quit with zero result - it means that the indicator is considered as not calculated
      return("error");
     }
   if(Stochastic_main[1] > Stochastic_signal[1] && Stochastic_main[2] < Stochastic_signal[2] && Stochastic_main[1] < 30)// && Stochastic_main[2] < 30)
      return "buy";
   else
      if(Stochastic_main[1] < Stochastic_signal[1] && Stochastic_main[2] > Stochastic_signal[2] && Stochastic_main[1] > 70)// && Stochastic_main[2] >70)
         return"sell";
      else
         return"none";
  }
//+------------------------------------------------------------------+
//|    0 - MAIN_LINE, 1 - SIGNAL_LINE.                                                           |
//+------------------------------------------------------------------+
string SignalMACD(int handle)
  {
   double Macd_m[];
   double Macd_s[];
   ArraySetAsSeries(Macd_m, true);
   ArraySetAsSeries(Macd_s, true);
//--- reset error code
   ResetLastError();
//--- fill a part of the iStochasticBuffer array with values from the indicator buffer that has 0 index
   if(CopyBuffer(handle, 0, 0, 10, Macd_m) < 0)
     {
      //--- if the copying fails, tell the error code
      PrintFormat("Failed to copy data from the iMacd, error code %d", GetLastError());
      //--- quit with zero result - it means that the indicator is considered as not calculated
      return "null";
     }

   if(CopyBuffer(handle, 0, 1, 10, Macd_s) < 0)
     {
      //--- if the copying fails, tell the error code
      PrintFormat("Failed to copy data from the iMacd, error code %d", GetLastError());
      //--- quit with zero result - it means that the indicator is considered as not calculated
      return "null";
     }
   if(Macd_m[1] >= Macd_s[1])
      return "buy";
   if(Macd_m[1] < Macd_s[1])
      return "sell";
   return "null";
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+1111111111111111111111111111111111111111111111
//+------------------------------------------------------------------+
