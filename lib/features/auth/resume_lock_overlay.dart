// The resume-lock biometric overlay was removed at the user's request — it
// popped up on every app resume (including after the image picker / system
// dialogs), which was intrusive. Biometrics now only gate cold start (handled
// by AuthController + the sign-in screen).
