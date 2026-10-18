-- Declaration validation only. Flags do not substitute for real calibration.
local M={}
local function number(v) assert(type(v)=='number' and v==v and math.abs(v)<math.huge);return v end
local function integer(v,max) number(v);assert(v>=1 and v<=max and v%1==0);return v end
local function array(v,count,lo,hi,nonzero)
    assert(type(v)=='table');local n=0;local out={}
    for k in pairs(v) do assert(type(k)=='number' and k>=1 and k<=count and k%1==0);n=n+1 end;assert(n==count)
    for i=1,count do local x=number(v[i]);assert(x>=lo and x<=hi and (not nonzero or x~=0));out[i]=x end
    return out
end
function M.parse(j,carID,patch)
    local ok,out=pcall(function()
        assert(type(j)=='table' and integer(j.schema,1)==1 and j.enabled==true and j.execution_mode=='worker_local_four_wheel_v1' and j.torque_argument_contract=='constant_raw_per_nm')
        assert(type(carID)=='string' and #carID>=1 and #carID<=200 and carID:match('^[a-zA-Z0-9_-]+$') and j.car_id==carID)
        assert(type(j.evidence_reference)=='string' and #j.evidence_reference>=1 and #j.evidence_reference<=500)
        local a,b=1,0;for i=1,#carID do a=(a+carID:byte(i))%65521;b=(b+a)%65521 end
        assert(integer(j.car_hash,4294967295)==b*65536+a and integer(j.patch_code,2147483646)==patch)
        local p={execution_mode=j.execution_mode,evidence_reference=j.evidence_reference,car_hash=j.car_hash,patch_code=patch,evidence_id=integer(j.evidence_id,9007199254740991)}
        for _,key in ipairs({'units_verified','baseline_isolated','single_four_wheel_owner_verified','legacy_brake_disabled_verified','legacy_drive_disabled_verified','coordinator_work_accounting_verified',
            'phase_verified','native_baseline_interval_verified','native_fade_double_counting_excluded','rwd_verified','paired_application_order_verified','bounds_verified','constant_torque_verified',
            'torque_error_verified','action_interval_verified','sample_units_verified','additional_windup_contract_verified','same_callback_sample_verified','additional_lsd_contract_verified','legacy_diff_disabled_verified','brake_fade_contract_verified'}) do
            assert(j[key]==true,key);p[key]=true
        end
        p.dt=number(j.dt);assert(p.dt>0 and p.dt<=.003)
        p.baseline_mode=integer(j.baseline_mode,2)
        p.baseline_scale_nm_per_raw=number(j.baseline_scale_nm_per_raw);assert(p.baseline_scale_nm_per_raw>0 and p.baseline_scale_nm_per_raw<=1000)
        p.command_scale_raw_per_nm=number(j.command_scale_raw_per_nm);assert(p.command_scale_raw_per_nm~=0 and math.abs(p.command_scale_raw_per_nm)<=1000)
        p.max_api_argument=number(j.max_api_argument);assert(p.max_api_argument>0 and p.max_api_argument<=20000)
        p.max_rear_additional_nm=number(j.max_rear_additional_nm);assert(p.max_rear_additional_nm>0 and p.max_rear_additional_nm<=12)
        p.lsd_nm_per_hint=number(j.lsd_nm_per_hint);assert(p.lsd_nm_per_hint>=0 and p.lsd_nm_per_hint<=12)
        p.windup_nm_per_normalized=array(j.windup_nm_per_normalized,2,-1000,1000,true)
        p.acceleration_bound_rad_s2=array(j.acceleration_bound_rad_s2,4,0,1e300)
        p.omega_error_rad_s=array(j.omega_error_rad_s,4,0,1e300)
        p.total_torque_error_nm=array(j.total_torque_error_nm,4,0,20000)
        p.initial_energy_j=number(j.initial_energy_j);assert(p.initial_energy_j==0)
        p.storage_capacity_j=j.storage_capacity_j==nil and 0 or number(j.storage_capacity_j);assert(p.storage_capacity_j>=0 and p.storage_capacity_j<=1)
        p.recovery_contract_verified=j.recovery_contract_verified==true;p.windup_scale_verified=j.windup_scale_verified==true
        assert((p.storage_capacity_j==0 or p.recovery_contract_verified) and (not p.recovery_contract_verified or p.windup_scale_verified))
        return p
    end)
    return ok and out or nil
end
return M
