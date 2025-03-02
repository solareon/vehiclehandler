local Progress = lib.load('data.progress')
local Settings = lib.load('data.vehicle')

local BONES <const> = {
    [0] =   'wheel_lf',
            'wheel_rf',
            'wheel_lm',
            'wheel_rm',
            'wheel_lr',
            'wheel_rr'
}

---@class Handler : OxClass
---@field private private { active: boolean, limited: boolean, oxfuel: boolean }
local Handler = lib.class('vehiclehandler')

function Handler:constructor()
    self:setActive(false)
    self:setLimited(false)
end

function Handler:isActive() return self.private.active end

function Handler:isLimited() return self.private.limited end

function Handler:isFuelOx() return self.private.oxfuel end

function Handler:isValid()
    if not cache.ped then return false end
    if cache.vehicle or IsPedInAnyPlane(cache.ped) then return true end

    return false
end

function Handler:isWheelBroken(vehicle, coords)
    if not vehicle or not coords then return false end
    
    for k,v in pairs(BONES) do
        local bone = GetEntityBoneIndexByName(vehicle, v)

        if bone ~= -1 then
            if IsVehicleTyreBurst(vehicle, k, true) then
                local pos = GetWorldPositionOfEntityBone(vehicle, bone)

                if #(coords - pos) < 2.5 then
                    return true
                end
            end
        end
    end

    return false
end

function Handler:getEngineData(vehicle)
    if not vehicle or vehicle == 0 then return end
    
    local backengine = Settings.backengine[GetEntityModel(vehicle)]
    local distance = backengine and -2.5 or 2.5
    local offset = GetOffsetFromEntityInWorldCoords(vehicle, 0, distance, 0)
    local index = backengine and 5 or 4
    local health = GetVehicleEngineHealth(vehicle)

    return backengine, offset, index, health
end

function Handler:setActive(state)
    if state ~= nil and type(state) == 'boolean' then
        self.private.active = state
    end
end

function Handler:setLimited(state)
    if state ~= nil and type(state) == 'boolean' then
        self.private.limited = state
    end
end

function Handler:breakTire(vehicle, index)
    if vehicle == nil or type(vehicle) ~= 'number' then return end
    if index == nil or type(index) ~= 'number' then return end

    local bone = GetEntityBoneIndexByName(vehicle, BONES[index])

    if bone ~= -1 then
        if not IsVehicleTyreBurst(vehicle, index, true) then

            lib.callback('vehiclehandler:sync', -1, function()
                SetVehicleTyreBurst(vehicle, index, true, 1000.0)
                BreakOffVehicleWheel(vehicle, index, true, true, true, false)
            end)
        end
    end
end

function Handler:adminfuel(newlevel)
    if not self:isValid() then return false end
    if not newlevel then return false end

    newlevel = tonumber(newlevel) + 0.0
    if newlevel < 0.0 then return false end
    if newlevel > 100.0 then newlevel = 100.0 end

    lib.callback('vehiclehandler:sync', -1, function()
        if self:isFuelOx() then
            Entity(cache.vehicle).state.fuel = newlevel
        else
            SetVehicleFuelLevel(cache.vehicle, newlevel)
            DecorSetFloat(cache.vehicle, '_FUEL_LEVEL', GetVehicleFuelLevel(cache.vehicle))
        end
    end)

    return true
end

function Handler:adminwash()
    if not self:isValid() then return false end

    lib.callback('vehiclehandler:sync', -1, function()
        SetVehicleDirtLevel(cache.vehicle, 0.0)
        WashDecalsFromVehicle(cache.vehicle, 1.0)
    end)

    return true
end

function Handler:adminfix()
    if not self:isValid() then return false end

    lib.callback('vehiclehandler:sync', -1, function()
        SetVehicleFixed(cache.vehicle)
        ResetVehicleWheels(cache.vehicle, true)

        if self:isFuelOx() then
            Entity(cache.vehicle).state.fuel = 100.0
        else
            SetVehicleFuelLevel(cache.vehicle, 100.0)
            DecorSetFloat(cache.vehicle, '_FUEL_LEVEL', GetVehicleFuelLevel(cache.vehicle))
        end
        
        SetVehicleUndriveable(cache.vehicle, false)
        SetVehicleEngineOn(cache.vehicle, true, true, true)
    end)

    return true
end

function Handler:basicwash()
    if not cache.ped then return false end

    local pos = GetEntityCoords(cache.ped)
    local vehicle,_ = lib.getClosestVehicle(pos, 3.0, false)
	if vehicle == nil or vehicle == 0 then return false end

    local vehpos = GetEntityCoords(vehicle)
    if #(pos - vehpos) > 3.0 or cache.vehicle then return false end

    local success = false
    LocalPlayer.state:set("inv_busy", true, true)
    TaskStartScenarioInPlace(cache.ped, "WORLD_HUMAN_MAID_CLEAN", 0, true)

    if lib.progressCircle(Progress['cleankit']) then
        success = true
        
        lib.callback('vehiclehandler:sync', -1, function()
            SetVehicleDirtLevel(vehicle, 0.0)
            WashDecalsFromVehicle(vehicle, 1.0)
        end)
    end

    ClearAllPedProps(cache.ped)
    ClearPedTasks(cache.ped)

    LocalPlayer.state:set("inv_busy", false, true)

    return success
end

function Handler:basicfix(fixtype)
    if not cache.ped then return false end
    if not fixtype or type(fixtype) ~= 'string' then return false end

    local coords = GetEntityCoords(cache.ped)
    local vehicle,_ = lib.getClosestVehicle(coords, 3.0, false)
	if vehicle == nil or vehicle == 0 then return false end

    if fixtype == 'tirekit' then
        local found = self:isWheelBroken(vehicle, coords)

        if found then
            local lastengine = GetVehicleEngineHealth(vehicle)
            local lastbody = GetVehicleBodyHealth(vehicle)
            local lasttank = GetVehiclePetrolTankHealth(vehicle)
            local lastdirt = GetVehicleDirtLevel(vehicle)
            local success = false

            LocalPlayer.state:set("inv_busy", true, true)

            if lib.progressCircle(Progress[fixtype]) then
                success = true

                lib.callback('vehiclehandler:sync', -1, function()
                    SetVehicleFixed(vehicle)
                    SetVehicleEngineHealth(vehicle, lastengine)
                    SetVehicleBodyHealth(vehicle, lastbody)
                    SetVehiclePetrolTankHealth(vehicle, lasttank)
                    SetVehicleDirtLevel(vehicle, lastdirt)
                end)
            end

            LocalPlayer.state:set("inv_busy", false, true)

            return success
        end
    elseif fixtype == 'smallkit' or fixtype == 'bigkit' then
        local backengine, offset, hoodindex, health = self:getEngineData(vehicle)

        if fixtype == 'smallkit' and health < 500 or fixtype == 'bigkit' and health < 1000 then
            if #(coords - offset) < 2.0 then
                local success = false

                LocalPlayer.state:set("inv_busy", true, true)

                if hoodindex then
                    SetVehicleDoorOpen(vehicle, hoodindex, false, false)
                end
    
                if lib.progressCircle(Progress[fixtype]) then
                    success = true

                    lib.callback('vehiclehandler:sync', -1, function()
                        if fixtype == 'smallkit' then
                            SetVehicleEngineHealth(vehicle, 500.0)
                        end

                        SetVehicleUndriveable(vehicle, false)
                    end)
                end
    
                if hoodindex then
                    SetVehicleDoorShut(vehicle, hoodindex, false)
                end
                
                LocalPlayer.state:set("inv_busy", false, true)
    
                if success and fixtype == 'bigkit' then
                    CreateThread(function()
                        Wait(1000)
                        SetVehicleFixed(vehicle)
                    end)
                end
    
                return success
            else
                if backengine then
                    lib.notify({
                        title = 'Engine bay is in back',
                        type = 'error'
                    })
                end
            end
        else
            lib.notify({
                title = 'Cannot repair vehicle any further',
                type = 'error'
            })
        end
    end

    return false
end

return Handler