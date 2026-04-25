-- viking_ta.lua
-- The Viking Terminal Standard Library (Vanilla Technicals)

-- Initialize the global namespace if it doesn't exist
viking = viking or {}

-- ==========================================
-- Simple Moving Average (Mapped from ta.sma)
-- ==========================================
function viking.sma(source_identifier, length)
    local sum = 0.0
    
    -- Loop back through Odin's ultra-fast ring buffer
    for i = 0, length - 1 do
        sum = sum + viking.get_history(source_identifier, i)
    end
    
    return sum / length
end

-- ==========================================
-- Exponential Moving Average (Mapped from ta.ema)
-- ==========================================
function viking.ema(source_identifier, length)
    local alpha = 2.0 / (length + 1)
    
    -- Grab the current tick's value
    local current_val = viking.get_history(source_identifier, 0)
    
    -- Grab the previous EMA state from Odin's memory
    -- (In TradingView, EMA is stateful, so Odin tracks the running value)
    local prev_ema = viking.get_history(source_identifier .. "_ema_state", 1)
    
    -- If there is no previous state, default to the current value (first tick)
    if not prev_ema then
        return current_val
    end
    
    return (current_val * alpha) + (prev_ema * (1 - alpha))
end

-- ==========================================
-- Average True Range (Mapped from ta.atr)
-- ==========================================
function viking.atr(length)
    local sum_tr = 0.0
    
    for i = 0, length - 1 do
        local high = viking.get_history("high", i)
        local low = viking.get_history("low", i)
        local prev_close = viking.get_history("close", i + 1)
        
        -- Calculate True Range for this specific historical candle
        local tr1 = high - low
        local tr2 = prev_close and math.abs(high - prev_close) or 0
        local tr3 = prev_close and math.abs(low - prev_close) or 0
        
        local true_range = math.max(tr1, tr2, tr3)
        sum_tr = sum_tr + true_range
    end
    
    -- Note: Real ATR uses RMA (Running Moving Average), but we use SMA here for simplicity
    return sum_tr / length
end

-- ==========================================
-- Relative Strength Index (Mapped from ta.rsi)
-- ==========================================
function viking.rsi(source_identifier, length)
    local sum_gain = 0.0
    local sum_loss = 0.0
    
    for i = 0, length - 1 do
        local current = viking.get_history(source_identifier, i)
        local previous = viking.get_history(source_identifier, i + 1)
        
        if previous then
            local change = current - previous
            if change > 0 then
                sum_gain = sum_gain + change
            else
                sum_loss = sum_loss + math.abs(change)
            end
        end
    end
    
    local avg_gain = sum_gain / length
    local avg_loss = sum_loss / length
    
    if avg_loss == 0 then return 100 end
    
    local rs = avg_gain / avg_loss
    return 100 - (100 / (1 + rs))
end