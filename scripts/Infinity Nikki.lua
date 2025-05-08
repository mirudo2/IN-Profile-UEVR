(function()
    UEVR_UObjectHook.set_disabled(true)

    local api = uevr.api
    local m_VR = uevr.params.vr
    local rootComp_char = nil

    local rotator_c = api:find_uobject("ScriptStruct /Script/CoreUObject.Rotator")
    local vr_cam_r = StructObject.new(rotator_c)

    local kismet_math_library_c = api:find_uobject("Class /Script/Engine.KismetMathLibrary")
    local kismet_math_library = kismet_math_library_c:get_class_default_object()

    local View_Target = nil
    local View_Target_old = ""

    local zoom = 170
    local z_offset = 0

    local leftTrigger = false
    local rightTrigger = false
    local LEFT_THUMB = false
    local RIGHT_THUMB = false
    local LEFT_SHOULDER = false
    local RIGHT_SHOULDER = false
    local GAMEPAD_X = false
    local GAMEPAD_Y = false
    local GAMEPAD_A = false
    local GAMEPAD_B = false
    local Attached = false

    local x_SkyLight = nil
    local x_SkyLight_seted = false
    local x_pressed = 0
    local last_GAMEPAD_A = false

    uevr.sdk.callbacks.on_xinput_get_state(function(retval, user_index, state)
        local gamepad = state.Gamepad

        LEFT_THUMB = gamepad.wButtons & XINPUT_GAMEPAD_LEFT_THUMB ~= 0
        RIGHT_THUMB = gamepad.wButtons & XINPUT_GAMEPAD_RIGHT_THUMB ~= 0
        RIGHT_SHOULDER = gamepad.wButtons & XINPUT_GAMEPAD_RIGHT_SHOULDER ~= 0
        LEFT_SHOULDER = gamepad.wButtons & XINPUT_GAMEPAD_LEFT_SHOULDER ~= 0
        GAMEPAD_Y = gamepad.wButtons & XINPUT_GAMEPAD_Y ~= 0
        GAMEPAD_X = gamepad.wButtons & XINPUT_GAMEPAD_X ~= 0
        GAMEPAD_A = gamepad.wButtons & XINPUT_GAMEPAD_A ~= 0
        GAMEPAD_B = gamepad.wButtons & XINPUT_GAMEPAD_B ~= 0

        if LEFT_THUMB and RIGHT_THUMB then
            --state.Gamepad.wButtons = state.Gamepad.wButtons & ~XINPUT_GAMEPAD_LEFT_THUMB
            --state.Gamepad.wButtons = state.Gamepad.wButtons & ~XINPUT_GAMEPAD_RIGHT_THUMB
        end

        if LEFT_THUMB and GAMEPAD_X then
            state.Gamepad.wButtons = state.Gamepad.wButtons & ~XINPUT_GAMEPAD_X
        end

        if LEFT_THUMB and GAMEPAD_Y then
            state.Gamepad.wButtons = state.Gamepad.wButtons & ~XINPUT_GAMEPAD_Y
        end

        if LEFT_THUMB then
            if RIGHT_SHOULDER then
                state.Gamepad.wButtons = state.Gamepad.wButtons & ~XINPUT_GAMEPAD_RIGHT_SHOULDER
                if x_pressed == 0 then
                    Attached = not Attached
                end
                x_pressed = 1

            elseif LEFT_SHOULDER then
                state.Gamepad.wButtons = state.Gamepad.wButtons & ~XINPUT_GAMEPAD_LEFT_SHOULDER
                if x_pressed == 0 then
                    x_SkyLight = api:find_uobject(
                        "SkyLight /Game/Maps/World/DynamicEnviroment/World_TimeofDay.World_TimeofDay.PersistentLevel.TOD_SkyLight"
                    )
                    if x_SkyLight then
                        if x_SkyLight_seted then
                            x_SkyLight.LightComponent:SetVisibility(true, true)
                            x_SkyLight_seted = false
                        else
                            x_SkyLight.LightComponent:SetVisibility(false, true)
                            x_SkyLight_seted = true
                        end
                    end
                end
                x_pressed = 1

            else
                x_pressed = 0
            end
        else
            x_pressed = 0
        end

        leftTrigger = gamepad.bLeftTrigger ~= 0
        rightTrigger = gamepad.bRightTrigger ~= 0
		
        if rightTrigger then
            local max_speed = 16000
            local thumb_x = gamepad.sThumbLX
            local thumb_y = gamepad.sThumbLY
            local magnitude = math.sqrt(thumb_x ^ 2 + thumb_y ^ 2)
            if magnitude > max_speed then
                local ratio = max_speed / magnitude
                thumb_x = thumb_x * ratio
                thumb_y = thumb_y * ratio
            end
            gamepad.sThumbLX = thumb_x
            gamepad.sThumbLY = thumb_y
        end

        if LEFT_THUMB and rightTrigger then
            zoom = zoom + 3
        end
        if LEFT_THUMB and leftTrigger then
            zoom = zoom - 3
        end
        if LEFT_THUMB and GAMEPAD_X then
            z_offset = z_offset - 2
        end
        if LEFT_THUMB and GAMEPAD_Y then
            z_offset = z_offset + 2
        end

        if LEFT_THUMB and GAMEPAD_A then
            state.Gamepad.wButtons = state.Gamepad.wButtons & ~XINPUT_GAMEPAD_A
            if not last_GAMEPAD_A then
                m_VR.recenter_view()
                m_VR.recenter_horizon()
            end
        end

        if LEFT_THUMB and leftTrigger then
            gamepad.bLeftTrigger = 0
        end

        last_GAMEPAD_A = GAMEPAD_A
    end)

    local rootComp = nil
    local C_Pawn = nil
    local is_Synced = true
    --m_VR.set_mod_value("VR_RenderingMethod", 1)
    --m_VR.set_mod_value("VR_AimMethod", 0)
    --m_VR.set_mod_value("VR_DesktopRecordingFix_V2", "true")
    --m_VR.set_mod_value("VR_DecoupledPitch", "false")
    --m_VR.set_mod_value("VR_DecoupledPitchUIAdjust", "true")
    --m_VR.set_mod_value("FrameworkConfig_AlwaysShowCursor", "false")
    --m_VR.set_mod_value("VR_2DScreenMode", "false")
    --m_VR.recenter_view()
    --m_VR.recenter_horizon()

    local stereoX, stereoY, stereoZ = nil, nil, nil
    local is_not_base = false
    local last_Z = nil
    local smoothZ = nil

    uevr.sdk.callbacks.on_early_calculate_stereo_view_offset(
        function(device, view_index, world_to_meters, position, rotation, is_double)
            if rootComp_char and Attached then
                vr_cam_r.Pitch = rotation.x
                vr_cam_r.Yaw = rotation.y
                vr_cam_r.Roll = rotation.z

                local cam_target = rootComp_char:GetSocketLocation("Neck_M")
                local forward_vector = kismet_math_library:Conv_RotatorToVector(vr_cam_r)
                local position_in_front_of_camera = cam_target - forward_vector * zoom

                stereoX = position_in_front_of_camera.X
                stereoY = position_in_front_of_camera.Y
                stereoZ = position_in_front_of_camera.Z

                if smoothZ then
                    position.x = stereoX
                    position.y = stereoY
                    if not is_not_base and last_Z then
                        if math.abs(last_Z - cam_target.Z) > 300
                           or C_Pawn.CharacterMovement.MaxWalkSpeed == 390
                           or leftTrigger then
                            position.z = position_in_front_of_camera.Z
                        else
                            position.z = smoothZ
                        end
                    else
                        position.z = smoothZ
                        last_Z = cam_target.Z
                    end
                end
            end
        end
    )

    local vector_c = api:find_uobject("ScriptStruct /Script/CoreUObject.Vector")
    local fhitresult = api:find_uobject("ScriptStruct /Script/Engine.HitResult")

    local new_pos = StructObject.new(vector_c)
    local new_dash_pos = StructObject.new(vector_c)
    local hit_result = StructObject.new(fhitresult)

    local stereoZ_old = nil

    local fpsCounter = { frames = 0, elapsed = 0.0, currentFPS = 0 }

    local function updateFPS(delta)
        fpsCounter.frames = fpsCounter.frames + 1
        fpsCounter.elapsed = fpsCounter.elapsed + delta
        if fpsCounter.elapsed >= 1.0 then
            fpsCounter.currentFPS = fpsCounter.frames
            fpsCounter.frames = 0
            fpsCounter.elapsed = fpsCounter.elapsed - 1.0
        end
        return fpsCounter.currentFPS
    end

    local function getNormalizedSpeed(baseSpeed, targetFPS)
        local fps = fpsCounter.currentFPS > 0 and fpsCounter.currentFPS or targetFPS
        if baseSpeed * (targetFPS / fps) < 0.5 then return 0.5 end
        return baseSpeed * (targetFPS / fps)
    end

    local fps = 0
    uevr.sdk.callbacks.on_pre_engine_tick(function(engine, delta)
        fps = updateFPS(delta)

        local lplayer = api:get_player_controller(0)

        View_Target = lplayer:GetViewTarget()
        if View_Target:get_full_name() ~= View_Target_old then
            print("View_Target: " .. View_Target:get_full_name())
            View_Target_old = View_Target:get_full_name()
        end

        View_Target = View_Target:get_fname():to_string()
        if is_Synced then
            if string.find(View_Target, "Cine") or string.find(View_Target, "Photo") then
                is_Synced = false
                --m_VR.set_mod_value("VR_RenderingMethod", 2)
            end
        end

        View_Target = string.sub(View_Target, 0, 16)
        if View_Target == "NikkiPlayer_BP_C" or View_Target == "BP_BikeWithVehic" then
            if not is_Synced then
                is_Synced = true
                --m_VR.set_mod_value("VR_RenderingMethod", 1)
            end

            if not rootComp then
                rootComp = lplayer.ControlPawn.RootComponent
                C_Pawn = lplayer.ControlPawn
            end
            if not rootComp_char then
                for i, c_Obj in ipairs(rootComp.AttachChildren) do
                    local objName = c_Obj:get_fname():to_string()
                    if string.sub(objName, 0, 13) == "CharacterMesh" then
                        rootComp_char = c_Obj
                        break
                    end
                end
            end

            if rootComp_char and lplayer.PlayerCameraManager.bDissolveEnable then
                lplayer.PlayerCameraManager.bDissolveEnable = false
            end

            if rootComp_char and Attached and stereoZ then
                local smooth_factor = 0.7
                if not stereoZ_old then
                    stereoZ_old = stereoZ
                else
                    smoothZ = stereoZ_old + (stereoZ - stereoZ_old) * smooth_factor
                    smoothZ = smoothZ + z_offset
                    stereoZ_old = smoothZ
                end
            end

        else
            rootComp_char = nil
            rootComp = nil
            C_Pawn = nil
            stereoX, stereoY, stereoZ = nil, nil, nil
            stereoZ_old = nil
            smoothZ = nil
        end

        if View_Target == "NikkiPlayer_BP_C" and rootComp and C_Pawn then
            local RootCompPos = rootComp:K2_GetComponentLocation()
            local RootComp_r = rootComp:K2_GetComponentRotation()
            local is_not_base = C_Pawn.CharacterMovement.bCrouchMaintainsBaseLocation

            local nSpeed = getNormalizedSpeed(16, 60)
            if leftTrigger and not is_not_base then
                new_pos.X, new_pos.Y, new_pos.Z = RootCompPos.X, RootCompPos.Y, RootCompPos.Z + nSpeed
                rootComp:K2_SetRelativeLocation(new_pos, 0, hit_result, 0)
            end
            if RIGHT_SHOULDER and not is_not_base then
                nSpeed = getNormalizedSpeed(8, 60)
                local d_forward_vector = kismet_math_library:Conv_RotatorToVector(RootComp_r)
                local d_position_in_front_of_camera = RootCompPos + d_forward_vector * nSpeed
                new_dash_pos.X, new_dash_pos.Y, new_dash_pos.Z = d_position_in_front_of_camera.X, d_position_in_front_of_camera.Y, d_position_in_front_of_camera.Z
                if leftTrigger then new_dash_pos.Z = d_position_in_front_of_camera.Z + nSpeed end
                rootComp:K2_SetRelativeLocation(new_dash_pos, 0, hit_result, 0)
            end
        end
    end)

end)()
