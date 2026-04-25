package main

import "core:fmt"
import "core:net"
import "core:encoding/json"
import "core:strings"

// 1. The Payload Structure (Matches exactly what Elixir expects)
TradeSignal :: struct {
    trader_id: string,
    action:    string,
    asset:     string,
    size:      string,
}

// 2. The Core Publisher Function
publish_to_redis :: proc(channel: string, signal: TradeSignal) -> bool {
    // Marshal our struct into a clean JSON byte array
    json_data, err := json.marshal(signal)
    if err != nil {
        fmt.eprintln("Failed to encode JSON:", err)
        return false
    }
    defer delete(json_data)
    json_string := string(json_data)

    // Connect to the local Redis server (or your Upstash endpoint)
    endpoint, ok := net.parse_endpoint("127.0.0.1:6379")
    socket, dial_err := net.dial_tcp(endpoint)
    if dial_err != nil {
        fmt.eprintln("Failed to connect to Redis:", dial_err)
        return false
    }
    defer net.close(socket)

    // Construct the strict RESP (Redis Serialization Protocol) command
    // Format: *<number of arguments>\r\n$<length of arg1>\r\n<arg1>\r\n...
    command := fmt.tprintf("*3\r\n$7\r\nPUBLISH\r\n$%d\r\n%s\r\n$%d\r\n%s\r\n", 
                           len(channel), channel, 
                           len(json_string), json_string)

    // Blast the command down the TCP pipe
    bytes_sent, send_err := net.send_tcp(socket, transmute([]byte)command)
    if send_err != nil {
        fmt.eprintln("Failed to send data to Redis:", send_err)
        return false
    }

    fmt.printf("⚡ Successfully published %d bytes to Redis channel '%s'\n", bytes_sent, channel)
    return true
}

// 3. The Test Fire
test_publisher :: proc() {
    fmt.println("--- Booting Odin Redis Bridge ---")

    // Simulate an elite sniper passing the algorithmic filter
    live_signal := TradeSignal{
        trader_id = "TRD-003",
        action    = "BUY",
        asset     = "XAUUSD",
        size      = "2 Lots",
    }

    // Fire the signal to the exact channel Elixir is listening to
    success := publish_to_redis("trade_signals", live_signal)
    
    if success {
        fmt.println("✅ Signal routed. Handing off to Elixir GenServers.")
    } else {
        fmt.println("❌ Network failure.")
    }
}