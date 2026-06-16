#if defined(DM_PLATFORM_ANDROID)

#include <dmsdk/sdk.h>
#include <dmsdk/dlib/android.h>

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

    jobject m_Bridge;
    jobject m_JNI;
    jmethodID m_Configure;
    jmethodID m_SignInPlayGames;
    jmethodID m_SignInGameCenter;
    jmethodID m_RefreshIdToken;
    jmethodID m_SignOut;
    jmethodID m_GetDebugState;
    lua_State* m_L;
    FirebaseAuthCommandQueue m_CommandQueue;
    uint32_t m_CommandCreateCount;
    uint32_t m_CommandQueuePushCount;
    uint32_t m_CommandFlushCount;
    uint32_t m_CommandFlushItemCount;
    uint32_t m_JniResultCount;
    uint32_t m_HandleCount;
    uint32_t m_SetupCallbackFailCount;
    uint32_t m_PCallErrorCount;
    int32_t m_LastResponseCode;
    uint32_t m_LastPayloadSize;
    const char* m_LastNativeStage;
};

static FirebaseAuthExt g_FirebaseAuth;

static void SetNativeStage(const char* stage)
{
    g_FirebaseAuth.m_LastNativeStage = stage;
}

static const char* GetStringField(lua_State* L, int index, const char* field)
{
    lua_getfield(L, index, field);
    const char* value = lua_isnil(L, -1) ? "" : lua_tostring(L, -1);
    lua_pop(L, 1);
    return value != 0 ? value : "";
}

static int FirebaseAuth_Configure(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 1);
    luaL_checktype(L, 1, LUA_TTABLE);

    const char* app_id = GetStringField(L, 1, "app_id");
    const char* api_key = GetStringField(L, 1, "api_key");
    const char* project_id = GetStringField(L, 1, "project_id");

    dmAndroid::ThreadAttacher threadAttacher;
    JNIEnv* env = threadAttacher.GetEnv();
    jstring app_id_j = env->NewStringUTF(app_id);
    jstring api_key_j = env->NewStringUTF(api_key);
    jstring project_id_j = env->NewStringUTF(project_id);
    jboolean ok = env->CallBooleanMethod(g_FirebaseAuth.m_Bridge, g_FirebaseAuth.m_Configure, app_id_j, api_key_j, project_id_j);
    env->DeleteLocalRef(app_id_j);
    env->DeleteLocalRef(api_key_j);
    env->DeleteLocalRef(project_id_j);

    lua_pushboolean(L, ok == JNI_TRUE);
    return 1;
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

static int FirebaseAuth_SignInPlayGames(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 0);
    const char* server_auth_code = luaL_checkstring(L, 1);
    luaL_checktype(L, 2, LUA_TFUNCTION);

    FirebaseAuthCommand* cmd = CreateCommand(L, 2);
    SetNativeStage("sign_in_request");
    dmAndroid::ThreadAttacher threadAttacher;
    JNIEnv* env = threadAttacher.GetEnv();
    jstring code_j = env->NewStringUTF(server_auth_code != 0 ? server_auth_code : "");
    env->CallVoidMethod(g_FirebaseAuth.m_Bridge, g_FirebaseAuth.m_SignInPlayGames, code_j, g_FirebaseAuth.m_JNI, (jlong)cmd);
    env->DeleteLocalRef(code_j);
    return 0;
}

static int FirebaseAuth_SignInGameCenter(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 0);
    luaL_checktype(L, 1, LUA_TFUNCTION);

    FirebaseAuthCommand* cmd = CreateCommand(L, 1);
    cmd->m_ResponseCode = FIREBASEAUTH_RESULT_ERROR;
    cmd->m_Data = strdup("{\"code\":\"unsupported_platform\",\"message\":\"Game Center sign-in is unavailable on Android\"}");
    FirebaseAuth_Queue_Push(&g_FirebaseAuth.m_CommandQueue, cmd);
    ++g_FirebaseAuth.m_CommandQueuePushCount;
    SetNativeStage("sign_in_game_center_unsupported");
    return 0;
}

static int FirebaseAuth_RefreshIdToken(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 0);
    bool force_refresh = lua_toboolean(L, 1);
    luaL_checktype(L, 2, LUA_TFUNCTION);

    FirebaseAuthCommand* cmd = CreateCommand(L, 2);
    SetNativeStage("refresh_request");
    dmAndroid::ThreadAttacher threadAttacher;
    JNIEnv* env = threadAttacher.GetEnv();
    env->CallVoidMethod(g_FirebaseAuth.m_Bridge, g_FirebaseAuth.m_RefreshIdToken, force_refresh ? JNI_TRUE : JNI_FALSE, g_FirebaseAuth.m_JNI, (jlong)cmd);
    return 0;
}

static int FirebaseAuth_SignOut(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 0);
    dmAndroid::ThreadAttacher threadAttacher;
    JNIEnv* env = threadAttacher.GetEnv();
    env->CallVoidMethod(g_FirebaseAuth.m_Bridge, g_FirebaseAuth.m_SignOut);
    return 0;
}

static int FirebaseAuth_GetDebugState(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 1);
    dmAndroid::ThreadAttacher threadAttacher;
    JNIEnv* env = threadAttacher.GetEnv();
    jstring state_j = (jstring)env->CallObjectMethod(g_FirebaseAuth.m_Bridge, g_FirebaseAuth.m_GetDebugState);
    const char* state = state_j != 0 ? env->GetStringUTFChars(state_j, 0) : 0;
    if (state != 0)
    {
        dmScript::JsonToLua(L, state, strlen(state));
        env->ReleaseStringUTFChars(state_j, state);
    }
    else
    {
        lua_newtable(L);
    }
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
    lua_pushstring(L, "jni_result_count");
    lua_pushnumber(L, g_FirebaseAuth.m_JniResultCount);
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
    lua_pushstring(L, "stage");
    lua_pushstring(L, g_FirebaseAuth.m_LastNativeStage != 0 ? g_FirebaseAuth.m_LastNativeStage : "");
    lua_rawset(L, -3);
    lua_rawset(L, -3);
    if (state_j != 0)
    {
        env->DeleteLocalRef(state_j);
    }
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

extern "C" {

JNIEXPORT void JNICALL Java_com_magicave_firebaseauth_FirebaseAuthJNI_onAuthResult(JNIEnv* env, jobject, jint responseCode, jstring payload, jlong cmdHandle)
{
    FirebaseAuthCommand* cmd = (FirebaseAuthCommand*)cmdHandle;
    ++g_FirebaseAuth.m_JniResultCount;
    g_FirebaseAuth.m_LastResponseCode = responseCode;
    SetNativeStage("jni_on_auth_result");
    if (cmd == 0)
    {
        SetNativeStage("jni_on_auth_result_missing_cmd");
        return;
    }

    const char* payload_text = payload != 0 ? env->GetStringUTFChars(payload, 0) : 0;
    cmd->m_ResponseCode = responseCode;
    if (payload_text != 0)
    {
        cmd->m_Data = strdup(payload_text);
        g_FirebaseAuth.m_LastPayloadSize = (uint32_t)strlen(payload_text);
        env->ReleaseStringUTFChars(payload, payload_text);
    }
    else
    {
        g_FirebaseAuth.m_LastPayloadSize = 0;
    }

    FirebaseAuth_Queue_Push(&g_FirebaseAuth.m_CommandQueue, cmd);
    ++g_FirebaseAuth.m_CommandQueuePushCount;
    SetNativeStage("jni_result_queued");
    delete cmd;
}

}

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

    dmAndroid::ThreadAttacher threadAttacher;
    JNIEnv* env = threadAttacher.GetEnv();
    jclass bridge_class = dmAndroid::LoadClass(env, "com.magicave.firebaseauth.FirebaseAuthBridge");
    jclass jni_class = dmAndroid::LoadClass(env, "com.magicave.firebaseauth.FirebaseAuthJNI");

    g_FirebaseAuth.m_Configure = env->GetMethodID(bridge_class, "configure", "(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Z");
    g_FirebaseAuth.m_SignInPlayGames = env->GetMethodID(bridge_class, "signInPlayGames", "(Ljava/lang/String;Lcom/magicave/firebaseauth/FirebaseAuthJNI;J)V");
    g_FirebaseAuth.m_SignInGameCenter = 0;
    g_FirebaseAuth.m_RefreshIdToken = env->GetMethodID(bridge_class, "refreshIdToken", "(ZLcom/magicave/firebaseauth/FirebaseAuthJNI;J)V");
    g_FirebaseAuth.m_SignOut = env->GetMethodID(bridge_class, "signOut", "()V");
    g_FirebaseAuth.m_GetDebugState = env->GetMethodID(bridge_class, "getDebugState", "()Ljava/lang/String;");

    jmethodID bridge_constructor = env->GetMethodID(bridge_class, "<init>", "(Landroid/app/Activity;)V");
    g_FirebaseAuth.m_Bridge = env->NewGlobalRef(env->NewObject(bridge_class, bridge_constructor, threadAttacher.GetActivity()->clazz));

    jmethodID jni_constructor = env->GetMethodID(jni_class, "<init>", "()V");
    g_FirebaseAuth.m_JNI = env->NewGlobalRef(env->NewObject(jni_class, jni_constructor));

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

    dmAndroid::ThreadAttacher threadAttacher;
    JNIEnv* env = threadAttacher.GetEnv();
    if (g_FirebaseAuth.m_Bridge != 0)
    {
        env->DeleteGlobalRef(g_FirebaseAuth.m_Bridge);
        g_FirebaseAuth.m_Bridge = 0;
    }
    if (g_FirebaseAuth.m_JNI != 0)
    {
        env->DeleteGlobalRef(g_FirebaseAuth.m_JNI);
        g_FirebaseAuth.m_JNI = 0;
    }
    return dmExtension::RESULT_OK;
}

DM_DECLARE_EXTENSION(FirebaseAuthExt, "FirebaseAuth", 0, 0, InitializeFirebaseAuth, UpdateFirebaseAuth, 0, FinalizeFirebaseAuth)

#endif
