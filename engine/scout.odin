package main

import "core:fmt"
import "core:math"

// --- THE DATA STRUCTURE ---
// This represents the data we pull from their trading history
TraderProfile :: struct {
    id:                 string,
    max_drawdown_pct:   f64,
    avg_trades_per_day: f64,
    gross_profit:       f64,
    gross_loss:         f64,
    daily_returns:      []f64, // Array of daily % returns for the consistency check
    holds_overnight:    bool,  // Did they violate the Flat-End protocol?
}

// --- PHASE 1: THE SNIPER PARAMETERS ---
MAX_DRAWDOWN       :: 5.0
MAX_TRADES_PER_DAY :: 3.0
MIN_PROFIT_FACTOR  :: 1.75
MAX_STD_DEV        :: 1.0 // Keep the variance incredibly tight

// --- THE CORE ALGORITHM ---
is_elite_sniper :: proc(trader: TraderProfile) -> (bool, string) {
    // 1. The Drawdown Guillotine
    if trader.max_drawdown_pct >= MAX_DRAWDOWN {
        return false, "Drawdown violation (>5%)"
    }

    // 2. The Frequency Filter
    if trader.avg_trades_per_day >= MAX_TRADES_PER_DAY {
        return false, "Overtrading (Tilt risk)"
    }

    // 3. The Flat-End Protocol
    if trader.holds_overnight {
        return false, "Overnight risk exposure"
    }

    // 4. The Profit Factor
    pf: f64 = 0.0
    if trader.gross_loss == 0.0 {
        pf = 999.0 // Infinite PF if no losses (highly unlikely, but mathematically safe)
    } else {
        pf = trader.gross_profit / math.abs(trader.gross_loss)
    }

    if pf <= MIN_PROFIT_FACTOR {
        return false, "Poor efficiency (PF < 1.75)"
    }

    // 5. The Consistency Curve (Standard Deviation)
    std_dev := calculate_std_dev(trader.daily_returns)
    if std_dev > MAX_STD_DEV {
        return false, "Inconsistent variance curve"
    }

    return true, "SNIPER APPROVED"
}

// Helper Math: Calculate Standard Deviation of daily returns
calculate_std_dev :: proc(returns: []f64) -> f64 {
    if len(returns) == 0 do return 0.0
    
    sum: f64 = 0.0
    for r in returns do sum += r
    mean := sum / f64(len(returns))

    variance_sum: f64 = 0.0
    for r in returns {
        diff := r - mean
        variance_sum += diff * diff
    }
    
    return math.sqrt(variance_sum / f64(len(returns)))
}

// --- THE TEST RUN ---
test_scout :: proc() {
    fmt.println("--- Booting Phase 1 Scouting Algorithm ---")

    // A simulated batch of retail users migrating to the Viking Terminal
    candidates := []TraderProfile{
        // Candidate 1: The Gambler (Hits huge wins, but fails DD and Overtrades)
        {"TRD-001", 15.2, 8.5, 15000.0, 14000.0, []f64{10.0, -8.0, 15.0, -12.0}, true},
        
        // Candidate 2: The Break-Even Grinder (Safe drawdown, but fails Profit Factor)
        {"TRD-002", 3.1, 1.2, 5000.0, 4800.0, []f64{0.5, 0.2, -0.4, 0.1}, false},
        
        // Candidate 3: The Elite Sniper (Passes every single metric cleanly)
        {"TRD-003", 1.8, 1.1, 12000.0, 4000.0, []f64{0.4, 0.3, -0.1, 0.5, 0.2}, false},
    }

    approved_count := 0

    for candidate in candidates {
        fmt.printf("Scanning %s... ", candidate.id)
        passed, reason := is_elite_sniper(candidate)
        
        if passed {
            fmt.printf("✅ [ACCEPTED] %s\n", reason)
            approved_count += 1
        } else {
            fmt.printf("❌ [REJECTED] %s\n", reason)
        }
    }

    fmt.printf("\nScan Complete. Elite Snipers secured: %d/%d\n", approved_count, len(candidates))
}