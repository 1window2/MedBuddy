// 파일명: LazySpeechChannel.kt
// 역할: 기기 TTS 엔진을 처음 읽기를 요청할 때 연결하고, Flutter의 재생·중지·음성 설정 요청을 처리한다.

package com.example.medbuddy_frontend

import android.content.Context
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale
import java.util.UUID

// Class Name: LazySpeechChannel
// Role: Serves the app's TTS channel without binding the speech engine at launch.
// Responsibilities: Create TextToSpeech on the first request that needs it, queue requests until the engine is
// ready, finish each speak request when its utterance ends, and report completion, cancellation and errors to Dart.
// Attributes: tts/engineReady track the engine connection; pendingCalls hold requests made while it connects;
// speakResult/currentUtterance belong to the utterance being read; latestUtterance is the last one started, so a
// late stop notice from an older utterance is not reported as the newer one's cancellation; params carries the volume.
internal class LazySpeechChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val NAME = "com.medbuddy.app/tts"
    }

    private val channel = MethodChannel(messenger, NAME)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val pendingCalls = mutableListOf<Pair<MethodCall, MethodChannel.Result>>()
    private val params = Bundle()
    private var tts: TextToSpeech? = null
    private var engineReady = false
    private var speakResult: MethodChannel.Result? = null
    private var currentUtterance: String? = null
    private var latestUtterance: String? = null
    private var audioFocusRequest: AudioFocusRequest? = null

    init {
        channel.setMethodCallHandler(this)
    }

    // Function Name: dispose
    // Description: Stops reading, releases the engine and detaches the channel when the Flutter engine is cleaned up.
    // Parameters: None.
    // Returns: Unit.
    fun dispose() {
        channel.setMethodCallHandler(null)
        tts?.stop()
        tts?.shutdown()
        tts = null
        engineReady = false
        releaseAudioFocus()
        finishSpeak(0)
        pendingCalls.clear()
    }

    // Function Name: onMethodCall
    // Description: Answers stop without connecting an engine that was never used, and otherwise runs or queues the call.
    // Parameters: call - Flutter request; result - channel response callback.
    // Returns: Unit; every request is answered once.
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "stop" && tts == null) {
            result.success(1)
            return
        }
        if (call.method !in setOf("stop", "speak", "setLanguage", "setSpeechRate", "setVolume", "setPitch")) {
            result.notImplemented()
            return
        }
        if (engineReady) {
            handle(call, result)
            return
        }
        pendingCalls.add(call to result)
        connectEngine()
    }

    // Function Name: connectEngine
    // Description: Binds the default speech engine once; its init callback runs the queued requests.
    // Parameters: None.
    // Returns: Unit.
    private fun connectEngine() {
        if (tts != null) return
        // 엔진 연결은 비동기이며 결과는 메인 스레드의 초기화 콜백으로 온다.
        tts = TextToSpeech(context) { status -> onEngineInit(status) }
    }

    // Function Name: onEngineInit
    // Description: Marks the engine ready and runs queued requests, or answers them as failed and forgets the
    // engine so a later request binds again (for example after a speech engine is installed).
    // Parameters: status - TextToSpeech initialization status.
    // Returns: Unit.
    private fun onEngineInit(status: Int) {
        val queued = pendingCalls.toList()
        pendingCalls.clear()
        if (status == TextToSpeech.SUCCESS && tts != null) {
            engineReady = true
            tts?.setOnUtteranceProgressListener(progressListener)
            queued.forEach { (call, result) -> handle(call, result) }
            return
        }
        tts?.shutdown()
        tts = null
        engineReady = false
        queued.forEach { (call, result) -> result.success(if (call.method == "stop") 1 else 0) }
    }

    // Function Name: handle
    // Description: Applies one request to the ready engine with the same value ranges the app used before.
    // Parameters: call - Flutter request; result - channel response callback.
    // Returns: Unit.
    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        val engine = tts ?: run {
            result.success(if (call.method == "stop") 1 else 0)
            return
        }
        when (call.method) {
            "stop" -> {
                engine.stop()
                finishSpeak(0)
                result.success(1)
            }
            "speak" -> speak(
                engine,
                call.argument<String>("text").orEmpty(),
                call.argument<Boolean>("focus") ?: false,
                result,
            )
            "setLanguage" -> {
                val locale = Locale.forLanguageTag(call.arguments.toString())
                if (engine.isLanguageAvailable(locale) >= TextToSpeech.LANG_AVAILABLE) {
                    engine.language = locale
                    result.success(1)
                } else {
                    result.success(0)
                }
            }
            // Dart의 0.5가 엔진 기본 속도 1.0에 해당한다.
            "setSpeechRate" -> {
                engine.setSpeechRate(call.arguments.toString().toFloat() * 2.0f)
                result.success(1)
            }
            "setVolume" -> {
                val volume = call.arguments.toString().toFloat()
                if (volume in 0.0f..1.0f) {
                    params.putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, volume)
                    result.success(1)
                } else {
                    result.success(0)
                }
            }
            "setPitch" -> {
                val pitch = call.arguments.toString().toFloat()
                if (pitch in 0.5f..2.0f) {
                    engine.setPitch(pitch)
                    result.success(1)
                } else {
                    result.success(0)
                }
            }
        }
    }

    // Function Name: speak
    // Description: Replaces any queued speech with the text and keeps the result until the utterance ends.
    // Parameters: engine - ready TTS engine; text - sentence to read; focus - whether to duck other audio;
    // result - answered with 1 when reading finishes, or 0 when it cannot start, is stopped or fails.
    // Returns: Unit.
    private fun speak(engine: TextToSpeech, text: String, focus: Boolean, result: MethodChannel.Result) {
        if (speakResult != null) {
            // Dart는 읽기 전에 항상 중지하므로 겹친 요청은 이전 동작과 같이 시작하지 않는다.
            result.success(0)
            return
        }
        if (focus) requestAudioFocus()
        val utteranceId = UUID.randomUUID().toString()
        currentUtterance = utteranceId
        latestUtterance = utteranceId
        speakResult = result
        if (engine.speak(text, TextToSpeech.QUEUE_FLUSH, params, utteranceId) != TextToSpeech.SUCCESS) {
            releaseAudioFocus()
            finishSpeak(0)
            // 엔진 서비스가 종료된 경우가 많으므로 다음 요청에서 다시 연결한다.
            engine.shutdown()
            tts = null
            engineReady = false
        }
    }

    // Function Name: finishSpeak
    // Description: Answers the pending speak request once and clears the current utterance.
    // Parameters: value - 1 when reading finished, otherwise 0.
    // Returns: Unit.
    private fun finishSpeak(value: Int) {
        val result = speakResult ?: return
        speakResult = null
        currentUtterance = null
        result.success(value)
    }

    // Engine callbacks arrive on binder threads; channel work happens on the main thread.
    private val progressListener = object : UtteranceProgressListener() {
        override fun onStart(utteranceId: String) = Unit

        override fun onDone(utteranceId: String) {
            mainHandler.post {
                if (utteranceId != currentUtterance) return@post
                releaseAudioFocus()
                channel.invokeMethod("onComplete", null)
                finishSpeak(1)
            }
        }

        override fun onStop(utteranceId: String, interrupted: Boolean) {
            mainHandler.post {
                if (utteranceId != latestUtterance) return@post
                releaseAudioFocus()
                channel.invokeMethod("onCancel", null)
            }
        }

        @Deprecated("Deprecated in Java")
        override fun onError(utteranceId: String) {
            onError(utteranceId, TextToSpeech.ERROR)
        }

        override fun onError(utteranceId: String, errorCode: Int) {
            mainHandler.post {
                if (utteranceId != currentUtterance) return@post
                releaseAudioFocus()
                // 오류 문구가 speak 결과보다 먼저 Dart에 도착해야 실패 원인이 남는다.
                channel.invokeMethod("onError", "Error from TextToSpeech (speak) - $errorCode")
                finishSpeak(0)
            }
        }
    }

    // Function Name: requestAudioFocus
    // Description: Asks other apps to lower their volume while the guide is read.
    // Parameters: None.
    // Returns: Unit.
    private fun requestAudioFocus() {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK).build()
            audioFocusRequest = request
            audioManager.requestAudioFocus(request)
        } else {
            @Suppress("DEPRECATION")
            audioManager.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
        }
    }

    // Function Name: releaseAudioFocus
    // Description: Returns audio focus after reading ends, stops or fails.
    // Parameters: None.
    // Returns: Unit.
    private fun releaseAudioFocus() {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            audioFocusRequest = null
        } else {
            @Suppress("DEPRECATION")
            audioManager.abandonAudioFocus(null)
        }
    }
}
