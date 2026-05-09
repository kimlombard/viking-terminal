import yfinance as yf

# NAS100 is often tracked as 'NQ=F' (Nasdaq 100 Futures) or '^NDX' (Index)
# We'll use the Index for clean historical pricing
ticker = "^NDX"

# print(f"Fetching 1-minute data for {ticker}...")
# data = yf.download(ticker, period="7d", interval="1m")

print(f"Fetching 5-minute data for {ticker}...")
data = yf.download(ticker, period="60d", interval="5m")

# Clean up the format for the Odin parser
#data.to_csv("NAS100_5min.csv")

# Convert the datetime index to Unix seconds
data['time'] = data.index.astype('int64') // 10**9 
data.to_csv("NAS100_5min.csv", index=False)
print("Done! 'NAS100_5min.csv' is ready for the Viking Engine.")
