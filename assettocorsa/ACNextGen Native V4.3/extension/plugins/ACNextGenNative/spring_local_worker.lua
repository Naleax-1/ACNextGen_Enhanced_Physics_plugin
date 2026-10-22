-- Development-only owner; no Common Worker composition or native transport yet.
local SpringLocalWorker={}
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function clone(v) if type(v)~='table' then return v end;local r={};for k,x in pairs(v) do r[k]=clone(x) end;return r end
function SpringLocalWorker.new(options,hash)
    local p=clone(options.spring_profile or {})
    local actorOptions={epoch=options.epoch,car_id=options.car_id,damper_profile=p}
    local actor=DamperForceWorker.new(actorOptions,hash);local observer=WheelIntervalObserver.new(actorOptions,hash)
    local anchor=SpringLocalKernel.anchor(p)
    local s={generation=0,sequence=0,sample_sequence=0,pending=nil,model=nil,lastModelSequence=0,last_clock=nil,
        balance_j=0,held_j=0,fault=false,reason='',sent=0,acked=0,reference_lease=0}
    function s:invalidateModel() self.model=nil end
    local function fail(reason) s.fault=true;s.reason=reason;actor:stop();observer:reset();anchor:invalidate();s.pending=nil;s.model=nil;s.reference_lease=0 end
    function s:stop()
        if self.pending then fail('stop_with_pending_command') else actor:stop();observer:reset();anchor:invalidate();self.model=nil;self.reference_lease=0;self.balance_j=0 end
    end
    local function accept(m,clock,generation)
        if type(m)~='table' or not finite(m.sequence) or m.sequence%1~=0 or m.sequence<=s.lastModelSequence or m.sequence>=1073741823 or
            m.epoch~=options.epoch or m.generation~=generation or m.car_hash~=hash or m.patch_code~=p.patch_code or m.evidence_id~=p.evidence_id or
            not finite(m.source_clock) or m.source_clock<0 or m.source_clock>clock or clock-m.source_clock>.1 or
            not finite(m.valid_mask) or m.valid_mask%1~=0 or m.valid_mask<1 or m.valid_mask>15 or type(m.excess_ratio)~='table' then return end
        for i=1,4 do if not finite(m.excess_ratio[i]) or m.excess_ratio[i]<0 then return end end
        s.model=clone(m);s.lastModelSequence=m.sequence
    end
    function s:step(dt,clock,flags,generation,model,conditions)
        if not finite(generation) or generation%1~=0 or generation<1 or generation>=2147483647 then self:stop();return self end
        if generation<self.generation then fail('generation_regressed');return self end
        if generation~=self.generation then
            self:stop();self.generation=generation;self.pending=nil;self.model=nil;self.balance_j=0;self.held_j=0;self.fault=false;self.reason='';self.last_clock=nil;self.lastModelSequence=0
            actor=DamperForceWorker.new(actorOptions,hash)
        end
        if self.fault then return self end
        if not conditions or conditions.enabled~=true or conditions.offline~=true or conditions.unpaused~=true then self:stop();return self end
        if flags~=15 or not finite(clock) or clock<0 or not finite(dt) or not finite(p.dt) or math.abs(dt-p.dt)>1e-7 then self:stop();return self end
        if self.last_clock and clock<=self.last_clock then fail('clock_not_increasing');return self end
        self.last_clock=clock;self.sample_sequence=self.sample_sequence+1
        local receipt=actor:step(nil,clock,dt,flags,generation)
        if self.pending then
            if not anchor.reference or self.pending.reference_lease~=anchor.reference.lease then fail('reference_changed_with_pending_command');return self end
            local work=DamperLocalKernel.receipt(p,self.pending.command,receipt)
            if not work then fail('invalid_application_or_work');return self end
            local debit=math.max(0,work.upper_j)
            if debit>self.held_j then fail('work_exceeds_reservation');return self end
            self.balance_j=math.min(p.storage_capacity_j,math.max(0,self.balance_j-debit)+math.min(p.storage_capacity_j,math.max(0,-work.upper_j)))
            self.held_j=0;self.pending=nil;self.acked=self.acked+1
        elseif actor.latched then fail('actor_latched');return self end
        local pair=observer:sample(clock,dt,flags,generation)
        accept(model,clock,generation)
        if not pair then if self.reference_lease~=0 then self:stop() end;return self end
        local input=DamperLocalKernel.sample(p,pair,clock)
        if not input then self:stop();return self end
        input.sequence=self.sample_sequence
        if not anchor.reference then
            local r=anchor:observe(input,conditions)
            if not r then self.reason='reference_not_registered';return self end
            self.balance_j=0;self.held_j=0;self.reference_lease=r.lease
        end
        if not anchor:permits(self.reference_lease,input,true) then self:stop();return self end
        if not self.model then return self end
        local candidate=SpringLocalKernel.candidate(p,self.model,input,anchor.reference,self.sequence+1)
        if not candidate then self.reason='qualified_candidate_unavailable';return self end
        local reserve=candidate.command.work_bound_j
        if reserve>self.balance_j-self.held_j then self.reason='insufficient_work_reserve';return self end
        if candidate.reference_lease~=self.reference_lease then fail('reference_lease_mismatch');return self end
        self.sequence=candidate.command.sequence;self.pending=candidate;self.held_j=reserve;self.sent=self.sent+1
        local r=actor:step(candidate.command,clock,dt,flags,generation)
        if not r.pending or r.fault then fail('application_failed');return self end
        self.reason='waiting_local_receipt';return self
    end
    return s
end
