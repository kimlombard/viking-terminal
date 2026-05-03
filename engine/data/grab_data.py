import yfinance as yf

# NAS100 is often tracked as 'NQ=F' (Nasdaq 100 Futures) or '^NDX' (Index)
# We'll use the Index for clean historical pricing
ticker = "^NDX"

print(f"Fetching 1-minute data for {ticker}...")
data = yf.download(ticker, period="7d", interval="1m")

# Clean up the format for the Odin parser
data.to_csv("NAS100_1min.csv")
print("Done! 'NAS100_1min.csv' is ready for the Viking Engine.")