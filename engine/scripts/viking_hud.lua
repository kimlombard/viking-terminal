-- viking_hud.lua
local ffi = require("ffi")

-- 1. Teach LuaJIT the Master HUD C-signature
ffi.cdef[[
    typedef struct {
        double lot_size;
        double target_prob;
        bool is_vacuum;
        double vol_ratio;
        bool bull_mz_failed;
        bool bear_mz_failed;
        bool kinetic_break;
        int confluence_score;
    } MasterHUDState;

    MasterHUDState calculate_master_hud(const char* asset_id, int tick_index);
]]

viking_hud = viking_hud or {}

-- 2. The Master HUD Wrapper
function viking_hud.master_hud(asset_identifier, tick_index)
    -- Calls the raw Odin Master HUD math [cite: 17, 18]
    local state = ffi.C.calculate_master_hud(asset_identifier, tick_index)
    
    return state.lot_size, state.target_prob, state.is_vacuum, state.vol_ratio,
           state.bull_mz_failed, state.bear_mz_failed, state.kinetic_break, state.confluence_score
end