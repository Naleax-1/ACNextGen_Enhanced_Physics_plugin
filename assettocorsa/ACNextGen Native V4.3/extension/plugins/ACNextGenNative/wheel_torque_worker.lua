-- Single four-wheel writer for already reserved canonical brake+drive+LSD plans.
-- Source-only until an independently qualified coordinator supplies the profile.
local WheelTorqueWorker={}
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function integer(v) return finite(v) and v>=1 and v<2147483647 and v%1==0 end
local function clone(v) if type(v)~='table' then return v end;local t={};for k,x in pairs(v) do t[k]=clone(x) end;return t end
function WheelTorqueWorker.new(options,hash)
    local p=clone(options.wheel_torque_profile or {})
    local qualified=finite(options.epoch) and options.epoch>=1 and options.epoch<=4294967295 and options.epoch%1==0 and finite(hash) and hash>=1 and hash<=4294967295 and hash%1==0 and options.drive_profile==nil and options.brake_profile==nil and p.car_hash==hash and finite(p.evidence_id) and p.evidence_id>=1 and p.evidence_id<=9007199254740991 and p.evidence_id%1==0 and integer(p.patch_code) and
        (p.baseline_mode==1 or p.baseline_mode==2) and finite(p.baseline_scale_nm_per_raw) and p.baseline_scale_nm_per_raw>0 and p.baseline_scale_nm_per_raw<=1000 and
        finite(p.command_scale_raw_per_nm) and p.command_scale_raw_per_nm~=0 and math.abs(p.command_scale_raw_per_nm)<=1000 and
        finite(p.dt) and p.dt>0 and p.dt<=.003 and finite(p.max_api_argument) and p.max_api_argument>0 and p.max_api_argument<=20000 and
        finite(p.max_rear_additional_nm) and p.max_rear_additional_nm>0 and p.max_rear_additional_nm<=12
    for _,key in ipairs({'units_verified','baseline_isolated','single_four_wheel_owner_verified','legacy_brake_disabled_verified','legacy_drive_disabled_verified',
        'coordinator_work_accounting_verified','phase_verified','native_baseline_interval_verified','native_fade_double_counting_excluded','rwd_verified','paired_application_order_verified','bounds_verified','constant_torque_verified'}) do
        qualified=qualified and p[key]==true
    end
    for i=1,4 do
        qualified=qualified and type(p.acceleration_bound_rad_s2)=='table' and type(p.omega_error_rad_s)=='table' and
            finite(p.acceleration_bound_rad_s2[i]) and p.acceleration_bound_rad_s2[i]>=0 and finite(p.omega_error_rad_s[i]) and p.omega_error_rad_s[i]>=0
    end
    local s={generation=0,lastSequence=0,pending=nil,latched=false}
    function s:stop() if self.pending then self.latched=true end;self.pending=nil end
    local function safe()
        local sim,car=ac.getSim(),ac.getCar(0)
        return sim and sim.isOnlineRace==false and sim.isPaused==false and sim.isSessionFinished~=true and sim.isReplayActive~=true and sim.isReplayOnlyMode~=true and
            ac.getCarID(0)==options.car_id and physics.allowed()==true and tonumber(ac.getPatchVersionCode())==p.patch_code and car and car.physicsAvailable==true and car.absInAction==false and
            finite(car.handbrake) and car.handbrake<=.001
    end
    function s:step(c,clock,dt,flags,generation)
        local empty={sequence=0,fault=true,completed_mask=0,calls=0,attempts=0,samples_valid=false,work_measurement_verified=false}
        if not integer(generation) or generation<self.generation then return empty end
        if generation~=self.generation then self:stop();self.generation=generation;self.lastSequence=0;self.latched=false end
        local ok,allowed=pcall(safe)
        if not qualified or self.latched or flags~=15 or not finite(clock) or clock<0 or not finite(dt) or dt<=0 or math.abs(dt-p.dt)>1e-7 or not ok or not allowed then self:stop();return empty end
        if self.pending then
            local r=self.pending;self.pending=nil;r.clock_after=clock;r.omega_after={}
            local sampled,detail=pcall(function()
                assert(clock>r.clock_before and math.abs(clock-r.clock_before-p.dt)<=1e-7,'Nonconsecutive interval')
                for i=0,3 do
                    local v=physics.getWheelAngularSpeed(0,i);assert(finite(v) and math.abs(v)<=2000)
                    assert(math.abs(v-r.omega_before[i])<=p.acceleration_bound_rad_s2[i+1]*(clock-r.clock_before)+2*p.omega_error_rad_s[i+1],'Velocity bound exceeded')
                    r.omega_after[i]=v
                end
            end)
            if not sampled then self.latched=true;r.detail=tostring(detail);return r end
            r.samples_valid=true;r.fault=false;return r
        end
        if not c then return empty end
        if c.epoch~=options.epoch or c.generation~=generation or c.car_hash~=hash or c.evidence_id~=p.evidence_id or not integer(c.sequence) or c.sequence<=self.lastSequence or
            not finite(c.source_clock) or c.source_clock<0 or c.source_clock>clock or clock-c.source_clock>.003001 then return empty end
        self.lastSequence=c.sequence
        local r={sequence=c.sequence,epoch=options.epoch,generation=generation,car_hash=hash,evidence_id=p.evidence_id,clock_before=clock,
            completed_mask=0,calls=0,attempts=0,fault=true,samples_valid=false,work_measurement_verified=false,applied_nm={},omega_before={},baseline_nm={},ratio={}}
        local targets,upper={},{}
        local prepared,detail=pcall(function()
            local frame=tonumber(ac.getSim().frame);assert(finite(frame) and frame>=0 and frame%1==0 and frame<=9007199254740991,'SDK frame missing')
            local cp=ac.getCarPhysics(0);assert(cp and cp.isAvailable==true and cp.wheels,'Physics unavailable')
            assert(finite(c.pair_nm[0]) and c.pair_nm[0]==-c.pair_nm[1],'Pair not closed')
            for i=0,3 do
                local w=cp.wheels[i];local omega=physics.getWheelAngularSpeed(0,i)
                assert(w and finite(w.brakeTorque) and finite(w.handbrakeTorque) and w.handbrakeTorque==0 and finite(omega) and math.abs(omega)<=2000,'Wheel unavailable')
                local baseline=w.brakeTorque*p.baseline_scale_nm_per_raw
                if p.baseline_mode==2 then assert(w.brakeTorque>=0 and (w.brakeTorque==0 or math.abs(omega)>=1));baseline=baseline*(omega>0 and -1 or 1) end
                assert(finite(baseline) and math.abs(baseline)<=20000 and baseline*omega<=0 and baseline==c.baseline_nm[i],'Baseline changed')
                assert(finite(c.ratio[i]) and c.ratio[i]>=0 and c.ratio[i]<=1 and finite(c.omega[i]) and math.abs(c.omega[i]-omega)<=2*p.omega_error_rad_s[i+1],'Plan input changed')
                local additional=0
                if i>=2 then assert(finite(c.drive_nm[i-2]) and math.abs(c.drive_nm[i-2])<=12 and math.abs(c.pair_nm[i-2])<=12,'Component limit');additional=c.drive_nm[i-2]+c.pair_nm[i-2];assert(finite(additional) and math.abs(additional)<=p.max_rear_additional_nm,'Rear limit') end
                local expected=baseline*c.ratio[i]-baseline+additional
                assert(finite(c.delta_nm[i]) and c.delta_nm[i]==expected,'Wrong composed correction')
                local raw=expected*p.command_scale_raw_per_nm;assert(finite(raw) and math.abs(raw)<=p.max_api_argument,'Actuator limit')
                targets[i]=raw;r.applied_nm[i]=expected;r.omega_before[i]=omega;r.baseline_nm[i]=baseline;r.ratio[i]=c.ratio[i]
                local combined=baseline*c.ratio[i]+additional
                upper[i]=combined*omega+math.abs(combined)*(p.acceleration_bound_rad_s2[i+1]*(p.dt+1e-7)+p.omega_error_rad_s[i+1])
                assert(finite(upper[i]))
            end
            local pairError=(p.acceleration_bound_rad_s2[3]+p.acceleration_bound_rad_s2[4])*(p.dt+1e-7)+p.omega_error_rad_s[3]+p.omega_error_rad_s[4]
            local pairPower=c.pair_nm[0]*(r.omega_before[2]-r.omega_before[3])+math.abs(c.pair_nm[0])*pairError
            assert(finite(pairPower) and pairPower<=0,'Pair could add work')
            r.sdk_frame_before=frame;r.sdk_frame_after=tonumber(ac.getSim().frame)
            assert(r.sdk_frame_after==frame,'SDK frame changed during preflight')
        end)
        if not prepared then r.detail=tostring(detail);return r end
        local order=upper[3]<upper[2] and {0,1,3,2} or {0,1,2,3}
        for _,i in ipairs(order) do
            if targets[i]~=0 then
                r.attempts=r.attempts+1
                local applied,message=pcall(physics.addWheelTorque,0,i,targets[i])
                if not applied then self.latched=true;r.detail=tostring(message);return r end
                r.calls=r.calls+1
            end
            r.completed_mask=r.completed_mask+2^i
        end
        self.pending=r;return {pending=true,fault=false,work_measurement_verified=false}
    end
    return s
end
