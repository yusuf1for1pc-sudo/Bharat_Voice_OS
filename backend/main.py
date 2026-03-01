import os
import json
import re
import tempfile
import base64
from io import BytesIO
from typing import Optional

import requests
import httpx
from fastapi import (
    FastAPI,
    UploadFile,
    File,
    HTTPException,
    WebSocket,
    WebSocketDisconnect,
)
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv
from google import genai
from google.genai import types
from PIL import Image
from groq import Groq
from sarvamai import AsyncSarvamAI
import asyncio

load_dotenv()

SARVAM_API_KEY = os.getenv("SARVAM_API_KEY")
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "AIzaSyCHP1hBULSgXvRFvsQff-Bptm8jzCl6f28")
GROQ_API_KEY = os.getenv("GROQ_API_KEY")

# Configure Gemini client
gemini_client = None
if GEMINI_API_KEY:
    gemini_client = genai.Client(api_key=GEMINI_API_KEY)

# Configure Groq
groq_client = None
if GROQ_API_KEY and GROQ_API_KEY != "YOUR_GROQ_API_KEY_HERE":
    groq_client = Groq(api_key=GROQ_API_KEY)

app = FastAPI(title="Bharat Voice OS Backend", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ─── Sarvam API helpers ─────────────────────────────────────────────

SARVAM_STT_URL = "https://api.sarvam.ai/speech-to-text"
SARVAM_TTS_URL = "https://api.sarvam.ai/text-to-speech"
SARVAM_TRANSLATE_URL = "https://api.sarvam.ai/translate"

SARVAM_HEADERS = {
    "api-subscription-key": SARVAM_API_KEY or "",
}


@app.websocket("/stt_stream")
async def stt_stream(websocket: WebSocket, language_code: str = "hi-IN"):
    """
    WebSocket endpoint for live Saaras v3 streaming STT.
    Receives raw PCM bytes from Flutter, streams to Sarvam, and sends back partial transcripts.
    Uses concurrent tasks to avoid blocking on send/recv.
    """
    await websocket.accept()
    if not SARVAM_API_KEY:
        await websocket.close(code=1011, reason="Sarvam API Key missing")
        return

    client = AsyncSarvamAI(api_subscription_key=SARVAM_API_KEY)

    try:
        async with client.speech_to_text_streaming.connect(
            model="saaras:v3",
            mode="transcribe",
            language_code=language_code,
            high_vad_sensitivity=True,
        ) as ws:
            # Task 1: Forward audio bytes from Flutter → Sarvam
            async def forward_audio():
                try:
                    while True:
                        data = await websocket.receive_bytes()
                        audio_b64 = base64.b64encode(data).decode("utf-8")
                        await ws.transcribe(audio=audio_b64)
                except WebSocketDisconnect:
                    pass
                except Exception as e:
                    print(f"[STT Stream] Forward audio error: {e}")

            # Task 2: Listen for transcripts from Sarvam → Flutter
            async def receive_transcripts():
                try:
                    while True:
                        response = await ws.recv()
                        if response:
                            # Convert SDK response object to a JSON-serializable dict
                            if hasattr(response, "model_dump"):
                                data = response.model_dump()
                            elif hasattr(response, "__dict__"):
                                data = response.__dict__
                            else:
                                data = {"transcript": str(response)}
                            await websocket.send_json(data)
                except Exception as e:
                    print(f"[STT Stream] Receive transcript error: {e}")

            # Run both tasks concurrently; when one ends, cancel the other
            done, pending = await asyncio.wait(
                [
                    asyncio.create_task(forward_audio()),
                    asyncio.create_task(receive_transcripts()),
                ],
                return_when=asyncio.FIRST_COMPLETED,
            )
            for task in pending:
                task.cancel()

    except WebSocketDisconnect:
        print("[STT Stream] Client disconnected")
    except Exception as e:
        print(f"[STT Stream] Error: {e}")
        try:
            await websocket.close(code=1011, reason=str(e))
        except:
            pass


def sarvam_stt(wav_bytes: bytes) -> dict:
    """Send WAV audio to Sarvam Saarika v2 for speech-to-text."""
    files = {"file": ("audio.wav", wav_bytes, "audio/wav")}
    data = {
        "model": "saarika:v2.5",
        "language_code": "unknown",
        "with_timestamps": "false",
    }
    try:
        resp = requests.post(
            SARVAM_STT_URL,
            headers=SARVAM_HEADERS,
            files=files,
            data=data,
            timeout=30,
        )
        print(f"[STT] Status: {resp.status_code}, Response: {resp.text[:500]}")
        resp.raise_for_status()
        result = resp.json()
        return {
            "transcript": result.get("transcript", ""),
            "language_code": result.get("language_code", "hi-IN"),
        }
    except Exception as e:
        print(f"Sarvam STT error: {e}")
        # Try to get response body for debugging
        try:
            print(f"[STT] Response body: {resp.text}")
        except:
            pass
        return {"transcript": "", "language_code": "hi-IN", "error": str(e)}


def sarvam_tts(text: str, language_code: str = "hi-IN") -> str:
    """Send text to Sarvam Bulbul TTS, returns base64 audio string."""
    payload = {
        "inputs": [text],
        "target_language_code": language_code,
        "speaker": "shubh",
        "model": "bulbul:v3",
        "pace": 1.0,
        "enable_preprocessing": True,
    }
    headers = {
        **SARVAM_HEADERS,
        "Content-Type": "application/json",
    }
    try:
        resp = requests.post(
            SARVAM_TTS_URL,
            headers=headers,
            json=payload,
            timeout=30,
        )
        resp.raise_for_status()
        result = resp.json()
        audios = result.get("audios", [])
        if audios:
            return audios[0]
        return ""
    except Exception as e:
        print(f"Sarvam TTS error: {e}")
        return ""


@app.get("/tts_stream")
def tts_stream(text: str, language_code: str = "hi-IN"):
    """
    Generate TTS audio. Tries Sarvam SDK first, falls back to Edge TTS.
    """
    from fastapi.responses import Response
    from sarvamai import SarvamAI

    clean_text = text.strip()
    if not clean_text:
        raise HTTPException(status_code=400, detail="Empty text")

    print(f"[TTS] Generating for: '{clean_text[:60]}...' lang={language_code}")

    # Method 1: Sarvam SDK
    try:
        client = SarvamAI(api_subscription_key=SARVAM_API_KEY)
        response = client.text_to_speech.convert(
            text=clean_text,
            target_language_code=language_code,
            speaker="shubh",
            model="bulbul:v3",
            pace=1.1,
            speech_sample_rate=8000,
            enable_preprocessing=True,
        )
        if hasattr(response, "audios") and response.audios:
            audio_b64 = response.audios[0]
            audio_bytes = base64.b64decode(audio_b64)
            print(f"[TTS] Sarvam success: {len(audio_bytes)} bytes")
            return Response(content=audio_bytes, media_type="audio/wav")
    except Exception as e:
        print(f"[TTS] Sarvam error: {e}")

    # Method 2: Edge TTS fallback (free, high quality)
    try:
        import edge_tts
        import asyncio
        import tempfile

        # Map language codes to Edge TTS voices
        voice_map = {
            "hi-IN": "hi-IN-MadhurNeural",
            "en-IN": "en-IN-PrabhatNeural",
            "en-US": "en-US-GuyNeural",
            "bn-IN": "bn-IN-BashkarNeural",
            "ta-IN": "ta-IN-ValluvarNeural",
            "te-IN": "te-IN-MohanNeural",
            "mr-IN": "mr-IN-ManoharNeural",
            "gu-IN": "gu-IN-NiranjanNeural",
            "kn-IN": "kn-IN-GaganNeural",
            "ml-IN": "ml-IN-MidhunNeural",
            "pa-IN": "pa-IN-GurpreetNeural",
        }
        voice = voice_map.get(language_code, "hi-IN-MadhurNeural")
        print(f"[TTS] Using Edge TTS fallback with voice: {voice}")

        async def generate():
            tmp = tempfile.NamedTemporaryFile(suffix=".mp3", delete=False)
            tmp.close()
            communicate = edge_tts.Communicate(clean_text, voice)
            await communicate.save(tmp.name)
            with open(tmp.name, "rb") as f:
                data = f.read()
            os.unlink(tmp.name)
            return data

        audio_bytes = asyncio.run(generate())
        print(f"[TTS] Edge TTS success: {len(audio_bytes)} bytes")
        return Response(content=audio_bytes, media_type="audio/mpeg")
    except Exception as e:
        print(f"[TTS] Edge TTS error: {e}")

    raise HTTPException(status_code=500, detail="All TTS methods failed")


def sarvam_chat(transcript: str, language_code: str, system_prompt: str) -> str:
    """Use Sarvam-M for answer generation (query intents only)."""
    # Sarvam-M via their chat completions style endpoint
    url = "https://api.sarvam.ai/v1/chat/completions"
    headers = {
        **SARVAM_HEADERS,
        "Content-Type": "application/json",
    }
    payload = {
        "model": "sarvam-m",
        "messages": [
            {
                "role": "system",
                "content": f"{system_prompt}. IMPORTANT: You MUST respond in the language code: {language_code}. Do NOT respond in English unless the request is in English.",
            },
            {"role": "user", "content": transcript},
        ],
        "max_tokens": 512,
    }
    try:
        resp = requests.post(url, headers=headers, json=payload, timeout=30)
        resp.raise_for_status()
        result = resp.json()
        choices = result.get("choices", [])
        if choices:
            return choices[0].get("message", {}).get("content", "")
        return ""
    except Exception as e:
        print(f"Sarvam-M chat error: {e}")
        return ""


# ─── Groq intent classification ─────────────────────────────────────

INTENT_SYSTEM_PROMPT = """You are an intent classifier for an Indian voice assistant. The user speaks Hindi, English, Marathi, Tamil, Telugu, Bengali, Gujarati, or mixed Hinglish. Classify the input into exactly one intent from this list:
- cab_booking with parameter destination
- whatsapp_message with parameters contact and message
- make_call with parameter contact
- pm_kisan_query (no parameters)
- ayushman_query (no parameters)
- ration_card_query (no parameters)
- crop_disease_query with parameters crop and symptom
- fertilizer_query with parameters crop and stage
- mandi_price_query with parameters crop and location
- food_order with parameters app and item and preference
- open_app with parameter app_name
- set_reminder with parameters time and task
- general_query (no parameters)

Return ONLY a single valid JSON object with fields: intent, parameters (nested object), confidence (float 0-1), response_language (matching the detected language code passed to you). No explanation. No markdown. No text before or after. Only the JSON object."""


def classify_intent(transcript: str, language_code: str) -> dict:
    """Use Groq (llama-3.3-70b) for fast intent classification."""
    if not groq_client:
        # Fallback: basic keyword matching
        return _keyword_fallback(transcript, language_code)

    user_msg = f"Language detected: {language_code}\nUser said: {transcript}"

    try:
        completion = groq_client.chat.completions.create(
            model="llama-3.3-70b-versatile",
            messages=[
                {"role": "system", "content": INTENT_SYSTEM_PROMPT},
                {"role": "user", "content": user_msg},
            ],
            temperature=0.1,
            max_tokens=256,
        )
        raw = completion.choices[0].message.content.strip()
        # Strip markdown code fences if present
        raw = re.sub(r"^```(?:json)?\s*", "", raw)
        raw = re.sub(r"\s*```$", "", raw)
        return json.loads(raw)
    except Exception as e:
        print(f"Groq classification error: {e}")
        return _keyword_fallback(transcript, language_code)


def _keyword_fallback(transcript: str, language_code: str) -> dict:
    """Simple keyword-based fallback when Groq is unavailable."""
    t = transcript.lower()
    if any(w in t for w in ["ola", "cab", "uber", "rapido", "taxi"]):
        dest = "Marine Drive"  # default
        return {
            "intent": "cab_booking",
            "parameters": {"destination": dest},
            "confidence": 0.7,
            "response_language": language_code,
        }
    if any(w in t for w in ["whatsapp", "message", "msg", "भेज"]):
        return {
            "intent": "whatsapp_message",
            "parameters": {"contact": "Rahul", "message": transcript},
            "confidence": 0.7,
            "response_language": language_code,
        }
    if any(w in t for w in ["pm kisan", "kisan", "किसान"]):
        return {
            "intent": "pm_kisan_query",
            "parameters": {},
            "confidence": 0.8,
            "response_language": language_code,
        }
    if any(w in t for w in ["call", "phone", "ring", "कॉल"]):
        return {
            "intent": "make_call",
            "parameters": {"contact": "Unknown"},
            "confidence": 0.6,
            "response_language": language_code,
        }
    if any(w in t for w in ["ayushman", "आयुष्मान"]):
        return {
            "intent": "ayushman_query",
            "parameters": {},
            "confidence": 0.8,
            "response_language": language_code,
        }
    if any(w in t for w in ["ration", "राशन"]):
        return {
            "intent": "ration_card_query",
            "parameters": {},
            "confidence": 0.8,
            "response_language": language_code,
        }
    if any(w in t for w in ["open", "khol", "खोल"]):
        app = transcript.split()[-1] if transcript.split() else "chrome"
        return {
            "intent": "open_app",
            "parameters": {"app_name": app},
            "confidence": 0.6,
            "response_language": language_code,
        }
    return {
        "intent": "general_query",
        "parameters": {},
        "confidence": 0.5,
        "response_language": language_code,
    }


# ─── App package mapping ────────────────────────────────────────────

APP_PACKAGES = {
    "ola": "com.olacabs.customer",
    "ola cabs": "com.olacabs.customer",
    "uber": "com.ubercab",
    "rapido": "com.rapido.passenger",
    "whatsapp": "com.whatsapp",
    "telegram": "org.telegram.messenger",
    "swiggy": "in.swiggy.android",
    "zomato": "com.application.zomato",
    "youtube": "com.google.android.youtube",
    "chrome": "com.android.chrome",
    "settings": "com.android.settings",
    "camera": "com.android.camera2",
    "contacts": "com.android.contacts",
    "maps": "com.google.android.apps.maps",
    "google maps": "com.google.android.apps.maps",
    "irctc": "com.cris.utsmobile",
    "amazon": "in.amazon.mShop.android.shopping",
    "flipkart": "com.flipkart.android",
    "phone": "com.android.dialer",
    "calculator": "com.google.android.calculator",
    "clock": "com.google.android.deskclock",
    "gallery": "com.google.android.apps.photos",
    "photos": "com.google.android.apps.photos",
}


def resolve_app_package(app_name: str) -> Optional[str]:
    """Case-insensitive lookup of app package name. Also checks partial matches."""
    name = app_name.strip().lower()
    # Exact match
    if name in APP_PACKAGES:
        return APP_PACKAGES[name]
    # Partial match — check if app_name is contained in any key
    for key, pkg in APP_PACKAGES.items():
        if name in key or key in name:
            return pkg
    return None


# ─── Language display helpers ────────────────────────────────────────

LANGUAGE_NAMES = {
    "hi-IN": "Hindi",
    "en-IN": "English",
    "mr-IN": "Marathi",
    "ta-IN": "Tamil",
    "te-IN": "Telugu",
    "bn-IN": "Bengali",
    "gu-IN": "Gujarati",
    "kn-IN": "Kannada",
    "ml-IN": "Malayalam",
    "pa-IN": "Punjabi",
    "or-IN": "Odia",
}

# Hardcoded demo intents — Phase 2 (cab_booking removed - uses real vision agent now)
HARDCODED_INTENTS = {"whatsapp_message", "pm_kisan_query"}


# ─── Confirmation question builders ─────────────────────────────────


def build_confirm_question(intent: str, params: dict, lang: str) -> dict:
    """Build a human-readable confirmation question for confirm-mode intents."""
    if intent == "cab_booking":
        dest = params.get("destination", "")
        if lang.startswith("hi"):
            question = f"{dest} ke liye Rapido cab book karein?"
        else:
            question = f"Shall I book a Rapido cab to {dest}?"
        details = [
            {"icon": "🚗", "text": f"Destination: {dest}"},
            {"icon": "⏱️", "text": "Estimated: 12 min"},
            {"icon": "💰", "text": "Estimated: ₹150-250"},
        ]
    elif intent == "whatsapp_message":
        contact = params.get("contact", "")
        message = params.get("message", "")
        if lang.startswith("hi"):
            question = f"{contact} ko ye message bhejein?"
        else:
            question = f"Shall I send this message to {contact}?"
        details = [
            {"icon": "👤", "text": f"Contact: {contact}"},
            {"icon": "💬", "text": f"Message: {message}"},
        ]
    elif intent == "make_call":
        contact = params.get("contact", "")
        if lang.startswith("hi"):
            question = f"{contact} ko call karein?"
        else:
            question = f"Shall I call {contact}?"
        details = [
            {"icon": "📞", "text": f"Contact: {contact}"},
        ]
    else:
        question = "Proceed with this action?"
        details = []

    return {"question": question, "details": details}


# ─── Narration builder ──────────────────────────────────────────────


def build_narration(intent: str, params: dict, lang: str) -> str:
    """Build a narration string telling the user what is about to happen."""
    if lang.startswith("hi"):
        narrations = {
            "cab_booking": f"Rapido khol raha hun, {params.get('destination', '')} ke liye cab book karunga",
            "whatsapp_message": f"WhatsApp khol raha hun, {params.get('contact', '')} ko message bhejunga",
            "make_call": f"{params.get('contact', '')} ko call kar raha hun",
            "food_order": f"{params.get('app', 'Swiggy')} khol raha hun, order karunga",
            "open_app": f"{params.get('app_name', 'App')} khol raha hun",
            "set_reminder": f"Reminder set kar raha hun",
        }
    else:
        narrations = {
            "cab_booking": f"Opening Rapido to book a cab to {params.get('destination', '')}",
            "whatsapp_message": f"Opening WhatsApp to message {params.get('contact', '')}",
            "make_call": f"Calling {params.get('contact', '')}",
            "food_order": f"Opening {params.get('app', 'Swiggy')} to order food",
            "open_app": f"Opening {params.get('app_name', 'the app')}",
            "set_reminder": f"Setting a reminder",
        }
    return narrations.get(
        intent,
        "Processing your request..."
        if not lang.startswith("hi")
        else "Kaam kar raha hun...",
    )


# ═══════════════════════════════════════════════════════════════════
# ENDPOINT 0 — POST /agent_step  (Vision Agent Brain)
# ═══════════════════════════════════════════════════════════════════

AGENT_SYSTEM_PROMPT = """You are a mobile phone automation agent. You see a screenshot of an Android phone screen and must decide the NEXT single action to accomplish the user's goal.

CRITICAL RULES:
1. The target app has ALREADY been opened for you. Do NOT try to go to the home screen, open app drawer, or search for the app.
2. You are already INSIDE the correct app. Focus on completing the task within this app.
3. Analyze the screenshot carefully. Identify all UI elements, buttons, text fields, icons, and their approximate pixel positions.
4. Return ONLY valid JSON — no markdown, no extra text.
5. Coordinates (x, y) are in PIXELS. Estimate positions based on the screenshot layout.

GOAL PARSING - VERY IMPORTANT:
When the goal mentions "message [CONTACT] saying [MESSAGE]" or "send [MESSAGE] to [CONTACT]":
  - CONTACT NAME = the person's name (e.g., "Yusuf", "Mom", "Rahul")
  - MESSAGE TEXT = what to send (e.g., "hi", "hello", "how are you")
  - NEVER confuse these! The contact name goes in SEARCH, the message goes in the CHAT INPUT.

TASK-SPECIFIC WORKFLOWS:

For WhatsApp messaging (goal mentions "message" + contact name + message text):
  FIRST: Parse the goal to identify CONTACT NAME vs MESSAGE TEXT
  Example: "message Yusuf on WhatsApp saying hi" → CONTACT="Yusuf", MESSAGE="hi"
  Example: "send hello to Mom on WhatsApp" → CONTACT="Mom", MESSAGE="hello"
  
  Step 1: If you see the WhatsApp chat list, look for a search icon (magnifying glass) at the top and tap it.
  Step 2: Type ONLY the CONTACT NAME (NOT the message!) in the search bar.
  Step 3: Tap on the matching contact from search results to open their chat.
  Step 4: Once in the chat, tap the message input field at the bottom (where it says "Type a message" or similar).
  Step 5: Type ONLY the MESSAGE TEXT in the message input field.
  Step 6: Tap the send button (green arrow icon on the right).
  Step 7: Return "done".

For opening an app (goal mentions "open"):
  - If you can see the app's main screen, return "done" immediately. The app is already open.

COMMON MISTAKES TO AVOID:
- Do NOT type the message text in the search bar! Search bar is ONLY for contact names.
- Do NOT type the contact name in the message input! Message input is ONLY for the message.
- Do NOT swipe away from the current app.
- Do NOT tap the back button unless you're in a wrong screen within the same app.
- If you see the target app's main screen, start using it — don't navigate elsewhere.
- For typing: ALWAYS tap on the text field first before typing. Never type without tapping a text field.

AVAILABLE ACTIONS:
- {"action": "tap", "x": <int>, "y": <int>, "reason": "why tapping here"}
- {"action": "type", "text": "<text to type>", "reason": "what we're typing"}
- {"action": "scroll", "direction": "up|down|left|right", "distance": <int 300-800>, "reason": "why scrolling"}
- {"action": "swipe", "x1": <int>, "y1": <int>, "x2": <int>, "y2": <int>, "reason": "why swiping"}
- {"action": "back", "reason": "why going back"}
- {"action": "wait", "seconds": <int 1-3>, "reason": "why waiting"}
- {"action": "confirm_needed", "message": "<what to confirm>", "reason": "why confirming"}
- {"action": "done", "result": "<summary>", "reason": "task complete"}
- {"action": "failed", "reason": "why failed"}

Return ONLY the JSON object, nothing else."""


from pydantic import BaseModel
from typing import List, Dict, Any


class AgentStepRequest(BaseModel):
    screenshot_base64: str
    goal: str
    history: List[Dict[str, Any]] = []
    step_number: int = 1


@app.post("/agent_step")
async def agent_step(req: AgentStepRequest):
    """
    Vision agent brain. Receives screenshot + goal, uses Groq Vision (llama-3.2-90b)
    to decide the next action (tap, type, scroll, etc.).
    Falls back to Gemini if Groq is unavailable.
    """
    try:
        # Build conversation context
        history_text = ""
        if req.history:
            history_text = "\n\nPREVIOUS ACTIONS:\n"
            for i, h in enumerate(req.history[-5:], 1):  # Last 5 steps
                history_text += (
                    f"  Step {i}: {h.get('action', '?')} — {h.get('reason', '')}\n"
                )

        # Pre-parse WhatsApp goals to extract contact and message
        goal_hint = ""
        goal_lower = req.goal.lower()
        if "whatsapp" in goal_lower and (
            "message" in goal_lower or "send" in goal_lower or "saying" in goal_lower
        ):
            import re

            contact = None
            message = None

            # Pattern 1: "saying X to Y" (e.g., "send message on WhatsApp saying hi to Yusuf")
            match1 = re.search(r"saying\s+(.+?)\s+to\s+(\w+)", goal_lower)
            # Pattern 2: "message X ... saying Y" (e.g., "message Yusuf on WhatsApp saying hi")
            match2 = re.search(r"message\s+(\w+).*?saying\s+(.+?)(?:\.|$)", goal_lower)
            # Pattern 3: "to X saying Y" (e.g., "send to Yusuf saying hello")
            match3 = re.search(r"to\s+(\w+)\s+saying\s+(.+?)(?:\.|$)", goal_lower)
            # Pattern 4: "whatsapp X saying Y"
            match4 = re.search(r"whatsapp\s+(\w+)\s+saying\s+(.+?)(?:\.|$)", goal_lower)

            if match1:
                message = match1.group(1).strip()
                contact = match1.group(2).strip().title()
            elif match2:
                contact = match2.group(1).strip().title()
                message = match2.group(2).strip()
            elif match3:
                contact = match3.group(1).strip().title()
                message = match3.group(2).strip()
            elif match4:
                contact = match4.group(1).strip().title()
                message = match4.group(2).strip()

            if contact and message:
                message = message.rstrip(".")
                goal_hint = f"\n\n⚠️ IMPORTANT - PARSED GOAL:\n  👤 CONTACT NAME (type this in SEARCH BAR): {contact}\n  💬 MESSAGE TEXT (type this in CHAT INPUT): {message}\n  ⚠️ DO NOT type '{message}' in search! Search is ONLY for '{contact}'!"

        user_prompt = f"""GOAL: {req.goal}{goal_hint}
CURRENT STEP: {req.step_number}
{history_text}
Look at this screenshot and decide the NEXT action to accomplish the goal. Return ONLY valid JSON."""

        text = ""

        # ── Try Gemini 2.0 Flash first (primary) ──
        if gemini_client:
            try:
                import base64

                image_data = base64.b64decode(req.screenshot_base64)

                # Try gemini-2.0-flash first, fall back to gemini-2.0-flash-lite if quota issues
                for model_name in ["gemini-2.0-flash", "gemini-2.0-flash-lite"]:
                    try:
                        response = gemini_client.models.generate_content(
                            model=model_name,
                            contents=[
                                types.Part.from_bytes(
                                    data=image_data, mime_type="image/png"
                                ),
                                user_prompt,
                            ],
                            config=types.GenerateContentConfig(
                                system_instruction=AGENT_SYSTEM_PROMPT,
                                temperature=0.1,
                                max_output_tokens=500,
                            ),
                        )
                        text = response.text.strip()
                        print(f"[Agent Step] Using {model_name}")
                        break
                    except Exception as model_error:
                        if "429" in str(model_error) or "RESOURCE_EXHAUSTED" in str(
                            model_error
                        ):
                            print(
                                f"[Agent Step] {model_name} quota exceeded, trying next model..."
                            )
                            continue
                        raise model_error
            except Exception as e:
                print(f"[Agent Step] Gemini 2.0 Flash failed: {e}")
                text = ""  # Fall through to Groq

        # ── Fallback to Groq Vision ──
        if not text and groq_client:
            try:
                completion = groq_client.chat.completions.create(
                    model="meta-llama/llama-4-scout-17b-16e-instruct",
                    messages=[
                        {"role": "system", "content": AGENT_SYSTEM_PROMPT},
                        {
                            "role": "user",
                            "content": [
                                {"type": "text", "text": user_prompt},
                                {
                                    "type": "image_url",
                                    "image_url": {
                                        "url": f"data:image/png;base64,{req.screenshot_base64}"
                                    },
                                },
                            ],
                        },
                    ],
                    temperature=0.1,
                    max_tokens=500,
                )
                text = completion.choices[0].message.content.strip()
                print(f"[Agent Step] Using Groq Vision (fallback)")
            except Exception as e:
                print(f"[Agent Step] Groq Vision failed: {e}")
                return {"action": "failed", "reason": f"Vision error: {str(e)}"}

        if not text:
            return {
                "action": "failed",
                "reason": "No vision API available (both Gemini and Groq failed)",
            }

        # Remove markdown code fences if present
        if text.startswith("```"):
            text = text.split("\n", 1)[1] if "\n" in text else text[3:]
            if text.endswith("```"):
                text = text[:-3]
            text = text.strip()

        result = json.loads(text)
        action = result.get("action", "failed")

        # Log detailed info for tap actions
        if action == "tap":
            x = result.get("x", "missing")
            y = result.get("y", "missing")
            print(
                f"[Agent Step {req.step_number}] Action: {action}, Coords: ({x}, {y}), Reason: {result.get('reason', '')}"
            )
        else:
            print(
                f"[Agent Step {req.step_number}] Action: {action}, Reason: {result.get('reason', '')}"
            )
        return result

    except json.JSONDecodeError as e:
        print(f"[Agent Step] JSON parse error: {e}, raw: {text[:200]}")
        return {"action": "failed", "reason": f"Could not parse AI response"}
    except Exception as e:
        print(f"[Agent Step] Error: {e}")
        return {"action": "failed", "reason": str(e)}


# ═══════════════════════════════════════════════════════════════════
# ENDPOINT 1 — POST /process
# ═══════════════════════════════════════════════════════════════════


@app.post("/process")
async def process_voice(file: UploadFile = File(...)):
    """
    Main endpoint. Flutter sends every voice recording here.
    Returns one of: answer, confirm, or agent_start mode.
    """
    tmp_path = None
    try:
        # Step 1 — Save uploaded WAV
        wav_bytes = await file.read()
        print(
            f"[/process] Received audio: {len(wav_bytes)} bytes, filename: {file.filename}"
        )
        tmp_fd, tmp_path = tempfile.mkstemp(suffix=".wav")
        with os.fdopen(tmp_fd, "wb") as f:
            f.write(wav_bytes)

        # Step 2 — Sarvam Saarika STT
        stt_result = sarvam_stt(wav_bytes)
        transcript = stt_result.get("transcript", "")
        language_code = stt_result.get("language_code", "hi-IN")
        print(f"[/process] STT result: transcript='{transcript}', lang={language_code}")

        if stt_result.get("error") or not transcript:
            print(
                f"[/process] STT failed or empty transcript. Error: {stt_result.get('error')}"
            )
            return {
                "mode": "error",
                "error": "Could not understand audio. Please try again.",
                "transcript": "",
                "detected_language": language_code,
            }

        # Step 4 — Groq intent classification
        intent_data = classify_intent(transcript, language_code)
        intent = intent_data.get("intent", "general_query")
        params = intent_data.get("parameters", {})
        response_lang = intent_data.get("response_language", language_code)

        # Check if this is a hardcoded demo flow
        use_hardcoded = intent in HARDCODED_INTENTS

        # Step 6 — Route based on intent
        # ── ANSWER MODE ──
        answer_intents = {
            "pm_kisan_query",
            "ayushman_query",
            "ration_card_query",
            "crop_disease_query",
            "fertilizer_query",
            "mandi_price_query",
            "general_query",
        }

        if intent in answer_intents:
            # Get answer from Sarvam-M
            answer_prompt = (
                f"Answer this question helpfully and accurately in the language "
                f"indicated by the code {language_code}. Use simple words that a "
                f"farmer or small business owner can understand. Maximum three "
                f"sentences. Do not use technical jargon. The user asked: "
            )
            answer_text = sarvam_chat(transcript, language_code, answer_prompt)
            if not answer_text:
                answer_text = "Sorry, I could not find an answer right now."

            return {
                "mode": "answer",
                "transcript": transcript,
                "detected_language": language_code,
                "answer": answer_text,
                "title": "Answer",
                "tts_text": answer_text,
                "use_hardcoded": use_hardcoded,
            }

        # ── CONFIRM MODE ──
        # Cab booking now goes through agent mode directly
        confirm_intents = set()  # No confirm mode intents - all go to agent

        if intent in confirm_intents:
            confirm = build_confirm_question(intent, params, language_code)
            question = confirm["question"]
            details = confirm["details"]

            return {
                "mode": "confirm",
                "transcript": transcript,
                "detected_language": language_code,
                "intent_data": intent_data,
                "confirm_question": question,
                "details": details,
                "title": question,
                "tts_text": question,
                "use_hardcoded": use_hardcoded,
            }

        # ── AGENT START MODE ──
        app_name = params.get("app_name", "")
        app_package = resolve_app_package(app_name) if app_name else None

        # If no app_name in params, resolve from intent name
        if not app_package:
            INTENT_TO_PACKAGE = {
                "whatsapp_message": "com.whatsapp",
                "cab_booking": "com.rapido.passenger",
                "food_order": None,  # resolved below from params
                "make_call": "com.android.dialer",
            }
            app_package = INTENT_TO_PACKAGE.get(intent)
            # For food_order, check the app param
            if intent == "food_order":
                food_app = params.get("app", "").lower()
                if "swiggy" in food_app:
                    app_package = "in.swiggy.android"
                elif "zomato" in food_app:
                    app_package = "com.application.zomato"

        print(
            f"[/process] Agent start: intent={intent}, app_package={app_package}, goal={transcript}"
        )

        # Build goal for vision agent
        goal = f"Complete this task: {transcript}"
        narration = build_narration(intent, params, language_code)

        return {
            "mode": "agent_start",
            "transcript": transcript,
            "detected_language": language_code,
            "intent_data": intent_data,
            "app_package": app_package,
            "goal": goal,
            "narration": narration,
            "title": narration,
            "tts_text": narration,
            "use_hardcoded": use_hardcoded,
        }

    except Exception as e:
        print(f"Process error: {e}")
        return {
            "mode": "error",
            "error": f"Server error: {str(e)}",
            "transcript": "",
            "detected_language": "hi-IN",
        }
    finally:
        # Step 7 — Cleanup
        if tmp_path and os.path.exists(tmp_path):
            try:
                os.unlink(tmp_path)
            except Exception:
                pass


# ═══════════════════════════════════════════════════════════════════
# ENDPOINT 2 — POST /agent_step
# ═══════════════════════════════════════════════════════════════════

VISION_PROMPT_TEMPLATE = """You are an AI agent controlling an Android smartphone to complete a task. The target app has ALREADY been opened for you.

Your task is: {goal}

{parsed_goal}

Actions taken so far:
{history}

CRITICAL RULES:
1. You are ALREADY INSIDE the correct app. Do NOT try to go to home screen or open another app.
2. Focus on completing the task within the current app.
3. Analyze the screenshot carefully — identify every button, text field, icon, and their pixel positions.
4. The screen is {screen_w}x{screen_h} pixels.

GOAL PARSING - VERY IMPORTANT:
When the goal mentions "message [CONTACT] saying [MESSAGE]" or "send [MESSAGE] to [CONTACT]":
  - CONTACT NAME = the person's name (e.g., "Yusuf", "Mom", "Rahul") → USE IN SEARCH BAR
  - MESSAGE TEXT = what to send (e.g., "hi", "hello") → USE IN MESSAGE INPUT
  - NEVER confuse these! Search bar is for CONTACT NAME only!

TASK-SPECIFIC WORKFLOWS:

For WhatsApp messaging (goal says "message" + a contact name + message text):
  1. If you see chat list → tap search icon (magnifying glass at top right)
  2. Type ONLY the CONTACT NAME in the search bar (NOT the message!)
  3. Tap the matching contact from results to open their chat
  4. Tap the message input field at bottom of chat (says "Type a message")
  5. Type ONLY the MESSAGE TEXT in the message input
  6. Tap send button (green arrow)
  7. Return "done"

For opening an app:
  - If the app's main screen is visible, return "done" immediately.

COMMON MISTAKES TO AVOID:
- Do NOT type the message text in the search bar — search is ONLY for CONTACT NAMES
- Do NOT type the contact name in the message input — message input is ONLY for the MESSAGE
- Do NOT swipe away from the current app
- ALWAYS tap a text field before typing
- If you already see the target app, start using it — don't navigate away
- Never tap the same coordinates as the previous step

Return ONLY a single valid JSON object. No markdown, no extra text.

Actions: tap (x,y,reason), type (text,reason), scroll (direction,distance,reason), swipe (x1,y1,x2,y2,reason), back (reason), wait (seconds,reason), confirm_needed (message,details), done (result,details), failed (reason)."""


@app.post("/agent_step")
async def agent_step(body: dict):
    """
    Runs one step of the vision agent loop.
    Flutter calls this repeatedly until the task is done.
    """
    screenshot_b64 = body.get("screenshot_base64", "")
    goal = body.get("goal", "")
    history = body.get("history", [])
    step_number = body.get("step_number", 1)

    # Max step guard
    if step_number > 15:
        return {
            "action": "failed",
            "reason": "Maximum steps reached. Task could not be completed automatically.",
        }

    if not screenshot_b64:
        return {"action": "failed", "reason": "No screenshot provided."}

    try:
        # Build history string
        history_str = "No actions taken yet." if not history else ""
        for i, step in enumerate(history, 1):
            history_str += (
                f"{i}. Action: {step.get('action', '?')} — {step.get('reason', '')}\n"
            )

        # Pre-parse WhatsApp goals to extract contact and message
        parsed_goal = ""
        goal_lower = goal.lower()
        if "whatsapp" in goal_lower and (
            "message" in goal_lower or "send" in goal_lower or "saying" in goal_lower
        ):
            import re

            contact = None
            message = None

            # Pattern 1: "saying X to Y" (e.g., "send message on WhatsApp saying hi to Yusuf")
            match1 = re.search(r"saying\s+(.+?)\s+to\s+(\w+)", goal_lower)
            # Pattern 2: "message X ... saying Y" (e.g., "message Yusuf on WhatsApp saying hi")
            match2 = re.search(r"message\s+(\w+).*?saying\s+(.+?)(?:\.|$)", goal_lower)
            # Pattern 3: "to X saying Y" (e.g., "send to Yusuf saying hello")
            match3 = re.search(r"to\s+(\w+)\s+saying\s+(.+?)(?:\.|$)", goal_lower)
            # Pattern 4: "whatsapp X saying Y"
            match4 = re.search(r"whatsapp\s+(\w+)\s+saying\s+(.+?)(?:\.|$)", goal_lower)

            if match1:
                message = match1.group(1).strip()
                contact = match1.group(2).strip().title()
            elif match2:
                contact = match2.group(1).strip().title()
                message = match2.group(2).strip()
            elif match3:
                contact = match3.group(1).strip().title()
                message = match3.group(2).strip()
            elif match4:
                contact = match4.group(1).strip().title()
                message = match4.group(2).strip()

            if contact and message:
                # Clean up message (remove trailing period)
                message = message.rstrip(".")
                parsed_goal = f"⚠️ IMPORTANT - PARSED GOAL:\n  👤 CONTACT NAME (type this in SEARCH BAR): {contact}\n  💬 MESSAGE TEXT (type this in CHAT INPUT): {message}\n  ⚠️ DO NOT type '{message}' in search! Search is ONLY for '{contact}'!"

        # Build prompt
        prompt = VISION_PROMPT_TEMPLATE.format(
            goal=goal,
            parsed_goal=parsed_goal,
            history=history_str,
            screen_w=1080,  # Default, will be updated if we decode image
            screen_h=2400,
        )

        raw = ""

        # ── Try Gemini 2.0 Flash first (primary) ──
        if gemini_client:
            try:
                import base64

                image_data = base64.b64decode(screenshot_b64)

                # Try gemini-2.0-flash first, fall back to gemini-2.0-flash-lite if quota issues
                for model_name in ["gemini-2.0-flash", "gemini-2.0-flash-lite"]:
                    try:
                        response = gemini_client.models.generate_content(
                            model=model_name,
                            contents=[
                                types.Part.from_bytes(
                                    data=image_data, mime_type="image/png"
                                ),
                                "Analyze this screenshot and return the next action as JSON.",
                            ],
                            config=types.GenerateContentConfig(
                                system_instruction=prompt,
                                temperature=0.1,
                                max_output_tokens=500,
                            ),
                        )
                        raw = response.text.strip()
                        print(f"[Agent Step {step_number}] Using {model_name}")
                        break
                    except Exception as model_error:
                        if "429" in str(model_error) or "RESOURCE_EXHAUSTED" in str(
                            model_error
                        ):
                            print(
                                f"[Agent Step {step_number}] {model_name} quota exceeded, trying next model..."
                            )
                            continue
                        raise model_error
            except Exception as e:
                print(f"[Agent Step] Gemini 2.0 Flash failed: {e}")
                raw = ""  # Fall through to Groq

        # ── Fallback to Groq Vision ──
        if not raw and groq_client:
            try:
                completion = groq_client.chat.completions.create(
                    model="meta-llama/llama-4-scout-17b-16e-instruct",
                    messages=[
                        {"role": "system", "content": prompt},
                        {
                            "role": "user",
                            "content": [
                                {
                                    "type": "text",
                                    "text": "Analyze this screenshot and return the next action as JSON.",
                                },
                                {
                                    "type": "image_url",
                                    "image_url": {
                                        "url": f"data:image/png;base64,{screenshot_b64}"
                                    },
                                },
                            ],
                        },
                    ],
                    temperature=0.1,
                    max_tokens=500,
                )
                raw = completion.choices[0].message.content.strip()
                print(f"[Agent Step {step_number}] Using Groq Vision (fallback)")
            except Exception as e:
                print(f"[Agent Step] Groq Vision failed: {e}")
                return {"action": "failed", "reason": f"Vision error: {str(e)}"}

        if not raw:
            return {
                "action": "failed",
                "reason": "No vision API available (both Gemini and Groq failed)",
            }

        # Strip markdown
        raw = re.sub(r"^```(?:json)?\s*", "", raw)
        raw = re.sub(r"\s*```$", "", raw)

        action_data = json.loads(raw)
        action = action_data.get("action", "?")

        # Log detailed info for tap actions
        if action == "tap":
            x = action_data.get("x", "missing")
            y = action_data.get("y", "missing")
            print(
                f"[Agent Step {step_number}] Action: {action}, Coords: ({x}, {y}), Reason: {action_data.get('reason', '')}"
            )
        else:
            print(
                f"[Agent Step {step_number}] Action: {action}, Reason: {action_data.get('reason', '')}"
            )
        return action_data

    except json.JSONDecodeError:
        return {"action": "failed", "reason": "Vision model returned invalid response."}
    except Exception as e:
        print(f"Agent step error: {e}")
        return {"action": "failed", "reason": f"Vision error: {str(e)}"}


# ═══════════════════════════════════════════════════════════════════
# ENDPOINT 3 — POST /open_app
# ═══════════════════════════════════════════════════════════════════


@app.post("/open_app")
async def open_app(body: dict):
    """Resolve app name to Android package name."""
    app_name = body.get("app_name", "")
    if not app_name:
        return {"package": None, "error": "No app name provided"}

    package = resolve_app_package(app_name)
    return {"package": package}


# ═══════════════════════════════════════════════════════════════════
# ENDPOINT 4 — POST /confirm
# ═══════════════════════════════════════════════════════════════════


@app.post("/confirm")
async def confirm_action(body: dict):
    """
    Called when user says yes on the confirmation screen.
    Resolves to agent_start mode.
    """
    intent_data = body.get("intent_data", {})
    intent = intent_data.get("intent", "")
    params = intent_data.get("parameters", {})
    language_code = intent_data.get("response_language", "hi-IN")

    # Resolve app package
    app_name_map = {
        "cab_booking": "rapido",
        "whatsapp_message": "whatsapp",
        "make_call": "phone",
        "food_order": params.get("app", "swiggy"),
    }
    app_name = app_name_map.get(intent, params.get("app_name", ""))
    app_package = resolve_app_package(app_name) if app_name else None

    # Build goal
    goal = f"Complete this task based on intent: {intent}, parameters: {json.dumps(params)}"
    narration = build_narration(intent, params, language_code)

    # TTS
    audio_b64 = sarvam_tts(narration, language_code)

    use_hardcoded = intent in HARDCODED_INTENTS

    return {
        "mode": "agent_start",
        "app_package": app_package,
        "goal": goal,
        "narration": narration,
        "intent_data": intent_data,
        "audio_base64": audio_b64,
        "use_hardcoded": use_hardcoded,
    }


# ═══════════════════════════════════════════════════════════════════
# HEALTH CHECK
# ═══════════════════════════════════════════════════════════════════


@app.get("/")
async def health():
    return {
        "status": "ok",
        "service": "Bharat Voice OS Backend",
        "sarvam_configured": bool(SARVAM_API_KEY),
        "gemini_configured": bool(gemini_client),
        "groq_configured": bool(GROQ_API_KEY),
        "vision_model": "gemini-2.0-flash (primary), llama-4-scout (fallback)",
    }
