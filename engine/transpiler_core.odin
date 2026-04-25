package main

import "core:fmt"
import "core:strings"

// --- 1. THE LEXER EXPANSION (The Vocabulary) ---
// We add the new symbols to our token dictionary so the transpiler doesn't panic
// when it sees them.
TokenType :: enum {
    Identifier,
    Number,
    Assign,       // =  (PineScript declaration)
    Reassign,     // := (PineScript mutation)
    LBracket,     // [  (History lookback)
    RBracket,     // ]
    EOF,
}

// --- 2. THE AST (Abstract Syntax Tree) ---
// We need new data structures to hold the concepts of "Lookback" and "Reassignment".
Expr :: union {
    ^IdentExpr,
    ^IndexExpr, 
}

IdentExpr :: struct { name: string }

// Represents something like: close[1] or high[5]
IndexExpr :: struct {
    identifier: string,
    lookback:   int, 
}

Stmt :: union {
    ^VarDecl,
    ^VarReassign,
    ^TupleDecl,    // NEW: For multiple returns
    ^IfStatement,  // NEW: For decision trees
}

VarDecl :: struct {
    name:  string,
    value: Expr,
}

VarReassign :: struct {
    name:  string,
    value: Expr,
}

// Represents: [macd, signal, hist] = viking.macd(close)
TupleDecl :: struct {
    names: []string,
    value: Expr, // The function call
}

// Represents: if close > open { ... }
IfStatement :: struct {
    condition:  string, // Keeping it simple for the example (e.g., "close > open")
    true_body:  []Stmt,
    false_body: []Stmt, // Optional else block
}

// --- 3. THE EMITTER (The Universal Translator) ---
// This is where the actual magic happens. We take the Odin AST and emit pure,
// highly optimized Lua code that our C-API ring buffer can understand.

// --- 3. THE EMITTER (The Universal Translator) ---
// This is where the actual magic happens. We take the Odin AST and emit pure,
// highly optimized Lua code that our C-API ring buffer can understand.

emit_lua_statement :: proc(stmt: Stmt, indent_level: int = 0) -> string {
    // Helper to handle Lua indentation
    indent := strings.repeat("  ", indent_level)

    switch s in stmt {
    case ^VarDecl:
        // PINE: my_var = close[1]
        // LUA:  local my_var = viking.get_history("close", 1)
        val_str := emit_lua_expression(s.value)
        return fmt.tprintf("%slocal %s = %s", indent, s.name, val_str)

    case ^VarReassign:
        // PINE: my_var := close[2]
        // LUA:  my_var = viking.get_history("close", 2)
        // CRITICAL: Notice we drop the 'local' keyword so Lua mutates the 
        // existing variable in memory rather than shadowing it!
        val_str := emit_lua_expression(s.value)
        return fmt.tprintf("%s%s = %s", indent, s.name, val_str)

    // THE TUPLE BRIDGE
    case ^TupleDecl:
        // PINE: [macd, signal, hist] = ta.macd(...)
        // LUA:  local macd, signal, hist = viking.macd(...)
        joined_names := strings.join(s.names, ", ")
        val_str := emit_lua_expression(s.value)
        return fmt.tprintf("%slocal %s = %s", indent, joined_names, val_str)

    // THE CONTROL FLOW BRIDGE
    case ^IfStatement:
        // PINE: if close > open
        // LUA:  if close > open then ... end
        builder: strings.Builder
        strings.builder_init(&builder)
        
        fmt.sbprintf(&builder, "%sif %s then\n", indent, s.condition)
        
        // Recursively emit the statements inside the true block
        for body_stmt in s.true_body {
            fmt.sbprintf(&builder, "%s\n", emit_lua_statement(body_stmt, indent_level + 1))
        }

        if len(s.false_body) > 0 {
            fmt.sbprintf(&builder, "%selse\n", indent)
            for body_stmt in s.false_body {
                fmt.sbprintf(&builder, "%s\n", emit_lua_statement(body_stmt, indent_level + 1))
            }
        }
        
        fmt.sbprintf(&builder, "%send", indent)
        return strings.to_string(builder)
    }
    return ""
}

emit_lua_expression :: proc(expr: Expr) -> string {
    switch e in expr {
    case ^IdentExpr:
        return e.name
    case ^IndexExpr:
        // THE BRIDGE: We translate the Pine bracket syntax into a native Lua 
        // function call that reaches directly into our Odin ring buffer.
        return fmt.tprintf("viking.get_history(\"%s\", %d)", e.identifier, e.lookback)
    }
    return ""
}

// --- 4. THE TEST FIRE ---
test_transpiler_core :: proc() {
    fmt.println("--- Booting Viking Transpiler Core ---")

    // Simulated Pine Script Line 1:  prev_close = close[1]
    decl := &VarDecl{
        name = "prev_close",
        value = &IndexExpr{identifier = "close", lookback = 1},
    }

    // Simulated Pine Script Line 2:  prev_close := close[2]
    reassign := &VarReassign{
        name = "prev_close",
        value = &IndexExpr{identifier = "close", lookback = 2},
    }

    fmt.println("\n[Translating Pine Script to Lua...]")
    
    lua_line_1 := emit_lua_statement(decl)
    fmt.printf("PINE: prev_close = close[1]  ->  LUA: %s\n", lua_line_1)

    lua_line_2 := emit_lua_statement(reassign)
    fmt.printf("PINE: prev_close := close[2] ->  LUA: %s\n", lua_line_2)
}