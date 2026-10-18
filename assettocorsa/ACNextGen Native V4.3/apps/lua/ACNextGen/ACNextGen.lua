---@diagnostic disable: undefined-global
-- Native V4.3 revision 31: reject brake snapshots crossing an SDK frame.
local observer=require('modules.observer')
observer.init()
function update(dt) observer.update(dt) end
function windowMain() observer.drawUI() end
