local WheelIntervalWire={}
local BODY=[[
uint32_t abi,epoch,sequence,generation,car_hash,flags,patch_code,reserved;
double dt,clock_before,clock_after;
double origin_before[3],origin_after[3],up_before[3],up_after[3];
double positions_before[4][3],positions_after[4][3],body_velocity_before[4][3],body_velocity_after[4][3];
]]
local function barrier() if ac.memoryBarrier then ac.memoryBarrier() end end
local function checksum(bytes) local a,b=1,0;for i=1,#bytes do a=(a+string.byte(bytes,i))%65521;b=(b+a)%65521 end;return b*65536+a end
local MATERIAL=[[
uint32_t abi,epoch,sequence,generation,car_hash,flags,patch_code,reserved;
double dt,clock_before,clock_after;
double body_before[4][3],body_after[4][3],wheel_before[4][3],wheel_after[4][3];
]]
local GEOMETRY=[[
uint32_t abi,epoch,sequence,generation,car_hash,flags,patch_code,reserved;
double clock,body_origin[3],body_axes[3][3],wheel_origin[4][3],wheel_axes[4][3][3];
]]
function WheelIntervalWire.new(options,carHash)
    local factory=assert(ac.StructItem.build or ac.StructItem.combine)
    local s={observer=WheelIntervalObserver.new(options,carHash),packet=factory(BODY),sequence=0}
    s.output=ac.writeMemoryMappedFile((options.mapping_prefix or 'AcTools.CSP.Limited.ACNextGen.V4')..'.WheelIntervalSensor',
        'uint32_t commit,checksum;struct {'..BODY..'} packet;',false)
    s.materialPacket=factory(MATERIAL)
    s.materialOutput=ac.writeMemoryMappedFile((options.mapping_prefix or 'AcTools.CSP.Limited.ACNextGen.V4')..'.WheelMaterialSensor',
        'uint32_t commit,checksum;struct {'..MATERIAL..'} packet;',false)
    s.geometryPacket=factory(GEOMETRY)
    s.geometryOutput=ac.writeMemoryMappedFile((options.mapping_prefix or 'AcTools.CSP.Limited.ACNextGen.V4')..'.WheelGeometrySensor',
        'uint32_t commit,checksum;struct {'..GEOMETRY..'} packet;',false)
    function s:disable() self.observer:reset();self.output.commit=0;self.materialOutput.commit=0;self.geometryOutput.commit=0 end
    function s:step(dt,clock,flags,generation)
        local pair=self.observer:sample(clock,dt,flags,generation)
        local ok,patch=pcall(function() return tonumber(ac.getPatchVersionCode()) end)
        if not pair or not ok or not patch or patch~=patch or patch<1 or patch>=2147483647 or patch%1~=0 or self.sequence>=1073741822 then self.output.commit=0;self.materialOutput.commit=0;self.geometryOutput.commit=0;return end
        self.sequence=self.sequence+1;local p=self.packet
        p.abi=1;p.epoch=pair.epoch;p.sequence=self.sequence;p.generation=generation;p.car_hash=carHash;p.flags=15;p.patch_code=patch;p.reserved=0
        p.dt=pair.dt;p.clock_before=pair.before.clock;p.clock_after=pair.after.clock
        for _,item in ipairs({{'before',pair.before},{'after',pair.after}}) do
            local suffix,snapshot=item[1],item[2]
            for j=0,2 do p['origin_'..suffix][j]=snapshot.origin[j+1];p['up_'..suffix][j]=snapshot.up[j+1] end
            for i=0,3 do for j=0,2 do
                p['positions_'..suffix][i][j]=snapshot.positions[i][j+1]
                p['body_velocity_'..suffix][i][j]=snapshot.body_velocity[i][j+1]
            end end
        end
        local raw=ac.structBytes(p);assert(#raw==536,'Wheel interval ABI mismatch')
        self.output.commit=self.sequence*2-1;barrier();ac.fillStructWithBytes(self.output.packet,raw)
        self.output.checksum=checksum(raw);barrier();self.output.commit=self.sequence*2
        local m=self.materialPacket
        for _,name in ipairs({'abi','epoch','sequence','generation','car_hash','flags','patch_code','reserved','dt','clock_before','clock_after'}) do m[name]=p[name] end
        for _,name in ipairs({'body_before','body_after','wheel_before','wheel_after'}) do
            for i=0,3 do for j=0,2 do m[name][i][j]=pair.material_points[name][i][j+1] end end
        end
        local materialRaw=ac.structBytes(m);assert(#materialRaw==440,'Wheel material ABI mismatch')
        self.materialOutput.commit=self.sequence*2-1;barrier();ac.fillStructWithBytes(self.materialOutput.packet,materialRaw)
        self.materialOutput.checksum=checksum(materialRaw);barrier();self.materialOutput.commit=self.sequence*2
        local g=self.geometryPacket
        for _,name in ipairs({'abi','epoch','sequence','generation','car_hash','flags','patch_code','reserved'}) do g[name]=p[name] end
        g.clock=pair.after.clock
        for j=0,2 do
            g.body_origin[j]=pair.after.origin[j+1]
            for a=0,2 do g.body_axes[a][j]=pair.after.axes[a+1][j+1] end
            for i=0,3 do
                g.wheel_origin[i][j]=pair.after.positions[i][j+1]
                for a=0,2 do g.wheel_axes[i][a][j]=pair.after.wheel_axes[i][a+1][j+1] end
            end
        end
        local geometryRaw=ac.structBytes(g);assert(#geometryRaw==520,'Wheel geometry ABI mismatch')
        self.geometryOutput.commit=self.sequence*2-1;barrier();ac.fillStructWithBytes(self.geometryOutput.packet,geometryRaw)
        self.geometryOutput.checksum=checksum(geometryRaw);barrier();self.geometryOutput.commit=self.sequence*2
    end
    return s
end
