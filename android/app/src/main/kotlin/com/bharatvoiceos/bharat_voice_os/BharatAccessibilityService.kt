package com.bharatvoiceos.bharat_voice_os

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Path
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.util.Log
import android.view.Display
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.io.ByteArrayOutputStream

class BharatAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "BharatAccessibility"
        var instance: BharatAccessibilityService? = null
    }

    private val mainHandler = Handler(Looper.getMainLooper())

    // ── Demo Pacing Constants ──
    object DemoPacing {
        const val APP_OPEN_WAIT = 2500L
        const val FIELD_FIND_WAIT = 800L
        const val CHAR_TYPE_DELAY = 80L
        const val AFTER_TYPE_WAIT = 600L
        const val SEARCH_RESULT_WAIT = 1200L
        const val RESULT_SELECT_WAIT = 700L
        const val CONFIRM_BUTTON_WAIT = 1000L
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        Log.d(TAG, "Accessibility service connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // React to accessibility events if needed
    }

    override fun onInterrupt() {
        Log.d(TAG, "Accessibility service interrupted")
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }

    // ═══════════════════════════════════════════════════════════════
    // SCREENSHOT — Android 11+ takeScreenshot API
    // ═══════════════════════════════════════════════════════════════

    fun captureScreen(callback: (String?) -> Unit) {
        try {
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshot: ScreenshotResult) {
                        try {
                            val bitmap = Bitmap.wrapHardwareBuffer(
                                screenshot.hardwareBuffer,
                                screenshot.colorSpace
                            )
                            if (bitmap != null) {
                                val stream = ByteArrayOutputStream()
                                // Use software bitmap for JPEG compression
                                val swBitmap = bitmap.copy(Bitmap.Config.ARGB_8888, false)
                                swBitmap.compress(Bitmap.CompressFormat.JPEG, 70, stream)
                                val base64 = Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)
                                swBitmap.recycle()
                                bitmap.recycle()
                                screenshot.hardwareBuffer.close()
                                callback(base64)
                            } else {
                                Log.e(TAG, "captureScreen: bitmap was null")
                                callback(null)
                            }
                        } catch (e: Exception) {
                            Log.e(TAG, "captureScreen processing error", e)
                            callback(null)
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        Log.e(TAG, "captureScreen failed with errorCode: $errorCode")
                        callback(null)
                    }
                }
            )
        } catch (e: Exception) {
            Log.e(TAG, "captureScreen exception", e)
            callback(null)
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // GESTURE EXECUTION — tap, type, scroll, back
    // ═══════════════════════════════════════════════════════════════

    fun executeGesture(params: Map<String, Any>): Boolean {
        val action = params["action"] as? String ?: return false
        return when (action) {
            "tap" -> performTap(params)
            "type" -> performType(params)
            "scroll" -> performScroll(params)
            "swipe" -> performSwipe(params)
            "back" -> performBack()
            else -> {
                Log.w(TAG, "Unknown gesture action: $action")
                false
            }
        }
    }

    private fun performTap(params: Map<String, Any>): Boolean {
        try {
            val x = (params["x"] as? Number)?.toFloat() ?: return false
            val y = (params["y"] as? Number)?.toFloat() ?: return false

            val path = Path()
            path.moveTo(x, y)

            val stroke = GestureDescription.StrokeDescription(path, 0, 100)
            val gesture = GestureDescription.Builder().addStroke(stroke).build()

            dispatchGesture(gesture, object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    Log.d(TAG, "Tap completed at ($x, $y)")
                }
                override fun onCancelled(gestureDescription: GestureDescription?) {
                    Log.w(TAG, "Tap cancelled at ($x, $y)")
                }
            }, null)
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Tap error", e)
            return false
        }
    }

    private fun performType(params: Map<String, Any>): Boolean {
        try {
            val text = params["text"] as? String ?: return false
            val root = rootInActiveWindow ?: return false

            // Find focused input field
            val focusedNode = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            if (focusedNode != null && trySetText(focusedNode, text)) {
                focusedNode.recycle()
                Log.d(TAG, "Typed (focused): $text")
                return true
            }
            focusedNode?.recycle()

            // Fallback 1: find any EditText and set text
            val editTexts = findEditTexts(root)
            for (node in editTexts) {
                node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                Thread.sleep(100) // Brief delay for focus
                if (trySetText(node, text)) {
                    node.recycle()
                    Log.d(TAG, "Typed (EditText): $text")
                    return true
                }
                node.recycle()
            }

            // Fallback 2: Use clipboard paste (most reliable for stubborn apps)
            val clipboardTyped = typeViaClipboard(text)
            if (clipboardTyped) {
                Log.d(TAG, "Typed (clipboard): $text")
                return true
            }

            Log.w(TAG, "No input field found for typing")
            return false
        } catch (e: Exception) {
            Log.e(TAG, "Type error", e)
            return false
        }
    }

    private fun trySetText(node: AccessibilityNodeInfo, text: String): Boolean {
        val args = Bundle()
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    private fun typeViaClipboard(text: String): Boolean {
        try {
            // Copy text to clipboard
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            val clip = ClipData.newPlainText("typed_text", text)
            clipboard.setPrimaryClip(clip)
            
            // Find focused node and paste
            val root = rootInActiveWindow ?: return false
            val focusedNode = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            if (focusedNode != null) {
                val result = focusedNode.performAction(AccessibilityNodeInfo.ACTION_PASTE)
                focusedNode.recycle()
                return result
            }
            
            // Try any EditText
            val editTexts = findEditTexts(root)
            for (node in editTexts) {
                node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                Thread.sleep(100)
                val result = node.performAction(AccessibilityNodeInfo.ACTION_PASTE)
                node.recycle()
                if (result) return true
            }
            
            return false
        } catch (e: Exception) {
            Log.e(TAG, "Clipboard type error", e)
            return false
        }
    }

    private fun findEditTexts(node: AccessibilityNodeInfo): List<AccessibilityNodeInfo> {
        val result = mutableListOf<AccessibilityNodeInfo>()
        if (node.className?.contains("EditText") == true) {
            result.add(node)
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            result.addAll(findEditTexts(child))
        }
        return result
    }

    private fun performScroll(params: Map<String, Any>): Boolean {
        try {
            val direction = params["direction"] as? String ?: "down"
            val distance = (params["distance"] as? Number)?.toInt() ?: 500

            val screenWidth = resources.displayMetrics.widthPixels
            val screenHeight = resources.displayMetrics.heightPixels
            val centerX = screenWidth / 2f
            val centerY = screenHeight / 2f

            val path = Path()
            when (direction) {
                "down" -> {
                    path.moveTo(centerX, centerY)
                    path.lineTo(centerX, centerY - distance)
                }
                "up" -> {
                    path.moveTo(centerX, centerY)
                    path.lineTo(centerX, centerY + distance)
                }
                "left" -> {
                    path.moveTo(centerX, centerY)
                    path.lineTo(centerX + distance, centerY)
                }
                "right" -> {
                    path.moveTo(centerX, centerY)
                    path.lineTo(centerX - distance, centerY)
                }
            }

            val stroke = GestureDescription.StrokeDescription(path, 0, 300)
            val gesture = GestureDescription.Builder().addStroke(stroke).build()

            dispatchGesture(gesture, object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    Log.d(TAG, "Scroll $direction completed")
                }
            }, null)
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Scroll error", e)
            return false
        }
    }

    private fun performSwipe(params: Map<String, Any>): Boolean {
        try {
            val x1 = (params["x1"] as? Number)?.toFloat() ?: return false
            val y1 = (params["y1"] as? Number)?.toFloat() ?: return false
            val x2 = (params["x2"] as? Number)?.toFloat() ?: return false
            val y2 = (params["y2"] as? Number)?.toFloat() ?: return false

            val path = Path()
            path.moveTo(x1, y1)
            path.lineTo(x2, y2)

            val stroke = GestureDescription.StrokeDescription(path, 0, 300)
            val gesture = GestureDescription.Builder().addStroke(stroke).build()

            dispatchGesture(gesture, object : GestureResultCallback() {
                override fun onCompleted(gestureDescription: GestureDescription?) {
                    Log.d(TAG, "Swipe completed")
                }
            }, null)
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Swipe error", e)
            return false
        }
    }

    private fun performBack(): Boolean {
        return performGlobalAction(GLOBAL_ACTION_BACK)
    }

    // ═══════════════════════════════════════════════════════════════
    // APP LAUNCHING
    // ═══════════════════════════════════════════════════════════════

    fun openApp(packageName: String): Boolean {
        // Try multiple package variants for common apps
        val variants = mutableListOf(packageName)
        when (packageName) {
            "com.whatsapp" -> variants.addAll(listOf(
                "com.whatsapp.w4b",  // WhatsApp Business
                "com.whatsapp"
            ))
            "com.android.camera2" -> variants.addAll(listOf(
                "com.android.camera",
                "com.google.android.GoogleCamera"
            ))
        }

        for (pkg in variants.distinct()) {
            try {
                val intent = packageManager.getLaunchIntentForPackage(pkg)
                if (intent != null) {
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    startActivity(intent)
                    Log.d(TAG, "Launched app: $pkg")
                    return true
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error launching $pkg", e)
            }
        }

        // Last resort: try opening via package name as URI
        try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                data = android.net.Uri.parse("market://details?id=$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            // Actually, just search for the app by name in installed apps
            val allApps = packageManager.getInstalledApplications(0)
            for (app in allApps) {
                if (app.packageName.contains("whatsapp", ignoreCase = true) && packageName.contains("whatsapp")) {
                    val launchIntent = packageManager.getLaunchIntentForPackage(app.packageName)
                    if (launchIntent != null) {
                        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        startActivity(launchIntent)
                        Log.d(TAG, "Launched app via search: ${app.packageName}")
                        return true
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error in fallback app launch", e)
        }

        Log.w(TAG, "App not installed: $packageName (tried ${variants.size} variants)")
        return false
    }

    // ═══════════════════════════════════════════════════════════════
    // HARDCODED DEMO FLOWS (Phase 2)
    // Note: Cab booking removed - now uses real vision agent
    // ═══════════════════════════════════════════════════════════════

    /**
     * Execute an action based on the action name and parameters.
     * Called from Flutter via MethodChannel.
     */
    fun executeAction(actionName: String, params: Map<String, Any>): Boolean {
        return when (actionName) {
            "send_whatsapp" -> sendWhatsApp(params)
            "check_pm_kisan" -> checkPmKisan(params)
            else -> {
                Log.w(TAG, "Unknown action: $actionName")
                false
            }
        }
    }

    // Note: bookOlaCab and related helper functions removed
    // Cab booking now uses the real vision agent for more reliable automation

    fun sendWhatsApp(params: Map<String, Any>): Boolean {
        try {
            val phone = params["phone"] as? String ?: params["contact"] as? String ?: ""
            val message = params["message"] as? String ?: ""

            // Use WhatsApp deep link — pre-fills contact and message
            val uri = Uri.parse("whatsapp://send?phone=$phone&text=${Uri.encode(message)}")
            val intent = Intent(Intent.ACTION_VIEW, uri)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            intent.setPackage("com.whatsapp")
            startActivity(intent)
            Log.d(TAG, "Opened WhatsApp for $phone")

            // Wait for WhatsApp to open, then find and tap send button
            mainHandler.postDelayed({
                try {
                    val root = rootInActiveWindow ?: return@postDelayed
                    // Try resource ID first
                    val sendButtons = root.findAccessibilityNodeInfosByViewId(
                        "com.whatsapp:id/send"
                    )
                    if (sendButtons.isNotEmpty()) {
                        sendButtons[0].performAction(AccessibilityNodeInfo.ACTION_CLICK)
                        Log.d(TAG, "Tapped WhatsApp send button")
                    } else {
                        // Fallback: find by content description
                        val allNodes = findNodesByContentDescription(root, "Send")
                        allNodes.firstOrNull()?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Error tapping send", e)
                }
            }, 1500)

            return true
        } catch (e: Exception) {
            Log.e(TAG, "Error sending WhatsApp", e)
            return false
        }
    }

    private fun findNodesByContentDescription(
        node: AccessibilityNodeInfo,
        description: String
    ): List<AccessibilityNodeInfo> {
        val result = mutableListOf<AccessibilityNodeInfo>()
        if (node.contentDescription?.toString()?.contains(description, ignoreCase = true) == true) {
            result.add(node)
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            result.addAll(findNodesByContentDescription(child, description))
        }
        return result
    }

    fun checkPmKisan(params: Map<String, Any>): Boolean {
        try {
            val uri = Uri.parse("https://pmkisan.gov.in/BeneficiaryStatus.aspx")
            val intent = Intent(Intent.ACTION_VIEW, uri)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            Log.d(TAG, "Opened PM Kisan portal")
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Error opening PM Kisan", e)
            return false
        }
    }
}
