---@diagnostic disable: undefined-global
-- Common observer/supervisor. It owns no native physics-model scheduler.
local M={}
local Bridge=require('modules.common_bridge')
local View=require('modules.observer_view')
local Metrics=require('modules.performance_metrics')
local ACROOT=ac.getFolder(ac.FolderID.Root):gsub('\\','/')
local ROOT=ACROOT..'/extension/plugins/ACNextGenNative'
local state={status=nil,error='',configError='',age=math.huge,lastHeartbeat=nil,enabled=false,
    sequence=0,hostID=nil,timer=0,leaseTimer=0,launchTimer=0,retryTimer=0,
    launching=false,sessionActive=false,shuttingDown=false,physicalEnabled=false,damagePolicy='original',inputContract='original'}
local metricsPath=ROOT..'/runtime/performance-'..os.time()..'-'..math.random(100000,999999)..'.jsonl'
local metrics=Metrics.new(function(row)
    local f,err=io.open(metricsPath,'ab');assert(f,err)
    local ok,message=pcall(function() local wrote,why=f:write(JSON.stringify(row),'\n');assert(wrote,why) end)
    f:close();assert(ok,message)
end)
local function metricSnapshot()
    local s=state.status or {};local b=s.bridge or {};local sim=ac.getSim()
    local trackOK,track=pcall(function() return ac.getTrackID() end)
    local carOK,car=pcall(function() return ac.getCar(0) end)
    return {timestamp=os.time(),host_id=state.hostID,car_id=ac.getCarID(0),
        host_status_age_seconds=state.age<math.huge and state.age or nil,host_status_fresh=state.age<=1,
        track_id=trackOK and track or nil,
        sdk_fps=sim.fps,cpu_occupancy=sim.cpuOccupancy,physics_late=sim.physicsLate,
        model_frame=s.model_frame,model_compute_us=s.last_compute_us,performance=s.performance,
        model_age_seconds=b.model_age,applied_frames=b.applied_frames,api_calls=b.api_calls,
        worker_status=b.worker_status,fault_code=b.fault_code,physical_requested=b.physical_requested,
        native_status=s.status,enhancement=s.enhancement,owned_actuation=(s.data or {}).owned_actuation,
        tyre_inputs=(s.data or {}).tyre_inputs,worker_epoch=b.sensor_epoch,worker_generation=b.generation,
        input_audit=Metrics.inputAudit(carOK and car or nil,sim),
        input_routes=(s.data or {}).input_routes,
        damper_local_channel=(s.data or {}).damper_local_channel,
        spring_local_channel=(s.data or {}).spring_local_channel,
        drive_local_channel=(s.data or {}).drive_local_channel,
        wheel_local_channel=(s.data or {}).wheel_local_channel,
        enhancement_apply_mask=Bridge.getState().enhancementApplyMask}
end
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function read(path)
    local f=io.open(path,'rb');if not f then return nil end
    local value=f:read('*a');f:close();return value
end
local function activeSession()
    local ok,sim=pcall(ac.getSim)
    return ok and sim and sim.isOnlineRace==false and sim.isSessionFinished~=true
end
local function liveHost()
    return state.status and state.status.status~='HOST_EXITED' and state.age<=1.
end
local function actualRun() return state.enabled and state.sessionActive and liveHost()==true and not state.shuttingDown end
local function publish()
    Bridge.setEnabled(actualRun())
    if not state.hostID then return false end
    local request={protocol=2,host_id=state.hostID,sequence=state.sequence,issued_at=os.time(),
        enabled=actualRun(),shutdown=state.shuttingDown,car_id=ac.getCarID(0),
        bridge_generation=Bridge.getState().generation,physical_enabled=state.physicalEnabled and actualRun() and not Bridge.getState().calibrationCaptureOnly}
    local f,err=io.open(ROOT..'/runtime/control.json','wb')
    if not f then state.error='Control file: '..tostring(err);return false end
    f:write(JSON.stringify(request),'\nNGP_CONTROL_END\n');f:close();return true
end
local function send()
    local ok,result=pcall(publish)
    if not ok then state.error=tostring(result);return false end
    return result
end
local function prepare() View.prepare(state,Bridge.getState()) end
local function launch()
    if state.launching or liveHost() or not state.sessionActive or state.retryTimer>0 then return end
    state.launching=true;state.retryTimer=2
    local arguments={'--session-managed','--ac-root',ACROOT,'--runtime',ROOT..'/runtime',
        '--damage-policy',state.damagePolicy,'--input-contract',state.inputContract}
    if state.wheelMaterialCapture then arguments[#arguments+1]='--wheel-material-capture' end
    local ok,err=pcall(os.runConsoleProcess,{
        filename=ROOT..'/bin/ACNextGenHost.exe',arguments=arguments,
        workingDirectory=ROOT..'/bin',timeout=0,terminateWithScript=true,assignJob=true,separateStderr=true
    },function(error,result)
        state.launching=false;state.retryTimer=1
        if state.sessionActive and (error or (result and result.exitCode~=0 and result.exitCode~=3)) then
            state.error='Native host: '..tostring(error or (result and result.stderr) or 'launch failed')
        end
    end)
    if not ok then state.launching=false;state.error='Native launch: '..tostring(err) end
end
local function beginSession()
    state.sessionActive=true;state.shuttingDown=false;state.enabled=true
    state.sequence=state.sequence+1;state.launchTimer=0;Bridge.newSession();send();prepare()
end
function M.shutdown()
    state.enabled=false;state.sessionActive=false;state.shuttingDown=true
    state.sequence=state.sequence+1;Bridge.shutdown();local result=send();prepare();return result
end
function M.init()
    local ok,cfg=pcall(function()
        local raw=read(ROOT..'/config.json');if not raw then return nil end
        assert(#raw<16384,'Configuration is too large');return JSON.parse(raw)
    end)
    if ok and type(cfg)=='table' and cfg.schema==1 and
        (cfg.physics_mode=='bounded' or cfg.physics_mode=='observe') and cfg.effect=='additional_yaw_damping' then
        state.physicalEnabled=cfg.physics_mode=='bounded'
        if cfg.model_damage_policy==nil or cfg.model_damage_policy=='original' then state.damagePolicy='original'
        elseif cfg.model_damage_policy=='event_only' then state.damagePolicy='event_only'
        elseif cfg.model_damage_policy=='event_root_v1' then state.damagePolicy='event_root_v1'
        else state.physicalEnabled=false;state.configError='Observe mode: invalid model_damage_policy' end
        if cfg.model_input_contract==nil or cfg.model_input_contract=='original' then state.inputContract='original'
        elseif cfg.model_input_contract=='csp_g_v1' then state.inputContract='csp_g_v1'
        else state.physicalEnabled=false;state.configError='Observe mode: invalid model_input_contract' end
    else state.configError='Observe mode: missing or invalid config.json' end
    Bridge.init(ROOT,state.physicalEnabled,ok and type(cfg)=='table' and cfg.enhancement or nil)
    state.wheelMaterialCapture=ok and type(cfg)=='table' and type(cfg.enhancement)=='table' and cfg.enhancement.wheel_interval_capture==true
    ac.onSessionStart(function() if activeSession() then beginSession() end end)
    ac.onRelease(function() M.shutdown() end)
    ac.log('[ACNextGen Native 4.3] Common Worker supervisor loaded; owned enhancement channels sample pending calibration')
    prepare()
end
function M.update(dt)
    if not finite(dt) or dt<=0 then return end
    local ok,sim=pcall(ac.getSim)
    local mode='inactive'
    if ok and sim and sim.isOnlineRace==false and sim.isSessionFinished~=true
        and sim.isPaused~=true and sim.isReplayActive~=true and sim.isReplayOnlyMode~=true then
        if not state.enabled then mode='models_off'
        elseif actualRun() and state.status.status=='RUNNING_NATIVE_MODELS' then
            mode=state.physicalEnabled and 'models_on_bounded' or 'models_on_observe'
        end
    end
    local rendered,renderDt=pcall(function() return ui.deltaTime() end)
    if rendered then
        local recorded,message=pcall(metrics.add,renderDt,mode,metricSnapshot)
        state.performanceError=recorded and metrics.error or tostring(message)
        state.renderMetrics=metrics.last;state.performanceLog=metricsPath
    end
    state.age=state.age+dt;state.timer=state.timer+dt;state.leaseTimer=state.leaseTimer+dt
    state.launchTimer=state.launchTimer+dt;state.retryTimer=math.max(0,state.retryTimer-dt)
    local active=activeSession()
    if active and not state.sessionActive then beginSession()
    elseif not active and state.sessionActive then M.shutdown() end
    local changed=false
    if state.timer>=.2 then
        state.timer=0;changed=true
        local ok,result=pcall(function()
            local raw=read(ROOT..'/runtime/status.json');if not raw then return nil end
            assert(#raw<=128000,'Status file too large')
            local obj=JSON.parse(raw)
            assert(type(obj)=='table' and obj.protocol==2 and type(obj.host_id)=='string','Invalid native status')
            assert(finite(obj.heartbeat) and obj.heartbeat>=0 and obj.heartbeat%1==0,'Invalid native heartbeat')
            return obj
        end)
        if ok and result then
            if result.host_id~=state.hostID then
                state.sequence=math.max(state.sequence,result.command_sequence or 0)+1
                state.lastHeartbeat=result.heartbeat;state.age=math.huge;state.hostID=result.host_id
                Bridge.newHost(result.host_id)
            elseif result.heartbeat~=state.lastHeartbeat then state.age=0;state.lastHeartbeat=result.heartbeat end
            state.status=result
            if liveHost() then state.error='' end
            if result.status=='MODEL_ERROR' and liveHost() then state.enabled=false end
        elseif not ok then state.error=tostring(result) end
    end
    Bridge.update(dt,state.sessionActive,actualRun(),ac.getCarID(0))
    if state.sessionActive and state.launchTimer>=.4 then launch() end
    if state.leaseTimer>=.05 then state.leaseTimer=0;send() end
    if changed then prepare() end
end
function M.start()
    if not activeSession() then state.error='Offline session required';prepare();return false end
    state.sessionActive=true;state.shuttingDown=false;state.enabled=true;state.sequence=state.sequence+1
    Bridge.resume();launch();send();prepare();return true
end
function M.stop()
    state.enabled=false;state.sequence=state.sequence+1;Bridge.setEnabled(false)
    local result=send();prepare();return result
end
function M.drawUI() View.draw(state,Bridge.getState(),M.stop,M.start) end
function M.getState() return state end
return M
