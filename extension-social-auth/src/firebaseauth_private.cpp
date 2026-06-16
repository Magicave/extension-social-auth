#include <dmsdk/sdk.h>

#include "firebaseauth_private.h"

void FirebaseAuth_PushError(lua_State* L, const char* code, const char* message)
{
    lua_newtable(L);
    lua_pushstring(L, "code");
    lua_pushstring(L, code != 0 ? code : "firebase_auth_error");
    lua_rawset(L, -3);
    lua_pushstring(L, "message");
    lua_pushstring(L, message != 0 ? message : "Firebase Auth error");
    lua_rawset(L, -3);
}

void FirebaseAuth_Queue_Create(FirebaseAuthCommandQueue* queue)
{
    queue->m_Mutex = dmMutex::New();
}

void FirebaseAuth_Queue_Destroy(FirebaseAuthCommandQueue* queue)
{
    dmMutex::Delete(queue->m_Mutex);
}

void FirebaseAuth_Queue_Push(FirebaseAuthCommandQueue* queue, FirebaseAuthCommand* cmd)
{
    DM_MUTEX_SCOPED_LOCK(queue->m_Mutex);
    if (queue->m_Commands.Full())
    {
        queue->m_Commands.OffsetCapacity(2);
    }
    queue->m_Commands.Push(*cmd);
}

void FirebaseAuth_Queue_Flush(FirebaseAuthCommandQueue* queue, FirebaseAuthCommandFn fn, void* ctx)
{
    if (queue->m_Commands.Empty())
    {
        return;
    }

    dmArray<FirebaseAuthCommand> tmp;
    {
        DM_MUTEX_SCOPED_LOCK(queue->m_Mutex);
        tmp.Swap(queue->m_Commands);
    }

    for (uint32_t i = 0; i != tmp.Size(); ++i)
    {
        fn(&tmp[i], ctx);
    }
}
