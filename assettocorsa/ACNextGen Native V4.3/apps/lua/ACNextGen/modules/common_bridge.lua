---@diagnostic disable: undefined-global
-- Common app supervisor. Models stay in C++; Worker handles transport and actuation.
local M={}
local s={root='',epoch=0,generation=1,heartbeat=0,timer=0,age=math.huge,lastClock=nil,
    requested=false,enabled=false,permission=false,active=false,retry=0,carID=nil,hostID=nil,
    status='Waiting for session',error='',physical=false,apiCalls=0,appliedFrames=0,ack=0,fault=0,stage=0}
local function releaseCalibrationBrake()
    if s.brakeOwner then
        s.brakeOwner=nil;s.brakeRemaining=0
        if physics and physics.forceUserHandbrakeFor then pcall(physics.forceUserHandbrakeFor,0) end
    end
end
local function store(key,value) ac.store('ngp4_'..key,value) end
local function load(key) return ac.load('ngp4_'..key) end
local function bump()
    releaseCalibrationBrake()
    s.generation=s.generation+1
    if s.generation>=2147483647 then s.generation=1 end
    if ac and type(ac.store)=='function' then store('generation',s.generation) end
end
local function apiReady()
    local checks={['ac.store']=ac and ac.store,['ac.load']=ac and ac.load,
        ['physics.allowed']=physics and physics.allowed,
        ['physics.startPhysicsWorker']=physics and physics.startPhysicsWorker}
    local missing={}
    for _,name in ipairs({'ac.store','ac.load','physics.allowed','physics.startPhysicsWorker'}) do
        local kind=type(checks[name])
        if kind~='function' and kind~='cdata' then missing[#missing+1]=name..' ('..kind..')' end
    end
    local diagnostic=table.concat(missing,', ')
    if diagnostic~='' then
        s.error='Unavailable API: '..diagnostic
        if diagnostic~=s.apiDiagnostic and ac and type(ac.log)=='function' then
            ac.log('[ACNextGen] '..s.error)
        end
    end
    s.apiDiagnostic=diagnostic
    return diagnostic==''
end
local function read(path)
    local f=io.open(path,'rb');if not f then return nil end
    local value=f:read('*a');f:close();return value
end
local function calibration()
    -- No request file ships with the package. Only a short-lived, explicitly
    -- issued one-shot request can launch the separate probe Worker.
    if not s.physical or not s.active or not s.enabled or not s.permission or s.age>.2 then return end
    local raw=read(s.root..'/runtime/calibration_request.json')
    if not raw or #raw>1024 then return end
    local ok,r=pcall(function() return JSON.parse(raw) end)
    if not ok or type(r)~='table' then return end
    local body=r.kind=='body_vertical' and r.force_n==20 and (r.frames==1 or r.frames==8) and
        (r.argument_mode=='scaled_dt' or r.argument_mode=='raw_one' or r.argument_mode=='control' or r.argument_mode=='raw_reference')
    local rear=r.kind=='rear_pair' and (r.torque_argument==.001 or r.torque_argument==0) and r.frames==1
    local wheel=s.calibrationCaptureOnly and r.kind=='wheel_vertical' and (r.argument==.1 or r.argument==1 or r.argument==10) and
        type(r.wheel_index)=='number' and r.wheel_index>=0 and r.wheel_index<=3 and r.wheel_index%1==0 and r.frames==8 and
        (r.argument_mode=='wheel_only' or r.argument_mode=='paired' or r.argument_mode=='control') and r.point_frame=='world'
    if r.schema~=1 or not (body or rear or wheel) or
        (r.rear_phase_aligned~=nil and (not rear or type(r.rear_phase_aligned)~='boolean')) or
        (r.settle_frames~=nil and r.settle_frames~=0 and r.settle_frames~=200) or
        (r.point_frame~=nil and r.point_frame~='local' and r.point_frame~='world') or
        r.epoch~=s.epoch or r.generation~=s.generation or r.host_id~=s.hostID or type(r.host_id)~='string' or
        type(r.id)~='string' or #r.id>80 or not r.id:match('^[%w_-]+$') or r.car_id~=s.carID or
        type(r.expires_at)~='number' or r.expires_at~=r.expires_at or r.expires_at<os.time() or r.expires_at>os.time()+15 then return end
    if load('calibration_consumed')==r.id then return end
    -- Consume before launch so a callback, Resume or App reload cannot replay it.
    store('calibration_consumed',r.id)
    local source=read(s.root..'/calibration_worker.lua')
    if not source then ac.log('[ACNextGen] Calibration source missing');return end
    if r.auto_handbrake==true then
        local car=ac.getCar(0)
        if not (body or wheel) or not car or car.physicsAvailable~=true or car.gear~=0 or
            type(car.gas)~='number' or car.gas~=car.gas or car.gas>.001 or
            type(car.steer)~='number' or car.steer~=car.steer or math.abs(car.steer)>1 or
            type(car.speedKmh)~='number' or car.speedKmh~=car.speedKmh or math.abs(car.speedKmh)>.18 or
            not physics.forceUserHandbrakeFor then return end
        local duration=r.keep_brake_after_probe==true and 2.5 or 1.1
        local held=pcall(physics.forceUserHandbrakeFor,duration,1)
        if not held then return end
        s.brakeOwner=r.id;s.brakeRemaining=duration
    end
    r.epoch=s.epoch;r.generation=s.generation
    local launched,message=pcall(physics.startPhysicsWorker,source,r,function(error)
        local complete=load('calibration_result_id')==r.id and load('calibration_completed')==1
        if s.brakeOwner==r.id and (error or not complete or r.keep_brake_after_probe~=true) then releaseCalibrationBrake() end
        ac.log('[ACNextGen CAL '..r.id..'] WORKER_EXIT '..tostring(error or 'normal'))
    end)
    if not launched then
        if s.brakeOwner==r.id then releaseCalibrationBrake() end
        ac.log('[ACNextGen CAL '..r.id..'] LAUNCH_FAILED '..tostring(message))
    end
end
function M.init(root,physical,enhancement)
    s.root=root;s.physical=physical==true
    s.requested=false;s.retry=0;s.lastClock=nil;s.age=math.huge
    s.enhancementCapture=type(enhancement)=='table' and enhancement.capture==true
    s.wheelIntervalCapture=s.enhancementCapture and enhancement.wheel_interval_capture==true
    s.calibrationCaptureOnly=type(enhancement)=='table' and enhancement.calibration_capture_only==true
    s.enhancementApply=s.physical and s.enhancementCapture and enhancement.apply==true and enhancement.calibration=='verified'
    s.tyreProfile=nil;s.enhancementApplyMask=0
    local profile=type(enhancement)=='table' and enhancement.tyre_lateral_profile or nil
    local patchOK,patch=pcall(function() return tonumber(ac.getPatchVersionCode()) end)
    if s.physical and s.enhancementCapture and type(profile)=='table' and profile.enabled==true and
        profile.force_unit=='N' and profile.evidence_id=='body-force-N-20261014' and
        type(profile.car_id)=='string' and patchOK and type(patch)=='number' and patch>0 and patch%1==0 and patch==profile.patch_code then
        s.tyreProfile={car_id=profile.car_id,patch_code=profile.patch_code}
    end
    if not apiReady() then s.status='Worker API unavailable';return end
    store('calibration_only',s.calibrationCaptureOnly and 1 or 0)
    s.epoch=math.random(1,1073741823)
    store('epoch',s.epoch);store('enabled',0);store('permission',0)
    store('generation',s.generation);store('parent_heartbeat',0)
end
function M.setEnabled(value)
    value=value==true
    if value~=s.enabled then s.enabled=value;bump() end
    if apiReady() then store('enabled',s.enabled and 1 or 0) end
end
function M.resume() bump();s.error='';s.fault=0 end
function M.shutdown()
    M.setEnabled(false);s.active=false;s.epoch=s.epoch+1
    if apiReady() then store('epoch',s.epoch) end
end
function M.newSession()
    M.shutdown();s.requested=false;s.retry=0;s.age=math.huge;s.lastClock=nil;bump()
end
function M.newHost(id)
    if id~=s.hostID then s.hostID=id;bump() end
end
local function damperProfile()
    if not s.physical or not s.enhancementCapture or s.calibrationCaptureOnly then return nil end
    local raw=read(s.root..'/damper_profile.json');if not raw or #raw>65536 then return nil end
    local ok,result=pcall(function()
        local parser=require('modules.damper_profile')
        return parser.parse(JSON.parse(raw),s.carID,tonumber(ac.getPatchVersionCode()))
    end)
    return ok and result or nil
end
local function springProfile()
    if not s.physical or not s.enhancementCapture or s.calibrationCaptureOnly then return nil end
    local raw=read(s.root..'/spring_local_profile.json');if not raw or #raw>65536 then return nil end
    local ok,result=pcall(function()
        return require('modules.spring_local_profile').parse(JSON.parse(raw),s.carID,tonumber(ac.getPatchVersionCode()))
    end)
    return ok and result or nil
end
local function driveProfile()
    if not s.physical or not s.enhancementCapture or s.calibrationCaptureOnly then return nil end
    local raw=read(s.root..'/drive_local_profile.json');if not raw or #raw>65536 then return nil end
    local ok,result=pcall(function()
        return require('modules.drive_local_profile').parse(JSON.parse(raw),s.carID,tonumber(ac.getPatchVersionCode()))
    end)
    return ok and result or nil
end
local function wheelTorqueProfile()
    if not s.physical or not s.enhancementCapture or s.calibrationCaptureOnly then return nil end
    local raw=read(s.root..'/wheel_torque_local_profile.json');if not raw then return nil end
    if #raw>65536 then return nil,'Wheel profile invalid' end
    local ok,result=pcall(function()
        return require('modules.wheel_torque_local_profile').parse(JSON.parse(raw),s.carID,tonumber(ac.getPatchVersionCode()))
    end)
    if not ok or not result then return nil,'Wheel profile invalid' end
    return result
end
local function bodyProfile()
    if not s.physical or not s.enhancementCapture or s.calibrationCaptureOnly then return nil end
    local raw=read(s.root..'/body_moment_profile.json')
    if not raw or #raw>65536 then return nil end
    local ok,p=pcall(function() return JSON.parse(raw) end)
    if not ok or type(p)~='table' or p.schema~=1 or p.enabled~=true or p.car_id~=s.carID or
        type(p.evidence_reference)~='string' or #p.evidence_reference<1 or #p.evidence_reference>500 then return nil end
    local function number(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
    local function integer(v,max) return number(v) and v>=1 and v<=max and v%1==0 end
    local patchOK,patch=pcall(function() return tonumber(ac.getPatchVersionCode()) end)
    local a,b=1,0;for i=1,#s.carID do a=(a+string.byte(s.carID,i))%65521;b=(b+a)%65521 end
    if not patchOK or not integer(p.patch_code,2147483646) or patch~=p.patch_code or p.car_hash~=b*65536+a or
        not integer(p.evidence_id,9007199254740991) or p.half_width_m~=.5 or p.half_length_m~=1 or
        not number(p.max_force_n) or p.max_force_n<=0 or p.max_force_n>20 or
        not number(p.storage_capacity_j) or p.storage_capacity_j<0 or p.storage_capacity_j>1 then return nil end
    for _,k in ipairs({'normalization_contract_verified','neutral_verified','exclusive_owner','body_force_units_verified','coordinates_verified'}) do
        if p[k]~=true then return nil end
    end
    local w=p.work;if type(w)~='table' or not number(w.dt) or w.dt<=0 or w.dt>.003 then return nil end
    for _,k in ipairs({'units_verified','interval_verified','constant_local_force_verified','sample_coordinates_verified','bounds_verified'}) do
        if w[k]~=true then return nil end
    end
    for _,entry in ipairs({{p.neutral_normalized,2,10},{p.signed_nm_per_normalized,2,1000},
        {w.acceleration_bound_ms2,4},{w.velocity_error_ms,4}}) do
        local values,n,limit=entry[1],entry[2],entry[3]
        if type(values)~='table' or #values~=n then return nil end
        for i=1,n do
            if not number(values[i]) or (limit and math.abs(values[i])>limit) or (not limit and values[i]<0) then return nil end
        end
    end
    return {car_hash=p.car_hash,patch_code=p.patch_code,evidence_id=p.evidence_id,dt=w.dt,max_force_n=p.max_force_n,
        units_verified=true,coordinates_verified=true,exclusive_owner=true,action_interval_verified=true,constant_local_force_verified=true}
end
local function launch()
    local damper=damperProfile()
    local spring=springProfile()
    local drive=driveProfile()
    local wheel,wheelError=wheelTorqueProfile()
    if wheelError then s.status=wheelError;s.error='Four-wheel profile refused; no legacy fallback';s.retry=2;return end
    if wheel and drive then s.status='Conflicting wheel profiles';s.error='Choose four-wheel or rear drive ownership';s.retry=2;return end
    local intervalCapture=s.wheelIntervalCapture or (damper~=nil and damper.execution_mode~='worker_local_v1')
    local source=read(s.root..'/common_worker.lua')
    if not source then s.status='Worker file missing';s.error='common_worker.lua is not installed';s.retry=2;return end
    if s.enhancementCapture then
        if intervalCapture then
            local observer,wire=read(s.root..'/wheel_interval_observer.lua'),read(s.root..'/wheel_interval_wire.lua')
            if not observer or not wire then s.status='Wheel interval file missing';s.retry=2;return end
            source=observer..'\n'..wire..'\n'..source
        end
        local extra=read(s.root..'/enhancement_worker.lua')
        if not extra then s.status='Enhancement file missing';s.error='enhancement_worker.lua is not installed';s.retry=2;return end
        source=extra..'\n'..source
        local spring=read(s.root..'/spring_candidate_worker.lua')
        if spring then source=spring..'\n'..source end
        local brake=read(s.root..'/brake_sensor.lua')
        if brake then source=brake..'\n'..source end
        local actor,wire=read(s.root..'/brake_force_worker.lua'),read(s.root..'/brake_force_wire_worker.lua')
        if actor and wire then source=actor..'\n'..wire..'\n'..source end
        local driveObserver=read(s.root..'/drive_work_observer.lua')
        if driveObserver then source=driveObserver..'\n'..source end
        local bodySensor=read(s.root..'/body_sensor.lua')
        if bodySensor then source=bodySensor..'\n'..source end
        local bodyActor,bodyWire=read(s.root..'/body_force_worker.lua'),read(s.root..'/body_force_wire_worker.lua')
        if bodyActor and bodyWire then source=bodyActor..'\n'..bodyWire..'\n'..source end
    end
    if damper or spring then
        local names={}
        if spring or (damper and damper.execution_mode=='worker_local_v1') then
            names={'wheel_interval_observer','damper_force_worker','damper_local_kernel'}
        else names={'damper_force_worker'} end
        if damper then
            if damper.execution_mode=='worker_local_v1' then names[#names+1]='damper_local_worker';names[#names+1]='damper_local_wire'
            else names[#names+1]='damper_force_wire_worker' end
        end
        if spring then for _,name in ipairs({'spring_local_conditions','spring_local_kernel','spring_local_worker','spring_local_wire'}) do names[#names+1]=name end end
        local parts={}
        for _,name in ipairs(names) do
            local part=read(s.root..'/'..name..'.lua')
            if not part then s.status=spring and 'Spring files missing' or 'Damper files missing';s.error='Qualified paired profile needs '..name;s.retry=2;return end
            parts[#parts+1]=part
        end
        source=table.concat(parts,'\n')..'\n'..source
    end
    if wheel then
        local parts={}
        for _,name in ipairs({'four_wheel_work','wheel_torque_worker','wheel_torque_local_worker','wheel_torque_model_worker','wheel_torque_local_wire'}) do
            local part=read(s.root..'/'..name..'.lua')
            if not part then s.status='Wheel files missing';s.error='Qualified four-wheel profile needs '..name;s.retry=2;return end
            parts[#parts+1]=part
        end
        source=table.concat(parts,'\n')..'\n'..source
    end
    if drive then
        local parts={}
        for _,name in ipairs({'drive_force_worker','drive_local_worker','drive_local_wire'}) do
            local part=read(s.root..'/'..name..'.lua')
            if not part then s.status='Drive files missing';s.error='Qualified drive profile needs '..name;s.retry=2;return end
            parts[#parts+1]=part
        end
        source=table.concat(parts,'\n')..'\n'..source
    end
    s.epoch=math.random(1,1073741823);s.lastClock=nil;s.age=math.huge
    s.apiCalls=0;s.appliedFrames=0;s.ack=0;s.fault=0;s.stage=0
    store('epoch',s.epoch);store('generation',s.generation)
    store('enabled',s.enabled and 1 or 0);store('permission',s.permission and 1 or 0)
    s.heartbeat=s.heartbeat+1;store('parent_heartbeat',s.heartbeat)
    local launchEpoch=s.epoch
    s.requested=true;s.status='Starting common worker';s.retry=1
    local ok,message=pcall(physics.startPhysicsWorker,source,
        {epoch=s.epoch,car_id=s.carID,physical_enabled=s.physical and not s.calibrationCaptureOnly,
            enhancement_capture=s.enhancementCapture,enhancement_apply=s.enhancementApply or s.enhancementApplyMask>0,
            enhancement_apply_mask=s.enhancementApplyMask,body_profile=bodyProfile(),damper_profile=damper,spring_profile=spring,drive_profile=drive,wheel_torque_profile=wheel,wheel_interval_capture=intervalCapture},function(error)
            if s.epoch~=launchEpoch then return end
            s.requested=false;s.retry=1;s.status=error and 'Worker stopped with error' or 'Worker stopped'
            if error then s.error=tostring(error) end
        end)
    if not ok then s.requested=false;s.status='Worker launch failed';s.error=tostring(message) end
end
function M.update(dt,active,enabled,carID)
    if s.brakeOwner then
        s.brakeRemaining=s.brakeRemaining-dt
        local car=ac.getCar(0)
        if s.brakeRemaining<=0 or active~=true or enabled~=true or not s.permission or
            not car or car.gear~=0 or type(car.gas)~='number' or car.gas~=car.gas or car.gas>.001 or
            type(car.steer)~='number' or car.steer~=car.steer or math.abs(car.steer)>1 then releaseCalibrationBrake() end
    end
    s.retry=math.max(0,s.retry-dt);s.age=s.age+dt;s.timer=s.timer+dt
    if not apiReady() then s.status='Worker API unavailable';return end
    if s.carID and s.carID~=carID then
        M.shutdown();s.requested=false;s.retry=0;bump()
    end
    s.carID=carID;s.active=active==true
    s.enhancementApplyMask=s.calibrationCaptureOnly and 0 or (s.enhancementApply and 7 or (s.tyreProfile and s.tyreProfile.car_id==carID and 2 or 0))
    M.setEnabled(s.active and enabled==true)
    if not s.active then s.status='Waiting for offline session';return end
    s.calibrationTimer=(s.calibrationTimer or 0)+dt
    if s.calibrationTimer>=1 then s.calibrationTimer=0;calibration() end
    if s.timer>=.05 then
        s.timer=0
        local ok,value=pcall(physics.allowed);local previous=s.permission;s.permission=ok and value==true
        if s.loggedPermission==nil or previous~=s.permission then
            ac.log('[ACNextGen] Common Worker physics.allowed='..tostring(s.permission))
            s.loggedPermission=s.permission
        end
        store('permission',s.permission and 1 or 0)
        s.heartbeat=s.heartbeat+1;store('parent_heartbeat',s.heartbeat)
        if load('worker_epoch')==s.epoch then
            local clock=load('worker_clock')
            if clock~=s.lastClock then s.age=0;s.lastClock=clock end
            s.apiCalls=load('worker_api_calls') or 0;s.appliedFrames=load('worker_applied_frames') or 0
            s.ack=load('worker_ack') or 0;s.fault=load('worker_fault') or 0;s.stage=load('worker_stage') or 0
            local status=load('worker_status')
            if s.age<=.2 then
                s.status=({[1]='Capturing',[2]='Inhibited',[3]='Ready',[4]='Applying',[5]='API fault',[8]='Stopped'})[status] or 'Worker running'
                if status==5 then s.error='Force API fault; press Resume after inspecting the stage' end
            end
        end
    end
    if not s.permission then s.status='Blocked by CSP physics permission';return end
    if not s.requested and s.retry<=0 then launch()
    elseif s.requested and s.age>1.5 and s.retry<=0 then
        -- Replace a worker only after its measured heartbeat failed to advance.
        s.epoch=s.epoch+1;store('epoch',s.epoch);s.requested=false;s.retry=.5
    end
end
function M.getState() return s end
return M
