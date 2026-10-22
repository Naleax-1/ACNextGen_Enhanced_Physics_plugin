local WheelTorqueLocalWire={}
local HINT=[[
uint32_t abi,epoch,generation,car_hash,patch_code,sequence,effect_id,reserved;
uint64_t evidence_id;double source_clock,demand,soft,transmission,windup,lsd_capacity,brake_ratio[4];
]]
local STATUS=[[
uint32_t abi,epoch,generation,car_hash,patch_code,sequence,sent,acked,fault,flags,effect_id,reason_code;
uint64_t evidence_id;double clock,held_j,balance_j;
]]
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function integer(v,lo,hi) return finite(v) and v>=lo and v<=hi and v%1==0 end
local function barrier() if ac.memoryBarrier then ac.memoryBarrier() end end
local function checksum(raw) local a,b=1,0;for i=1,#raw do a=(a+raw:byte(i))%65521;b=(b+a)%65521 end;return b*65536+a end
local reasons={pending=1,model_unavailable=2,native_sample_unavailable=3,insufficient_energy=4,inhibited=5,plan_context=6,context_or_interval=7,
    missing_components=8,windup_unqualified=9,rear_limit=10,windup_limit=11,pair_not_closed=12,wheel_input=13,noncanonical_correction=14,baseline_interval=15,pair_not_passive=16,
    invalid_power=17,nonfinite_work=18,receipt_context=19,incomplete_receipt=20,missing_samples=21,altered_samples=22,work_exceeds_reservation=23,actor_refused_or_partial=24,
    actor_latched=25,clock_not_increasing=26,generation_regressed=27,stopped_with_pending=28}
function WheelTorqueLocalWire.new(options,hash)
    local p=assert(options.wheel_torque_profile);local patch,evidence=p.patch_code,p.evidence_id
    local factory=assert(ac.StructItem.build or ac.StructItem.combine)
    local prefix=options.mapping_prefix or 'AcTools.CSP.Limited.ACNextGen.V4'
    local s={controller=WheelTorqueModelWorker.new(options,hash),candidate=factory(HINT),status=factory(STATUS),sequence=0}
    s.output=ac.writeMemoryMappedFile(prefix..'.WheelLocalStatus','uint32_t commit,checksum;struct {'..STATUS..'} packet;',false)
    function s:stop() self.controller:stop();self.output.commit=0 end
    function s:step(dt,clock,flags,generation)
        if not finite(clock) or clock<0 or not integer(flags,0,15) or not integer(generation,1,2147483646) then self:stop();return end
        if not self.input then local ok,v=pcall(ac.readMemoryMappedFile,prefix..'.WheelLocalHint','uint32_t commit,checksum;struct {'..HINT..'} packet;',false);if ok then self.input=v end end
        local model=nil
        if self.input then
            local token=tonumber(self.input.commit)
            if integer(token,2,2147483644) and token%2==0 then
                barrier();local ok,raw=pcall(ac.structBytes,self.input.packet);barrier()
                if ok and #raw==120 and token==tonumber(self.input.commit) and checksum(raw)==tonumber(self.input.checksum) and pcall(ac.fillStructWithBytes,self.candidate,raw) then
                    local q=self.candidate
                    if q.abi==1 and q.effect_id==4 and q.reserved==0 and q.sequence*2==token and q.epoch==options.epoch and q.generation==generation and q.car_hash==hash and q.patch_code==patch and tonumber(q.evidence_id)==evidence and
                        finite(q.source_clock) and q.source_clock>=0 and q.source_clock<=clock and clock-q.source_clock<=.1 and
                        finite(q.demand) and math.abs(q.demand)<=1 and finite(q.soft) and math.abs(q.soft)<=1 and finite(q.transmission) and math.abs(q.transmission)<=2 and finite(q.windup) and math.abs(q.windup)<=2 and
                        math.abs(q.transmission+q.windup-(q.soft-q.demand))<=1e-12 and finite(q.lsd_capacity) and q.lsd_capacity>=0 and q.lsd_capacity<=1 then
                        local valid=true;local ratios={}
                        for i=0,3 do local r=tonumber(q.brake_ratio[i]);valid=valid and finite(r) and r>=0 and r<=1;ratios[i]=r end
                        if valid then model={epoch=q.epoch,generation=q.generation,car_hash=q.car_hash,patch_code=q.patch_code,evidence_id=tonumber(q.evidence_id),sequence=q.sequence,source_clock=q.source_clock,
                            demand=q.demand,soft=q.soft,transmission=q.transmission,windup=q.windup,lsd_capacity=q.lsd_capacity,brake_ratio=ratios} end
                    end
                end
            end
        end
        -- Unavailable, corrupt, and explicitly invalid packets all revoke the
        -- cached model. A preceding completed interval is still settled first.
        if not model then self.controller:invalidateModel() end
        local c=self.controller:step(dt,clock,flags,generation,model)
        if self.sequence>=1073741822 then self:stop();return end
        self.sequence=self.sequence+1;local q=self.status
        q.abi=2;q.epoch=options.epoch;q.generation=generation;q.car_hash=hash;q.patch_code=patch;q.sequence=self.sequence
        q.sent=c.sent;q.acked=c.acked;q.fault=c.fault and 1 or 0;q.flags=flags+(c.pending and 16 or 0);q.effect_id=4;q.reason_code=reasons[c.reason] or (c.reason=='' and 0 or 29)
        q.evidence_id=evidence;q.clock=clock;q.held_j=c.held_j;q.balance_j=c.balance_j
        local raw=ac.structBytes(q);assert(#raw==80,'Wheel local status ABI mismatch')
        self.output.commit=q.sequence*2-1;barrier();ac.fillStructWithBytes(self.output.packet,raw);self.output.checksum=checksum(raw);barrier();self.output.commit=q.sequence*2
    end
    return s
end
