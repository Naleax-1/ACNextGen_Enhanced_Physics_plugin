-- Declaration validation only. Evidence must be certified before deployment.
local M={}
local function number(v) assert(type(v)=='number' and v==v and math.abs(v)<math.huge);return v end
local function integer(v,max) number(v);assert(v>=1 and v<=max and v%1==0);return v end
local function yes(v) assert(v==true) end
local function hash(text) local a,b=1,0;for i=1,#text do a=(a+text:byte(i))%65521;b=(b+a)%65521 end;return b*65536+a end
local function array(v,max)
    assert(type(v)=='table');local result={};local count=0
    for k in pairs(v) do assert(type(k)=='number' and k>=1 and k<=4 and k%1==0);count=count+1 end
    assert(count==4)
    for i=1,4 do local n=number(v[i]);assert(n>=0 and (not max or n<=max));result[i]=n end
    return result
end
function M.parse(j,carID,patch)
    local ok,result=pcall(function()
        local api=j.force_argument
        if api~=nil then
            assert(type(api)=='table' and (api.mode=='force' or api.mode=='force_times_dt'));yes(api.verified)
        end

        assert(type(j)=='table' and integer(j.schema,1)==1);yes(j.enabled)
        local mode=j.execution_mode;if mode==nil then mode='host_command_v1' end
        assert(mode=='host_command_v1' or mode=='worker_local_v1')
        assert(type(j.car_id)=='string' and #j.car_id>=1 and #j.car_id<=200 and j.car_id:match('^[a-zA-Z0-9_-]+$') and j.car_id==carID)
        assert(type(j.evidence_reference)=='string' and #j.evidence_reference>=1 and #j.evidence_reference<=500)
        local carHash=integer(j.car_hash,4294967295);assert(carHash==hash(j.car_id))
        local version=integer(j.patch_code,2147483646);assert(version==patch)
        local proof=integer(j.evidence_id,9007199254740991)
        for _,k in ipairs({'additional_damping_contract_verified','neutral_verified','relative_velocity_verified','force_units_verified','wheel_reaction_verified','exclusive_owner','coordinates_verified','material_points_verified','sampled_together_verified'}) do yes(j[k]) end
        local neutral,gain=array(j.neutral_scale,10),array(j.gain_ns_m,10000)
        local force,capacity=number(j.max_force_n),number(j.storage_capacity_j)
        assert(force>0 and force<=20 and capacity>=0 and capacity<=1)
        local w=j.work;assert(type(w)=='table')
        for _,k in ipairs({'bounds_verified','force_interval_verified','constant_world_force_verified'}) do yes(w[k]) end
        local dt=number(w.dt);assert(dt>0 and dt<=.003)
        local bounds={}
        for _,k in ipairs({'body_acceleration_bound_ms2','wheel_acceleration_bound_ms2','body_velocity_error_ms','wheel_velocity_error_ms'}) do bounds[k]=array(w[k]) end
        bounds.bounds_verified=true
        assert(type(j.receipt)=='table');yes(j.receipt.displacement_bounds_verified)
        local bodyError,wheelError=array(j.receipt.body_displacement_error_m),array(j.receipt.wheel_displacement_error_m)
        local input=j.input;assert(type(input)=='table' and input.source=='common_worker_interval_geometry_v1')
        for _,k in ipairs({'body_point_velocity_contract_verified','rigid_geometry_verified','history_bound_verified','endpoint_error_verified','time_interval_verified','coordinates_verified'}) do yes(input[k]) end
        local history=array(input.history_acceleration_bound_ms2);local beforeError,afterError=array(input.position_before_error_m),array(input.position_after_error_m)
        return {api_argument_mode=api and api.mode or nil,api_argument_verified=api~=nil,car_hash=carHash,patch_code=version,evidence_id=proof,dt=dt,max_force_n=force,execution_mode=mode,
            units_verified=true,wheel_reaction_verified=true,coordinates_verified=true,material_points_verified=true,
            exclusive_owner=true,action_interval_verified=true,constant_world_force_verified=true,
            neutral_scale=neutral,gain_ns_m=gain,storage_capacity_j=capacity,work=bounds,
            body_displacement_error_m=bodyError,wheel_displacement_error_m=wheelError,evidence_reference=j.evidence_reference,
            input={source=input.source,history_acceleration_bound_ms2=history,position_before_error_m=beforeError,position_after_error_m=afterError}}
    end)
    return ok and result or nil
end
return M
