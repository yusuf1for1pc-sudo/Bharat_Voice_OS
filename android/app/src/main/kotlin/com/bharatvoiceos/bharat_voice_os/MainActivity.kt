package com.bharatvoiceos.bharat_voice_os

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.PowerManager

class MainActivity : FlutterActivity() {
    private val ACCESSIBILITY_CHANNEL = "bharat_voice_os/accessibility"
    private val SCREENSHOT_CHANNEL = "bharat_voice_os/screenshot"
    private val BUBBLE_CHANNEL = "bharat_voice_os/bubble"
    private val BUBBLE_EVENTS_CHANNEL = "bharat_voice_os/bubble_events"
    
    private var bubbleEventsChannel: MethodChannel? = null
    private var wakeLock: PowerManager.WakeLock? = null

    // Handle legacy bubble tap (backward compatibility)
    private val bubbleTapReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "COM.BHARATVOICEOS.BUBBLE_TAP") {
                bubbleEventsChannel?.invokeMethod("onBubbleTap", null)
                bringAppToFront()
            }
        }
    }

    // Handle bubble/pill button actions
    private val bubbleActionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == "COM.BHARATVOICEOS.BUBBLE_ACTION") {
                val action = intent.getStringExtra("action") ?: return
                when (action) {
                    "start_listening" -> {
                        // Bubble tapped in idle mode - start listening
                        bubbleEventsChannel?.invokeMethod("onBubbleStartListening", null)
                        bringAppToFront()
                    }
                    "stop_listening" -> {
                        // Bubble tapped in listening mode - stop
                        bubbleEventsChannel?.invokeMethod("onBubbleStopListening", null)
                    }
                    "stop" -> {
                        bubbleEventsChannel?.invokeMethod("onBubbleStop", null)
                    }
                    "pause" -> {
                        bubbleEventsChannel?.invokeMethod("onBubblePause", null)
                    }
                    "resume" -> {
                        bubbleEventsChannel?.invokeMethod("onBubbleResume", null)
                    }
                    "ask" -> {
                        bubbleEventsChannel?.invokeMethod("onBubbleAsk", null)
                        bringAppToFront()
                    }
                }
            }
        }
    }

    private fun bringAppToFront() {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        launchIntent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
        startActivity(launchIntent)
    }

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(bubbleTapReceiver, IntentFilter("COM.BHARATVOICEOS.BUBBLE_TAP"), Context.RECEIVER_NOT_EXPORTED)
            registerReceiver(bubbleActionReceiver, IntentFilter("COM.BHARATVOICEOS.BUBBLE_ACTION"), Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(bubbleTapReceiver, IntentFilter("COM.BHARATVOICEOS.BUBBLE_TAP"))
            registerReceiver(bubbleActionReceiver, IntentFilter("COM.BHARATVOICEOS.BUBBLE_ACTION"))
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try { unregisterReceiver(bubbleTapReceiver) } catch (_: Exception) {}
        try { unregisterReceiver(bubbleActionReceiver) } catch (_: Exception) {}
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ── Accessibility MethodChannel ──
        // Handles: executeAction, executeGesture, openApp, isAccessibilityEnabled
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACCESSIBILITY_CHANNEL)
            .setMethodCallHandler { call, result ->
                val service = BharatAccessibilityService.instance

                when (call.method) {
                    "executeAction" -> {
                        val actionName = call.argument<String>("action") ?: ""
                        val params = call.argument<Map<String, Any>>("params") ?: emptyMap()

                        if (service != null) {
                            val success = service.executeAction(actionName, params)
                            result.success(success)
                        } else {
                            result.error(
                                "SERVICE_NOT_RUNNING",
                                "Accessibility service is not running. Please enable it in Settings.",
                                null
                            )
                        }
                    }

                    "executeGesture" -> {
                        val params = call.argument<Map<String, Any>>("params") ?: emptyMap()

                        if (service != null) {
                            val success = service.executeGesture(params)
                            result.success(success)
                        } else {
                            result.error(
                                "SERVICE_NOT_RUNNING",
                                "Accessibility service is not running.",
                                null
                            )
                        }
                    }

                    "openApp" -> {
                        val packageName = call.argument<String>("package") ?: ""

                        if (service != null) {
                            val success = service.openApp(packageName)
                            result.success(success)
                        } else {
                            // Fallback: launch from activity context
                            try {
                                val intent = packageManager.getLaunchIntentForPackage(packageName)
                                if (intent != null) {
                                    intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                                    startActivity(intent)
                                    result.success(true)
                                } else {
                                    result.success(false)
                                }
                            } catch (e: Exception) {
                                result.error("LAUNCH_ERROR", e.message, null)
                            }
                        }
                    }

                    // Note: bookOlaCab removed - cab booking now uses the real vision agent

                    "sendWhatsApp" -> {
                        val params = call.arguments as? Map<String, Any> ?: emptyMap()
                        if (service != null) {
                            result.success(service.sendWhatsApp(params))
                        } else {
                            result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running.", null)
                        }
                    }

                    "checkPmKisan" -> {
                        val params = call.arguments as? Map<String, Any> ?: emptyMap()
                        if (service != null) {
                            result.success(service.checkPmKisan(params))
                        } else {
                            result.error("SERVICE_NOT_RUNNING", "Accessibility service is not running.", null)
                        }
                    }

                    "isAccessibilityEnabled" -> {
                        result.success(service != null)
                    }

                    "openAccessibilitySettings" -> {
                        val intent = Intent(android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(intent)
                        result.success(true)
                    }

                    "bringToFront" -> {
                        val intent = packageManager.getLaunchIntentForPackage(packageName)
                        intent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT)
                        startActivity(intent)
                        result.success(true)
                    }

                    "moveToBackground" -> {
                        moveTaskToBack(true)
                        result.success(true)
                    }

                    "acquireWakeLock" -> {
                        try {
                            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                            wakeLock = pm.newWakeLock(
                                PowerManager.PARTIAL_WAKE_LOCK,
                                "BharatVoiceOS:AgentWakeLock"
                            )
                            wakeLock?.acquire(10 * 60 * 1000L) // 10 min max
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("WAKELOCK", e.message, null)
                        }
                    }

                    "releaseWakeLock" -> {
                        try {
                            wakeLock?.let { if (it.isHeld) it.release() }
                            wakeLock = null
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(true)
                        }
                    }

                    else -> {
                        result.notImplemented()
                    }
                }
            }

        // ── Screenshot MethodChannel ──
        // Handles: captureScreen
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREENSHOT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "captureScreen" -> {
                        val service = BharatAccessibilityService.instance
                        if (service != null) {
                            service.captureScreen { base64 ->
                                if (base64 != null) {
                                    result.success(base64)
                                } else {
                                    result.error(
                                        "SCREENSHOT_FAILED",
                                        "Could not capture screen.",
                                        null
                                    )
                                }
                            }
                        } else {
                            result.error(
                                "SERVICE_NOT_RUNNING",
                                "Accessibility service is not running. Screenshots require accessibility access.",
                                null
                            )
                        }
                    }

                    else -> {
                        result.notImplemented()
                    }
                }
            }

        // ── Bubble MethodChannel (Flutter → Native: commands) ──
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BUBBLE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "showBubble" -> {
                        val initialState = call.argument<String>("state") ?: "idle"
                        val intent = Intent(this, FloatingBubbleService::class.java)
                        intent.putExtra("initialState", initialState)
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "showPill" -> {
                        // Directly show pill mode for agent
                        val intent = Intent(this, FloatingBubbleService::class.java)
                        intent.putExtra("initialState", "working")
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "hideBubble" -> {
                        val intent = Intent(this, FloatingBubbleService::class.java)
                        stopService(intent)
                        result.success(true)
                    }
                    "updateBubbleState" -> {
                        val state = call.argument<String>("state") ?: "idle"
                        FloatingBubbleService.updateState(state)
                        result.success(true)
                    }
                    "setOverlayVisibility" -> {
                        val visible = call.argument<Boolean>("visible") ?: true
                        FloatingBubbleService.instance?.setOverlayVisibility(visible)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── Bubble Events Channel (Native → Flutter: events like onBubbleTap) ──
        bubbleEventsChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BUBBLE_EVENTS_CHANNEL)
        // This channel is used to send events TO Flutter, not to receive from Flutter.
        // Flutter sets its own handler on this channel via setMethodCallHandler.
    }
}
