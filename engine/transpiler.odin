package main

import "core:fmt"

// --- 1. LEXER ---
Token_Kind :: enum { EOF, Identifier, Number, Comma, LParen, RParen, Plus, Minus, Star, Slash, Assign, Invalid }
Token :: struct { kind: Token_Kind, text: string }

tokenize :: proc(input: string) -> [dynamic]Token {
	tokens: [dynamic]Token
	pos := 0

	for pos < len(input) {
		c := input[pos]
		if c == ' ' || c == '\t' || c == '\n' { pos += 1; continue }
		if c == '(' { append(&tokens, Token{.LParen, "("}); pos += 1; continue }
		if c == ')' { append(&tokens, Token{.RParen, ")"}); pos += 1; continue }
		if c == ',' { append(&tokens, Token{.Comma, ","}); pos += 1; continue }
		if c == '+' { append(&tokens, Token{.Plus, "+"}); pos += 1; continue }
		if c == '-' { append(&tokens, Token{.Minus, "-"}); pos += 1; continue }
		if c == '*' { append(&tokens, Token{.Star, "*"}); pos += 1; continue }
		if c == '/' { append(&tokens, Token{.Slash, "/"}); pos += 1; continue }
		if c == '=' { append(&tokens, Token{.Assign, "="}); pos += 1; continue } // The new Memory Trigger!
		
		if c >= '0' && c <= '9' {
			start := pos
			for pos < len(input) && ((input[pos] >= '0' && input[pos] <= '9') || input[pos] == '.') do pos += 1
			append(&tokens, Token{.Number, input[start:pos]})
			continue
		}
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' {
			start := pos
			for pos < len(input) {
				curr := input[pos]
				if (curr >= 'a' && curr <= 'z') || (curr >= 'A' && curr <= 'Z') || curr == '_' || curr == '.' || (curr >= '0' && curr <= '9') do pos += 1
				else do break
			}
			append(&tokens, Token{.Identifier, input[start:pos]})
			continue
		}
		append(&tokens, Token{.Invalid, input[pos:pos+1]}); pos += 1
	}
	append(&tokens, Token{.EOF, ""})
	return tokens
}

// --- 2. PARSER ---
AST_Kind :: enum { Identifier, Number, FunctionCall, BinaryOp, Assignment }
AST_Node :: struct {
	kind:     AST_Kind,
	value:    string,
	callee:   string,
	args:     [dynamic]^AST_Node,
	op:       string,
	left:     ^AST_Node,
	right:    ^AST_Node,
	var_name: string,      // Used for Assignment
	expr:     ^AST_Node,   // Used for Assignment
}

parse_factor :: proc(tokens: []Token, pos: ^int) -> ^AST_Node {
	if pos^ >= len(tokens) do return nil
	token := tokens[pos^]

	if token.kind == .Identifier && pos^ + 1 < len(tokens) && tokens[pos^ + 1].kind == .LParen {
		node := new(AST_Node); node.kind = .FunctionCall; node.callee = token.text; pos^ += 2
		for pos^ < len(tokens) && tokens[pos^].kind != .RParen {
			arg := parse_expression(tokens, pos)
			if arg != nil do append(&node.args, arg)
			if pos^ < len(tokens) && tokens[pos^].kind == .Comma do pos^ += 1
		}
		if pos^ < len(tokens) && tokens[pos^].kind == .RParen do pos^ += 1
		return node
	}
	if token.kind == .Identifier {
		node := new(AST_Node); node.kind = .Identifier; node.value = token.text; pos^ += 1; return node
	}
	if token.kind == .Number {
		node := new(AST_Node); node.kind = .Number; node.value = token.text; pos^ += 1; return node
	}
	return nil
}

parse_term :: proc(tokens: []Token, pos: ^int) -> ^AST_Node {
	node := parse_factor(tokens, pos)
	for pos^ < len(tokens) && (tokens[pos^].kind == .Star || tokens[pos^].kind == .Slash) {
		op_token := tokens[pos^]
		pos^ += 1
		right := parse_factor(tokens, pos)
		new_node := new(AST_Node); new_node.kind = .BinaryOp; new_node.op = op_token.text
		new_node.left = node; new_node.right = right; node = new_node
	}
	return node
}

parse_expression :: proc(tokens: []Token, pos: ^int) -> ^AST_Node {
	node := parse_term(tokens, pos)
	for pos^ < len(tokens) && (tokens[pos^].kind == .Plus || tokens[pos^].kind == .Minus) {
		op_token := tokens[pos^]
		pos^ += 1
		right := parse_term(tokens, pos)
		new_node := new(AST_Node); new_node.kind = .BinaryOp; new_node.op = op_token.text
		new_node.left = node; new_node.right = right; node = new_node
	}
	return node
}

// NEW: The Statement Parser (Checks for '=' before doing math)
parse_statement :: proc(tokens: []Token, pos: ^int) -> ^AST_Node {
	if pos^ >= len(tokens) do return nil

	// Lookahead: Is it an Identifier immediately followed by '='?
	if pos^ + 1 < len(tokens) && tokens[pos^].kind == .Identifier && tokens[pos^ + 1].kind == .Assign {
		node := new(AST_Node)
		node.kind = .Assignment
		node.var_name = tokens[pos^].text
		pos^ += 2 // Skip the variable name and the '='
		
		// The right side of the equals sign is just a normal expression!
		node.expr = parse_expression(tokens, pos) 
		return node
	}

	// If it's not an assignment, just parse it as normal math/functions
	return parse_expression(tokens, pos)
}

// --- 3. EMITTER ---
emit_lua :: proc(node: ^AST_Node) -> string {
	if node == nil do return ""

	#partial switch node.kind {
	case .Number, .Identifier:
		if node.value == "close" do return "tick.close"
		if node.value == "open" do return "tick.open"
		return node.value

	case .BinaryOp:
		return fmt.tprintf("%s %s %s", emit_lua(node.left), node.op, emit_lua(node.right))

	case .FunctionCall:
		mapped := node.callee
		if mapped == "ta.sma" do mapped = "viking.sma"

		out := fmt.tprintf("%s(", mapped)
		for arg, i in node.args {
			out = fmt.tprintf("%s%s", out, emit_lua(arg))
			if i < len(node.args) - 1 do out = fmt.tprintf("%s, ", out)
		}
		return fmt.tprintf("%s)", out)

	case .Assignment:
		// Translate PineScript assignment to a strict Lua 'local' variable
		return fmt.tprintf("local %s = %s", node.var_name, emit_lua(node.expr))
	}
	return ""
}

print_ast :: proc(node: ^AST_Node, indent: string = "") {
	if node == nil do return
	if node.kind == .Assignment {
		fmt.printf("%s[Assignment] -> %s =\n", indent, node.var_name)
		print_ast(node.expr, fmt.tprintf("%s  ", indent))
	} else if node.kind == .BinaryOp {
		fmt.printf("%s[Math: %s]\n", indent, node.op)
		print_ast(node.left, fmt.tprintf("%s  L: ", indent))
		print_ast(node.right, fmt.tprintf("%s  R: ", indent))
	} else if node.kind == .FunctionCall {
		fmt.printf("%s[Function Call] -> %s()\n", indent, node.callee)
		for arg, i in node.args {
			fmt.printf("%s  Arg %d:\n", indent, i)
			print_ast(arg, fmt.tprintf("%s    ", indent))
		}
	} else {
		fmt.printf("%s[%v] -> %s\n", indent, node.kind, node.value)
	}
}

test_transpiler :: proc() {
	// Our new test script: Creating a variable!
	script := "my_custom_sma = ta.sma(close + open / 2, 10)"
	fmt.println("1. User Pastes PineScript:", script)
	
	tokens := tokenize(script)
	pos := 0
	
	// Notice we use parse_statement now instead of parse_expression!
	ast_root := parse_statement(tokens[:], &pos)

	fmt.println("\n--- The Parser Brain (AST) ---")
	print_ast(ast_root)

	lua_code := emit_lua(ast_root)
	fmt.println("\n2. Viking Terminal Generates Lua:")
	fmt.println("---------------------------------")
	fmt.println(lua_code)
	fmt.println("---------------------------------")
}