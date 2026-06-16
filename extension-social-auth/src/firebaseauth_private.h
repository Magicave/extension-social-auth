#ifndef FIREBASEAUTH_PRIVATE_H
#define FIREBASEAUTH_PRIVATE_H

#include <dmsdk/sdk.h>
#include <string.h>

enum FirebaseAuthResult
{
    FIREBASEAUTH_RESULT_OK = 0,
    FIREBASEAUTH_RESULT_ERROR = 1,
};

struct DM_ALIGNED(16) FirebaseAuthCommand
{
    FirebaseAuthCommand()
    {
        memset(this, 0, sizeof(FirebaseAuthCommand));
        m_CallbackRef = LUA_NOREF;
    }

    int m_CallbackRef;
    int32_t m_ResponseCode;
    void* m_Data;
};

struct FirebaseAuthCommandQueue
{
    dmArray<FirebaseAuthCommand> m_Commands;
    dmMutex::HMutex m_Mutex;
};

typedef void (*FirebaseAuthCommandFn)(FirebaseAuthCommand* cmd, void* ctx);

void FirebaseAuth_Queue_Create(FirebaseAuthCommandQueue* queue);
void FirebaseAuth_Queue_Destroy(FirebaseAuthCommandQueue* queue);
void FirebaseAuth_Queue_Push(FirebaseAuthCommandQueue* queue, FirebaseAuthCommand* cmd);
void FirebaseAuth_Queue_Flush(FirebaseAuthCommandQueue* queue, FirebaseAuthCommandFn fn, void* ctx);
void FirebaseAuth_PushError(lua_State* L, const char* code, const char* message);

#endif
