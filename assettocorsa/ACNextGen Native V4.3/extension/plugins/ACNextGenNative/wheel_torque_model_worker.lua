-- Convert owned normalized model hints using registered scales and THIS callback's
-- native brake/omega samples. No externally supplied Nm, work, or energy credit.
local WheelTorqueModelWorker={}
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function clone(v) if type(v)~='table' then return v end;local r={};for k,x in pairs(v) do r[k]=clone(x) end;return r end
function WheelTorqueModelWorker.new(options,hash)
    local p=clone(assert(options.wheel_torque_profile))
    for _,key in ipairs({'additional_windup_contract_verified','same_callback_sample_verified','additional_lsd_contract_verified','legacy_diff_disabled_verified','brake_fade_contract_verified'}) do assert(p[key]==true,key) end
    assert(type(p.windup_nm_per_normalized)=='table')
    for i=1,2 do local x=p.windup_nm_per_normalized[i];assert(finite(x) and x~=0 and math.abs(x)<=1000) end
    assert(finite(p.lsd_nm_per_hint) and p.lsd_nm_per_hint>=0 and p.lsd_nm_per_hint<=12)
    local s={owner=WheelTorqueLocalWorker.new(options,hash),generation=0,sequence=0,lastModelSequence=0,model=nil,reason=''}
    function s:stop() self.model=nil;self.owner:stop() end
    function s:invalidateModel() self.model=nil end
    function s:step(dt,clock,flags,generation,hint)
        if generation~=self.generation and finite(generation) and generation>self.generation then
            self.generation=generation;self.sequence=0;self.lastModelSequence=0;self.model=nil
        end
        if hint and hint.epoch==options.epoch and hint.generation==generation and hint.car_hash==hash and hint.patch_code==p.patch_code and hint.evidence_id==p.evidence_id and
            finite(hint.sequence) and hint.sequence>=self.lastModelSequence and hint.sequence<=1073741822 and hint.sequence%1==0 and
            finite(hint.source_clock) and hint.source_clock>=0 and hint.source_clock<=clock and clock-hint.source_clock<=.1 and
            finite(hint.demand) and math.abs(hint.demand)<=1 and finite(hint.soft) and math.abs(hint.soft)<=1 and
            finite(hint.transmission) and math.abs(hint.transmission)<=2 and finite(hint.windup) and math.abs(hint.windup)<=2 and
            math.abs(hint.transmission+hint.windup-(hint.soft-hint.demand))<=1e-12 and finite(hint.lsd_capacity) and hint.lsd_capacity>=0 and hint.lsd_capacity<=1 then
            local valid=type(hint.brake_ratio)=='table'
            for i=0,3 do local r=valid and hint.brake_ratio[i];valid=valid and finite(r) and r>=0 and r<=1 end
            if valid then
                if hint.sequence>self.lastModelSequence then self.model=clone(hint);self.lastModelSequence=hint.sequence end
            else self.model=nil end
        elseif hint then self.model=nil end
        local c=nil;local m=self.model
        if flags==15 and finite(clock) and m and clock>=m.source_clock and clock-m.source_clock<=.1 and self.sequence<2147483646 then
            local ok,value=pcall(function()
                local frame=tonumber(ac.getSim().frame);assert(finite(frame) and frame>=0 and frame%1==0 and frame<=9007199254740991)
                local cp=ac.getCarPhysics(0);assert(cp and cp.isAvailable==true and cp.wheels)
                local plan={epoch=options.epoch,generation=generation,car_hash=hash,evidence_id=p.evidence_id,sequence=self.sequence+1,source_clock=clock,
                    baseline_nm={},omega={},ratio={},drive_nm={},windup_nm={},windup_qualified=p.recovery_contract_verified==true,delta_nm={},pair_nm={}}
                for i=0,3 do
                    local w=cp.wheels[i];local omega=physics.getWheelAngularSpeed(0,i)
                    assert(w and finite(w.brakeTorque) and finite(w.handbrakeTorque) and w.handbrakeTorque==0 and finite(omega) and math.abs(omega)>=1 and math.abs(omega)<=2000)
                    local baseline=w.brakeTorque*p.baseline_scale_nm_per_raw
                    if p.baseline_mode==2 then assert(w.brakeTorque>=0);baseline=baseline*(omega>0 and -1 or 1) end
                    assert(finite(baseline) and math.abs(baseline)<=20000 and baseline*omega<=0)
                    plan.baseline_nm[i]=baseline;plan.omega[i]=omega;plan.ratio[i]=m.brake_ratio[i]
                end
                local difference=plan.omega[2]-plan.omega[3]
                local pair=-math.max(-1,math.min(1,difference))*m.lsd_capacity*p.lsd_nm_per_hint
                plan.pair_nm[0]=pair;plan.pair_nm[1]=-pair
                for i=0,1 do
                    plan.drive_nm[i]=(m.transmission+m.windup)*p.windup_nm_per_normalized[i+1]
                    plan.windup_nm[i]=m.windup*p.windup_nm_per_normalized[i+1]
                end
                for i=0,3 do plan.delta_nm[i]=plan.baseline_nm[i]*plan.ratio[i]-plan.baseline_nm[i]+(i>=2 and plan.drive_nm[i-2]+plan.pair_nm[i-2] or 0) end
                assert(tonumber(ac.getSim().frame)==frame)
                return plan
            end)
            if ok then c=value;self.sequence=c.sequence;self.reason='candidate' else self.reason='native_sample_unavailable' end
        else self.reason=flags~=15 and 'inhibited' or 'model_unavailable' end
        self.owner:step(c,clock,dt,flags,generation)
        if not c and not self.owner.pending and not self.owner.fault then self.owner.reason=self.reason end
        return self.owner
    end
    return s
end
