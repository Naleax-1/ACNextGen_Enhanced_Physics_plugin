---@diagnostic disable: undefined-global
-- Render-time evidence only. This module never enables or changes physics.
local M={}
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
-- Diagnostic metadata only; never a force input or a physical-phase certificate.
function M.nativeReference()
    local function field(o,k) local ok,v=pcall(function() return o[k] end);if ok then return v end end
    local function read(f) local ok,v=pcall(f);if ok then return v end end
    local before=read(function() return ac.getSim().frame end)
    local liveCar=read(function() return ac.getCar(0) end)
    local livePhysics=read(function() return ac.getCarPhysics(0) end)
    local id=read(function() return ac.getCarID(0) end)
    local timeBefore=field(liveCar,'timestamp')
    -- Copy the fields inside the brackets, not after capturing the end frame.
    local car={physicsAvailable=field(liveCar,'physicsAvailable'),wheels={}}
    local cp={isAvailable=field(livePhysics,'isAvailable'),wheels={}}
    for _,name in ipairs({'differentialPreload','differentialPower','differentialCoast','drivetrainTorque',
        'mass','gear','gas','brake','handbrake'}) do car[name]=field(liveCar,name) end
    for _,name in ipairs({'gearRatio','finalRatio','engineInertia','drivetrainInertia','drivetrainVelocity',
        'clutchInertia','clutchState'}) do cp[name]=field(livePhysics,name) end
    for i=0,3 do
        local w=field(field(liveCar,'wheels'),i);local pw=field(field(livePhysics,'wheels'),i)
        car.wheels[i]={angularSpeed=field(w,'angularSpeed'),load=field(w,'load'),suspensionTravel=field(w,'suspensionTravel')}
        local copy={};cp.wheels[i]=copy
        for _,name in ipairs({'brakeTorque','handbrakeTorque','electricTorque','feedbackTorque',
            'angularInertia','shaftVelocity','shaftInertia'}) do copy[name]=field(pw,name) end
    end
    local timeAfter=field(liveCar,'timestamp')
    local idAfter=read(function() return ac.getCarID(0) end)
    local after=read(function() return ac.getSim().frame end)
    local beforeType,afterType=type(before),type(after)
    -- LuaJIT can expose a uint64 SDK frame as cdata. Numeric strings remain
    -- invalid, and integers beyond exact double precision are not admitted.
    local function frame(v)
        if type(v)~='number' and type(v)~='cdata' then return nil end
        local n=tonumber(v)
        if finite(n) and n>=0 and n<=9007199254740991 and n%1==0 then return n end
    end
    before,after=frame(before),frame(after)
    local stable=before~=nil and after~=nil and before==after
    local sameIdentity=type(id)=='string' and id~='' and id==idAfter
    local timeBeforeType,timeAfterType=type(timeBefore),type(timeAfter)
    local function recordTime(v)
        if type(v)~='number' and type(v)~='cdata' then return nil end
        local n=tonumber(v);if finite(n) and n>=0 and n<=9007199254740991 then return n end
    end
    timeBefore,timeAfter=recordTime(timeBefore),recordTime(timeAfter)
    local timeKnown=finite(timeBefore) and finite(timeAfter)
    local timeConflict=(finite(timeBefore)~=finite(timeAfter)) or (timeKnown and timeBefore~=timeAfter)
    local physicsAvailable=field(car,'physicsAvailable')==true
    local cpAvailable=field(cp,'isAvailable')==true
    local r={schema=2,source='render_sdk_native_reference_v2',timestamp_unix_s=os.time(),
        car_id=type(id)=='string' and id or nil,sdk_frame_before=finite(before) and before or nil,
        sdk_frame_after=finite(after) and after or nil,same_sdk_frame=stable,
        sdk_frame_before_type=beforeType,sdk_frame_after_type=afterType,
        same_car_id=sameIdentity,car_record_time_available=timeKnown,same_car_record_time=timeKnown and not timeConflict,
        car_record_time_before_type=timeBeforeType,car_record_time_after_type=timeAfterType,
        car_record_time_before_ms_raw=finite(timeBefore) and timeBefore or nil,
        car_record_time_after_ms_raw=finite(timeAfter) and timeAfter or nil,
        physics_available=physicsAvailable,car_physics_available=cpAvailable,
        physics_phase_verified=false,units_qualified=false,actuation_allowed=false,mass_scope_verified=false,
        available={},wheels={}}
    local function number(destination,key,value,allowed,availability)
        local valid=allowed and finite(value) or false
        availability[key]=valid;if valid then destination[key]=value end
    end
    local allowed=stable and sameIdentity and not timeConflict and physicsAvailable
    number(r,'differential_preload_raw',field(car,'differentialPreload'),allowed,r.available)
    number(r,'drivetrain_torque_raw',field(car,'drivetrainTorque'),allowed,r.available)
    number(r,'differential_power_raw',field(car,'differentialPower'),allowed,r.available)
    number(r,'differential_coast_raw',field(car,'differentialCoast'),allowed,r.available)
    number(r,'mass_reported_raw',field(car,'mass'),allowed,r.available)
    for key,name in pairs({gear_ratio_raw='gearRatio',final_ratio_raw='finalRatio',engine_inertia_raw='engineInertia',
        drivetrain_inertia_raw='drivetrainInertia',drivetrain_velocity_raw='drivetrainVelocity',
        clutch_inertia_raw='clutchInertia',clutch_state_raw='clutchState'}) do
        number(r,key,field(cp,name),allowed and cpAvailable,r.available)
    end
    for _,name in ipairs({'gear','gas','brake','handbrake'}) do
        number(r,name..'_raw',field(car,name),allowed,r.available)
    end
    for i=0,3 do
        local w=field(field(car,'wheels'),i);local pw=field(field(cp,'wheels'),i)
        local row={index=i,available={}}
        number(row,'angular_speed_raw',field(w,'angularSpeed'),allowed,row.available)
        number(row,'brake_torque_raw',field(pw,'brakeTorque'),allowed and cpAvailable,row.available)
        number(row,'handbrake_torque_raw',field(pw,'handbrakeTorque'),allowed and cpAvailable,row.available)
        for key,name in pairs({electric_torque_raw='electricTorque',feedback_torque_raw='feedbackTorque',
            angular_inertia_raw='angularInertia',shaft_velocity_raw='shaftVelocity',shaft_inertia_raw='shaftInertia'}) do
            number(row,key,field(pw,name),allowed and cpAvailable,row.available)
        end
        number(row,'load_raw',field(w,'load'),allowed,row.available)
        number(row,'suspension_travel_raw',field(w,'suspensionTravel'),allowed,row.available)
        r.wheels[#r.wheels+1]=row
    end
    r.status=not stable and 'frame_unavailable_or_changed' or not sameIdentity and 'identity_unavailable_or_changed'
        or timeConflict and 'car_record_time_changed_or_partial' or not physicsAvailable and 'physics_unavailable'
        or not cpAvailable and 'partial_unqualified' or 'available_unqualified'
    return r
end
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
        local radius,width=field(w,'tyreRadius'),field(w,'tyreWidth')
        a.wheels[#a.wheels+1]={index=i,contact_point_world_m=p,contact_normal_world=n,
            normal_well_formed=norm~=nil and norm>=.81 and norm<=1.21,
            wheel_position_world_m=vector(field(w,'position')),load_n=finite(load) and load or nil,
            tyre_radius_nominal_m=finite(radius) and radius>0 and radius or nil,
            tyre_width_nominal_m=finite(width) and width>0 and width or nil,
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
