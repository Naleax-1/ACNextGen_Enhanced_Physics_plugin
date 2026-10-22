-- One local owner: reserve -> four-wheel Actor -> measured receipt -> settle.
-- Accepts canonical component plans, never a wire-supplied work/energy claim.
local WheelTorqueLocalWorker={}
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function clone(v) if type(v)~='table' then return v end;local r={};for k,x in pairs(v) do r[k]=clone(x) end;return r end
function WheelTorqueLocalWorker.new(options,hash)
    local opts=clone(options);local p=assert(opts.wheel_torque_profile)
    assert(opts.drive_profile==nil and opts.brake_profile==nil,'Conflicting wheel owners')
    local capacity=p.storage_capacity_j or 0
    assert(finite(capacity) and capacity>=0 and capacity<=1 and (p.initial_energy_j==nil or p.initial_energy_j==0))
    assert(capacity==0 or p.recovery_contract_verified==true)
    assert(finite(p.max_rear_additional_nm) and p.max_rear_additional_nm>0 and p.max_rear_additional_nm<=12)
    local accounting=FourWheelWork.new(p,hash)
    local actor=WheelTorqueWorker.new(opts,hash)
    local s={generation=0,lastSequence=0,pending=nil,balance_j=0,held_j=0,fault=false,reason='',sent=0,acked=0,spent_j=0}
    local function fail(reason) actor:stop();s.fault=true;s.reason=reason;s.pending=nil end
    function s:stop()
        if self.pending then fail('stopped_with_pending') else actor:stop() end
    end
    function s:step(c,clock,dt,flags,generation)
        if not finite(generation) or generation<1 or generation%1~=0 or generation>=2147483647 then self:stop();return self end
        if generation<self.generation then fail('generation_regressed');return self end
        if generation~=self.generation then
            self:stop();self.generation=generation;self.lastSequence=0;self.pending=nil;self.balance_j=0;self.held_j=0;self.spent_j=0;self.lastClock=nil;self.fault=false;self.reason=''
            actor=WheelTorqueWorker.new(opts,hash)
        end
        if self.fault then return self end
        if not finite(clock) or clock<0 or not finite(dt) or dt<=0 or math.abs(dt-p.dt)>1e-7 or flags~=15 then self:stop();return self end
        if self.lastClock and clock<=self.lastClock then fail('clock_not_increasing');return self end;self.lastClock=clock
        local raw=actor:step(nil,clock,dt,flags,generation)
        if self.pending then
            local measured,reason=accounting:receipt(self.pending,raw)
            if not measured then fail(reason);return self end
            if measured.positive_work_upper_j>self.held_j then fail('work_exceeds_reservation');return self end
            self.balance_j=math.min(capacity,self.balance_j+self.held_j-measured.positive_work_upper_j+measured.absorbed_work_lower_j)
            self.spent_j=self.spent_j+measured.positive_work_upper_j;self.held_j=0;self.pending=nil;self.acked=self.acked+1
        elseif actor.latched then fail('actor_latched');return self end
        if not c then return self end
        if type(c)~='table' then self.reason='plan_context';return self end
        if c.epoch~=opts.epoch or c.generation~=generation or c.car_hash~=hash or c.evidence_id~=p.evidence_id or not finite(c.sequence) or c.sequence<=self.lastSequence or c.sequence%1~=0 or c.sequence>=2147483647 or
            not finite(c.source_clock) or c.source_clock<0 or c.source_clock>clock or clock-c.source_clock>.003001 then self.reason='plan_context';return self end
        self.lastSequence=c.sequence
        local retained=clone(c)
        local reservation,reason=accounting:reserve(retained)
        if not reservation then self.reason=reason;return self end
        if reservation.positive_work_upper_j>self.balance_j then self.reason='insufficient_energy';return self end
        self.held_j=reservation.positive_work_upper_j;self.balance_j=self.balance_j-self.held_j
        local started=actor:step(retained,clock,dt,flags,generation)
        if not started.pending then fail('actor_refused_or_partial');return self end
        self.pending=retained;self.sent=self.sent+1;self.reason='pending'
        return self
    end
    return s
end
