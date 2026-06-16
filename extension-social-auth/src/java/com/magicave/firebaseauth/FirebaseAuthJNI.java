package com.magicave.firebaseauth;

public class FirebaseAuthJNI {
    public static final int RESULT_OK = 0;
    public static final int RESULT_ERROR = 1;

    public FirebaseAuthJNI() {
    }

    public native void onAuthResult(int responseCode, String payload, long cmdHandle);
}
