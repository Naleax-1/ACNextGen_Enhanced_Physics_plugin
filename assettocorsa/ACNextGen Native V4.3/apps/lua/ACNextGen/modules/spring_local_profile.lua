-- Validates declarations, never independently certifies their measurements.
local M={}
local function number(v) assert(type(v)=='number' and v==v and math.abs(v)<math.huge);return v end
local function integer(v,cap) number(v);assert(v>=1 and v<=cap and v%1==0);return v end
local function yes(v) assert(v==true) end
local function array(v,cap)
    assert(type(v)=='table');local count=0;local out={}
    for k in pairs(v) do assert(type(k)=='number' and k>=1 and k<=4 and k%1==0);count=count+1 end;assert(count==4)
    for i=1,4 do out[i]=number(v[i]);assert(out[i]>=0 and out[i]<=(cap or 1e300)) end;return out
end
function M.parse(j,carID,patch)
    local ok,result=pcall(function()
        local api=j.force_argument
        if api~=nil then
            assert(type(api)=='table' and (api.mode=='force' or api.mode=='force_times_dt'));yes(api.verified)
        end

        assert(integer(j.schema,1)==1 and j.execution_mode=='worker_local_spring_v1');yes(j.enabled)
        assert(type(j.car_id)=='string' and j.car_id==carID and #carID>=1 and #carID<=200 and carID:match('^[a-zA-Z0-9_-]+$'))
        assert(type(j.evidence_reference)=='string' and #j.evidence_reference>=1 and #j.evidence_reference<=500)
        local hash=integer(j.car_hash,4294967295);local a,b=1,0;for i=1,#carID do a=(a+carID:byte(i))%65521;b=(b+a)%65521 end;assert(hash==b*65536+a)
        assert(integer(j.patch_code,2147483646)==patch);local proof=integer(j.evidence_id,9007199254740991)
        for _,k in ipairs({'additional_contract_verified','force_units_verified','wheel_reaction_verified','geometry_verified','height_error_verified','exclusive_owner','coordinates_verified','material_points_verified','sampled_together_verified'}) do yes(j[k]) end
        local gain,force,capacity=number(j.additional_gain_n_m),number(j.max_force_n),number(j.storage_capacity_j)
        assert(gain>=0 and gain<=120 and force>0 and force<=12 and capacity>=0 and capacity<=1)
        local current=array(j.current_height_error_m,.001);local w=j.work
        for _,k in ipairs({'bounds_verified','force_interval_verified','constant_world_force_verified'}) do yes(w[k]) end
        local dt=number(w.dt);assert(dt>0 and dt<=.003);local work={bounds_verified=true}
        for _,k in ipairs({'body_acceleration_bound_ms2','wheel_acceleration_bound_ms2','body_velocity_error_ms','wheel_velocity_error_ms'}) do work[k]=array(w[k]) end
        yes(j.receipt.displacement_bounds_verified);local bodyError,wheelError=array(j.receipt.body_displacement_error_m,.001),array(j.receipt.wheel_displacement_error_m,.001)
        local r=j.reference;assert(r.control_source=='csp_statecar_render_v1')
        for _,k in ipairs({'controls_contract_verified','support_from_load_verified','stationary_contract_verified','ground_contact_contract_verified'}) do yes(r[k]) end
        local dwell,speed,drift=number(r.dwell_s),number(r.max_speed_ms),number(r.max_height_drift_m)
        assert(dwell>=.05 and dwell<=2 and speed>=0 and speed<=.005 and drift>=0 and drift<=.001)
        local input=j.input;assert(input.source=='common_worker_interval_geometry_v1')
        for _,k in ipairs({'body_point_velocity_contract_verified','rigid_geometry_verified','history_bound_verified','endpoint_error_verified','time_interval_verified','coordinates_verified'}) do yes(input[k]) end
        return {api_argument_mode=api and api.mode or nil,api_argument_verified=api~=nil,car_hash=hash,patch_code=patch,evidence_id=proof,evidence_reference=j.evidence_reference,execution_mode=j.execution_mode,
            additional_gain_n_m=gain,max_force_n=force,storage_capacity_j=capacity,dt=dt,current_height_error_m=current,
            additional_contract_verified=true,units_verified=true,wheel_reaction_verified=true,geometry_verified=true,height_error_verified=true,
            exclusive_owner=true,coordinates_verified=true,material_points_verified=true,action_interval_verified=true,constant_world_force_verified=true,receipt_bounds_verified=true,
            work=work,body_displacement_error_m=bodyError,wheel_displacement_error_m=wheelError,
            reference={control_source=r.control_source,controls_contract_verified=true,support_from_load_verified=true,stationary_contract_verified=true,ground_contact_contract_verified=true,dwell_s=dwell,max_speed_ms=speed,max_height_drift_m=drift},
            input={source=input.source,history_acceleration_bound_ms2=array(input.history_acceleration_bound_ms2),position_before_error_m=array(input.position_before_error_m),position_after_error_m=array(input.position_after_error_m)}}
    end)
    return ok and result or nil
end
return M
