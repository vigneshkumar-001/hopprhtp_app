package com.fenizotechnologies.escrow

import android.app.Activity
import android.content.Intent
import android.content.IntentSender
import com.google.android.gms.auth.api.identity.GetPhoneNumberHintIntentRequest
import com.google.android.gms.auth.api.identity.Identity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth.
class MainActivity : FlutterFragmentActivity() {
    private val channelName = "com.fenizotechnologies.escrow/phone_hint"
    private var pendingResult: MethodChannel.Result? = null

    companion object {
        private const val REQUEST_PHONE_NUMBER_HINT = 1001
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method != "choosePhoneNumber") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }

                val request = GetPhoneNumberHintIntentRequest.builder().build()
                Identity.getSignInClient(this)
                    .getPhoneNumberHintIntent(request)
                    .addOnSuccessListener { pendingIntent ->
                        try {
                            pendingResult = result
                            startIntentSenderForResult(
                                pendingIntent.intentSender,
                                REQUEST_PHONE_NUMBER_HINT,
                                null,
                                0,
                                0,
                                0,
                            )
                        } catch (e: IntentSender.SendIntentException) {
                            pendingResult = null
                            result.error("PHONE_HINT_FAILED", e.message, null)
                        }
                    }
                    .addOnFailureListener { e ->
                        result.error("PHONE_HINT_UNAVAILABLE", e.message, null)
                    }
            }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_PHONE_NUMBER_HINT) return

        val result = pendingResult
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data == null) {
            result?.success(null)
            return
        }

        try {
            val phoneNumber = Identity.getSignInClient(this).getPhoneNumberFromIntent(data)
            result?.success(phoneNumber)
        } catch (e: Exception) {
            result?.error("PHONE_HINT_FAILED", e.message, null)
        }
    }
}
