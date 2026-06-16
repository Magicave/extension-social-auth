#if defined(DM_PLATFORM_IOS)

#include <dmsdk/sdk.h>

#include <Foundation/Foundation.h>
#include <GameKit/GameKit.h>
#include <UIKit/UIKit.h>
#include <dispatch/dispatch.h>

#if __has_include(<FirebaseCore/FirebaseCore.h>)
#include <FirebaseCore/FirebaseCore.h>
#define FIREBASEAUTH_IOS_HAS_FIREBASE_CORE 1
#else
#define FIREBASEAUTH_IOS_HAS_FIREBASE_CORE 0
#endif

#if __has_include(<FirebaseAuth/FIRAuth.h>)
#include <FirebaseAuth/FIRAuth.h>
#define FIREBASEAUTH_IOS_HAS_FIREBASE_AUTH 1
#else
#define FIREBASEAUTH_IOS_HAS_FIREBASE_AUTH 0
#endif

#include <stdlib.h>
#include <string.h>

#include "firebaseauth_private.h"

#define LIB_NAME "firebaseauth"

struct FirebaseAuthExt
{
    FirebaseAuthExt()
    {
        memset(this, 0, sizeof(*this));
    }

    lua_State* m_L;
    FirebaseAuthCommandQueue m_CommandQueue;
    uint32_t m_CommandCreateCount;
    uint32_t m_CommandQueuePushCount;
    uint32_t m_CommandFlushCount;
    uint32_t m_CommandFlushItemCount;
    uint32_t m_HandleCount;
    uint32_t m_SetupCallbackFailCount;
    uint32_t m_PCallErrorCount;
    int32_t m_LastResponseCode;
    uint32_t m_LastPayloadSize;
    const char* m_LastNativeStage;
    bool m_Configured;
};

static FirebaseAuthExt g_FirebaseAuth;

static void SetNativeStage(const char* stage)
{
    g_FirebaseAuth.m_LastNativeStage = stage;
    dmLogInfo("firebaseauth_ios stage=%s", stage != 0 ? stage : "");
}

static FirebaseAuthCommand* CreateCommand(lua_State* L, int callback_index)
{
    FirebaseAuthCommand* cmd = new FirebaseAuthCommand;
    lua_pushvalue(L, callback_index);
    cmd->m_CallbackRef = luaL_ref(L, LUA_REGISTRYINDEX);
    ++g_FirebaseAuth.m_CommandCreateCount;
    SetNativeStage("command_created");
    return cmd;
}

static void QueueCommandResult(FirebaseAuthCommand* cmd, int32_t response_code, const char* payload)
{
    if (cmd == 0)
    {
        SetNativeStage("queue_result_missing_cmd");
        return;
    }

    cmd->m_ResponseCode = response_code;
    if (payload != 0)
    {
        cmd->m_Data = strdup(payload);
        g_FirebaseAuth.m_LastPayloadSize = (uint32_t)strlen(payload);
    }
    else
    {
        g_FirebaseAuth.m_LastPayloadSize = 0;
    }

    g_FirebaseAuth.m_LastResponseCode = response_code;
    FirebaseAuth_Queue_Push(&g_FirebaseAuth.m_CommandQueue, cmd);
    ++g_FirebaseAuth.m_CommandQueuePushCount;
    SetNativeStage("result_queued");
    delete cmd;
}

static const char* JsonStringFromDictionary(NSDictionary* dictionary)
{
    NSError* error = nil;
    NSData* data = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:&error];
    if (data == nil || error != nil)
    {
        return 0;
    }
    NSString* json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (json == nil)
    {
        return 0;
    }
    return strdup([json UTF8String]);
}

static NSString* Base64EncodedString(NSData* data)
{
    if (data == nil || [data length] == 0)
    {
        return @"";
    }
    return [data base64EncodedStringWithOptions:0];
}

static NSString* StringOrEmpty(NSString* value)
{
    if (value == nil)
    {
        return @"";
    }
    return value;
}

static NSString* LuaStringField(lua_State* L, int index, const char* field)
{
    lua_getfield(L, index, field);
    const char* value = lua_isnil(L, -1) ? "" : lua_tostring(L, -1);
    lua_pop(L, 1);
    return value != 0 ? [NSString stringWithUTF8String:value] : @"";
}

static NSString* SenderIdFromGoogleAppId(NSString* app_id)
{
    if (app_id == nil || [app_id length] == 0)
    {
        return @"";
    }
    NSArray<NSString*>* parts = [app_id componentsSeparatedByString:@":"];
    if ([parts count] >= 2)
    {
        NSString* sender_id = parts[1];
        if (sender_id != nil && [sender_id length] > 0)
        {
            return sender_id;
        }
    }
    return @"";
}

static NSString* PreferredPlayerIdOrEmpty(GKLocalPlayer* player)
{
    if (player == nil)
    {
        return @"";
    }

    SEL legacy_player_id_selector = NSSelectorFromString(@"playerID");
    if ([player respondsToSelector:legacy_player_id_selector])
    {
        IMP implementation = [player methodForSelector:legacy_player_id_selector];
        if (implementation != 0)
        {
            NSString* (*func)(id, SEL) = (NSString* (*)(id, SEL))implementation;
            NSString* legacy_player_id = func(player, legacy_player_id_selector);
            if (legacy_player_id != nil && [legacy_player_id length] > 0)
            {
                return legacy_player_id;
            }
        }
    }
    return @"";
}

static void QueueGameCenterError(FirebaseAuthCommand* cmd, NSString* code, NSString* message)
{
    dmLogError("firebaseauth_ios gamecenter error code=%s message=%s",
        code != nil ? [code UTF8String] : "",
        message != nil ? [message UTF8String] : "");
    NSDictionary* error_dict = @{
        @"code": StringOrEmpty(code),
        @"message": StringOrEmpty(message)
    };
    const char* json = JsonStringFromDictionary(error_dict);
    QueueCommandResult(cmd, FIREBASEAUTH_RESULT_ERROR, json);
    if (json != 0) free((void*)json);
}

static void QueueGameCenterSuccess(
    FirebaseAuthCommand* cmd,
    NSString* player_id,
    NSString* display_name,
    NSString* game_player_id,
    NSString* team_player_id,
    NSURL* publicKeyURL,
    NSData* signature,
    NSData* salt,
    uint64_t timestamp)
{
    dmLogInfo("firebaseauth_ios gamecenter success teamPlayerID=%s gamePlayerID=%s",
        team_player_id != nil ? [team_player_id UTF8String] : "",
        game_player_id != nil ? [game_player_id UTF8String] : "");
    NSMutableDictionary* result = [NSMutableDictionary dictionary];
    result[@"provider"] = @"gamecenter";
    result[@"public_key_url"] = [publicKeyURL absoluteString] != nil ? [publicKeyURL absoluteString] : @"";
    result[@"signature"] = Base64EncodedString(signature);
    result[@"salt"] = Base64EncodedString(salt);
    result[@"timestamp"] = [NSNumber numberWithUnsignedLongLong:timestamp];
    result[@"player_id"] = StringOrEmpty(player_id);
    result[@"display_name"] = StringOrEmpty(display_name);
    result[@"native_provider_fetch"] = @YES;
    result[@"game_player_id"] = StringOrEmpty(game_player_id);
    result[@"team_player_id"] = StringOrEmpty(team_player_id);

    const char* json = JsonStringFromDictionary(result);
    SetNativeStage("gamecenter_identity_success");
    QueueCommandResult(cmd, FIREBASEAUTH_RESULT_OK, json);
    if (json != 0) free((void*)json);
}

static void QueueFirebaseAuthSuccess(FirebaseAuthCommand* cmd, NSString* uid, NSString* id_token, uint64_t expires_in)
{
    NSMutableDictionary* result = [NSMutableDictionary dictionary];
    result[@"uid"] = StringOrEmpty(uid);
    result[@"localId"] = StringOrEmpty(uid);
    result[@"idToken"] = StringOrEmpty(id_token);
    result[@"expiresIn"] = [NSNumber numberWithUnsignedLongLong:expires_in];
    result[@"provider"] = @"gamecenter";
    result[@"native_firebase_auth"] = @YES;

    const char* json = JsonStringFromDictionary(result);
    SetNativeStage("firebase_auth_success");
    QueueCommandResult(cmd, FIREBASEAUTH_RESULT_OK, json);
    if (json != 0) free((void*)json);
}

static NSString* FirebaseUidOrEmpty(id user)
{
    if (user == nil)
    {
        return @"";
    }

    SEL uid_selector = NSSelectorFromString(@"uid");
    if ([user respondsToSelector:uid_selector])
    {
        IMP implementation = [user methodForSelector:uid_selector];
        if (implementation != 0)
        {
            NSString* (*func)(id, SEL) = (NSString* (*)(id, SEL))implementation;
            NSString* uid = func(user, uid_selector);
            if (uid != nil && [uid length] > 0)
            {
                return uid;
            }
        }
    }

    return @"";
}

static id FirebaseAuthSharedInstance()
{
    Class auth_class = NSClassFromString(@"FIRAuth");
    SEL auth_selector = NSSelectorFromString(@"auth");
    if (auth_class == Nil || ![auth_class respondsToSelector:auth_selector])
    {
        return nil;
    }

    IMP auth_imp = [auth_class methodForSelector:auth_selector];
    if (auth_imp == 0)
    {
        return nil;
    }

    id (*auth_func)(id, SEL) = (id (*)(id, SEL))auth_imp;
    return auth_func(auth_class, auth_selector);
}

static id FirebaseCurrentUser()
{
    id auth = FirebaseAuthSharedInstance();
    if (auth == nil)
    {
        return nil;
    }

    SEL current_user_selector = NSSelectorFromString(@"currentUser");
    if (![auth respondsToSelector:current_user_selector])
    {
        return nil;
    }

    IMP current_user_imp = [auth methodForSelector:current_user_selector];
    if (current_user_imp == 0)
    {
        return nil;
    }

    id (*current_user_func)(id, SEL) = (id (*)(id, SEL))current_user_imp;
    return current_user_func(auth, current_user_selector);
}

static void SendCurrentUserToken(FirebaseAuthCommand* cmd, BOOL force_refresh)
{
#if FIREBASEAUTH_IOS_HAS_FIREBASE_AUTH
    id user = FirebaseCurrentUser();
    if (user == nil)
    {
        SetNativeStage("firebase_auth_missing_current_user");
        QueueGameCenterError(cmd, @"missing_current_user", @"Firebase has no signed-in user");
        return;
    }

    SEL token_selector = NSSelectorFromString(@"getIDTokenForcingRefresh:completion:");
    if (![user respondsToSelector:token_selector])
    {
        SetNativeStage("firebase_auth_token_selector_missing");
        QueueGameCenterError(cmd, @"token_selector_missing", @"Firebase user cannot provide an ID token");
        return;
    }

    SetNativeStage(force_refresh ? "firebase_auth_token_request_forced" : "firebase_auth_token_request");
    [user getIDTokenForcingRefresh:force_refresh completion:^(NSString* _Nullable token, NSError* _Nullable error) {
        if (error != nil)
        {
            SetNativeStage("firebase_auth_token_error");
            QueueGameCenterError(cmd, @"token_failed", error.localizedDescription != nil ? error.localizedDescription : @"Firebase token request failed");
            return;
        }

        NSString* resolved_token = token != nil ? token : @"";
        if ([resolved_token length] == 0)
        {
            SetNativeStage("firebase_auth_token_missing");
            QueueGameCenterError(cmd, @"missing_id_token", @"Firebase returned an empty ID token");
            return;
        }

        uint64_t expires_in = 3600;
        QueueFirebaseAuthSuccess(cmd, FirebaseUidOrEmpty(user), resolved_token, expires_in);
    }];
#else
    (void)force_refresh;
    SetNativeStage("firebase_auth_unavailable");
    QueueGameCenterError(cmd, @"firebase_auth_unavailable", @"Firebase Auth iOS SDK is unavailable");
#endif
}

static int FirebaseAuth_Configure(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 1);
    luaL_checktype(L, 1, LUA_TTABLE);
#if FIREBASEAUTH_IOS_HAS_FIREBASE_CORE && FIREBASEAUTH_IOS_HAS_FIREBASE_AUTH
    NSString* app_id = LuaStringField(L, 1, "app_id");
    NSString* api_key = LuaStringField(L, 1, "api_key");
    NSString* project_id = LuaStringField(L, 1, "project_id");

    if ([app_id length] == 0 || [api_key length] == 0)
    {
        g_FirebaseAuth.m_Configured = false;
        SetNativeStage("configure_missing_options");
        lua_pushboolean(L, 0);
        return 1;
    }

    void (^configure_block)(void) = ^{
        if ([FIRApp defaultApp] == nil)
        {
            FIROptions* options = [[FIROptions alloc] initWithGoogleAppID:app_id GCMSenderID:SenderIdFromGoogleAppId(app_id)];
            options.APIKey = api_key;
            if ([project_id length] > 0)
            {
                options.projectID = project_id;
            }
            NSString* bundle_id = [[NSBundle mainBundle] bundleIdentifier];
            if (bundle_id != nil && [bundle_id length] > 0)
            {
                options.bundleID = bundle_id;
            }
            [FIRApp configureWithOptions:options];
        }
        g_FirebaseAuth.m_Configured = ([FIRApp defaultApp] != nil);
    };
    if ([NSThread isMainThread])
    {
        configure_block();
    }
    else
    {
        dispatch_sync(dispatch_get_main_queue(), configure_block);
    }
    SetNativeStage(g_FirebaseAuth.m_Configured ? "configure" : "configure_failed");
    lua_pushboolean(L, g_FirebaseAuth.m_Configured ? 1 : 0);
#else
    g_FirebaseAuth.m_Configured = false;
    SetNativeStage("configure_unavailable");
    lua_pushboolean(L, 0);
#endif
    return 1;
}

static int FirebaseAuth_SignInPlayGames(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 0);
    luaL_checkstring(L, 1);
    luaL_checktype(L, 2, LUA_TFUNCTION);

    FirebaseAuthCommand* cmd = CreateCommand(L, 2);
    NSDictionary* error_dict = @{
        @"code": @"unsupported_provider",
        @"message": @"Google Play Games native sign-in is unavailable on iOS"
    };
    const char* json = JsonStringFromDictionary(error_dict);
    QueueCommandResult(cmd, FIREBASEAUTH_RESULT_ERROR, json);
    if (json != 0) free((void*)json);
    return 0;
}

static int FirebaseAuth_SignInGameCenter(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 0);
    luaL_checktype(L, 1, LUA_TFUNCTION);

    FirebaseAuthCommand* cmd = CreateCommand(L, 1);
#if !(FIREBASEAUTH_IOS_HAS_FIREBASE_AUTH)
    SetNativeStage("gamecenter_firebase_sdk_missing");
    QueueGameCenterError(cmd, @"firebase_auth_unavailable", @"Firebase Auth iOS SDK is unavailable");
    return 0;
#endif
    SetNativeStage("gamecenter_identity_dispatch_main");
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool
        {
            GKLocalPlayer* local_player = [GKLocalPlayer localPlayer];
            dmLogInfo("firebaseauth_ios localPlayer acquired authenticated=%d", local_player != nil && local_player.isAuthenticated ? 1 : 0);
            if (local_player == nil || !local_player.isAuthenticated)
            {
                SetNativeStage("gamecenter_not_authenticated");
                QueueGameCenterError(cmd, @"game_center_not_authenticated", @"Game Center is not signed in");
                return;
            }

            SetNativeStage("gamecenter_identity_request");
            NSString* player_id = PreferredPlayerIdOrEmpty(local_player);
            NSString* display_name = local_player.displayName != nil ? [local_player.displayName copy] : @"";
            NSString* game_player_id = @"";
            NSString* team_player_id = @"";
            if (@available(iOS 13.0, *))
            {
                game_player_id = local_player.gamePlayerID != nil ? [local_player.gamePlayerID copy] : @"";
                team_player_id = local_player.teamPlayerID != nil ? [local_player.teamPlayerID copy] : @"";
            }

            dmLogInfo("firebaseauth_ios using GameCenterAuthProvider credential");
            Class game_center_auth_provider_class = NSClassFromString(@"FIRGameCenterAuthProvider");
            SEL credential_selector = NSSelectorFromString(@"getCredentialWithCompletion:");
            if (game_center_auth_provider_class == Nil || ![game_center_auth_provider_class respondsToSelector:credential_selector])
            {
                SetNativeStage("gamecenter_credential_provider_missing");
                QueueGameCenterError(cmd, @"game_center_provider_missing", @"Firebase Game Center provider is unavailable");
                return;
            }

            [game_center_auth_provider_class getCredentialWithCompletion:^(id credential, NSError* _Nullable error) {
                if (error != nil)
                {
                    SetNativeStage("gamecenter_credential_error");
                    QueueGameCenterError(cmd, @"game_center_credential_failed", error.localizedDescription != nil ? error.localizedDescription : @"Firebase Game Center credential failed");
                    return;
                }
                if (credential == nil)
                {
                    SetNativeStage("gamecenter_credential_missing");
                    QueueGameCenterError(cmd, @"game_center_credential_missing", @"Firebase did not return a Game Center credential");
                    return;
                }

                SetNativeStage("firebase_auth_signin_request");
                id auth = FirebaseAuthSharedInstance();
                SEL sign_in_selector = NSSelectorFromString(@"signInWithCredential:completion:");
                if (auth == nil || ![auth respondsToSelector:sign_in_selector])
                {
                    SetNativeStage("firebase_auth_signin_selector_missing");
                    QueueGameCenterError(cmd, @"sign_in_selector_missing", @"Firebase Auth sign-in is unavailable");
                    return;
                }

                [auth signInWithCredential:credential completion:^(id auth_result, NSError* _Nullable sign_in_error) {
                    if (sign_in_error != nil)
                    {
                        SetNativeStage("firebase_auth_signin_error");
                        QueueGameCenterError(cmd, @"sign_in_failed", sign_in_error.localizedDescription != nil ? sign_in_error.localizedDescription : @"Firebase sign-in failed");
                        return;
                    }

                    id signed_in_user = nil;
                    SEL user_selector = NSSelectorFromString(@"user");
                    if (auth_result != nil && [auth_result respondsToSelector:user_selector])
                    {
                        IMP user_imp = [auth_result methodForSelector:user_selector];
                        if (user_imp != 0)
                        {
                            id (*user_func)(id, SEL) = (id (*)(id, SEL))user_imp;
                            signed_in_user = user_func(auth_result, user_selector);
                        }
                    }

                    if (auth_result == nil || signed_in_user == nil)
                    {
                        SetNativeStage("firebase_auth_signin_missing_user");
                        QueueGameCenterError(cmd, @"missing_current_user", @"Firebase sign-in did not return a user");
                        return;
                    }

                    dmLogInfo("firebaseauth_ios firebase sign-in success playerID=%s teamPlayerID=%s gamePlayerID=%s",
                        player_id != nil ? [player_id UTF8String] : "",
                        team_player_id != nil ? [team_player_id UTF8String] : "",
                        game_player_id != nil ? [game_player_id UTF8String] : "");
                    SendCurrentUserToken(cmd, YES);
                }];
            }];
        }
    });
    return 0;
}

static int FirebaseAuth_RefreshIdToken(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 0);
    bool force_refresh = lua_toboolean(L, 1);
    luaL_checktype(L, 2, LUA_TFUNCTION);

    FirebaseAuthCommand* cmd = CreateCommand(L, 2);
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool
        {
            SendCurrentUserToken(cmd, force_refresh ? YES : NO);
        }
    });
    return 0;
}

static int FirebaseAuth_SignOut(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 0);
#if FIREBASEAUTH_IOS_HAS_FIREBASE_AUTH
    NSError* error = nil;
    id auth = FirebaseAuthSharedInstance();
    SEL sign_out_selector = NSSelectorFromString(@"signOut:");
    if (auth != nil && [auth respondsToSelector:sign_out_selector])
    {
        typedef BOOL (*SignOutFn)(id, SEL, NSError**);
        SignOutFn sign_out = (SignOutFn)[auth methodForSelector:sign_out_selector];
        sign_out(auth, sign_out_selector, &error);
        if (error != nil)
        {
            dmLogError("firebaseauth_ios sign_out failed: %s", error.localizedDescription != nil ? [error.localizedDescription UTF8String] : "");
        }
    }
#endif
    g_FirebaseAuth.m_Configured = false;
    SetNativeStage("sign_out");
    return 0;
}

static int FirebaseAuth_GetDebugState(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 1);
    lua_newtable(L);
    lua_pushstring(L, "configured");
    lua_pushboolean(L, g_FirebaseAuth.m_Configured ? 1 : 0);
    lua_rawset(L, -3);
    lua_pushstring(L, "signed_in");
    #if FIREBASEAUTH_IOS_HAS_FIREBASE_AUTH
    lua_pushboolean(L, FirebaseCurrentUser() != nil ? 1 : 0);
    #else
    lua_pushboolean(L, 0);
    #endif
    lua_rawset(L, -3);
    lua_pushstring(L, "stage");
    lua_pushstring(L, g_FirebaseAuth.m_LastNativeStage != 0 ? g_FirebaseAuth.m_LastNativeStage : "");
    lua_rawset(L, -3);
    lua_pushstring(L, "native_cpp");
    lua_newtable(L);
    lua_pushstring(L, "command_create_count");
    lua_pushnumber(L, g_FirebaseAuth.m_CommandCreateCount);
    lua_rawset(L, -3);
    lua_pushstring(L, "queue_push_count");
    lua_pushnumber(L, g_FirebaseAuth.m_CommandQueuePushCount);
    lua_rawset(L, -3);
    lua_pushstring(L, "flush_count");
    lua_pushnumber(L, g_FirebaseAuth.m_CommandFlushCount);
    lua_rawset(L, -3);
    lua_pushstring(L, "flush_item_count");
    lua_pushnumber(L, g_FirebaseAuth.m_CommandFlushItemCount);
    lua_rawset(L, -3);
    lua_pushstring(L, "handle_count");
    lua_pushnumber(L, g_FirebaseAuth.m_HandleCount);
    lua_rawset(L, -3);
    lua_pushstring(L, "setup_callback_fail_count");
    lua_pushnumber(L, g_FirebaseAuth.m_SetupCallbackFailCount);
    lua_rawset(L, -3);
    lua_pushstring(L, "pcall_error_count");
    lua_pushnumber(L, g_FirebaseAuth.m_PCallErrorCount);
    lua_rawset(L, -3);
    lua_pushstring(L, "last_response_code");
    lua_pushnumber(L, g_FirebaseAuth.m_LastResponseCode);
    lua_rawset(L, -3);
    lua_pushstring(L, "last_payload_size");
    lua_pushnumber(L, g_FirebaseAuth.m_LastPayloadSize);
    lua_rawset(L, -3);
    lua_rawset(L, -3);
    return 1;
}

static int FirebaseAuth_IsSupported(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 1);
    lua_pushboolean(L, 1);
    return 1;
}

static const luaL_reg FirebaseAuth_methods[] =
{
    {"configure", FirebaseAuth_Configure},
    {"sign_in_play_games", FirebaseAuth_SignInPlayGames},
    {"sign_in_game_center", FirebaseAuth_SignInGameCenter},
    {"refresh_id_token", FirebaseAuth_RefreshIdToken},
    {"sign_out", FirebaseAuth_SignOut},
    {"get_debug_state", FirebaseAuth_GetDebugState},
    {"is_supported", FirebaseAuth_IsSupported},
    {0, 0}
};

static void HandleAuthResult(FirebaseAuthCommand* cmd, void*)
{
    ++g_FirebaseAuth.m_HandleCount;
    SetNativeStage("handle_auth_result");
    lua_State* L = g_FirebaseAuth.m_L;
    if (L == 0 || cmd->m_CallbackRef == LUA_NOREF)
    {
        SetNativeStage("handle_auth_result_missing_callback");
        if (cmd->m_Data != 0)
        {
            free(cmd->m_Data);
            cmd->m_Data = 0;
        }
        return;
    }
    int top = lua_gettop(L);
    lua_rawgeti(L, LUA_REGISTRYINDEX, cmd->m_CallbackRef);
    if (!lua_isfunction(L, -1))
    {
        ++g_FirebaseAuth.m_SetupCallbackFailCount;
        SetNativeStage("setup_callback_failed");
        lua_pop(L, 1);
        luaL_unref(L, LUA_REGISTRYINDEX, cmd->m_CallbackRef);
        cmd->m_CallbackRef = LUA_NOREF;
        if (cmd->m_Data != 0)
        {
            free(cmd->m_Data);
            cmd->m_Data = 0;
        }
        assert(top == lua_gettop(L));
        return;
    }
    lua_pushnil(L);

    const char* json = (const char*)cmd->m_Data;
    if (cmd->m_ResponseCode == FIREBASEAUTH_RESULT_OK)
    {
        if (json != 0 && json[0] != '\0')
        {
            dmScript::JsonToLua(L, json, strlen(json));
        }
        else
        {
            lua_newtable(L);
        }
        lua_pushnil(L);
    }
    else
    {
        lua_pushnil(L);
        if (json != 0 && json[0] != '\0')
        {
            dmScript::JsonToLua(L, json, strlen(json));
        }
        else
        {
            FirebaseAuth_PushError(L, "firebase_auth_error", "Firebase Auth failed");
        }
    }

    int pcall_result = dmScript::PCall(L, 3, 0);
    if (pcall_result != 0)
    {
        ++g_FirebaseAuth.m_PCallErrorCount;
        SetNativeStage("pcall_failed");
        lua_pop(L, 1);
    }
    else
    {
        SetNativeStage("callback_completed");
    }
    luaL_unref(L, LUA_REGISTRYINDEX, cmd->m_CallbackRef);
    cmd->m_CallbackRef = LUA_NOREF;
    if (cmd->m_Data != 0)
    {
        free(cmd->m_Data);
        cmd->m_Data = 0;
    }
    assert(top == lua_gettop(L));
}

static dmExtension::Result InitializeFirebaseAuth(dmExtension::Params* params)
{
    FirebaseAuth_Queue_Create(&g_FirebaseAuth.m_CommandQueue);
    SetNativeStage("initialize");

    lua_State* L = params->m_L;
    g_FirebaseAuth.m_L = L;
    int top = lua_gettop(L);
    luaL_register(L, LIB_NAME, FirebaseAuth_methods);
    lua_pop(L, 1);
    assert(top == lua_gettop(L));

    return dmExtension::RESULT_OK;
}

static dmExtension::Result UpdateFirebaseAuth(dmExtension::Params* params)
{
    ++g_FirebaseAuth.m_CommandFlushCount;
    uint32_t before = g_FirebaseAuth.m_HandleCount;
    FirebaseAuth_Queue_Flush(&g_FirebaseAuth.m_CommandQueue, HandleAuthResult, 0);
    g_FirebaseAuth.m_CommandFlushItemCount += (g_FirebaseAuth.m_HandleCount - before);
    return dmExtension::RESULT_OK;
}

static dmExtension::Result FinalizeFirebaseAuth(dmExtension::Params* params)
{
    FirebaseAuth_Queue_Destroy(&g_FirebaseAuth.m_CommandQueue);
    return dmExtension::RESULT_OK;
}

DM_DECLARE_EXTENSION(FirebaseAuthExt, "FirebaseAuth", 0, 0, InitializeFirebaseAuth, UpdateFirebaseAuth, 0, FinalizeFirebaseAuth)

#endif
