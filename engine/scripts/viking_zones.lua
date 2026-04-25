-- viking_zones.lua
local ffi = require("ffi")

-- 1. Define the structures for Zones and SVP
ffi.cdef[[
    typedef struct {
        double poc;
        double vah;
        double val;
        double dyn_thickness;
    } SVPState;

    typedef struct {
        double top;
        double bottom;
        float strength;
        bool is_bullish;
        bool mitigated;
    } ZoneState;

    SVPState calculate_svp(const char* asset_id, int tick_index);
    ZoneState get_nearest_zones(const char* asset_id, int tick_index);
]]

viking_zones = viking_zones or {}

-- 2. The SVP Wrapper
function viking_zones.svp(asset_identifier, tick_index)
    local state = ffi.C.calculate_svp(asset_identifier, tick_index)
    return state.poc, state.vah, state.val, state.dyn_thickness
end

-- 3. The Mitigation Zone Wrapper
function viking_zones.nearest_zones(asset_identifier, tick_index)
    local state = ffi.C.get_nearest_zones(asset_identifier, tick_index)
    return state.top, state.bottom, state.strength, state.is_bullish, state.mitigated
end