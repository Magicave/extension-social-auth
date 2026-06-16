#if !defined(DM_PLATFORM_ANDROID) && !defined(DM_PLATFORM_IOS)

#include <dmsdk/sdk.h>

#include "firebaseauth_private.h"

#define LIB_NAME "firebaseauth"

static void CallUnsupportedCallback(lua_State* L, int callback_index)
{
    dmScript::LuaCallbackInfo* callback = dmScript::CreateCallback(L, callback_index);
    lua_State* callback_lua = dmScript::GetCallbackLuaContext(callback);
    if (!dmScript::SetupCallback(callback))
    {
        dmScript::DestroyCallback(callback);
        return;
    }
    lua_pushnil(callback_lua);
    FirebaseAuth_PushError(callback_lua, "unsupported_platform", "Firebase Auth native extension is unavailable on this platform");
    dmScript::PCall(callback_lua, 3, 0);
    dmScript::TeardownCallback(callback);
    dmScript::DestroyCallback(callback);
}

static int FirebaseAuth_Configure(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 1);
    lua_pushboolean(L, 0);
    return 1;
}

static int FirebaseAuth_SignInPlayGames(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 0);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    CallUnsupportedCallback(L, 2);
    return 0;
}

static int FirebaseAuth_SignInGameCenter(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 0);
    luaL_checktype(L, 1, LUA_TFUNCTION);
    CallUnsupportedCallback(L, 1);
    return 0;
}

static int FirebaseAuth_RefreshIdToken(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 0);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    CallUnsupportedCallback(L, 2);
    return 0;
}

static int FirebaseAuth_SignOut(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 0);
    return 0;
}

static int FirebaseAuth_GetDebugState(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 1);
    lua_newtable(L);
    lua_pushstring(L, "configured");
    lua_pushboolean(L, 0);
    lua_rawset(L, -3);
    lua_pushstring(L, "signed_in");
    lua_pushboolean(L, 0);
    lua_rawset(L, -3);
    lua_pushstring(L, "stage");
    lua_pushstring(L, "unsupported_platform");
    lua_rawset(L, -3);
    return 1;
}

static int FirebaseAuth_IsSupported(lua_State* L)
{
    DM_LUA_STACK_CHECK(L, 1);
    lua_pushboolean(L, 0);
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

static dmExtension::Result InitializeFirebaseAuth(dmExtension::Params* params)
{
    lua_State* L = params->m_L;
    int top = lua_gettop(L);
    luaL_register(L, LIB_NAME, FirebaseAuth_methods);
    lua_pop(L, 1);
    assert(top == lua_gettop(L));
    return dmExtension::RESULT_OK;
}

DM_DECLARE_EXTENSION(FirebaseAuthExt, "FirebaseAuth", 0, 0, InitializeFirebaseAuth, 0, 0, 0)

#endif
