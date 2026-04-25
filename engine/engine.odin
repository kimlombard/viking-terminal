package main

import "core:fmt"
import "core:time"
import "core:os"            // Needed for the buffer flush
import "core:c"             // Needed for c.int
import "core:math/rand"
import lua "vendor:lua/5.4" // The magic bridge!


Candle :: struct {
	time:      i64,
	open:      f64,
	high:      f64,
	low:       f64,
	close:     f64,
	volume:    f64,
	indicator: f64, // Renamed from 'sma' to be our generic Lua result
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
    // In the future, this string comes directly from our Transpiler!
    // For now, we load a Lua function that remembers history and calculates an SMA.
    user_script: cstring = `
        local history = {}
        local period = 10

        -- The engine will call this function every single tick
        function on_tick(close_price)
            table.insert(history, close_price)
            if #history > period then
                table.remove(history, 1)
            end

            local sum = 0
            for i=1, #history do
                sum = sum + history[i]
            end
            
            return sum / #history
        end
    `
    if lua.L_dostring(L, user_script) != 0 {
        fmt.printf("Lua Init Error: %s\n", lua.tostring(L, -1))
        return
    }

	price := 100.0
	initial_balance := 2000.0 

    // --- NEW VARIABLES ---
    MAX_DRAWDOWN : f64 = 0.05
    asset_id     : cstring = "NAS100"
    tick_index   : c.int = 0

    // --- 3. THE LIVE MARKET LOOP ---
	for {
		c: Candle
		c.time  = time.to_unix_nanoseconds(time.now()) / 1_000_000_000
		c.open  = price
		c.high  = price
		c.low   = price
		c.volume = 0.0 
		c.indicator = 0.0

		// Simulate 5 sub-ticks to form 1 candle
		for _ in 0..<5 {
			move := (rand.float64() - 0.5)
			price += move
			c.volume += rand.float64() * 100 
			if price > c.high do c.high = price
			if price < c.low  do c.low  = price
			time.sleep(200 * time.Millisecond)
		}
		c.close = price

		// --- 4. THE LUA HANDOFF ---
        // Tell Lua we want to run the 'on_tick' function
        lua.getglobal(L, "on_tick") 
        
        // Push the current closing price onto the stack as an argument
        lua.pushnumber(L, lua.Number(c.close)) 
        
        // Execute! (1 argument in, 1 result out)
        if lua.pcall(L, 1, 1, 0) != 0 {
            // We print to standard error so it doesn't break our Phoenix CSV stream
            fmt.eprintf("Lua Tick Error: %s\n", lua.tostring(L, -1))
        } else {
            // Grab the calculated SMA from the top of the stack
            c.indicator = f64(lua.tonumber(L, -1))
            lua.pop(L, 1) // Clean the stack for the next tick
        }

		// Drawdown Guard
		drawdown := (initial_balance - (initial_balance * (price / 100.0))) / initial_balance
		status := "OK"
		if drawdown > MAX_DRAWDOWN do status = "VIOLATION"

        // 1. Increment our tick and call the matrix engine
        tick_index += 1
        kinetic := calculate_kinetic_candle(asset_id, tick_index)

        // 2. DYNAMIC STATE HACK: Override the state_code based on the candle's move
        // If it closed higher than it opened, it's bullish. If it moved a LOT, it's HyperBull.
        price_diff := c.close - c.open
        if price_diff > 0.5 {
            kinetic.state_code = 2  // HyperBull
        } else if price_diff > 0 {
            kinetic.state_code = 1  // BuildBull
        } else if price_diff > -0.5 {
            kinetic.state_code = -1 // BuildBear
        } else {
            kinetic.state_code = -2 // HyperBear
        }

        // 3. Output to Phoenix
        fmt.printf("candle:%d,%.2f,%.2f,%.2f,%.2f,%.2f,%.2f,%s,%d\n", 
            c.time, c.open, c.high, c.low, c.close, c.volume, c.indicator, "OK", kinetic.state_code)
        
        // 4. Force the OS to send the data immediately!
        os.flush(os.stdout)
	}
}