package main

import "core:math"

// --- THE EFFICIENCY RATIO (ER) ENGINE ---
// ER = Signal / Noise
// Signal = ABS(Current Close - Close N Periods Ago)
// Noise = Sum of ABS(Current Close - Previous Close) over N Periods

update_er :: proc(er: ^EfficiencyRatio, current_close: f64) -> f64 {
    // 1. Add current close to history buffer
    append(&er.history, current_close)
    
    // 2. Wait until we have enough data (Period + 1 to calculate N differences)
    if len(er.history) <= er.period {
        return 0.0 // Not enough data yet
    }

    // 3. Keep buffer exactly at period + 1 size by removing the oldest entry
    if len(er.history) > er.period + 1 {
        ordered_remove(&er.history, 0)
    }

    // 4. Calculate Signal (Absolute net change over the whole period)
    signal := math.abs(er.history[er.period] - er.history[0])

    // 5. Calculate Noise (Sum of all individual candle absolute changes)
    noise: f64 = 0.0
    for i := 1; i <= er.period; i += 1 {
        noise += math.abs(er.history[i] - er.history[i-1])
    }

    // 6. Calculate Ratio (Safety check for divide by zero on flatlines)
    if noise == 0.0 {
        er.last_er = 0.0
    } else {
        er.last_er = signal / noise
    }

    return er.last_er
}

/// --- GAUSSIAN PROBABILITY DENSITY FUNCTION ---
// Replaces the f_pdf from PineScript
f_pdf :: proc(x: f64, mu: f64, sigma: f64) -> f64 {
    variance := sigma * sigma
    if variance == 0.0 do return 0.0
    
    // FIX 1: math.PI is uppercase.
    // FIX 2: math.pow expects two f64s, so '2' becomes '2.0'.
    return (1.0 / math.sqrt(2.0 * math.PI * variance)) * math.exp(-math.pow(x - mu, 2.0) / (2.0 * variance))
}

// --- THE MATRIX ENGINE ---
MatrixState :: struct {
    prob_bull:  f64,
    prob_bear:  f64,
    prob_chop:  f64,
    net_regime: f64,
}

init_matrix_state :: proc() -> MatrixState {
    return MatrixState{
        prob_bull = 0.3333,
        prob_bear = 0.3333,
        prob_chop = 0.3333,
        net_regime = 0.0,
    }
}

// The Core HMM Bayesian Update
update_matrix :: proc(ms: ^MatrixState, state: ^EngineState, er: f64, obs_mom: f64, obs_vol: f64) -> f64 {
    
    // 1. Calculate Dynamic Transition Probabilities (Adaptive Logic)
    dyn_p_stay_bull := math.min(0.99, state.base_bull + (er * 0.25 * state.hmm_sens))
    dyn_p_stay_bear := math.min(0.99, state.base_bear + (er * 0.25 * state.hmm_sens))
    dyn_p_stay_chop := math.min(0.99, state.base_chop + ((1.0 - er) * 0.35 * state.hmm_sens))

    // 2. Base Transition Matrix Rules
    trans_bull_bear := (1.0 - dyn_p_stay_bull) * 0.2
    trans_bull_chop := (1.0 - dyn_p_stay_bull) * 0.8
    trans_bear_bull := (1.0 - dyn_p_stay_bear) * 0.2
    trans_bear_chop := (1.0 - dyn_p_stay_bear) * 0.8
    trans_chop_bull := (1.0 - dyn_p_stay_chop) * 0.5
    trans_chop_bear := (1.0 - dyn_p_stay_chop) * 0.5

    // 3. Prior Probabilities (What we expect to happen before seeing data)
    prior_bull := (ms.prob_bull * dyn_p_stay_bull) + (ms.prob_bear * trans_bear_bull) + (ms.prob_chop * trans_chop_bull)
    prior_bear := (ms.prob_bull * trans_bull_bear) + (ms.prob_bear * dyn_p_stay_bear) + (ms.prob_chop * trans_chop_bear)
    prior_chop := (ms.prob_bull * trans_bull_chop) + (ms.prob_bear * trans_bear_chop) + (ms.prob_chop * dyn_p_stay_chop)

    // 4. Likelihoods (How well does current price action match our definitions of Bull/Bear/Chop?)
    like_bull := f_pdf(obs_mom, 1.0, 1.0) * f_pdf(obs_vol, -0.5, 1.0)
    like_bear := f_pdf(obs_mom, -1.0, 1.0) * f_pdf(obs_vol, 1.0, 1.0)
    like_chop := f_pdf(obs_mom, 0.0, 0.5) * f_pdf(obs_vol, 1.5, 1.0)

    // 5. Posterior Probabilities (Bayes' Theorem applied)
    post_bull := prior_bull * like_bull
    post_bear := prior_bear * like_bear
    post_chop := prior_chop * like_chop

    total_post := post_bull + post_bear + post_chop

    // Normalize probabilities so they add up to 1.0
    if total_post > 0.0 {
        ms.prob_bull = post_bull / total_post
        ms.prob_bear = post_bear / total_post
        ms.prob_chop = post_chop / total_post
    }

    // 6. The Net Regime Output
    pct_bull := ms.prob_bull * 100.0
    pct_bear := ms.prob_bear * 100.0
    
    ms.net_regime = pct_bull - pct_bear
    return ms.net_regime
}

// ==========================================
// --- QUANTITATIVE MATH LIBRARY ---
// ==========================================

// --- 1. EXPONENTIAL MOVING AVERAGE (EMA) ---
EmaTracker :: struct {
    period: f64,
    alpha:  f64,
    value:  f64,
    seeded: bool,
}

init_ema :: proc(period: int) -> EmaTracker {
    return EmaTracker{
        period = f64(period),
        alpha  = 2.0 / (f64(period) + 1.0),
        value  = 0.0,
        seeded = false,
    }
}

update_ema :: proc(ema: ^EmaTracker, current_val: f64) -> f64 {
    if !ema.seeded {
        ema.value = current_val
        ema.seeded = true
    } else {
        ema.value = ema.value + ema.alpha * (current_val - ema.value)
    }
    return ema.value
}

// --- 2. ROLLING WINDOW (SMA & StDev) ---
RollingWindow :: struct {
    period: int,
    window: [dynamic]f64,
    index:  int,
    filled: bool,
}

init_rolling_window :: proc(period: int) -> RollingWindow {
    return RollingWindow{
        period = period,
        window = make([dynamic]f64, period),
        index  = 0,
        filled = false,
    }
}

update_window :: proc(rw: ^RollingWindow, val: f64) {
    rw.window[rw.index] = val
    rw.index += 1
    if rw.index >= rw.period {
        rw.index = 0
        rw.filled = true
    }
}

get_sma :: proc(rw: ^RollingWindow) -> f64 {
    if !rw.filled && rw.index == 0 do return 0.0
    
    limit := rw.filled ? rw.period : rw.index
    sum: f64 = 0.0
    for i := 0; i < limit; i += 1 {
        sum += rw.window[i]
    }
    return sum / f64(limit)
}

get_stdev :: proc(rw: ^RollingWindow, sma: f64) -> f64 {
    if !rw.filled && rw.index < 2 do return 0.0
    
    limit := rw.filled ? rw.period : rw.index
    sum_sq_diff: f64 = 0.0
    for i := 0; i < limit; i += 1 {
        diff := rw.window[i] - sma
        sum_sq_diff += diff * diff
    }
    
    // Using population variance
    variance := sum_sq_diff / f64(limit) 
    return math.sqrt(variance)
}

get_percentrank :: proc(rw: ^RollingWindow, current_val: f64) -> f64 {
    if !rw.filled && rw.index == 0 do return 0.0
    
    limit := rw.filled ? rw.period : rw.index
    if limit == 0 do return 0.0
    
    count := 0
    for i := 0; i < limit; i += 1 {
        if rw.window[i] <= current_val {
            count += 1
        }
    }
    return f64(count) / f64(limit)
}

get_highest :: proc(rw: ^RollingWindow) -> f64 {
    if !rw.filled && rw.index == 0 do return 0.0
    limit := rw.filled ? rw.period : rw.index
    max_val := -9999999.0
    for i := 0; i < limit; i += 1 {
        if rw.window[i] > max_val do max_val = rw.window[i]
    }
    return max_val
}

get_lowest :: proc(rw: ^RollingWindow) -> f64 {
    if !rw.filled && rw.index == 0 do return 0.0
    limit := rw.filled ? rw.period : rw.index
    min_val := 9999999.0
    for i := 0; i < limit; i += 1 {
        if rw.window[i] < min_val do min_val = rw.window[i]
    }
    return min_val
}

// --- 3. THE TRUE JOAT PULSE ENGINE ---
JoatPulse :: struct {
    fast_ema:     EmaTracker,
    slow_ema:     EmaTracker,
    width_window: RollingWindow,
    max_thick:    f64,
}

init_joat_pulse :: proc(fast_len: int, slow_len: int, max_thick: f64) -> JoatPulse {
    return JoatPulse{
        fast_ema     = init_ema(fast_len),
        slow_ema     = init_ema(slow_len),
        width_window = init_rolling_window(50),
        max_thick    = max_thick,
    }
}

update_joat_pulse :: proc(jp: ^JoatPulse, close: f64, net_regime: f64) -> (f64, f64, int) {
    fast := update_ema(&jp.fast_ema, close)
    slow := update_ema(&jp.slow_ema, close)
    
    trend_dir := fast > slow ? 1 : -1
    
    // Percent width of the EMAs
    ribbon_width_pct := (math.abs(fast - slow) / close) * 100.0
    
    // Calculate PercentRank (Strength compared to last 50 periods)
    strength := get_percentrank(&jp.width_window, ribbon_width_pct)
    
    // Update window AFTER calculating rank
    update_window(&jp.width_window, ribbon_width_pct)
    
    dyn_thickness := jp.max_thick * strength
    
    nr_top := net_regime + dyn_thickness
    nr_bot := net_regime - dyn_thickness
    
    return nr_top, nr_bot, trend_dir
}

// --- 3. ADAPTIVE SIGNAL LINE (KAMA) ---
AdaptiveSignal :: struct {
    fast_alpha: f64,
    slow_alpha: f64,
    last_sig:   f64,
    is_seeded:  bool,
}

init_adaptive_signal :: proc(fast_len: int, slow_len: int) -> AdaptiveSignal {
    return AdaptiveSignal{
        fast_alpha = 2.0 / (f64(fast_len) + 1.0),
        slow_alpha = 2.0 / (f64(slow_len) + 1.0),
        last_sig   = 0.0,
        is_seeded  = false,
    }
}

update_adaptive_signal :: proc(as: ^AdaptiveSignal, net_regime: f64, er: f64) -> f64 {
    if !as.is_seeded {
        as.last_sig = net_regime
        as.is_seeded = true
        return as.last_sig
    }
    // sc = ((er * fast_alpha) + ((1.0 - er) * slow_alpha))^2
    sc := math.pow((er * as.fast_alpha) + ((1.0 - er) * as.slow_alpha), 2.0)
    as.last_sig = as.last_sig + sc * (net_regime - as.last_sig)
    return as.last_sig
}

// --- 4. ZERO-LAG DIVERGENCE ENGINE ---
SwingTracker :: struct {
    div_len:        int,
    close_window:   RollingWindow,
    prev_time:      i64,
    prev_close:     f64,
    prev_osc:       f64,
    
    last_high_p:    f64,
    last_high_osc:  f64,
    last_high_time: i64,
    
    last_low_p:     f64,
    last_low_osc:   f64,
    last_low_time:  i64,
    
    is_seeded:      bool,
}

init_swing_tracker :: proc(div_len: int) -> SwingTracker {
    return SwingTracker{
        div_len      = div_len,
        close_window = init_rolling_window(div_len),
        last_high_p  = -1.0,
        last_low_p   = -1.0,
        is_seeded    = false,
    }
}

// Returns: (RegBull, RegBear, HidBull, HidBear, PivotTime)
update_swing_tracker :: proc(st: ^SwingTracker, current_time: i64, close: f64, osc: f64) -> (bool, bool, bool, bool, i64) {
    if !st.is_seeded {
        st.prev_time = current_time // <-- Seed the time
        st.prev_close = close
        st.prev_osc = osc
        update_window(&st.close_window, close)
        st.is_seeded = true
        return false, false, false, false, 0
    }

    reg_bull, reg_bear, hid_bull, hid_bear := false, false, false, false
    pivot_time: i64 = 0

    highest_prev := get_highest(&st.close_window)
    lowest_prev  := get_lowest(&st.close_window)

    // Check Swing High
    if st.prev_close == highest_prev && close < st.prev_close {
        if st.last_high_p != -1.0 {
            if st.prev_close > st.last_high_p && st.prev_osc < st.last_high_osc do reg_bear = true
            if st.prev_close < st.last_high_p && st.prev_osc > st.last_high_osc do hid_bear = true
        }
        st.last_high_p = st.prev_close
        st.last_high_osc = st.prev_osc
        st.last_high_time = st.prev_time // <-- Use exact tracked time!
        pivot_time = st.last_high_time
    }

    // Check Swing Low
    if st.prev_close == lowest_prev && close > st.prev_close {
        if st.last_low_p != -1.0 {
            if st.prev_close < st.last_low_p && st.prev_osc > st.last_low_osc do reg_bull = true
            if st.prev_close > st.last_low_p && st.prev_osc < st.last_low_osc do hid_bull = true
        }
        st.last_low_p = st.prev_close
        st.last_low_osc = st.prev_osc
        st.last_low_time = st.prev_time // <-- Use exact tracked time!
        pivot_time = st.last_low_time
    }

    // Prepare for next tick
    update_window(&st.close_window, close)
    st.prev_time = current_time // <-- Save current time for next tick
    st.prev_close = close
    st.prev_osc = osc

    return reg_bull, reg_bear, hid_bull, hid_bear, pivot_time
}