package com.magicave.firebaseauth;

import android.app.Activity;

import com.google.android.gms.tasks.Task;
import com.google.firebase.FirebaseApp;
import com.google.firebase.FirebaseOptions;
import com.google.firebase.auth.AuthCredential;
import com.google.firebase.auth.FirebaseAuth;
import com.google.firebase.auth.FirebaseUser;
import com.google.firebase.auth.GetTokenResult;
import com.google.firebase.auth.PlayGamesAuthProvider;

import org.json.JSONObject;

import java.util.List;

public class FirebaseAuthBridge {
    private final Activity activity;
    private FirebaseAuth auth;
    private String lastStage = "init";
    private String lastError = "";
    private int signInRequestCount = 0;
    private int refreshRequestCount = 0;
    private int tokenRequestCount = 0;
    private int tokenSuccessCount = 0;
    private int tokenErrorCount = 0;
    private int dispatchOkCount = 0;
    private int dispatchErrorCount = 0;
    private int dispatchExceptionCount = 0;

    public FirebaseAuthBridge(Activity activity) {
        this.activity = activity;
    }

    public boolean configure(String appId, String apiKey, String projectId) {
        lastStage = "configure";
        lastError = "";
        try {
            if (isBlank(appId) || isBlank(apiKey)) {
                lastError = "missing_firebase_options";
                return false;
            }
            List<FirebaseApp> apps = FirebaseApp.getApps(activity.getApplicationContext());
            if (apps == null || apps.isEmpty()) {
                FirebaseOptions.Builder builder = new FirebaseOptions.Builder()
                    .setApplicationId(appId)
                    .setApiKey(apiKey);
                if (!isBlank(projectId)) {
                    builder.setProjectId(projectId);
                }
                FirebaseApp.initializeApp(activity.getApplicationContext(), builder.build());
            }
            auth = FirebaseAuth.getInstance();
            return true;
        } catch (Exception exception) {
            lastError = safeMessage(exception);
            return false;
        }
    }

    public void signInPlayGames(String serverAuthCode, FirebaseAuthJNI jni, long cmdHandle) {
        lastStage = "sign_in_play_games";
        signInRequestCount += 1;
        if (auth == null) {
            sendError(jni, cmdHandle, "not_configured", "Firebase Auth is not configured");
            return;
        }
        if (isBlank(serverAuthCode)) {
            sendError(jni, cmdHandle, "missing_server_auth_code", "Missing Play Games server auth code");
            return;
        }
        AuthCredential credential = PlayGamesAuthProvider.getCredential(serverAuthCode);
        auth.signInWithCredential(credential).addOnCompleteListener(activity, task -> {
            if (!task.isSuccessful()) {
                sendTaskError(jni, cmdHandle, "sign_in_failed", task);
                return;
            }
            sendCurrentUserToken(jni, cmdHandle, true);
        });
    }

    public void refreshIdToken(boolean forceRefresh, FirebaseAuthJNI jni, long cmdHandle) {
        lastStage = "refresh_id_token";
        refreshRequestCount += 1;
        if (auth == null) {
            sendError(jni, cmdHandle, "not_configured", "Firebase Auth is not configured");
            return;
        }
        sendCurrentUserToken(jni, cmdHandle, forceRefresh);
    }

    public void signOut() {
        lastStage = "sign_out";
        lastError = "";
        if (auth != null) {
            auth.signOut();
        }
    }

    public String getDebugState() {
        try {
            JSONObject json = new JSONObject();
            FirebaseUser user = auth != null ? auth.getCurrentUser() : null;
            json.put("configured", auth != null);
            json.put("signed_in", user != null);
            json.put("uid", user != null ? user.getUid() : "");
            json.put("stage", lastStage);
            json.put("error", lastError);
            json.put("sign_in_requests", signInRequestCount);
            json.put("refresh_requests", refreshRequestCount);
            json.put("token_requests", tokenRequestCount);
            json.put("token_success", tokenSuccessCount);
            json.put("token_error", tokenErrorCount);
            json.put("dispatch_ok", dispatchOkCount);
            json.put("dispatch_error", dispatchErrorCount);
            json.put("dispatch_exception", dispatchExceptionCount);
            return json.toString();
        } catch (Exception exception) {
            return "{\"configured\":false,\"signed_in\":false,\"stage\":\"debug_failed\"}";
        }
    }

    private void sendCurrentUserToken(FirebaseAuthJNI jni, long cmdHandle, boolean forceRefresh) {
        lastStage = forceRefresh ? "token_request_forced" : "token_request";
        tokenRequestCount += 1;
        FirebaseUser user = auth.getCurrentUser();
        if (user == null) {
            tokenErrorCount += 1;
            sendError(jni, cmdHandle, "missing_current_user", "Firebase has no signed-in user");
            return;
        }
        user.getIdToken(forceRefresh).addOnCompleteListener(activity, tokenTask -> {
            if (!tokenTask.isSuccessful()) {
                lastStage = "token_failed";
                tokenErrorCount += 1;
                sendTaskError(jni, cmdHandle, "token_failed", tokenTask);
                return;
            }
            GetTokenResult tokenResult = tokenTask.getResult();
            String token = tokenResult != null ? tokenResult.getToken() : "";
            if (isBlank(token)) {
                lastStage = "token_missing";
                tokenErrorCount += 1;
                sendError(jni, cmdHandle, "missing_id_token", "Firebase returned an empty ID token");
                return;
            }
            try {
                long nowSeconds = System.currentTimeMillis() / 1000L;
                long expirySeconds = tokenResult.getExpirationTimestamp() / 1000L;
                long expiresIn = Math.max(60L, expirySeconds - nowSeconds);
                JSONObject json = new JSONObject();
                json.put("uid", user.getUid());
                json.put("localId", user.getUid());
                json.put("idToken", token);
                json.put("expiresIn", expiresIn);
                json.put("provider", "google");
                json.put("native_firebase_auth", true);
                lastError = "";
                lastStage = "dispatch_ok";
                tokenSuccessCount += 1;
                dispatchOkCount += 1;
                jni.onAuthResult(FirebaseAuthJNI.RESULT_OK, json.toString(), cmdHandle);
            } catch (Exception exception) {
                lastStage = "dispatch_ok_exception";
                tokenErrorCount += 1;
                dispatchExceptionCount += 1;
                sendError(jni, cmdHandle, "session_json_failed", safeMessage(exception));
            }
        });
    }

    private void sendTaskError(FirebaseAuthJNI jni, long cmdHandle, String code, Task<?> task) {
        Exception exception = task != null ? task.getException() : null;
        sendError(jni, cmdHandle, code, safeMessage(exception));
    }

    private void sendError(FirebaseAuthJNI jni, long cmdHandle, String code, String message) {
        lastError = message;
        lastStage = "dispatch_error_" + code;
        dispatchErrorCount += 1;
        try {
            JSONObject json = new JSONObject();
            json.put("code", code);
            json.put("message", message);
            json.put("stage", lastStage);
            jni.onAuthResult(FirebaseAuthJNI.RESULT_ERROR, json.toString(), cmdHandle);
        } catch (Exception exception) {
            dispatchExceptionCount += 1;
            jni.onAuthResult(FirebaseAuthJNI.RESULT_ERROR, "{\"code\":\"native_error\",\"message\":\"Firebase Auth native error\"}", cmdHandle);
        }
    }

    private static boolean isBlank(String value) {
        return value == null || value.trim().isEmpty();
    }

    private static String safeMessage(Exception exception) {
        if (exception == null) {
            return "";
        }
        String message = exception.getMessage();
        if (message == null || message.trim().isEmpty()) {
            return exception.getClass().getSimpleName();
        }
        return message;
    }
}
