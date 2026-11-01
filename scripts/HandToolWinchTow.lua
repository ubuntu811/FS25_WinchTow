--[[
    HandToolWinchTow.lua -- the hand winch: held in the hand, the primary action hooks onto the attacher joint of the vehicle you look at, or lets it go again. What the hooked vehicle does is WinchHand's.
]]
HandToolWinchTow = {}
HandToolWinchTow.SPEC_TABLE_NAME = "spec_" .. g_currentModName .. ".winchTowHand"

function HandToolWinchTow.prerequisitesPresent(_)
    return true
end

function HandToolWinchTow.registerEventListeners(handToolType)
    SpecializationUtil.registerEventListener(handToolType, "onLoad", HandToolWinchTow)
    SpecializationUtil.registerEventListener(handToolType, "onRegisterActionEvents", HandToolWinchTow)
    SpecializationUtil.registerEventListener(handToolType, "onHeldStart", HandToolWinchTow)
    SpecializationUtil.registerEventListener(handToolType, "onHeldEnd", HandToolWinchTow)
end

function HandToolWinchTow:onLoad(_)
    self[HandToolWinchTow.SPEC_TABLE_NAME] = { actionEventId = nil }
end

function HandToolWinchTow:onRegisterActionEvents()
    local spec = self[HandToolWinchTow.SPEC_TABLE_NAME]
    if self:getIsActiveForInput(true) then
        local _, actionEventId = self:addActionEvent(InputAction.ACTIVATE_HANDTOOL, self, HandToolWinchTow.onAction, true, true, false, true, nil)
        spec.actionEventId = actionEventId
        g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_HIGH)
        g_inputBinding:setActionEventText(actionEventId, g_i18n:getText("action_winchTowHand"))
        g_inputBinding:setActionEventActive(actionEventId, self:getIsHeld())
    end
end

function HandToolWinchTow:onHeldStart()
    local spec = self[HandToolWinchTow.SPEC_TABLE_NAME]
    if spec.actionEventId ~= nil then
        g_inputBinding:setActionEventActive(spec.actionEventId, true)
    end
    if WinchHand ~= nil then
        WinchHand.hold(self.rootNode)
    end
end

function HandToolWinchTow:onHeldEnd()
    local spec = self[HandToolWinchTow.SPEC_TABLE_NAME]
    if spec.actionEventId ~= nil then
        g_inputBinding:setActionEventActive(spec.actionEventId, false)
    end
    if WinchHand ~= nil then
        WinchHand.putAway(self.rootNode)
    end
end

function HandToolWinchTow:onAction(_, inputValue)
    if inputValue > 0.5 and WinchHand ~= nil then
        WinchHand.notify(WinchHand.toggle())
    end
end
