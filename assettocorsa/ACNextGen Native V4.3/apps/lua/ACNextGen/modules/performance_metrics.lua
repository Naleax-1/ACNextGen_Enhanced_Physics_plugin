---@diagnostic disable: undefined-global
-- Render-time evidence only. This module never enables or changes physics.
local M={}
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
-- Render-rate input evidence only; never forward these vectors to a force API.
function M.inputAudit(car,sim)
    local function field(o,k)
        local ok,v=pcall(function() return o[k] end);if ok then return v end
    end
    local function vector(v)
        local x,y,z=field(v,'x'),field(v,'y'),field(v,'z')
        if finite(x) and finite(y) and finite(z) then return {x,y,z} end
    end
    local a={schema=1,source='render_sdk',acceleration_units='g',acceleration_axes='car: X lateral, Y vertical, Z longitudinal',
        live=sim and sim.isOnlineRace==false and sim.isPaused==false and sim.isReplayActive==false or false,
        acceleration_g=vector(field(car,'acceleration')),wheels={}}
    local wheels=field(car,'wheels')
    for i=0,3 do
        local w=field(wheels,i);local p=vector(field(w,'contactPoint'));local n=vector(field(w,'contactNormal'))
        local norm=n and n[1]^2+n[2]^2+n[3]^2
        local load,travel=field(w,'load'),field(w,'suspensionTravel')
        a.wheels[#a.wheels+1]={index=i,contact_point_world_m=p,contact_normal_world=n,
            normal_well_formed=norm~=nil and norm>=.81 and norm<=1.21,
            wheel_position_world_m=vector(field(w,'position')),load_n=finite(load) and load or nil,
            suspension_travel_m=finite(travel) and travel or nil}
    end
    return a
end
function M.new(writer)
    local s={frames={},elapsed=0,mode=nil,sequence=0,rows=0,last=nil,error=''}
    function s.reset(mode) s.frames={};s.elapsed=0;s.mode=mode end
    function s.add(dt,mode,snapshot)
        if mode~=s.mode then s.reset(mode) end
        if not finite(dt) or dt<=0 or dt>10 or mode=='inactive' then return end
        s.frames[#s.frames+1]=dt*1000;s.elapsed=s.elapsed+dt
        if s.elapsed<1 then return end
        table.sort(s.frames)
        local n=#s.frames
        local function percentile(p) return s.frames[math.max(1,math.ceil(n*p))] end
        local slow=math.max(1,math.ceil(n*.01));local sum=0
        for i=n-slow+1,n do sum=sum+s.frames[i] end
        s.sequence=s.sequence+1
        -- Metadata/JSON are acquired once per window, never per render frame.
        local row=snapshot()
        row.schema=1;row.sequence=s.sequence;row.mode=mode;row.source='ui.deltaTime'
        row.frame_count=n;row.window_seconds=s.elapsed;row.mean_fps=n/s.elapsed
        row.frame_ms_p50=percentile(.50);row.frame_ms_p95=percentile(.95)
        row.frame_ms_p99=percentile(.99);row.frame_ms_max=s.frames[n]
        row.low_1_percent_fps=1000/(sum/slow)
        s.last=row
        if s.rows<3600 then
            local ok,message=pcall(writer,row)
            if ok then s.rows=s.rows+1;s.error='' else s.error=tostring(message) end
        end
        s.reset(mode)
    end
    return s
end
return M
