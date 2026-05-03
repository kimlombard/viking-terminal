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

main :: proc() {
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

        for price, vol in volume_profile {
            if vol > max_volume {
                max_volume = vol
                poc_price = price
            }
        }

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
        broadcast_candle(c, metrics, status, poc_price) 

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

broadcast_candle :: proc(c: Candle, kd: KineticData, status: string, poc_price: f64) {
    // Added an extra %.2f at the end for the POC, and added poc_price to the variables
    fmt.printf("candle:%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%s,%d,%.1f,%.1f,%.2f\n", 
        c.time, c.open, c.high, c.low, c.close, c.volume, c.indicator, status, kd.state_code, kd.lot_size, kd.probability, poc_price)
}