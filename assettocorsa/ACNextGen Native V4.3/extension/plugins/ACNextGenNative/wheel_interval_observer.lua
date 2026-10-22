-- Read-only paired endpoints from consecutive physics callbacks. Not velocity truth.
local WheelIntervalObserver={}
local function finite(v) return type(v)=='number' and v==v and math.abs(v)<math.huge end
local function vector(v,limit)
    assert(v and finite(v.x) and finite(v.y) and finite(v.z))
    assert(math.abs(v.x)<=limit and math.abs(v.y)<=limit and math.abs(v.z)<=limit)
    return {v.x,v.y,v.z}
end
function WheelIntervalObserver.new(options,carHash)
    local s={previous=nil}
    function s:reset() self.previous=nil end
    function s:sample(clock,dt,flags,generation)
        if flags~=15 or not finite(clock) or clock<0 or not finite(dt) or dt<=0 or dt>.02 or
            not finite(generation) or generation<1 or generation>=2147483647 or generation%1~=0 then self:reset();return nil end
        local ok,current=pcall(function()
            local sim=ac.getSim()
            assert(sim and sim.isOnlineRace==false and sim.isPaused==false and sim.isReplayActive~=true and
                sim.isReplayOnlyMode~=true and sim.isSessionFinished~=true and ac.getCarID(0)==options.car_id)
            if physics.allowed~=nil then assert(physics.allowed()==true)
            else assert(ac.load and ac.load('ngp4_permission')==1 and ac.load('ngp4_epoch')==options.epoch and ac.load('ngp4_generation')==generation) end
            local body=physics.getBodyTransform(0,-1,false)
            local r={clock=clock,generation=generation,origin=vector(body.position,1e7),up=vector(body.up,1.01),positions={},body_velocity={},wheel_axes={},axes={vector(body.side,1.01),vector(body.up,1.01),vector(body.look,1.01)}}
            local norm=0;for _,v in ipairs(r.up) do norm=norm+v*v end;assert(math.abs(norm-1)<1e-4)
            for a=1,3 do for b=a,3 do
                local dot=0;for j=1,3 do dot=dot+r.axes[a][j]*r.axes[b][j] end
                assert(math.abs(dot-(a==b and 1 or 0))<1e-4)
            end end
            for i=0,3 do
                local transform=physics.getBodyTransform(0,i,false);local p=transform.position
                r.positions[i]=vector(p,1e7)
                local axes={vector(transform.side,1.01),vector(transform.up,1.01),vector(transform.look,1.01)}
                for a=1,3 do for b=a,3 do
                    local dot=0;for j=1,3 do dot=dot+axes[a][j]*axes[b][j] end;assert(math.abs(dot-(a==b and 1 or 0))<1e-4)
                end end;r.wheel_axes[i]=axes
                r.body_velocity[i]=vector(physics.getPointVelocity(0,p,false),300)
            end
            return r
        end)
        if not ok then self:reset();return nil end
        local before=self.previous;self.previous=current
        if not before or before.generation~=generation or before.clock>=clock or math.abs(clock-before.clock-dt)>1e-7 then return nil end
        -- Track the body material point coincident with each wheel centre at
        -- the start. Do not project a fresh point onto the body at the end.
        local material={body_before={},body_after={},wheel_before={},wheel_after={}}
        for i=0,3 do
            local localPoint={0,0,0}
            for a=1,3 do for j=1,3 do localPoint[a]=localPoint[a]+(before.positions[i][j]-before.origin[j])*before.axes[a][j] end end
            material.body_before[i]={};material.body_after[i]={};material.wheel_before[i]={};material.wheel_after[i]={}
            for j=1,3 do
                local finish=current.origin[j]
                for a=1,3 do finish=finish+localPoint[a]*current.axes[a][j] end
                material.body_before[i][j]=before.positions[i][j];material.body_after[i][j]=finish
                material.wheel_before[i][j]=before.positions[i][j];material.wheel_after[i][j]=current.positions[i][j]
            end
        end
        return {epoch=options.epoch,generation=generation,car_hash=carHash,dt=dt,before=before,after=current,material_points=material,
            wheel_velocity_verified=false,interval_work_verified=false}
    end
    return s
end
