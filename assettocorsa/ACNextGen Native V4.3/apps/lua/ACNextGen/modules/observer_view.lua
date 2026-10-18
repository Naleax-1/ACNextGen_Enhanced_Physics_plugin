---@diagnostic disable: undefined-global
-- English dashboard. Text/series are prepared at the status rate, not render rate.
local M={}
-- Drawing coordinates include the CSP window title bar; leave it clear.
local function point(x,y) return vec2(x,y+24) end
local P={bg=rgbm(.045,.060,.080,1),card=rgbm(.080,.105,.135,1),line=rgbm(.15,.21,.27,1),
    text=rgbm(.88,.92,.96,1),muted=rgbm(.48,.59,.69,1),cyan=rgbm(.12,.78,.88,1),
    green=rgbm(.30,.83,.57,1),amber=rgbm(.98,.69,.28,1),red=rgbm(.95,.37,.39,1)}
local cache={lines={},order={},history={},frame=nil,version='ACNEXTGEN  /  NATIVE 4.3'}
local function fmt(v,digits) return type(v)=='number' and string.format('%.'..(digits or 1)..'f',v) or '--' end
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
-- Explain model gain only. Contact/TTL/permission at the Worker are separate.
function M.tyreReasons(inputs,owned,i)
    if type(inputs)~='table' or inputs.schema~=1 or type(owned)~='table' then return 'Diagnostics unavailable' end
    if owned.result~=0 then return 'Owner extraction unavailable ('..tostring(owned.result)..')' end
    local w=(inputs.wheels or {})[i];local gain=(owned.tyre_ns_m or {})[i]
    if type(w)~='table' or not finite(gain) then return 'Diagnostics unavailable' end
    for _,name in ipairs({'wheel_audit','thermal','damage_state','vehicle_condition','tire_force'}) do
        if (inputs.states or {})[name]~='RUNNING' then return name..' not running' end
    end
    if not w.exists then return 'Wheel unavailable' end
    if not inputs.wheels_valid then return 'Owner wheels invalid' end
    if not w.load_available then return 'Load unavailable' end
    if not w.active then return 'Owner inactive' end
    if not finite(w.slip_angle_rad) or not finite(w.contact_quality) or not finite(w.damage) or not finite(inputs.tyre_stress) then
        return 'Owner input unavailable'
    end
    if math.abs(w.slip_angle_rad)>math.pi/2 then return 'Slip outside supported range' end
    if gain>0 then return 'Gain available (application checked separately)' end
    local reasons={}
    if w.slip_angle_rad==0 then reasons[#reasons+1]='zero slip' end
    if w.contact_quality<=0 then reasons[#reasons+1]='zero contact quality' end
    if inputs.tyre_stress>=1 then reasons[#reasons+1]='thermal suppression' end
    if w.damage>=1 then reasons[#reasons+1]='damage suppression' end
    return #reasons>0 and table.concat(reasons,' + ') or 'Zero gain: unresolved'
end
function M.prepare(state,bridge)
    local s=state.status or {};local b=s.bridge or {};local perf=s.performance or {};local data=s.data or {}
    cache.host=state.age<=1 and (({RUNNING_NATIVE_MODELS='Running',MODEL_ERROR='Model fault',STOPPED='Stopped',
        STALE_TELEMETRY='Input stale',PAUSED_OR_REPLAY='Paused',WAITING_FOR_AC='Waiting for AC'})[s.status] or 'Starting') or 'Disconnected'
    cache.route=({['Starting common worker']='Starting',['Worker stopped with error']='Worker error',
        ['Worker stopped']='Stopped',['Worker launch failed']='Launch failed',['Worker file missing']='File missing',
        ['Waiting for offline session']='Waiting',['Worker API unavailable']='API unavailable',
        ['Blocked by CSP physics permission']='Permission blocked'})[bridge.status] or bridge.status or 'Waiting'
    cache.physical=(bridge.fault==24 and 'FAULT') or (s.force_armed and 'ARMED' or 'INHIBITED')
    cache.car=tostring(s.car_id or bridge.carID or 'No car selected')
    cache.frames=tostring(s.model_frame or 0);cache.modules=tostring(s.module_count or 51)
    cache.compute=fmt((s.last_compute_us or 0)/1000,2)..' ms';cache.fast=fmt(perf.fast_effect_us,2)..' us'
    cache.ack=tostring(b.ack_sequence or bridge.ack or 0);cache.calls=tostring(b.api_calls or bridge.apiCalls or 0)
    cache.applied=tostring(b.applied_frames or bridge.appliedFrames or 0)
    cache.zeroValidation=b.zero_api_validated and 'Accepted' or 'Not confirmed'
    cache.power=fmt(b.power_w,2)..' W';cache.moment=fmt(b.yaw_moment_nm,2)..' Nm'
    cache.mode=bridge.calibrationCaptureOnly and 'Calibration: normal model forces OFF' or (bridge.physical and 'Bounded additional yaw damping' or 'Observe only')
    cache.input=tostring(s.input_source or 'Waiting for telemetry')
    cache.permission=bridge.permission and 'ALLOWED' or 'BLOCKED'
    cache.stage=tostring(b.api_stage or bridge.stage or 0);cache.fault=tostring(b.fault_code or bridge.fault or 0)
    cache.sensor=fmt(type(b.sensor_age)=='number' and b.sensor_age*1000 or nil,1)..' ms'
    cache.modelAge=fmt(type(b.model_age)=='number' and b.model_age*1000 or nil,1)..' ms'
    cache.error=state.error~='' and state.error or (state.configError~='' and state.configError or bridge.error)
    local render=state.renderMetrics
    cache.renderText=render and ('Render '..fmt(render.mean_fps,1)..' FPS / p99 '..fmt(render.frame_ms_p99,2)..' ms')
        or 'Render metrics: waiting for live frames'
    cache.metricsError=state.performanceError
    cache.inputRoutes={}
    local localDamper=data.damper_local_channel or {}
    local localState=not localDamper.selected and 'Not configured' or
        ((state.age>1 or not localDamper.fresh) and 'Stale' or (localDamper.fault_latched and 'FAULT - Resume required' or
        (localDamper.application_enabled and 'Applying / local receipt' or 'Inhibited')))
    cache.localDamperText='Local damper: '..localState..' / sent '..tostring(localDamper.commands_sent or 0)..
        ' / confirmed '..tostring(localDamper.commands_acked or 0)
    cache.localDamperWork='Damper work: available '..fmt(localDamper.available_j,6)..' J / reserved '..fmt(localDamper.unresolved_j,6)..' J'
    cache.localDamperFault=localDamper.selected and localDamper.fresh and localDamper.fault_latched
    local spring=data.spring_local_channel or {}
    local springState=not spring.selected and 'Not configured' or ((state.age>1 or not spring.fresh) and 'Stale' or
        (spring.fault_latched and 'FAULT - Resume required' or ((spring.reference_lease or 0)==0 and 'Waiting for stationary reference' or
        (spring.application_enabled and 'Active / local receipt' or 'Inhibited'))))
    cache.localSpringText='Local spring: '..springState..' / reference '..tostring(spring.reference_lease or 0)
    cache.localSpringWork='Spring confirmed '..tostring(spring.commands_acked or 0)..' / available '..fmt(spring.available_j,6)..' J / reserved '..fmt(spring.unresolved_j,6)..' J'
    cache.localSpringFault=spring.selected and spring.fresh and spring.fault_latched
    local drive=data.drive_local_channel or {}
    local driveState=not drive.selected and 'Not configured' or ((state.age>1 or not drive.fresh) and 'Stale' or
        (drive.fault_latched and 'FAULT - Resume required' or (drive.application_enabled and 'Applying / local receipt' or 'Inhibited')))
    cache.localDriveText=((tonumber(drive.lsd_nm_per_hint) or 0)>0 and 'Local drive + LSD: ' or 'Local windup: ')..driveState..' / confirmed '..tostring(drive.commands_acked or 0)
    cache.localDriveWork='Windup work: available '..(drive.balance_reported and fmt(drive.available_j,6)..' J' or 'unavailable')..' / reserved '..fmt(drive.unresolved_j,6)..' J'
    cache.localDriveFault=drive.selected and drive.fresh and drive.fault_latched
    local wheel=data.wheel_local_channel or {}
    cache.localWheelVisible=wheel.declared==true or wheel.selected==true or wheel.profile_conflict==true
    local wheelFresh=state.age<=1 and wheel.fresh==true
    local wheelState=not cache.localWheelVisible and 'Not configured' or (state.age>1 and 'Status unavailable' or
        (wheel.profile_conflict and 'Configuration conflict' or (wheel.profile_valid==false and 'Invalid configuration' or
        (not wheel.selected and 'Vehicle mismatch' or (not wheelFresh and 'Status unavailable' or
        (wheel.fault_latched and 'FAULT - Resume required' or (wheel.application_enabled and 'Output interval pending' or 'Waiting / inhibited')))))))
    local wheelReasons={none='No decision reported',pending='Waiting for the next interval measurement',model_unavailable='Model input missing or expired',
        native_sample_unavailable='Native brake or wheel samples unavailable',insufficient_energy='Stored windup energy is insufficient',inhibited='Session, permission or output switch inhibits writes',
        plan_context='Plan identity or freshness rejected',context_or_interval='Profile or update interval rejected',missing_components='Required components missing',
        windup_unqualified='Windup attribution not qualified',rear_limit='Rear torque limit exceeded',windup_limit='Windup attribution limit exceeded',pair_not_closed='LSD pair is not closed',
        wheel_input='Wheel input outside supported range',noncanonical_correction='Composed correction does not match',baseline_interval='Native braking cannot be bounded for this interval',
        pair_not_passive='LSD work cannot be certified nonpositive',invalid_power='Power bound invalid',nonfinite_work='Work bound invalid',receipt_context='Receipt identity mismatch',
        incomplete_receipt='Interval receipt incomplete',missing_samples='Receipt samples missing',altered_samples='Applied torque or samples changed',work_exceeds_reservation='Measured work exceeds reservation',
        actor_refused_or_partial='Actuator preflight refused or API write failed',actor_latched='Actuator fault is latched',clock_not_increasing='Worker clock did not advance',generation_regressed='Old generation rejected',
        stopped_with_pending='Stopped before interval receipt completed',unknown='Unrecognized decision'}
    local reason=wheelFresh and (wheelReasons[wheel.reason] or 'Decision unavailable') or 'Fresh Worker status required'
    if state.age>1 then reason='Fresh Worker status required'
    elseif wheel.profile_conflict then reason='Four-wheel and legacy drive configurations overlap'
    elseif wheel.declared and wheel.profile_valid==false then reason='Four-wheel configuration was rejected'
    elseif cache.localWheelVisible and not wheel.selected then reason='Configuration does not match the current vehicle' end
    cache.localWheelText='Four-wheel: '..wheelState
    cache.localWheelReason='Reason: '..reason
    cache.localWheelCounts='Hints '..tostring(wheel.hint_sequence or 0)..' / intervals sent '..tostring(wheel.commands_sent or 0)..' / API-confirmed '..tostring(wheel.commands_acked or 0)
    local balance=wheelFresh and wheel.balance_reported and finite(wheel.available_j)
    cache.localWheelWork='Windup: available '..(balance and fmt(wheel.available_j,6)..' J' or 'unavailable')..' / reserved '..
        (wheelFresh and finite(wheel.unresolved_j) and fmt(wheel.unresolved_j,6)..' J' or 'unavailable')
    cache.localWheelFault=state.age<=1 and (wheelFresh and wheel.fault_latched or wheel.profile_conflict==true or (wheel.declared and wheel.profile_valid==false))
    cache.localWheelProof='API confirmation does not verify vehicle response.'
    for _,name in ipairs({'damage_event','impact_sensor','vehicle_condition','load_transfer','arm_compliance','road_input_interpreter'}) do
        local route=(data.input_routes or {})[name]
        cache.inputRoutes[#cache.inputRoutes+1]=name..': '..(route and route.status or 'original input')
    end
    local audit=render and render.input_audit or {};local g=audit.acceleration_g or {}
    cache.inputAudit='Render SDK acceleration G (X/Y/Z): '..fmt(g[1],3)..' / '..fmt(g[2],3)..' / '..fmt(g[3],3)
    cache.contactAudit={}
    for _,w in ipairs(audit.wheels or {}) do
        cache.contactAudit[#cache.contactAudit+1]='Wheel '..tostring(w.index)..': contact geometry '..
            ((w.contact_point_world_m and w.normal_well_formed) and 'available' or 'unavailable')..
            '; load '..fmt(w.load_n,1)..' N; travel '..fmt(w.suspension_travel_m,4)..' m'
    end
    local enhancement=s.enhancement or {}
    cache.enhancementText='Additional channels: '..tostring(enhancement.status or 'Waiting')..
        ' / candidates '..tostring(enhancement.candidate_channels or 0)..' / ACK '..tostring(enhancement.ack or 0)
    cache.enhancementMask='Configured physical mask '..tostring(bridge.enhancementApplyMask or 0)..
        ' (1=suspension, 2=tyre body, 4=LSD)'
    cache.enhancementCounts='Applied suspension / tyre / LSD: '..tostring(enhancement.applied_suspension or 0)..
        ' / '..tostring(enhancement.applied_tyre or 0)..' / '..tostring(enhancement.applied_diff or 0)
    cache.enhancementFault='Extra API stage '..tostring(enhancement.api_stage or 0)..' / fault '..tostring(enhancement.fault or 0)..
        ' / compute '..tostring(enhancement.compute_result or 0)
    cache.tyreLines={};local inputs=data.tyre_inputs or {};local owned=data.owned_actuation or {}
    local context=state.age>1 and 'stale' or (s.status=='RUNNING_NATIVE_MODELS' and 'model snapshot' or 'held / inactive')
    cache.tyreContext='Tyre gain diagnostics: '..context..' / frame '..cache.frames..' / stress '..fmt(inputs.tyre_stress,3)
    local damage=inputs.damage_runtime or {}
    cache.damageContext='Wear candidate '..fmt(damage.runtimeDamageAdd,5)..'/s; accumulation scale '..
        fmt((inputs.damage_parameters or {}).runtimeAccumulationScale,1)..'; event delta '..fmt(damage.lastEventDelta,5)
    for i,label in ipairs({'FL','FR','RL','RR'}) do
        local w=(inputs.wheels or {})[i] or {}
        cache.tyreLines[#cache.tyreLines+1]=label..': '..M.tyreReasons(inputs,owned,i)
        cache.tyreLines[#cache.tyreLines+1]='  gain '..fmt((owned.tyre_ns_m or {})[i],5)..' Ns/m; slip '..fmt(w.slip_angle_rad,5)..
            ' rad; contact '..fmt(w.contact_quality,3)..'; damage '..fmt(w.damage,3)
    end
    cache.order={};cache.states=data.module_status or {};cache.errors=data.errors or {}
    cache.signals=data.signals or {}
    for _,row in ipairs((s.models or {}).modules or {}) do cache.order[#cache.order+1]=row.name end
    cache.slowest,cache.cost='--',0
    for name,value in pairs(perf.modules_us or {}) do if value>cache.cost then cache.slowest,cache.cost=name,value end end
    cache.costText=fmt(cache.cost/1000,2)..' ms'
    if s.model_frame and s.model_frame~=cache.frame then
        cache.frame=s.model_frame;cache.history[#cache.history+1]=(s.last_compute_us or 0)/1000
        if #cache.history>48 then table.remove(cache.history,1) end
    end
end
local function text(x,y,value,color) ui.drawText(value,point(x,y),color or P.text) end
local function card(x,y,w,h,label,value,color)
    ui.drawRectFilled(point(x,y),point(x+w,y+h),P.card,7)
    text(x+14,y+10,label,P.muted);text(x+14,y+33,value,color or P.text)
end
function M.draw(state,bridge,stop,resume)
    local width=math.max(560,ui.availableSpaceX())
    local wheelHeight=cache.localWheelVisible and 104 or 0
    ui.drawRectFilled(point(0,0),point(width,476+wheelHeight),P.bg,9)
    ui.drawRectFilled(point(0,0),point(4,62),P.cyan,2)
    text(18,12,cache.version,P.cyan)
    text(18,35,'COMMON PHYSICS WORKER  /  NO CAR DATA EDITS',P.muted)
    ui.setCursor(point(width-178,15))
    if ui.button('Stop',vec2(72,30)) then stop() end
    ui.sameLine()
    if ui.button('Resume',vec2(80,30)) then resume() end
    local gap=10;local cw=(width-36-2*gap)/3
    card(18,74,cw,68,'NATIVE HOST',cache.host,state.age<=1 and P.green or P.amber)
    card(18+cw+gap,74,cw,68,'COMMON WORKER',cache.route,bridge.fault==24 and P.red or (bridge.permission and P.cyan or P.amber))
    local armed=state.enabled and state.sessionActive and state.age<=1 and bridge.permission and bridge.age<=.2
        and state.status and state.status.force_armed
    local physical=bridge.fault==24 and 'FAULT' or (armed and 'ARMED' or 'INHIBITED')
    card(18+2*(cw+gap),74,cw,68,'YAW OUTPUT',physical,bridge.fault==24 and P.red or (armed and P.green or P.amber))
    text(20,158,cache.car,P.text)
    text(20,181,cache.mode..'   |   '..cache.input,P.muted)
    local half=(width-46)/2
    card(18,211,half,71,'MODEL COMPUTE  /  51 MODELS',cache.compute,P.text)
    card(28+half,211,half,71,'FAST EFFECT  /  200 HZ TARGET',cache.fast,P.cyan)
    ui.drawRectFilled(point(18,294),point(width-18,358),P.card,6)
    text(30,301,'COMPUTE HISTORY  /  50 ms model budget',P.muted)
    local h=cache.history;local plotW=width-60
    ui.drawLine(point(30,336.5),point(width-30,336.5),P.line,1)
    for i=2,#h do
        local x1=30+(i-2)*plotW/47;local x2=30+(i-1)*plotW/47
        ui.drawLine(point(x1,350-math.min(h[i-1],100)*.27),point(x2,350-math.min(h[i],100)*.27),P.cyan,1.5)
    end
    text(20,371,'ACK '..cache.ack..'    API CALLS '..cache.calls..'    APPLIED FRAMES '..cache.applied,P.text)
    text(20,394,'YAW MOMENT '..cache.moment..'    PAIR POWER '..cache.power,P.cyan)
    text(20,417,'PERMISSION '..cache.permission..'    API STAGE '..cache.stage..'    FAULT '..cache.fault,P.muted)
    text(20,440,'SENSOR AGE '..cache.sensor..'    MODEL AGE '..cache.modelAge,P.muted)
    if cache.localWheelVisible then
        text(20,477,cache.localWheelText,cache.localWheelFault and P.red or P.cyan)
        text(20,500,cache.localWheelCounts,P.text)
        text(20,523,cache.localWheelReason,P.muted)
        text(20,546,cache.localWheelWork,P.muted)
    end
    ui.setCursor(point(18,488+wheelHeight))
    if cache.error and cache.error~='' then ui.textColored(cache.error,P.red) end
    ui.treeNode('Diagnostics & model status',function()
        ui.text('Slowest: '..cache.slowest..' / '..cache.costText)
        ui.text('Models: '..cache.modules..' / frames: '..cache.frames..' / errors: '..#cache.errors)
        ui.text('Zero-force API validation: '..cache.zeroValidation)
        ui.textColored(cache.localDamperText,cache.localDamperFault and P.red or P.muted)
        ui.text(cache.localDamperWork)
        ui.textColored(cache.localSpringText,cache.localSpringFault and P.red or P.muted)
        ui.text(cache.localSpringWork)
        ui.textColored(cache.localDriveText,cache.localDriveFault and P.red or P.muted)
        ui.text(cache.localDriveWork)
        ui.textColored(cache.localWheelText,cache.localWheelFault and P.red or P.muted)
        ui.text(cache.localWheelReason)
        ui.text(cache.localWheelProof)
        ui.text(cache.renderText)
        ui.text(cache.inputAudit)
        ui.text('Contact geometry availability is not proof of ground contact.')
        for _,line in ipairs(cache.contactAudit) do ui.text(line) end
        ui.text('Model acceleration input routes')
        for _,line in ipairs(cache.inputRoutes) do ui.text(line) end
        ui.text(cache.enhancementText)
        ui.text(cache.enhancementMask)
        ui.text(cache.enhancementCounts)
        ui.text(cache.enhancementFault)
        ui.text(cache.tyreContext)
        ui.text(cache.damageContext)
        for _,line in ipairs(cache.tyreLines) do ui.text(line) end
        if cache.metricsError and cache.metricsError~='' then ui.textColored('Render metrics: '..cache.metricsError,P.amber) end
        ui.childWindow('native_model_status',vec2(0,180),function()
            for _,name in ipairs(cache.order) do
                local value=cache.states[name]
                if not value and name=='impact_sensor' then value=cache.signals.ngp_impact_status end
                ui.text(name..'  '..tostring(value or 'Not updated'))
            end
        end)
    end)
    ui.textColored('Experimental additional effect. Original AC physics remains the base.',P.muted)
end
function M.getCache() return cache end
return M
