-- Declaration validation only; no asserted flag certifies a measurement.
local M={}
local function number(v) assert(type(v)=='number' and v==v and math.abs(v)<math.huge);return v end
local function integer(v,max) number(v);assert(v>=1 and v<=max and v%1==0);return v end
local function yes(v) assert(v==true) end
local function array(v,signed)
    assert(type(v)=='table');local count=0;local out={}
    for k in pairs(v) do assert(type(k)=='number' and k>=1 and k<=2 and k%1==0);count=count+1 end;assert(count==2)
    for i=1,2 do local x=number(v[i]);if signed then assert(x~=0 and math.abs(x)<=1000) else assert(x>=0 and x<=1e300) end;out[i]=x end
    return out
end
function M.parse(j,carID,patch)
    local ok,result=pcall(function()
        assert(type(j)=='table' and integer(j.schema,1)==1);yes(j.enabled)
        assert(j.execution_mode=='worker_local_additional_windup_v1' and j.torque_argument_contract=='constant_raw_per_nm')
        assert(type(j.car_id)=='string' and j.car_id==carID and #carID>=1 and #carID<=200 and carID:match('^[a-zA-Z0-9_-]+$'))
        assert(type(j.evidence_reference)=='string' and #j.evidence_reference>=1 and #j.evidence_reference<=500)
        local hash=integer(j.car_hash,4294967295);local a,b=1,0;for i=1,#carID do a=(a+carID:byte(i))%65521;b=(b+a)%65521 end;assert(hash==b*65536+a)
        assert(integer(j.patch_code,2147483646)==patch);local evidence=integer(j.evidence_id,9007199254740991)
        local out={car_hash=hash,patch_code=patch,evidence_id=evidence,evidence_reference=j.evidence_reference,execution_mode=j.execution_mode,torque_argument_contract=j.torque_argument_contract}
        for _,k in ipairs({'additional_windup_contract_verified','same_callback_sample_verified','units_verified','rwd_verified','exclusive_owner','controls_contract_verified','action_interval_verified','constant_torque_verified','acceleration_bound_verified','sample_units_verified'}) do yes(j[k]);out[k]=true end
        out.dt=number(j.dt);out.max_torque_nm=number(j.max_torque_nm);out.command_scale_raw_per_nm=number(j.command_scale_raw_per_nm)
        assert(out.dt>0 and out.dt<=.003 and out.max_torque_nm>0 and out.max_torque_nm<=12 and out.command_scale_raw_per_nm~=0 and math.abs(out.command_scale_raw_per_nm)<=1000 and number(j.initial_energy_j)==0)
        out.storage_capacity_j=0
        if j.storage_capacity_j~=nil then
            out.storage_capacity_j=number(j.storage_capacity_j);assert(out.storage_capacity_j>=0 and out.storage_capacity_j<=1)
            if out.storage_capacity_j>0 then yes(j.recovery_contract_verified);out.recovery_contract_verified=true end
        end
        out.lsd_nm_per_hint=0
        if j.lsd_nm_per_hint~=nil then
            out.lsd_nm_per_hint=number(j.lsd_nm_per_hint);assert(out.lsd_nm_per_hint>=0 and out.lsd_nm_per_hint<=12)
            if out.lsd_nm_per_hint>0 then
                for _,k in ipairs({'additional_lsd_contract_verified','paired_application_order_verified','legacy_diff_disabled_verified'}) do yes(j[k]);out[k]=true end
            end
        end
        out.initial_energy_j=0;out.windup_nm_per_normalized=array(j.windup_nm_per_normalized,true)
        out.acceleration_bound_rad_s2=array(j.acceleration_bound_rad_s2,false);out.omega_error_rad_s=array(j.omega_error_rad_s,false)
        return out
    end)
    return ok and result or nil
end
return M
