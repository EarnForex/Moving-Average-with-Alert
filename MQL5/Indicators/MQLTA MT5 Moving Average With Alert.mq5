#property link          "https://www.earnforex.com/metatrader-indicators/moving-average-alert/"
#property version       "1.03"
#property copyright     "EarnForex.com - 2019-20213"
#property description   "A classic moving average with alerts."
#property description   " "
#property description   "WARNING: Use this software at your own risk."
#property description   "The creator of these plugins cannot be held responsible for any damage or loss."
#property description   " "
#property description   "Find More on www.EarnForex.com"
#property icon          "\\Files\\EF-Icon-64x64px.ico"

#property indicator_chart_window
#property indicator_buffers 1
#property indicator_plots 1
#property indicator_color1 clrRed
#property indicator_type1   DRAW_LINE
#property indicator_width1  1
#property indicator_label1  "Moving Average"

#include <MQLTA ErrorHandling.mqh>
#include <MQLTA Utils.mqh>

enum ENUM_TRADE_SIGNAL
{
    SIGNAL_BUY = 1,    // BUY
    SIGNAL_SELL = -1,  // SELL
    SIGNAL_NEUTRAL = 0 // NEUTRAL
};

enum ENUM_CANDLE_TO_CHECK
{
    CURRENT_CANDLE = 0, // CURRENT CANDLE
    CLOSED_CANDLE = 1   // PREVIOUS CANDLE
};

enum ENUM_MA_METHOD_EXTENDED
{
    EXT_MODE_SMA,  // Simple averaging
    EXT_MODE_EMA,  // Exponential averaging
    EXT_MODE_SMMA, // Smoothed averaging
    EXT_MODE_LWMA, // Linear-weighted averaging
    EXT_MODE_HULL  // Hull MA
};

input string Comment1 = "========================"; // MQLTA Moving Average With Alert
input string IndicatorName = "MQLTA-MAWA";          // Indicator Short Name
input string Comment2 = "========================"; // Indicator Parameters
input int MAPeriod = 25;                            // Moving Average Period
input int MAShift = 0;                              // Moving Average Shift
input ENUM_MA_METHOD_EXTENDED MAMethod = EXT_MODE_SMA; // Moving Average Method
input ENUM_APPLIED_PRICE MAAppliedPrice = PRICE_CLOSE; // Moving Average Applied Price
input ENUM_CANDLE_TO_CHECK CandleToCheck = CURRENT_CANDLE; // Candle To Use For Analysis
input int BarsToScan = 500;                         // Number Of Candles To Analyse
input string Comment_3 = "======================="; // Notification Options
input bool EnableNotify = false;                    // Enable Notifications Feature
input bool SendAlert = true;                        // Send Alert Notification
input bool SendApp = false;                         // Send Notification to Mobile
input bool SendEmail = false;                       // Send Notification via Email
input string Comment_4 = "======================="; // Drawing Options
input bool EnableDrawArrows = true;                 // Draw Signal Arrows
input int ArrowBuy = 241;                           // Buy Arrow Code
input int ArrowSell = 242;                          // Sell Arrow Code
input int ArrowSize = 3;                            // Arrow Size (1-5)

double BufferMA[];

int BufferMAHandle; // Normal MA for all timeframes. In case of Hull MA, will store the p / 2 WMA handle.
int BufferMAHandle2; // Only for Hull MA - second WMA handle.

datetime LastNotificationTime;
ENUM_TRADE_SIGNAL LastNotificationDirection;
double MALevel = 0; // For horizontal line cross signals.
int Shift = 0;

int OnInit()
{
    IndicatorSetString(INDICATOR_SHORTNAME, IndicatorName);

    OnInitInitialization();
    if (!OnInitPreChecksPass())
    {
        return INIT_FAILED;
    }

    InitialiseHandles();
    InitialiseBuffers();

    return INIT_SUCCEEDED;
}

int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
    bool IsNewCandle = CheckIfNewCandle();
    
    int counted_bars = 0;
    if (prev_calculated == 0)
    {
        for (int i = 0; i < rates_total; i++)
        {
            BufferMA[i] = 0;
        }
    }
    if (prev_calculated > 0) counted_bars = prev_calculated - 1;

    if (counted_bars < 0) return -1;
    if (counted_bars > 0) counted_bars--;
    int limit = rates_total - counted_bars;

    if (limit > BarsToScan)
    {
        limit = BarsToScan;
        if (rates_total < BarsToScan + MAPeriod + MAShift) limit = BarsToScan - 2 - MAPeriod - MAShift;
        if (limit <= 0)
        {
            Print("Need more historical data.");
            return 0;
        }
    }
    if (limit > rates_total - 2 - MAPeriod - MAShift) limit = rates_total - 2 - MAPeriod - MAShift;

    if (MAMethod == EXT_MODE_HULL)
    {
        // Do Hull MA calculations.
        if (iHull(-MAShift, limit, BufferMA) <= 0)
        {
            Print("Waiting for data...");
            return 0;
        }
    }
    else
    {
        if (CopyBuffer(BufferMAHandle, 0, -MAShift, limit, BufferMA) <= 0)
        {
            Print("Waiting for data...");
            return 0;
        }
    }

    if ((IsNewCandle) || (prev_calculated == 0))
    {
        if (EnableDrawArrows) DrawArrows(limit);
        CleanUpOldArrows();
    }

    if (EnableDrawArrows) DrawArrow(0);

    if (EnableNotify) NotifyHit();

    return rates_total;
}

void OnDeinit(const int reason)
{
    CleanChart();
}

void OnInitInitialization()
{
    LastNotificationTime = TimeCurrent();
    Shift = CandleToCheck;
}

bool OnInitPreChecksPass()
{
    if (MAPeriod <= 0)
    {
        Print("MA Period should be a positive number.");
        return false;
    }
    if (Bars(Symbol(), PERIOD_CURRENT) < MAPeriod + MAShift)
    {
        Print("Not enough historical candles.");
        return false;
    }
    return true;
}

void CleanChart()
{
    ObjectsDeleteAll(ChartID(), IndicatorName);
}

void InitialiseHandles()
{
    if (MAMethod != EXT_MODE_HULL) // Normal MAs.
    {
        BufferMAHandle = iMA(Symbol(), PERIOD_CURRENT, MAPeriod, MAShift, (ENUM_MA_METHOD)MAMethod, MAAppliedPrice);
    }
    else // Hull MA.
    {
        BufferMAHandle =  iMA(Symbol(), PERIOD_CURRENT, MAPeriod / 2, MAShift, MODE_LWMA, MAAppliedPrice);
        BufferMAHandle2 = iMA(Symbol(), PERIOD_CURRENT, MAPeriod,     MAShift, MODE_LWMA, MAAppliedPrice);
    }    
}

void InitialiseBuffers()
{
    SetIndexBuffer(0, BufferMA, INDICATOR_DATA);
    ArraySetAsSeries(BufferMA, true);
    ArrayInitialize(BufferMA, 0);
    IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
    PlotIndexSetInteger(0, PLOT_SHIFT, MAShift);
    PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0);
}

datetime NewCandleTime = TimeCurrent();
bool CheckIfNewCandle()
{
    if (NewCandleTime == iTime(Symbol(), 0, 0)) return false;
    else
    {
        NewCandleTime = iTime(Symbol(), 0, 0);
        return true;
    }
}

// Check if it is a trade Signla 0 - Neutral, 1 - Buy, -1 - Sell.
ENUM_TRADE_SIGNAL IsSignal(int i)
{
    int j = i + Shift;
    MALevel = BufferMA[j];
    if ((iOpen(Symbol(), Period(), j) < BufferMA[j]) && (iClose(Symbol(), Period(), j) > BufferMA[j])) return SIGNAL_BUY;
    if ((iOpen(Symbol(), Period(), j) > BufferMA[j]) && (iClose(Symbol(), Period(), j) < BufferMA[j])) return SIGNAL_SELL;
    if ((iClose(Symbol(), Period(), j + 1) < BufferMA[j + 1]) && (iClose(Symbol(), Period(), j) > BufferMA[j])) return SIGNAL_BUY;
    if ((iClose(Symbol(), Period(), j + 1) > BufferMA[j + 1]) && (iClose(Symbol(), Period(), j) < BufferMA[j])) return SIGNAL_SELL;

    return SIGNAL_NEUTRAL;
}

void NotifyHit()
{
    if ((!SendAlert) && (!SendApp) && (!SendEmail)) return;
    if ((CandleToCheck == CLOSED_CANDLE) && (iTime(Symbol(), Period(), 0) <= LastNotificationTime)) return;
    ENUM_TRADE_SIGNAL Signal = IsSignal(0);
    if (Signal == SIGNAL_NEUTRAL)
    {
        LastNotificationDirection = Signal;
        return;
    }
    if (Signal == LastNotificationDirection) return;
    string EmailSubject = IndicatorName + " " + Symbol() + " Notification";
    string EmailBody = AccountCompany() + " - " + AccountName() + " - " + IntegerToString(AccountNumber()) + "\r\n" + IndicatorName + " Notification for " + Symbol() + " @ " + EnumToString((ENUM_TIMEFRAMES)Period()) + "\r\n";
    string AlertText = "";
    string AppText = AccountCompany() + " - " + AccountName() + " - " + IntegerToString(AccountNumber()) + " - " + IndicatorName + " - " + Symbol() + " @ " + EnumToString((ENUM_TIMEFRAMES)Period()) + " - ";
    string Text = "";

    if (Signal == SIGNAL_BUY) Text += "Close Price (" + DoubleToString(iClose(Symbol(), Period(), Shift), _Digits) + ") > MA (" + DoubleToString(MALevel, _Digits) + ")";
    else if (Signal == SIGNAL_SELL) Text += "Close Price (" + DoubleToString(iClose(Symbol(), Period(), Shift), _Digits) + ") < MA (" + DoubleToString(MALevel, _Digits) + ")";

    EmailBody += Text;
    AlertText += Text;
    AppText += Text;
    if (SendAlert) Alert(AlertText);
    if (SendEmail)
    {
        if (!SendMail(EmailSubject, EmailBody)) Print("Error sending email " + IntegerToString(GetLastError()));
    }
    if (SendApp)
    {
        if (!SendNotification(AppText)) Print("Error sending notification " + IntegerToString(GetLastError()));
    }
    LastNotificationTime = iTime(Symbol(), Period(), 0);
    LastNotificationDirection = Signal;
}

void DrawArrows(int limit)
{
    for (int i = limit - 1; i >= 1; i--)
    {
        DrawArrow(i);
    }
}

void RemoveArrows()
{
    ObjectsDeleteAll(ChartID(), IndicatorName + "-ARWS-");
}

void DrawArrow(int i)
{
    RemoveArrowCurr();
    ENUM_TRADE_SIGNAL Signal = IsSignal(i);
    if (Signal == SIGNAL_NEUTRAL) return;
    datetime ArrowDate = iTime(Symbol(), 0, i);
    string ArrowName = IndicatorName + "-ARWS-" + IntegerToString(ArrowDate);
    double ArrowPrice = 0;
    ENUM_OBJECT ArrowType = OBJ_ARROW;
    color ArrowColor = 0;
    int ArrowAnchor = 0;
    string ArrowDesc = "";
    if (Signal == SIGNAL_BUY)
    {
        ArrowPrice = iLow(Symbol(), Period(), i);
        ArrowType = (ENUM_OBJECT)ArrowBuy;
        ArrowColor = clrGreen;
        ArrowAnchor = ANCHOR_TOP;
        ArrowDesc = "BUY";
    }
    if (Signal == SIGNAL_SELL)
    {
        ArrowPrice = iHigh(Symbol(), Period(), i);
        ArrowType = (ENUM_OBJECT)ArrowSell;
        ArrowColor = clrRed;
        ArrowAnchor = ANCHOR_BOTTOM;
        ArrowDesc = "SELL";
    }
    ObjectCreate(0, ArrowName, OBJ_ARROW, 0, ArrowDate, ArrowPrice);
    ObjectSetInteger(0, ArrowName, OBJPROP_COLOR, ArrowColor);
    ObjectSetInteger(0, ArrowName, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(0, ArrowName, OBJPROP_HIDDEN, true);
    ObjectSetInteger(0, ArrowName, OBJPROP_ANCHOR, ArrowAnchor);
    ObjectSetInteger(0, ArrowName, OBJPROP_ARROWCODE, ArrowType);
    ObjectSetInteger(0, ArrowName, OBJPROP_WIDTH, ArrowSize);
    ObjectSetInteger(0, ArrowName, OBJPROP_STYLE, STYLE_SOLID);
    ObjectSetInteger(0, ArrowName, OBJPROP_BGCOLOR, ArrowColor);
    ObjectSetString(0, ArrowName, OBJPROP_TEXT, ArrowDesc);
}
void RemoveArrowCurr()
{
    datetime ArrowDate = iTime(Symbol(), 0, Shift);
    string ArrowName = IndicatorName + "-ARWS-" + IntegerToString(ArrowDate);
    ObjectDelete(0, ArrowName);
}

// Delete all arrows that are older than BarsToScan bars.
void CleanUpOldArrows()
{
    int total = ObjectsTotal(ChartID(), 0, OBJ_ARROW);
    for (int i = total - 1; i >= 0; i--)
    {
        string ArrowName = ObjectName(ChartID(), i, 0, OBJ_ARROW);
        datetime time = (datetime)ObjectGetInteger(ChartID(), ArrowName, OBJPROP_TIME);
        int bar = iBarShift(Symbol(), Period(), time);
        if (bar >= BarsToScan) ObjectDelete(ChartID(), ArrowName);
    }
}

// Implements Hull moving average calculation. Copies the results into buff[].
// Returns the number of copied elements.
int iHull(const int start, const int limit, double &buff[])
{
    double HMABuffer[];
    int sqrt_period = (int)MathFloor(MathSqrt(MAPeriod));
    ArrayResize(HMABuffer, sqrt_period);

    double Buf1[], Buf2[];
    ArrayResize(Buf1, sqrt_period);
    ArrayResize(Buf2, sqrt_period);
    ArraySetAsSeries(Buf1, true);
    ArraySetAsSeries(Buf2, true);

    for (int i = start; i < limit; i++)
    {
        int weightsum = 0;
        double WMA = 0;

        int count = CopyBuffer(BufferMAHandle, 0, i, sqrt_period, Buf1);
        if (count < sqrt_period)
        {
            Print("MA data not ready...");
            return 0;
        }
        count = CopyBuffer(BufferMAHandle2, 0, i, sqrt_period, Buf2);
        if (count < sqrt_period)
        {
            Print("MA data not ready...");
            return 0;
        }
    
        for (int j = 0; j < sqrt_period; j++)
        {
            HMABuffer[j] = 2 * Buf1[j] - Buf2[j];
            WMA += HMABuffer[j] * (sqrt_period - j);
            weightsum += (j + 1);
        }
        WMA /= weightsum;
        buff[i] = WMA;
    }
    return limit;
}
//+------------------------------------------------------------------+