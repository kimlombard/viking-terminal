package main

import "core:fmt"
import "core:time"
import "core:os"            
import "core:c"             
import "core:math"          
import "core:math/rand"
import "core:strings"       // Added: Required for split_lines
import "core:strconv"       // Added: Required for parse_f64
import lua "vendor:lua/5.4" 

Candle :: struct {
    time:      i64,
    open:      f64,
    high:      f64,
    low:       f64,
    close:     f64,
    volume:    f64,
    indicator: f64, 
}

KineticData :: struct {
    state_code: int,
    probability: f64,
    lot_size: f64,
}

EngineState :: struct {
    prev_close: f64,
    prev_atr:   f64,
    is_seeded:  bool,
    prev_state_idx: int,          
    transitions:    [4][4]int,    
}

// --- ALMA ENGINE (Arnaud Legoux Moving Average) ---
AlmaState :: struct {
    period:     int,
    window:     [dynamic]f64,
    weights:    [dynamic]f64,
    weight_sum: f64,
    index:      int,
    filled:     bool,
}

// --- MITIGATION ZONES (Ghost Levels) ---
ZoneType :: enum { POC, VAH, VAL }

MitigationZone :: struct {
    price:      f64,
    z_type:     ZoneType,
    is_bullish: bool, // true if created by an UPWARD break
    active:     bool,
    created_at: i64,
}

// --- EXECUTION MODULE (The Broker) ---
PositionType :: enum { NONE, LONG, SHORT }

Position :: struct {
    type:        PositionType,
    entry_price: f64,
    size:        f64,
    sl:          f64, // Stop Loss
    tp:          f64, // Take Profit
    pnl:         f64,
}

Broker :: struct {
    balance:  f64,
    position: Position,
}

// Boot up the ALMA and pre-calculate the heavy Gaussian math
init_alma :: proc(period: int, offset: f64, sigma: f64) -> AlmaState {
    state: AlmaState
    state.period = period
    state.window = make([dynamic]f64, period)
    state.weights = make([dynamic]f64, period)
    
    m := offset * f64(period - 1)
    s := f64(period) / sigma

    for i := 0; i < period; i += 1 {
        // The Gaussian distribution formula
        w := math.exp(-((f64(i) - m) * (f64(i) - m)) / (2.0 * s * s))
        state.weights[i] = w
        state.weight_sum += w
    }
    
    return state
}

// The ultra-fast, per-tick update
update_alma :: proc(state: ^AlmaState, price: f64) -> f64 {
    // 1. Add newest price to our rolling circular buffer
    state.window[state.index] = price
    state.index = (state.index + 1) % state.period
    
    // Check if we have enough data to calculate a true ALMA
    if state.index == 0 do state.filled = true
    if !state.filled do return price 

    // 2. Apply the pre-calculated weights to the price window
    alma: f64 = 0.0
    for i := 0; i < state.period; i += 1 {
        // We iterate from the oldest price in the buffer to the newest
        buffer_idx := (state.index + i) % state.period
        alma += state.window[buffer_idx] * state.weights[i]
    }

    return alma / state.weight_sum
}

// --- NEW: Initialize the Broker ---
    broker := Broker{ 
        balance = 100000.0, // $100k Starting Capital
        position = Position{type = .NONE} 
    }

    // --- 4. THE HISTORICAL PROCESSING LOOP ---

main :: proc() {
    kd: KineticData
    // --- 1. BOOT THE LUA BRAIN ---
    L := lua.L_newstate()
    if L == nil {
        fmt.println("CRITICAL: Failed to boot Lua VM.")
        return
    }
    defer lua.close(L)
    lua.L_openlibs(L)

    // --- 2. LOAD THE SCRIPT ---
    user_script: cstring = `
        local bsp_history = {}
        local min_period = 5
        local max_period = 14
        function on_tick(open, high, low, close)
            local range = high - low
            local bsp_raw = 0
            if range > 0 then
                bsp_raw = ((close - open) / range) * 100
            end
            table.insert(bsp_history, bsp_raw)
            if #bsp_history > max_period then
                table.remove(bsp_history, 1)
            end
            if #bsp_history < min_period then return bsp_raw end
            local noise = 0
            for i=2, #bsp_history do
                noise = noise + math.abs(bsp_history[i] - bsp_history[i-1])
            end
            local signal = math.abs(bsp_history[#bsp_history] - bsp_history[1])
            local er = 0
            if noise > 0 then
                er = signal / noise
            end
            local fastest = 0.666
            local slowest = 0.0645
            local smooth_weight = (er * (fastest - slowest) + slowest) ^ 2
            local prev_smooth = bsp_history[#bsp_history - 1] or 0
            local adaptive_bsp = prev_smooth + smooth_weight * (bsp_raw - prev_smooth)
            bsp_history[#bsp_history] = adaptive_bsp
            return adaptive_bsp
        end
    `
    if lua.L_dostring(L, user_script) != 0 {
        fmt.printf("Lua Init Error: %s\n", lua.tostring(L, -1))
        return
    }

    // --- 3. LOAD THE HISTORICAL FILE ---
    filepath := "/home/kim/dev/trading_lab/engine/data/NAS100_1min.csv"
    // Pass context.allocator as the second argument
    data, err := os.read_entire_file_from_path(filepath, context.allocator)
    if err != 0 {
        fmt.eprintf("CRITICAL: Could not find %s. Error code: %v\n", filepath, err)
        return
    }
    defer delete(data)

    lines := strings.split_lines(string(data))
    tick_index : c.int = 0
    initial_balance := 26820.0
    state := EngineState{ is_seeded = false }

    // Initialize the volume profile map (Price -> Volume)
    volume_profile := make(map[f64]f64)

    // Initialize the ALMA States
    alma20_high_state := init_alma(20, 0.85, 6.0)
    alma20_low_state := init_alma(20, 0.85, 6.0)
    alma200_high_state := init_alma(200, 0.85, 6.0)
    alma200_low_state := init_alma(200, 0.85, 6.0)

    // --- NEW: The Ghost Level Tracker ---
    active_zones := make([dynamic]MitigationZone)

    // --- 4. THE HISTORICAL PROCESSING LOOP ---
    for i := 3; i < len(lines); i += 1 {
        line := lines[i]
        if len(line) == 0 do continue

        columns := strings.split(line, ",")
        if len(columns) < 6 do continue

        c: Candle
        // Use real unix seconds to keep the browser chart happy
        c.time = time.to_unix_nanoseconds(time.now()) / 1_000_000_000
        
        // FIX: Handling the error return from parse_f64
        c.close, _ = strconv.parse_f64(columns[1])
        c.high, _  = strconv.parse_f64(columns[2])
        c.low, _   = strconv.parse_f64(columns[3])
        c.open, _  = strconv.parse_f64(columns[4])
        c.volume, _ = strconv.parse_f64(columns[5])

        // The "Resolution" of your profile. 
        // Use 1.0 for NAS100 (whole numbers), or maybe 0.5 for XAUUSD.
        tick_size: f64 = 1.0 

        // Round price to the nearest bucket
        // We use c.close and c.volume because that's where strconv.parse_f64 put them!
        bucket: f64 = math.round(c.close / tick_size) * tick_size

        // Add the volume to that specific price bucket
        volume_profile[bucket] += c.volume

        max_volume: f64 = 0.0
        poc_price: f64 = c.close // Default to current price

        // --- NEW: THE TRUE VALUE AREA (70%) ALGORITHM (Float-Safe) ---
        total_session_vol: f64 = 0.0
        for _, vol in volume_profile {
            total_session_vol += vol
        }

        target_vol := total_session_vol * 0.70
        current_va_vol := volume_profile[poc_price]
        
        vah := poc_price
        val := poc_price

        // Expand outwards until we capture 70% of the volume
        for current_va_vol < target_vol {
            // Find the immediate next traded price level UP
            next_up_price: f64 = 999999.0
            up_vol: f64 = 0.0
            for p, v in volume_profile {
                if p > vah && p < next_up_price {
                    next_up_price = p
                    up_vol = v
                }
            }

            // Find the immediate next traded price level DOWN
            next_down_price: f64 = -1.0
            down_vol: f64 = 0.0
            for p, v in volume_profile {
                if p < val && p > next_down_price {
                    next_down_price = p
                    down_vol = v
                }
            }

            if up_vol == 0.0 && down_vol == 0.0 {
                break // Safety break: No more volume to expand into
            }

            // Consume the node with the highest volume
            if up_vol >= down_vol {
                current_va_vol += up_vol
                vah = next_up_price
            } else {
                current_va_vol += down_vol
                val = next_down_price
            }
        }
        // --- END VALUE AREA ALGORITHM ---

        // --- THE LUA HANDOFF ---
        lua.getglobal(L, "on_tick") 
        lua.pushnumber(L, lua.Number(c.open)) 
        lua.pushnumber(L, lua.Number(c.high)) 
        lua.pushnumber(L, lua.Number(c.low)) 
        lua.pushnumber(L, lua.Number(c.close))
        
        if lua.pcall(L, 4, 1, 0) == 0 {
            c.indicator = f64(lua.tonumber(L, -1))
            lua.pop(L, 1)
        }

        // Drawdown & Metrics
        drawdown := (initial_balance - (initial_balance * (c.close / initial_balance))) / initial_balance
        status := drawdown > 0.05 ? "VIOLATION" : "OK"

        tick_index += 1
        metrics := calculate_viking_metrics(c, drawdown, &state) 

        // --- Calculate Live ALMA ---
        live_alma20_high := update_alma(&alma20_high_state, c.high)
        live_alma20_low := update_alma(&alma20_low_state, c.low)
        live_alma200_high := update_alma(&alma200_high_state, c.high)
        live_alma200_low := update_alma(&alma200_low_state, c.low)

        // ==========================================
        // --- PHASE 1: MITIGATION CHECK ---
        // Has the price returned to fill a ghost level?
        // ==========================================
        for j := 0; j < len(active_zones); j += 1 {
            if !active_zones[j].active do continue
            z := &active_zones[j]
            
            // If it was a Bullish break, the whale left orders BELOW current price.
            // It mitigates if the candle's LOW touches or drops below the zone.
            if z.is_bullish && c.low <= z.price {
                z.active = false
                fmt.printf("[ODIN] 👻 GHOST LEVEL MITIGATED: %f (Bullish %v filled)\n", z.price, z.z_type)
            } else if !z.is_bullish && c.high >= z.price {
                // Notice the '} else if' is on the same line!
                z.active = false
                fmt.printf("[ODIN] 👻 GHOST LEVEL MITIGATED: %f (Bearish %v filled)\n", z.price, z.z_type)
            }
        }

        // ==========================================
        // --- PHASE 2: NEW WHALE FOOTPRINTS ---
        // Did we violently slice through a key node?
        // ==========================================
        if state.is_seeded {
            // Check for BULLISH Hyper Velocity (State 2)
            if kd.state_code == 2 { 
                if state.prev_close < poc_price && c.close > poc_price {
                    append(&active_zones, MitigationZone{price = poc_price, z_type = .POC, is_bullish = true, active = true, created_at = c.time})
                    fmt.printf("[ODIN] 🐋 WHALE FOOTPRINT: Bullish punch through POC at %f\n", poc_price)
                }
                if state.prev_close < vah && c.close > vah {
                    append(&active_zones, MitigationZone{price = vah, z_type = .VAH, is_bullish = true, active = true, created_at = c.time})
                    fmt.printf("[ODIN] 🐋 WHALE FOOTPRINT: Bullish punch through VAH at %f\n", vah)
                }
                if state.prev_close < val && c.close > val {
                    append(&active_zones, MitigationZone{price = val, z_type = .VAL, is_bullish = true, active = true, created_at = c.time})
                }
            } else if kd.state_code == -2 {
                // Notice the '} else if' is on the same line!
                if state.prev_close > poc_price && c.close < poc_price {
                    append(&active_zones, MitigationZone{price = poc_price, z_type = .POC, is_bullish = false, active = true, created_at = c.time})
                    fmt.printf("[ODIN] 🐋 WHALE FOOTPRINT: Bearish punch through POC at %f\n", poc_price)
                }
                if state.prev_close > val && c.close < val {
                    append(&active_zones, MitigationZone{price = val, z_type = .VAL, is_bullish = false, active = true, created_at = c.time})
                    fmt.printf("[ODIN] 🐋 WHALE FOOTPRINT: Bearish punch through VAL at %f\n", val)
                }
                if state.prev_close > vah && c.close < vah {
                    append(&active_zones, MitigationZone{price = vah, z_type = .VAH, is_bullish = false, active = true, created_at = c.time})
                }
            }
        }

        // --- WHALE ABSORPTION LOGIC ---
        whale_signal := "none"
        avg_vol := total_session_vol / f64(tick_index)
        
        // If volume is 3x the average and we are within 2 ticks of a key level
        at_key_level := (math.abs(c.close - poc_price) <= tick_size * 2.0) || 
                        (math.abs(c.close - vah) <= tick_size * 2.0) || 
                        (math.abs(c.close - val) <= tick_size * 2.0)

        if c.volume > (avg_vol * 3.0) && at_key_level {
            // High Volume + Small Candle Range = Absorption
            candle_range := math.abs(c.high - c.low)
            if candle_range < (state.prev_atr * 0.5) {
                whale_signal = "ABSORPTION"
            } else {
                whale_signal = "EXHAUSTION"
            }
        }

        // ==========================================
        // --- THE BROKER: EXECUTION & MANAGEMENT ---
        // ==========================================
        
        // 1. Manage Active Position (Calculate PnL & Check Exits)
        if broker.position.type != .NONE {
            // Calculate Unrealized PnL (assuming $10 per point for a standard lot)
            point_value := 10.0 * broker.position.size
            if broker.position.type == .LONG {
                broker.position.pnl = (c.close - broker.position.entry_price) * point_value
                // Exit Long (SL or TP)
                if c.close <= broker.position.sl || c.close >= broker.position.tp {
                    broker.balance += broker.position.pnl
                    broker.position = Position{type = .NONE} // Close position
                    fmt.printf("[EXECUTION] 🛡️ CLOSED LONG at %f | Balance: $%.2f\n", c.close, broker.balance)
                }
            } else if broker.position.type == .SHORT {
                broker.position.pnl = (broker.position.entry_price - c.close) * point_value
                // Exit Short (SL or TP)
                if c.close >= broker.position.sl || c.close <= broker.position.tp {
                    broker.balance += broker.position.pnl
                    broker.position = Position{type = .NONE} // Close position
                    fmt.printf("[EXECUTION] 🛡️ CLOSED SHORT at %f | Balance: $%.2f\n", c.close, broker.balance)
                }
            }
        }

        // 2. Confluence Entry Logic (Only if flat)
        if broker.position.type == .NONE && whale_signal == "ABSORPTION" {
            risk_points := state.prev_atr * 2.0 // Dynamic Stop Loss based on volatility
            
            // CONFLUENCE: Bullish Flow (State 2) + Whale Absorption at VAL
            if kd.state_code == 2 && math.abs(c.close - val) <= tick_size * 2.0 {
                broker.position = Position{
                    type = .LONG,
                    entry_price = c.close,
                    size = kd.lot_size,
                    sl = c.close - risk_points,
                    tp = c.close + (risk_points * 2.0), // 1:2 Risk/Reward
                    pnl = 0.0,
                }
                fmt.printf("[EXECUTION] ⚔️ ENTERED LONG at %f | SL: %f | TP: %f\n", c.close, broker.position.sl, broker.position.tp)
            } else if kd.state_code == -2 && math.abs(c.close - vah) <= tick_size * 2.0 {
                // CONFLUENCE: Bearish Flow (State -2) + Whale Absorption at VAH
                broker.position = Position{
                    type = .SHORT,
                    entry_price = c.close,
                    size = kd.lot_size,
                    sl = c.close + risk_points,
                    tp = c.close - (risk_points * 2.0), // 1:2 Risk/Reward
                    pnl = 0.0,
                }
                fmt.printf("[EXECUTION] ⚔️ ENTERED SHORT at %f | SL: %f | TP: %f\n", c.close, broker.position.sl, broker.position.tp)
            }
        }

        broadcast_candle(c, metrics, status, poc_price, vah, val, live_alma20_high, live_alma20_low, live_alma200_high, live_alma200_low, &active_zones, whale_signal, broker)
        // 1. Slow it down significantly. 
        // 100ms = 10 ticks per second (Good for "watching" the strategy)
        // 500ms = 2 ticks per second (Very calm, easy to debug)
        time.sleep(200 * time.Millisecond) 

        // 2. CRITICAL: Explicitly flush after every single tick
        // This prevents the OS from "batching" 100 ticks and sending them all at once
        os.flush(os.stdout)
    }

    fmt.println("HISTORICAL_DATA_COMPLETE: Engine staying alive for sync.")
    
    // THE FIX: An infinite loop at the end prevents the process from exiting 
    // and keeps the Elixir Port from restarting it constantly.
    for {
        time.sleep(1000 * time.Millisecond)
    }
}

state_to_index :: proc(state: int) -> int {
    switch state {
        case -2: return 0 
        case -1: return 1 
        case  1: return 2 
        case  2: return 3 
        case:    return 1 
    }
}

calculate_viking_metrics :: proc(c: Candle, drawdown: f64, state: ^EngineState) -> KineticData {
    kd: KineticData
    tr: f64
    if !state.is_seeded {
        tr = c.high - c.low
        state.prev_atr = tr
    } else {
        hl   := c.high - c.low
        h_pc := math.abs(c.high - state.prev_close)
        l_pc := math.abs(c.low - state.prev_close)
        tr = math.max(hl, math.max(h_pc, l_pc))
    }

    period := 14.0
    atr := (state.prev_atr * (period - 1.0) + tr) / period
    price_diff := c.close - c.open
    hyper_threshold := atr * 1.2 

    if price_diff > hyper_threshold {
        kd.state_code = 2  
    } else if price_diff > 0 {
        kd.state_code = 1  
    } else if price_diff < -hyper_threshold {
        kd.state_code = -2 
    } else {
        kd.state_code = -1 
    }

    current_idx := state_to_index(kd.state_code)
    if state.is_seeded {
        state.transitions[state.prev_state_idx][current_idx] += 1
    }

    row := state.transitions[current_idx]
    total_transitions := row[0] + row[1] + row[2] + row[3]

    if total_transitions > 5 { 
        if kd.state_code > 0 {
            bull_stays := row[2] + row[3]
            kd.probability = (f64(bull_stays) / f64(total_transitions)) * 100.0
        } else {
            bear_stays := row[0] + row[1]
            kd.probability = (f64(bear_stays) / f64(total_transitions)) * 100.0
        }
    } else {
        kd.probability = 50.0 
    }

    if kd.probability < 1.0 do kd.probability = 1.0
    if kd.probability > 99.0 do kd.probability = 99.0

    state.prev_close = c.close
    state.prev_atr = atr
    state.prev_state_idx = current_idx
    state.is_seeded = true
    
    kd.lot_size = 1.0 - drawdown 
    if kd.lot_size < 0 do kd.lot_size = 0 
    
    return kd
}

broadcast_candle :: proc(c: Candle, kd: KineticData, status: string, poc_price: f64, vah: f64, val: f64, alma20_high: f64, alma20_low: f64, alma200_high: f64, alma200_low: f64, active_zones: ^[dynamic]MitigationZone, whale_signal: string, broker: Broker) {
    
    // 1. Pack the active zones into a string
    b: strings.Builder
    strings.builder_init(&b)
    defer strings.builder_destroy(&b)

    active_count := 0
    for z in active_zones {
        if z.active {
            bull_flag := z.is_bullish ? 1 : 0
            fmt.sbprintf(&b, "%f:%d|", z.price, bull_flag)
            active_count += 1
        }
    }
    
    ghost_str := strings.to_string(b)
    if active_count == 0 {
        ghost_str = "none"
    }

    // --- NEW: Map the Position Enum to an Integer ---
    pos_code := 0
    if broker.position.type == .LONG do pos_code = 1
    if broker.position.type == .SHORT do pos_code = -1

    // 2. The perfectly widened 23-variable print statement
    fmt.printf("candle:%v,%f,%f,%f,%f,%f,%f,%s,%d,%f,%f,%f,%f,%f,%f,%f,%f,%f,%s,%s,%d,%f,%f\n", 
        c.time, c.open, c.high, c.low, c.close, c.volume, c.indicator, 
        status, kd.state_code, kd.lot_size, kd.probability, poc_price, 
        vah, val, 
        alma20_high, alma20_low, alma200_high, alma200_low, 
        ghost_str,
        whale_signal,
        pos_code, broker.position.pnl, broker.balance // <-- Using 'pos_code' instead of the struct!
    )
}