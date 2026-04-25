package main

import "core:c"
import "core:fmt"
import "core:math" // Essential for math.exp, math.cos, and math.abs
import "base:runtime" // For the @(export) directive to expose functions to LuaJIT

// --- THE MATRIX DATA STRUCTURES ---
// We force this struct to use C-compatible memory alignment.
// This allows LuaJIT to read it directly without translation.
HMMState :: struct {
    regime:          c.int,    // 0 = Ranging, 1 = Bull Trend, 2 = Bear Trend
    probability:     c.double, // e.g., 92.5% confidence
    volatility_node: c.double, // The dynamic volatility boundary
}

// --- THE NATIVE MATH FUNCTIONS ---
// The @(export, c) directive tells the compiler to expose this function 
// to the outside world (LuaJIT) as a standard C function.
@(export)
calculate_hmm_state :: proc "c" (asset_id: cstring, tick_index: c.int) -> HMMState {
    context = runtime.default_context() // Banishes the context error
    
    // In production, this reaches into your pre-allocated Odin ring buffer
    // and runs the heavy matrix multiplication for the Hidden Markov Model.
    
    // For the test fire, we simulate returning a high-probability Bull Regime
    return HMMState{
        regime          = 1, 
        probability     = 92.5,
        volatility_node = 1.34,
    }
}

// --- ADAPTIVE BSP STRUCTURES ---

AdaptiveBSPState :: struct {
    pressure_baseline: c.double, // The core adaptive trend line
    upper_band:        c.double, // Dynamic resistance
    lower_band:        c.double, // Dynamic support
    trend_velocity:    c.double, // Rate of change (momentum)
}

// --- ADAPTIVE BSP MATH BINDING ---

@(export)
calculate_adaptive_bsp :: proc "c" (asset_id: cstring, tick_index: c.int) -> AdaptiveBSPState {
    context = runtime.default_context() // Banishes the context error
    
    // In production, Odin grabs the raw volume and tick velocity 
    // to dynamically calculate the spline/pressure curve.
    
    // For the test fire, we simulate a bullish pressure state on the NAS100
    return AdaptiveBSPState{
        pressure_baseline = 15240.50,
        upper_band        = 15265.00,
        lower_band        = 15210.00,
        trend_velocity    = 2.4, 
    }
}

// --- KINETIC CANDLE STRUCTURES ---

KineticCandleState :: struct {
    // Physics
    velocity:   c.double,
    accel:      c.double,
    jerk:       c.double,
    state_code: c.int,     // 2 = HyperBull, 1 = BuildBull, -2 = HyperBear, -1 = BuildBear, 0 = Squeeze
    
    // Volume & CVD
    buy_vol:    c.double,
    sell_vol:   c.double,
    delta:      c.double,
    rel_vol:    c.double,  // Relative volume for Equivolume width
    
    // Whale Triggers
    whale_bull: c.bool,
    whale_bear: c.bool,
}

// --- KINETIC MATH BINDING ---

@(export)
calculate_kinetic_candle :: proc "c" (asset_id: cstring, tick_index: c.int) -> KineticCandleState {
    
    // In production, Odin loops through its ring buffer to calculate the WMA 
    // of the price changes, slicing the volume into Buy/Sell delta based on your 
    // exact price-action formula.
    
    // For the test fire, we simulate a 'Bull Hyper' Whale Anomaly
    return KineticCandleState{
        velocity   = 3.5,
        accel      = 1.2,
        jerk       = 0.5,
        state_code = 2,       // HyperBull
        buy_vol    = 850.0,
        sell_vol   = 200.0,
        delta      = 650.0,
        rel_vol    = 2.1,     // Over 2x normal volume (Wide candle)
        whale_bull = true,    // Triggers the anomaly footprint
        whale_bear = false,
    }
}

// --- QUANTUM NEURAL CORE v8.1 STRUCTURES ---

NeuralCoreState :: struct{
    // HMM Bayesian Output
    prob_bull:   c.double,
    prob_bear:   c.double,
    prob_chop:   c.double,
    
    // Trendilo & BSP (Z-Scores)
    z_trendilo:  c.double,
    z_bsp:       c.double,
    rms_band:    c.double,
    
    // JOAT Pulse
    ribbon_strength: c.double,
    trend_dir:       c.int,    // 1 for Bull, -1 for Bear
}

// --- NEURAL CORE MATH BINDING ---

@(export)
calculate_neural_core :: proc "c" (asset_id: cstring, tick_index: c.int) -> NeuralCoreState {
    context = runtime.default_context() // Banishes the context error
    
    // Odin implementation of your Bayesian Engine:
    // This will run the Ehlers SuperSmoother and the HMM PDF math 
    // in raw C-compiled machine code.
    
    return NeuralCoreState{
        prob_bull       = 0.15,
        prob_bear       = 0.05,
        prob_chop       = 0.80, // High chop! HMM Chop Protection Active.
        z_trendilo      = 0.45,
        z_bsp           = -0.22,
        rms_band        = 1.10,
        ribbon_strength = 0.35,
        trend_dir       = 1,
    }
}

// --- MASTER ENGINE v10.8 STRUCTURES ---

MasterHUDState :: struct {
    // Risk & HUD
    lot_size:        c.double,
    target_prob:     c.double,
    is_vacuum:       c.bool,
    vol_ratio:       c.double,
    
    // Protocol 3: Zone Failure Indicators
    bull_mz_failed:  c.bool,
    bear_mz_failed:  c.bool,
    kinetic_break:   c.bool,
    
    // MTF Confluence (Aggregated)
    confluence_score: c.int, // 0-4 based on how many TFs align
}

// --- MASTER HUD MATH BINDING ---

@(export)
calculate_master_hud :: proc "c" (asset_id: cstring, tick_index: c.int) -> MasterHUDState {
    context = runtime.default_context() // Banishes the context error
    // This is where Odin runs your Bayesian HMM across all 4 timeframes (tf1-tf4)
    // and calculates the Mitigation Zone violations.

    // 1. We grab the current price from our buffer
    current_price := get_latest_price(asset_id)
    
    // 2. We check our nearest Mitigation Zones [cite: 30]
    // In your v5.0 logic: Price was inside a Bullish MZ and closed below its floor [cite: 31]
    bull_zone_floor := 15210.0 // Simulated from your HVN engine
    bear_zone_ceil  := 15265.0
    
    // 3. Detect the "Zone Failure" (Protocol 3)
    bull_failed := current_price < bull_zone_floor // Institutional support destroyed
    bear_failed := current_price > bear_zone_ceil  // Institutional resistance destroyed
    
    // 4. Combine with Kinetic Breakout (Velocity > Threshold) [cite: 70]
    kinetic_active := check_kinetic_velocity(asset_id, 1.3) // Using your knife_thr=1.3
    
    return MasterHUDState{
        lot_size         = 1.25,
        target_prob      = 68.5,
        is_vacuum        = false,
        vol_ratio        = 1.15,
        bull_mz_failed   = false,
        bear_mz_failed   = true,  // Triggering Protocol 3!
        kinetic_break    = true,
        confluence_score = 3,
    }
}

// --- SVP DATA STRUCTURES ---
SVPState :: struct {
    poc:           c.double,
    vah:           c.double,
    val:           c.double,
    dyn_thickness: c.double,
}

// --- SVP MATH BINDING ---
@(export)
calculate_svp :: proc "c" (asset_id: cstring, tick_index: c.int) -> SVPState {
    context = runtime.default_context() // Banishes the context error
    // In production, this calculates the alpha_svp based on g_er [cite: 33]
    // and uses a 64-bit double ring buffer for ultra-precise Value Area math.
    
    return SVPState{
        poc           = 15225.50,
        vah           = 15245.00,
        val           = 15210.00,
        dyn_thickness = 5.5,
    }
}

// --- ADAPTIVE HVN / MITIGATION ZONE LOGIC ---

// We represent the "Strength" as a float to capture that 0-100% score from your v5.0 script [cite: 19]
HVNNode :: struct {
    top:       f64,
    bottom:    f64,
    strength:  f64,
    is_bull:   bool,
    mitigated: bool,
}

// THE FUSION ENGINE: This is the Odin version of your array.new<MitigationZone>() [cite: 16]
// It checks if a new volume anomaly overlaps with an existing zone [cite: 20]
calculate_hvn_fusion :: proc(new_top, new_bot, strength: f64, is_bull: bool, existing_zones: []HVNNode) -> (HVNNode, bool) {
    for zone in existing_zones {
        if zone.is_bull == is_bull {
            // Price Overlap Detection [cite: 20]
            if new_top >= zone.bottom && new_bot <= zone.top {
                return HVNNode{
                    top       = max(zone.top, new_top),       // Fuse the ceiling [cite: 21]
                    bottom    = min(zone.bottom, new_bot),    // Fuse the floor [cite: 21]
                    strength  = max(zone.strength, strength), // Take the higher intensity [cite: 21]
                    is_bull   = is_bull,
                    mitigated = false,                        // Reactivate on fusion! [cite: 21]
                }, true
            }
        }
    }
    return HVNNode{new_top, new_bot, strength, is_bull, false}, false
}

// --- VIRGIN POC (VPOC) STRUCTURES ---

VPOCNode :: struct {
    price:      c.double,
    start_time: c.int,      // bar_index in Pine
    is_active:  bool,
    is_tested:  bool,       // True if price has returned to touch it
}

// Global buffer for current active VPOCs
active_vpocs: [dynamic]VPOCNode

// THE VPOC ENGINE: Handles creation and cleanup
update_vpoc_engine :: proc(current_poc: f64, current_bar: int, high: f64, low: f64) {
    
    // 1. Overlap Prevention (Odin version of canCreateVPOC)
    // Only create a new one if it's at least 5 ticks away from others 
    can_create := true
    MINTICK :: 0.25 // Example for NAS100
    
    for v in active_vpocs {
        if math.abs(v.price - current_poc) <= (MINTICK * 5.0) {
            can_create = false
            break
        }
    }

    // 2. Mitigation Check (The Sniper Trap)
    // We loop backwards through active VPOCs to see if they were hit
    for i := len(active_vpocs) - 1; i >= 0; i -= 1 {
        v := &active_vpocs[i]
        
        // 15-Bar Grace Period: Price must escape before the trap is armed 
        if current_bar - int(v.start_time) > 15 {
            if high >= v.price && low <= v.price {
                // POC MITIGATED: Remove it from the live engine
                unordered_remove(&active_vpocs, i)
            }
        }
    }
}

// --- DIGITAL SIGNAL PROCESSING UTILITIES ---

// Ehlers SuperSmoother Filter
// This is the direct Odin translation of your f_supersmoother 
calculate_supersmoother :: proc(src: []f64, length: int) -> f64 {
    if len(src) < 3 do return src[0] // Safety check for early bars

    // Constants based on the Butterworth filter math 
    PI :: 3.14159265358979323846
    SQRT2 :: 1.41421356237
    
    arg := SQRT2 * PI / f64(max(length, 1))
    a1 := math.exp(-arg)
    b1 := 2.0 * a1 * math.cos(arg)
    c2 := b1
    c3 := -a1 * a1
    c1 := 1.0 - c2 - c3

    // In Odin, we reach directly into our pre-allocated ring buffer [cite: 4]
    // PINE: filt := c1 * (src + nz(src[1])) / 2.0 + c2 * nz(filt[1]) + c3 * nz(filt[2]) 
    
    // Note: 'src' here represents the historical values at indices 0, 1, 2
    filt := c1 * (src[0] + src[1]) / 2.0 + c2 * src[1] + c3 * src[2]
    
    return filt
}