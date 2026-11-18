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
        local _, unhitchId = self:addActionEvent(InputAction.WINCH_UNHITCH, self, HandToolWinchTow.onUnhitch, false, true, false, true, nil)
        spec.unhitchEventId = unhitchId
        g_inputBinding:setActionEventTextPriority(unhitchId, GS_PRIO_HIGH)
        g_inputBinding:setActionEventText(unhitchId, g_i18n:getText("action_winchUnhitch"))
        g_inputBinding:setActionEventActive(unhitchId, self:getIsHeld())
        -- Q, the game's attach/detach key, unhitches too (people are used to it): the same as U
        local _, qId = self:addActionEvent(InputAction.ATTACH, self, HandToolWinchTow.onUnhitch, false, true, false, true, nil)
        spec.unhitchQEventId = qId
        if qId ~= nil and qId ~= "" then
            g_inputBinding:setActionEventTextPriority(qId, GS_PRIO_HIGH)
            g_inputBinding:setActionEventText(qId, g_i18n:getText("action_winchUnhitch"))
            g_inputBinding:setActionEventActive(qId, self:getIsHeld())
        end
        -- the winch's own pair of keys (K pulls in, M lets out) reels in the wires laid between bridge pieces (WinchWire); only shown while there are wires
        -- registered inactive: the hand tool passes "disable conflicting bindings" and an active registration lets any K collision unbind the action
        local reelOk, reelId, reelOther = self:addActionEvent(InputAction.WINCH_CONTROL, self, HandToolWinchTow.onReel, false, true, true, false, nil)
        local reelAction = g_inputBinding.nameActions ~= nil and g_inputBinding.nameActions[InputAction.WINCH_CONTROL] or nil
        Logging.info("[WinchTow] reel key (WINCH_CONTROL) registered: %s, event %s, active bindings %s", tostring(reelOk), tostring(reelId), reelAction ~= nil and tostring(reelAction:getNumActiveBindings()) or "?")
        if not reelOk or reelId == nil or reelId == "" then
            return
        end
        spec.reelEventId = reelId
        g_inputBinding:setActionEventTextPriority(reelId, GS_PRIO_HIGH)
        g_inputBinding:setActionEventText(reelId, g_i18n:getText("action_winchReel"))
        g_inputBinding:setActionEventActive(reelId, false)
        if WinchWire ~= nil then
            WinchWire.reelEventId, WinchWire.reelEventOn = reelId, false
        end
    end
end

function HandToolWinchTow:onHeldStart()
    local spec = self[HandToolWinchTow.SPEC_TABLE_NAME]
    if spec.actionEventId ~= nil then
        g_inputBinding:setActionEventActive(spec.actionEventId, true)
    end
    if spec.unhitchEventId ~= nil then
        g_inputBinding:setActionEventActive(spec.unhitchEventId, true)
    end
    if spec.unhitchQEventId ~= nil and spec.unhitchQEventId ~= "" then
        g_inputBinding:setActionEventActive(spec.unhitchQEventId, true)
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
    if spec.unhitchEventId ~= nil then
        g_inputBinding:setActionEventActive(spec.unhitchEventId, false)
    end
    if spec.unhitchQEventId ~= nil and spec.unhitchQEventId ~= "" then
        g_inputBinding:setActionEventActive(spec.unhitchQEventId, false)
    end
    if WinchWire ~= nil then
        WinchWire.setReelInput(0)
        WinchWire.release()
    end
    if WinchHand ~= nil then
        WinchHand.putAway(self.rootNode)
    end
end

function HandToolWinchTow:onAction(_, inputValue)
    if WinchHand == nil then
        return
    end
    if inputValue > 0.5 then
        if WinchWire ~= nil and WinchWire.wantsPress(WinchHand.target ~= nil) then
            WinchWire.press()                                    -- wires laid, nothing hooked: held = reel, let go early = the click
        else
            WinchHand.notify(WinchHand.toggle())
        end
    elseif WinchWire ~= nil and WinchWire.pressMs ~= nil then
        if not WinchWire.release() then
            WinchHand.notify(WinchHand.toggle())
        end
    end
end

function HandToolWinchTow:onReel(_, inputValue)
    if WinchWire ~= nil then
        WinchWire.setReelInput(inputValue)
    end
end

function HandToolWinchTow:onUnhitch(_, inputValue)
    if inputValue > 0.5 and WinchHand ~= nil then
        WinchHand.notify(WinchHand.unhitchAll())
    end
end
