package com.bharatvoiceos.bharat_voice_os

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.graphics.Color
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Build
import android.os.IBinder
import android.util.DisplayMetrics
import android.util.TypedValue
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import android.view.WindowManager
import android.animation.ValueAnimator
import android.view.animation.OvershootInterpolator
import androidx.core.app.NotificationCompat

class FloatingBubbleService : Service() {
    private lateinit var windowManager: WindowManager
    
    // Bubble mode views
    private lateinit var bubbleView: FrameLayout
    private lateinit var bubbleIcon: ImageView
    private lateinit var bubbleParams: WindowManager.LayoutParams
    
    // Pill mode views
    private lateinit var pillView: LinearLayout
    private lateinit var pillParams: WindowManager.LayoutParams
    private lateinit var statusText: TextView
    private lateinit var stopButton: FrameLayout
    private lateinit var pauseButton: FrameLayout
    private lateinit var askButton: FrameLayout
    
    // Remove target view (trash zone)
    private lateinit var removeTargetView: FrameLayout
    private lateinit var removeTargetParams: WindowManager.LayoutParams
    private var isRemoveTargetVisible = false
    
    private var screenWidth = 0
    private var screenHeight = 0
    
    // State
    private var currentMode = "bubble"  // "bubble" or "pill"
    private var currentState = "idle"   // idle, listening, working, paused
    private var isPillVisible = false
    private var isBubbleVisible = false

    companion object {
        var instance: FloatingBubbleService? = null
        var isRunning = false

        fun updateState(state: String) {
            instance?.updateState(state)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        isRunning = true
        
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        (getSystemService(WINDOW_SERVICE) as WindowManager).defaultDisplay.getMetrics(metrics)
        screenWidth = metrics.widthPixels
        screenHeight = metrics.heightPixels
        
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        
        startForegroundServiceNotification()
        createRemoveTargetView()
        createBubbleView()
        createPillView()
        
        // Don't auto-show - let Flutter control the state via updateState()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // Check if an initial state was passed
        val initialState = intent?.getStringExtra("initialState")
        if (initialState != null) {
            updateState(initialState)
        } else if (!isBubbleVisible && !isPillVisible) {
            // Default to bubble mode if nothing is visible
            showBubble()
        }
        return START_STICKY
    }

    private fun startForegroundServiceNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = "floating_bubble_channel"
            val channel = NotificationChannel(
                channelId,
                "Bharat Voice Agent",
                NotificationManager.IMPORTANCE_LOW
            )
            getSystemService(NotificationManager::class.java).createNotificationChannel(channel)

            val notification: Notification = NotificationCompat.Builder(this, channelId)
                .setContentTitle("Bharat Voice Agent")
                .setContentText("Tap to interact")
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setOngoing(true)
                .build()

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(2, notification, android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(2, notification)
            }
        }
    }

    private fun dpToPx(dp: Int): Int {
        return TypedValue.applyDimension(
            TypedValue.COMPLEX_UNIT_DIP,
            dp.toFloat(),
            resources.displayMetrics
        ).toInt()
    }

    // ═══════════════════════════════════════════════════════════════
    // REMOVE TARGET (trash zone at bottom)
    // ═══════════════════════════════════════════════════════════════

    private fun createRemoveTargetView() {
        removeTargetView = FrameLayout(this)
        
        // Background circle with trash icon
        val bg = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.parseColor("#E0F44336"))
            setStroke(dpToPx(3), Color.WHITE)
        }
        removeTargetView.background = bg
        
        // Trash icon (X)
        val trashIcon = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_menu_close_clear_cancel)
            setColorFilter(Color.WHITE)
        }
        val iconParams = FrameLayout.LayoutParams(dpToPx(32), dpToPx(32)).apply {
            gravity = Gravity.CENTER
        }
        removeTargetView.addView(trashIcon, iconParams)
        
        // Layout params - positioned at bottom center
        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        removeTargetParams = WindowManager.LayoutParams(
            dpToPx(72), dpToPx(72),
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or 
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or 
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        removeTargetParams.gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
        removeTargetParams.y = dpToPx(80)
    }

    private fun showRemoveTarget() {
        if (!isRemoveTargetVisible) {
            isRemoveTargetVisible = true
            // Animate in with scale
            removeTargetView.alpha = 0f
            removeTargetView.scaleX = 0.5f
            removeTargetView.scaleY = 0.5f
            windowManager.addView(removeTargetView, removeTargetParams)
            removeTargetView.animate()
                .alpha(1f)
                .scaleX(1f)
                .scaleY(1f)
                .setDuration(200)
                .start()
        }
    }

    private fun hideRemoveTarget() {
        if (isRemoveTargetVisible) {
            isRemoveTargetVisible = false
            removeTargetView.animate()
                .alpha(0f)
                .scaleX(0.5f)
                .scaleY(0.5f)
                .setDuration(150)
                .withEndAction {
                    try { windowManager.removeView(removeTargetView) } catch (_: Exception) {}
                }
                .start()
        }
    }

    private fun isOverRemoveTarget(bubbleX: Int, bubbleY: Int): Boolean {
        val bubbleCenterX = bubbleX + dpToPx(28)
        val bubbleCenterY = bubbleY + dpToPx(28)
        
        // Remove target is at bottom center
        val targetCenterX = screenWidth / 2
        val targetCenterY = screenHeight - dpToPx(80) - dpToPx(36) // 80dp from bottom + half of target size
        
        val distance = Math.sqrt(
            Math.pow((bubbleCenterX - targetCenterX).toDouble(), 2.0) +
            Math.pow((bubbleCenterY - targetCenterY).toDouble(), 2.0)
        )
        
        return distance < dpToPx(60) // Within 60dp radius
    }

    private fun updateRemoveTargetHighlight(isHovering: Boolean) {
        val bg = removeTargetView.background as? GradientDrawable ?: return
        if (isHovering) {
            bg.setColor(Color.parseColor("#FFF44336"))
            removeTargetView.scaleX = 1.2f
            removeTargetView.scaleY = 1.2f
        } else {
            bg.setColor(Color.parseColor("#E0F44336"))
            removeTargetView.scaleX = 1f
            removeTargetView.scaleY = 1f
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // BUBBLE MODE (compact circle)
    // ═══════════════════════════════════════════════════════════════

    private fun createBubbleView() {
        bubbleView = FrameLayout(this)
        
        // Background circle
        val bg = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.parseColor("#1E88E5"))
            setStroke(dpToPx(2), Color.WHITE)
        }
        bubbleView.background = bg
        
        // Icon
        bubbleIcon = ImageView(this).apply {
            setImageResource(android.R.drawable.ic_btn_speak_now)
            setColorFilter(Color.WHITE)
        }
        val iconParams = FrameLayout.LayoutParams(dpToPx(28), dpToPx(28)).apply {
            gravity = Gravity.CENTER
        }
        bubbleView.addView(bubbleIcon, iconParams)
        
        // Layout params
        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        bubbleParams = WindowManager.LayoutParams(
            dpToPx(56), dpToPx(56),
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        bubbleParams.gravity = Gravity.TOP or Gravity.START
        bubbleParams.x = 0
        bubbleParams.y = screenHeight / 3
        
        setupBubbleTouchListener()
    }

    private fun setupBubbleTouchListener() {
        bubbleView.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f
            private var isDragging = false
            private var isHoveringOverRemove = false

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = bubbleParams.x
                        initialY = bubbleParams.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        isDragging = false
                        isHoveringOverRemove = false
                        return true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - initialTouchX
                        val dy = event.rawY - initialTouchY
                        if (Math.abs(dx) > 10 || Math.abs(dy) > 10) {
                            if (!isDragging) {
                                isDragging = true
                                showRemoveTarget()
                            }
                        }
                        if (isDragging) {
                            bubbleParams.x = initialX + dx.toInt()
                            bubbleParams.y = initialY + dy.toInt()
                            if (isBubbleVisible) {
                                windowManager.updateViewLayout(bubbleView, bubbleParams)
                            }
                            
                            // Check if hovering over remove target
                            val hovering = isOverRemoveTarget(bubbleParams.x, bubbleParams.y)
                            if (hovering != isHoveringOverRemove) {
                                isHoveringOverRemove = hovering
                                updateRemoveTargetHighlight(hovering)
                            }
                        }
                        return true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (!isDragging) {
                            // TAP: Toggle listening
                            onBubbleTapped()
                        } else {
                            // Check if dropped on remove target
                            if (isOverRemoveTarget(bubbleParams.x, bubbleParams.y)) {
                                hideRemoveTarget()
                                // Stop the service
                                val intent = Intent("COM.BHARATVOICEOS.BUBBLE_ACTION")
                                intent.putExtra("action", "stop")
                                sendBroadcast(intent)
                                stopSelf()
                                return true
                            }
                            
                            hideRemoveTarget()
                            
                            // Snap to edge
                            val centerX = bubbleParams.x + dpToPx(28)
                            bubbleParams.x = if (centerX < screenWidth / 2) 0 else screenWidth - dpToPx(56)
                            if (isBubbleVisible) {
                                windowManager.updateViewLayout(bubbleView, bubbleParams)
                            }
                        }
                        return true
                    }
                    MotionEvent.ACTION_CANCEL -> {
                        hideRemoveTarget()
                        return true
                    }
                }
                return false
            }
        })
    }

    private fun onBubbleTapped() {
        when (currentState) {
            "idle" -> {
                // Start listening
                updateState("listening")
                val intent = Intent("COM.BHARATVOICEOS.BUBBLE_ACTION")
                intent.putExtra("action", "start_listening")
                sendBroadcast(intent)
            }
            "listening" -> {
                // Stop/pause listening
                updateState("idle")
                val intent = Intent("COM.BHARATVOICEOS.BUBBLE_ACTION")
                intent.putExtra("action", "stop_listening")
                sendBroadcast(intent)
            }
        }
    }

    private fun updateBubbleAppearance() {
        val bg = bubbleView.background as? GradientDrawable ?: return
        
        when (currentState) {
            "idle" -> {
                bg.setColor(Color.parseColor("#1E88E5"))  // Blue
                bubbleIcon.setImageResource(android.R.drawable.ic_btn_speak_now)
            }
            "listening" -> {
                bg.setColor(Color.parseColor("#4CAF50"))  // Green
                bubbleIcon.setImageResource(android.R.drawable.ic_media_pause)
            }
        }
    }

    private fun showBubble() {
        if (!isBubbleVisible) {
            isBubbleVisible = true
            windowManager.addView(bubbleView, bubbleParams)
        }
        updateBubbleAppearance()
    }

    private fun hideBubble() {
        if (isBubbleVisible) {
            isBubbleVisible = false
            try { windowManager.removeView(bubbleView) } catch (_: Exception) {}
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // PILL MODE (expanded control bar for agent)
    // ═══════════════════════════════════════════════════════════════

    private fun createPillView() {
        pillView = LinearLayout(this).apply {
            orientation = LinearLayout.HORIZONTAL
            gravity = Gravity.CENTER_VERTICAL
            setPadding(dpToPx(12), dpToPx(8), dpToPx(12), dpToPx(8))
        }

        val pillBackground = GradientDrawable().apply {
            shape = GradientDrawable.RECTANGLE
            cornerRadius = dpToPx(28).toFloat()
            setColor(Color.parseColor("#E8212121"))
            setStroke(dpToPx(2), Color.parseColor("#3DFFFFFF"))
        }
        pillView.background = pillBackground

        // Status dot
        val statusDot = View(this).apply {
            val dotBg = GradientDrawable().apply {
                shape = GradientDrawable.OVAL
                setColor(Color.parseColor("#FB8C00"))
            }
            background = dotBg
            tag = "statusDot"
        }
        pillView.addView(statusDot, LinearLayout.LayoutParams(dpToPx(8), dpToPx(8)).apply {
            marginEnd = dpToPx(8)
        })

        // Status text
        statusText = TextView(this).apply {
            text = "Working..."
            setTextColor(Color.WHITE)
            textSize = 12f
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        }
        pillView.addView(statusText, LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.WRAP_CONTENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { marginEnd = dpToPx(12) })

        // Divider
        val divider = View(this).apply {
            setBackgroundColor(Color.parseColor("#4DFFFFFF"))
        }
        pillView.addView(divider, LinearLayout.LayoutParams(dpToPx(1), dpToPx(24)).apply {
            marginEnd = dpToPx(8)
        })

        // Ask button
        askButton = createPillButton(android.R.drawable.ic_btn_speak_now, "#2196F3") {
            onPillAskTapped()
        }
        pillView.addView(askButton, createPillButtonParams())

        // Pause button
        pauseButton = createPillButton(android.R.drawable.ic_media_pause, "#FF9800") {
            onPillPauseTapped()
        }
        pillView.addView(pauseButton, createPillButtonParams())

        // Stop button
        stopButton = createPillButton(android.R.drawable.ic_menu_close_clear_cancel, "#F44336") {
            onPillStopTapped()
        }
        pillView.addView(stopButton, createPillButtonParams())

        // Layout params
        val layoutFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

        pillParams = WindowManager.LayoutParams(
            WindowManager.LayoutParams.WRAP_CONTENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            layoutFlag,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT
        )
        // Position pill on RIGHT side at middle height - all taps are at center (x=540)
        // so right side (x=900+) is safe and visible for demo
        pillParams.gravity = Gravity.TOP or Gravity.START
        pillParams.x = screenWidth - dpToPx(180)  // Right side, ~180dp from right edge for pill width
        pillParams.y = screenHeight / 2 - dpToPx(25)  // Vertically centered
        
        setupPillTouchListener()
    }

    private fun createPillButton(iconRes: Int, bgColor: String, onClick: () -> Unit): FrameLayout {
        val button = FrameLayout(this)
        val bg = GradientDrawable().apply {
            shape = GradientDrawable.OVAL
            setColor(Color.parseColor(bgColor))
        }
        button.background = bg
        
        val icon = ImageView(this).apply {
            setImageResource(iconRes)
            setColorFilter(Color.WHITE)
        }
        button.addView(icon, FrameLayout.LayoutParams(dpToPx(18), dpToPx(18)).apply {
            gravity = Gravity.CENTER
        })
        
        button.setOnClickListener { onClick() }
        return button
    }

    private fun createPillButtonParams(): LinearLayout.LayoutParams {
        return LinearLayout.LayoutParams(dpToPx(36), dpToPx(36)).apply {
            marginStart = dpToPx(4)
            marginEnd = dpToPx(4)
        }
    }

    private fun setupPillTouchListener() {
        pillView.setOnTouchListener(object : View.OnTouchListener {
            private var initialX = 0
            private var initialY = 0
            private var initialTouchX = 0f
            private var initialTouchY = 0f
            private var isDragging = false
            private var isHoveringOverRemove = false

            override fun onTouch(v: View, event: MotionEvent): Boolean {
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = pillParams.x
                        initialY = pillParams.y
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        isDragging = false
                        isHoveringOverRemove = false
                        return false
                    }
                    MotionEvent.ACTION_MOVE -> {
                        val dx = event.rawX - initialTouchX
                        val dy = event.rawY - initialTouchY
                        if (Math.abs(dx) > 15 || Math.abs(dy) > 15) {
                            if (!isDragging) {
                                isDragging = true
                                showRemoveTarget()
                            }
                            pillParams.x = initialX + dx.toInt()
                            pillParams.y = initialY + dy.toInt()
                            if (isPillVisible) {
                                windowManager.updateViewLayout(pillView, pillParams)
                            }
                            
                            // Check if hovering over remove target
                            val pillCenterX = pillParams.x + pillView.width / 2
                            val pillCenterY = pillParams.y + pillView.height / 2
                            val hovering = isOverRemoveTargetForPill(pillCenterX, pillCenterY)
                            if (hovering != isHoveringOverRemove) {
                                isHoveringOverRemove = hovering
                                updateRemoveTargetHighlight(hovering)
                            }
                            return true
                        }
                        return false
                    }
                    MotionEvent.ACTION_UP -> {
                        if (isDragging) {
                            val pillCenterX = pillParams.x + pillView.width / 2
                            val pillCenterY = pillParams.y + pillView.height / 2
                            if (isOverRemoveTargetForPill(pillCenterX, pillCenterY)) {
                                hideRemoveTarget()
                                val intent = Intent("COM.BHARATVOICEOS.BUBBLE_ACTION")
                                intent.putExtra("action", "stop")
                                sendBroadcast(intent)
                                stopSelf()
                                return true
                            }
                            hideRemoveTarget()
                        }
                        return isDragging
                    }
                    MotionEvent.ACTION_CANCEL -> {
                        hideRemoveTarget()
                        return true
                    }
                }
                return false
            }
        })
    }

    private fun isOverRemoveTargetForPill(centerX: Int, centerY: Int): Boolean {
        val targetCenterX = screenWidth / 2
        val targetCenterY = screenHeight - dpToPx(80) - dpToPx(36)
        
        val distance = Math.sqrt(
            Math.pow((centerX - targetCenterX).toDouble(), 2.0) +
            Math.pow((centerY - targetCenterY).toDouble(), 2.0)
        )
        
        return distance < dpToPx(80) // Larger radius for pill
    }

    private fun onPillAskTapped() {
        // Stay in pill mode but show listening state
        currentState = "listening"
        updatePillAppearance()
        val intent = Intent("COM.BHARATVOICEOS.BUBBLE_ACTION")
        intent.putExtra("action", "ask")
        sendBroadcast(intent)
    }

    private fun onPillPauseTapped() {
        if (currentState == "paused") {
            updateState("working")
            val intent = Intent("COM.BHARATVOICEOS.BUBBLE_ACTION")
            intent.putExtra("action", "resume")
            sendBroadcast(intent)
        } else {
            updateState("paused")
            val intent = Intent("COM.BHARATVOICEOS.BUBBLE_ACTION")
            intent.putExtra("action", "pause")
            sendBroadcast(intent)
        }
    }

    private fun onPillStopTapped() {
        val intent = Intent("COM.BHARATVOICEOS.BUBBLE_ACTION")
        intent.putExtra("action", "stop")
        sendBroadcast(intent)
        stopSelf()
    }

    private fun updatePillAppearance() {
        try {
            val statusDot = pillView.findViewWithTag<View>("statusDot")
            val dotBg = statusDot?.background as? GradientDrawable
            val pauseIcon = (pauseButton.getChildAt(0) as? ImageView)
            val pauseBg = pauseButton.background as? GradientDrawable

            when (currentState) {
                "working" -> {
                    statusText.text = "Working..."
                    dotBg?.setColor(Color.parseColor("#FB8C00"))
                    pauseIcon?.setImageResource(android.R.drawable.ic_media_pause)
                    pauseBg?.setColor(Color.parseColor("#FF9800"))
                }
                "paused" -> {
                    statusText.text = "Paused"
                    dotBg?.setColor(Color.parseColor("#9E9E9E"))
                    pauseIcon?.setImageResource(android.R.drawable.ic_media_play)
                    pauseBg?.setColor(Color.parseColor("#4CAF50"))
                }
                "listening" -> {
                    statusText.text = "Listening..."
                    dotBg?.setColor(Color.parseColor("#4CAF50"))
                }
            }
        } catch (_: Exception) {}
    }

    private fun showPill() {
        if (!isPillVisible) {
            isPillVisible = true
            windowManager.addView(pillView, pillParams)
        }
        updatePillAppearance()
    }

    private fun hidePill() {
        if (isPillVisible) {
            isPillVisible = false
            try { windowManager.removeView(pillView) } catch (_: Exception) {}
        }
    }

    // ═══════════════════════════════════════════════════════════════
    // STATE MANAGEMENT
    // ═══════════════════════════════════════════════════════════════

    fun updateState(state: String) {
        currentState = state
        
        when (state) {
            "idle" -> {
                // Bubble mode (idle)
                if (currentMode != "bubble") {
                    currentMode = "bubble"
                    hidePill()
                    showBubble()
                }
                updateBubbleAppearance()
            }
            "listening" -> {
                // If already in pill mode, stay in pill but update appearance
                // If in bubble mode, stay in bubble but update appearance
                if (currentMode == "pill") {
                    updatePillAppearance()
                } else {
                    updateBubbleAppearance()
                }
            }
            "working", "paused" -> {
                // Pill mode
                if (currentMode != "pill") {
                    currentMode = "pill"
                    hideBubble()
                    showPill()
                }
                updatePillAppearance()
            }
            "answer" -> {
                // Hide overlay, let app show answer sheet
                hidePill()
                hideBubble()
            }
            "hidden" -> {
                hidePill()
                hideBubble()
            }
        }
    }

    fun switchToPillMode() {
        currentMode = "pill"
        currentState = "working"
        hideBubble()
        showPill()
    }

    fun switchToBubbleMode() {
        currentMode = "bubble"
        currentState = "idle"
        hidePill()
        showBubble()
    }

    // Track previous visibility state for restore
    private var wasVisible = false
    private var previousMode = "bubble"

    /**
     * Temporarily hide/show overlay to avoid blocking taps and screenshots.
     * Call setOverlayVisibility(false) before gestures, then setOverlayVisibility(true) after.
     */
    fun setOverlayVisibility(visible: Boolean) {
        if (!visible) {
            // Save current state and hide
            wasVisible = isPillVisible || isBubbleVisible
            previousMode = currentMode
            if (isPillVisible) hidePill()
            if (isBubbleVisible) hideBubble()
        } else {
            // Restore previous state
            if (wasVisible) {
                if (previousMode == "pill") {
                    showPill()
                } else {
                    showBubble()
                }
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        hideBubble()
        hidePill()
        if (isRemoveTargetVisible) {
            try { windowManager.removeView(removeTargetView) } catch (_: Exception) {}
            isRemoveTargetVisible = false
        }
        instance = null
        isRunning = false
    }
}
