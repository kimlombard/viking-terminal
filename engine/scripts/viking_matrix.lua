-- viking_matrix.lua
local ffi = require("ffi")

-- 1. Teach LuaJIT the exact signature of the Odin C-struct and function
ffi.cdef[[
    typedef struct {
        double velocity; double accel; double jerk; int state_code;
        double buy_vol; double sell_vol; double delta; double rel_vol;
        bool whale_bull; bool whale_bear;
    } KineticCandleState;

    typedef struct {
        double prob_bull; double prob_bear; double prob_chop;
        double z_trendilo; double z_bsp; double rms_band;
        double ribbon_strength; int trend_dir;
    } NeuralCoreState;

    typedef struct {
        double pressure_baseline;
        double upper_band;
        double lower_band;
        double trend_velocity;
    } AdaptiveBSPState;

    typedef struct {
        int regime;
        double probability;
        double volatility_node;
    } HMMState;

    KineticCandleState calculate_kinetic_candle(const char* asset_id, int tick_index);
    NeuralCoreState calculate_neural_core(const char* asset_id, int tick_index);
    AdaptiveBSPState calculate_adaptive_bsp(const char* asset_id, int tick_index);
    HMMState calculate_hmm_state(const char* asset_id, int tick_index);
]]

viking_matrix = viking_matrix or {}

-- ==========================================
-- KINETIC PHYSICS WRAPPER
-- ==========================================
function viking_matrix.kinetic_state(asset_identifier, tick_index)
    local state = ffi.C.calculate_kinetic_candle(asset_identifier, tick_index)
    
    return state.velocity, state.accel, state.jerk, state.state_code, 
           state.delta, state.rel_vol, state.whale_bull, state.whale_bear
end

-- ==========================================
-- QUANTUM NEURAL CORE v8.1 WRAPPER
-- ==========================================
function viking_matrix.neural_core(asset_identifier, tick_index)
    local state = ffi.C.calculate_neural_core(asset_identifier, tick_index)
    
    return state.prob_bull, state.prob_bear, state.prob_chop, 
           state.z_trendilo, state.z_bsp, state.rms_band, 
           state.ribbon_strength, state.trend_dir
end

-- ==========================================
-- HMM REGIME WRAPPER
-- ==========================================
function viking_matrix.hmm_state(asset_identifier, tick_index)
    local state = ffi.C.calculate_hmm_state(asset_identifier, tick_index)
    
    return state.regime, state.probability
end

-- ==========================================
-- ADAPTIVE BSP WRAPPER
-- ==========================================
function viking_matrix.adaptive_bsp(asset_identifier, tick_index)
    local state = ffi.C.calculate_adaptive_bsp(asset_identifier, tick_index)
    
    return state.pressure_baseline, state.upper_band, state.lower_band, state.trend_velocity
end