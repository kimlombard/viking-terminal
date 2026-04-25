package main

import "core:fmt"
import lua "vendor:lua/5.4" // The Lua C API bindings for Odin

test_sandbox :: proc() {
	fmt.println("--- Booting Viking Lua VM ---")

	// 1. Initialize the Virtual Machine
	// This creates an isolated "State" where our scripts will run safely.
	L := lua.L_newstate()
	if L == nil {
		fmt.println("CRITICAL: Failed to boot Lua VM.")
		return
	}
	// Ensure we shut down the VM and free memory when the program ends
	defer lua.close(L) 

	// 2. Load standard Lua libraries (math, string, etc.)
	lua.L_openlibs(L)

	// 3. The Script (Imagine our Transpiler just spit this out)
	script: cstring = `
		-- This is running inside the Lua VM!
		local close_price = 150.50
		local multiplier = 2
		
		-- Let's do some math
		local target = close_price * multiplier
		
		-- Send a message to the console from inside Lua
		print("[Lua Sandbox] Calculating target: " .. target)
		
		-- Return the value back to Odin
		return target
	`

	// 4. Execute the Script
	// dostring compiles and runs the text. If it's not 'OK', we catch the error.
	if lua.L_dostring(L, script) != 0 {
		// If the user wrote bad code, Lua pushes the error to the top of the stack
		err_msg := lua.tostring(L, -1)
		fmt.printf("Lua Execution Error: %s\n", err_msg)
		lua.pop(L, 1) // Clean the error off the stack
		return
	}

	// 5. Retrieve the Result
	// Lua communicates with Odin using a "Stack". 
	// Our 'return target' pushed the result to the top of the stack (index -1).
	if lua.isnumber(L, -1) {
		result := lua.tonumber(L, -1)
		fmt.printf("--- Odin Received Result: %.2f ---\n", result)
	} else {
		fmt.println("Script did not return a number!")
	}
	
	// Clean up the stack
	lua.pop(L, 1) 
}