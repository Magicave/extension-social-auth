local M = {
    _VERSION = "1.0",
    _DESCRIPTION = "Lua adapter for native Firebase Auth",
    _AUTHOR = "Codex",
    _LICENSE = "Copyright Magicave.io 2026"
}

local async_dispatch = require("socialauth.async_dispatch")

local configured = false
local last_error = nil
local debug_state = {
    sign_in_request_count = 0,
    refresh_request_count = 0,
    callback_count = 0,
    success_count = 0,
    error_count = 0,
    in_flight = false,
    active_request = nil,
    last_request_started_at = 0,
    last_callback_at = 0,
    last_callback_ok = nil,
    last_result_uid = nil,
    last_result_expires_in = nil
}

local function native_api()
    return firebaseauth
end

local function get_system_name()
    if sys ~= nil and sys.get_sys_info ~= nil then
        local info = sys.get_sys_info()
        if type(info) == "table" and type(info.system_name) == "string" then
            return info.system_name
        end
    end
    return nil
end

local function trim(value)
    if value == nil then
        return nil
    end
    if type(value) ~= "string" then
        value = tostring(value)
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function error_payload(code, message)
    return {
        status = 0,
        code = code,
        message = message or code
    }
end

local function dispatch_callback(callback, ...)
    if callback == nil then
        return
    end
    async_dispatch.enqueue(callback, ...)
end

function M.is_supported()
    local native = native_api()
    return native ~= nil and native.is_supported ~= nil and native.is_supported() == true
end

function M.configure(config)
    if configured == true then
        return true
    end
    if M.is_supported() ~= true then
        last_error = error_payload("native_firebase_auth_unavailable", "Native Firebase Auth is unavailable")
        return false, last_error
    end
    local cfg = type(config) == "table" and config or {}
    local system_name = get_system_name()
    local app_id = nil
    local missing_app_id_code = "missing_firebase_android_app_id"
    local missing_app_id_message = "Missing Firebase Android app ID"
    local api_key = trim(cfg.api_key)
    local project_id = trim(cfg.project_id)
    if system_name == "iPhone OS" then
        app_id = trim(cfg.firebase_ios_app_id or cfg.apple_app_id or cfg.app_id or cfg.firebase_android_app_id or cfg.google_app_id)
        missing_app_id_code = "missing_firebase_ios_app_id"
        missing_app_id_message = "Missing Firebase iOS app ID"
    else
        app_id = trim(cfg.firebase_android_app_id or cfg.google_app_id or cfg.app_id or cfg.firebase_ios_app_id or cfg.apple_app_id)
    end
    if app_id == nil or app_id == "" then
        last_error = error_payload(missing_app_id_code, missing_app_id_message)
        return false, last_error
    end
    if api_key == nil or api_key == "" then
        last_error = error_payload("missing_api_key", "Missing Firebase API key")
        return false, last_error
    end
    local ok = native_api().configure({
        app_id = app_id,
        api_key = api_key,
        project_id = project_id or ""
    })
    configured = ok == true
    if configured ~= true then
        last_error = error_payload("native_firebase_configure_failed", "Native Firebase Auth configure failed")
        return false, last_error
    end
    last_error = nil
    return true
end

function M.sign_in_with_game_center(config, callback)
    local ok, err = M.configure(config)
    if ok ~= true then
        if callback ~= nil then
            callback(false, err)
        end
        return
    end
    local native = native_api()
    if native == nil or native.sign_in_game_center == nil then
        if callback ~= nil then
            callback(false, error_payload("game_center_sign_in_unavailable", "Native Game Center sign-in is unavailable"))
        end
        return
    end
    debug_state.sign_in_request_count = (tonumber(debug_state.sign_in_request_count) or 0) + 1
    debug_state.in_flight = true
    debug_state.active_request = "sign_in_game_center"
    debug_state.last_request_started_at = os.time()
    print("[firebase_auth_native] sign_in_with_game_center request")
    native.sign_in_game_center(function(_, result, native_error)
        debug_state.callback_count = (tonumber(debug_state.callback_count) or 0) + 1
        debug_state.last_callback_at = os.time()
        debug_state.in_flight = false
        debug_state.active_request = nil
        if native_error ~= nil then
            debug_state.error_count = (tonumber(debug_state.error_count) or 0) + 1
            debug_state.last_callback_ok = false
            debug_state.last_result_uid = nil
            debug_state.last_result_expires_in = nil
            last_error = native_error
            print(string.format("[firebase_auth_native] sign_in_with_game_center error: %s", tostring(native_error.code or native_error.message or native_error)))
            dispatch_callback(callback, false, native_error)
            return
        end
        debug_state.success_count = (tonumber(debug_state.success_count) or 0) + 1
        debug_state.last_callback_ok = true
        debug_state.last_result_uid = type(result) == "table" and tostring(result.player_id or result.team_player_id or result.game_player_id or "") or nil
        debug_state.last_result_expires_in = nil
        last_error = nil
        print(string.format("[firebase_auth_native] sign_in_with_game_center success uid=%s", tostring(debug_state.last_result_uid or "")))
        dispatch_callback(callback, true, result)
    end)
end

function M.sign_in_with_play_games_code(server_auth_code, config, callback)
    local ok, err = M.configure(config)
    if ok ~= true then
        if callback ~= nil then
            callback(false, err)
        end
        return
    end
    if server_auth_code == nil or server_auth_code == "" then
        if callback ~= nil then
            callback(false, error_payload("missing_server_auth_code", "Missing Play Games server auth code"))
        end
        return
    end
    debug_state.sign_in_request_count = (tonumber(debug_state.sign_in_request_count) or 0) + 1
    debug_state.in_flight = true
    debug_state.active_request = "sign_in_play_games"
    debug_state.last_request_started_at = os.time()
    native_api().sign_in_play_games(tostring(server_auth_code), function(_, result, native_error)
        debug_state.callback_count = (tonumber(debug_state.callback_count) or 0) + 1
        debug_state.last_callback_at = os.time()
        debug_state.in_flight = false
        debug_state.active_request = nil
        if native_error ~= nil then
            debug_state.error_count = (tonumber(debug_state.error_count) or 0) + 1
            debug_state.last_callback_ok = false
            debug_state.last_result_uid = nil
            debug_state.last_result_expires_in = nil
            last_error = native_error
            dispatch_callback(callback, false, native_error)
            return
        end
        debug_state.success_count = (tonumber(debug_state.success_count) or 0) + 1
        debug_state.last_callback_ok = true
        debug_state.last_result_uid = type(result) == "table" and tostring(result.uid or result.localId or result.local_id or "") or nil
        debug_state.last_result_expires_in = type(result) == "table" and tonumber(result.expiresIn or result.expires_in) or nil
        last_error = nil
        dispatch_callback(callback, true, result)
    end)
end

function M.refresh_id_token(config, force_refresh, callback)
    local ok, err = M.configure(config)
    if ok ~= true then
        if callback ~= nil then
            callback(false, err)
        end
        return
    end
    debug_state.refresh_request_count = (tonumber(debug_state.refresh_request_count) or 0) + 1
    debug_state.in_flight = true
    debug_state.active_request = force_refresh == true and "refresh_id_token_forced" or "refresh_id_token"
    debug_state.last_request_started_at = os.time()
    native_api().refresh_id_token(force_refresh == true, function(_, result, native_error)
        debug_state.callback_count = (tonumber(debug_state.callback_count) or 0) + 1
        debug_state.last_callback_at = os.time()
        debug_state.in_flight = false
        debug_state.active_request = nil
        if native_error ~= nil then
            debug_state.error_count = (tonumber(debug_state.error_count) or 0) + 1
            debug_state.last_callback_ok = false
            debug_state.last_result_uid = nil
            debug_state.last_result_expires_in = nil
            last_error = native_error
            dispatch_callback(callback, false, native_error)
            return
        end
        debug_state.success_count = (tonumber(debug_state.success_count) or 0) + 1
        debug_state.last_callback_ok = true
        debug_state.last_result_uid = type(result) == "table" and tostring(result.uid or result.localId or result.local_id or "") or nil
        debug_state.last_result_expires_in = type(result) == "table" and tonumber(result.expiresIn or result.expires_in) or nil
        last_error = nil
        dispatch_callback(callback, true, result)
    end)
end

function M.sign_out()
    local native = native_api()
    if native ~= nil and native.sign_out ~= nil then
        native.sign_out()
    end
    configured = false
    debug_state.in_flight = false
    debug_state.active_request = nil
end

function M.get_debug_state()
    local native = native_api()
    local native_debug = nil
    if native ~= nil and native.get_debug_state ~= nil then
        native_debug = native.get_debug_state()
    end
    return {
        supported = M.is_supported(),
        configured = configured == true,
        last_error = last_error,
        sign_in_request_count = tonumber(debug_state.sign_in_request_count) or 0,
        refresh_request_count = tonumber(debug_state.refresh_request_count) or 0,
        callback_count = tonumber(debug_state.callback_count) or 0,
        success_count = tonumber(debug_state.success_count) or 0,
        error_count = tonumber(debug_state.error_count) or 0,
        in_flight = debug_state.in_flight == true,
        active_request = debug_state.active_request,
        last_request_started_at = tonumber(debug_state.last_request_started_at) or 0,
        last_callback_at = tonumber(debug_state.last_callback_at) or 0,
        last_callback_ok = debug_state.last_callback_ok,
        last_result_uid = debug_state.last_result_uid,
        last_result_expires_in = tonumber(debug_state.last_result_expires_in) or nil,
        native = type(native_debug) == "table" and native_debug or nil
    }
end

return M
