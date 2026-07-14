//// recorder_compositor.js
//// Place this file in your Flutter project's  web/  directory.
//// Loaded by index.html: <script src="recorder_compositor.js"></script>
//
//(function () {
//  'use strict';
//
//  const CHUNK_INTERVAL_MS = 10_000;    // 10 s timeslice
//  const CANVAS_W          = 1280;
//  const CANVAS_H          = 720;
//  const VIDEO_BITRATE     = 1_500_000; // 1.5 Mbps
//
//  // ── Per-session state (fully reset on every start()) ──────────────────────
//  let _canvas, _ctx, _audioCtx, _dest, _recorder;
//  let _rafId          = null;
//  let _sessionId, _apiUrl, _authToken;
//  let _chunkIndex     = 0;
//  let _pendingUploads = 0;
//  let _stopping       = false;   // ← MUST be false when a new session starts
//  let _nextChunkIsFinal = false;
//
//  const _sources = {};
//
//  // ── Helpers ────────────────────────────────────────────────────────────────
//
//  function _bestMime() {
//    const candidates = [
//      'video/webm;codecs=vp9,opus',
//      'video/webm;codecs=vp8,opus',
//      'video/webm',
//    ];
//    return candidates.find(m => MediaRecorder.isTypeSupported(m)) || 'video/webm';
//  }
//
//  function _drawFrame() {
//    if (!_ctx) return;
//    _ctx.fillStyle = '#000';
//    _ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);
//
//    const screen = _sources['screen'];
//    if (screen && screen.videoEl && screen.videoEl.readyState >= 2) {
//      _ctx.drawImage(screen.videoEl, 0, 0, CANVAS_W, CANVAS_H);
//    }
//
//    const camera = _sources['camera'];
//    if (camera && camera.videoEl && camera.videoEl.readyState >= 2) {
//      if (screen && screen.videoEl) {
//        _ctx.drawImage(camera.videoEl, CANVAS_W - 220, CANVAS_H - 130, 200, 120);
//        _ctx.strokeStyle = '#00D4FF';
//        _ctx.lineWidth = 2;
//        _ctx.strokeRect(CANVAS_W - 220, CANVAS_H - 130, 200, 120);
//      } else {
//        _ctx.drawImage(camera.videoEl, 0, 0, CANVAS_W, CANVAS_H);
//      }
//    }
//
//    _rafId = requestAnimationFrame(_drawFrame);
//  }
//
//  function _connectAudio(stream, label) {
//    if (!_audioCtx || !_dest) return null;
//    try {
//      const tracks = stream.getAudioTracks();
//      if (!tracks.length) return null;
//      const node = _audioCtx.createMediaStreamSource(new MediaStream(tracks));
//      node.connect(_dest);
//      return node;
//    } catch (e) {
//      console.warn('[Compositor] audio connect error', label, e);
//      return null;
//    }
//  }
//
//  function _makeVideoEl(stream) {
//    const tracks = stream.getVideoTracks();
//    if (!tracks.length) return null;
//    const el = document.createElement('video');
//    el.srcObject = new MediaStream(tracks);
//    el.muted = true;
//    el.autoplay = true;
//    el.playsInline = true;
//    el.play().catch(() => {});
//    return el;
//  }
//
//  async function _uploadChunk(blob, index, isFinal) {
//    _pendingUploads++;
//    const form = new FormData();
//    form.append('chunk_index', String(index));
//    form.append('is_final',    isFinal ? '1' : '0');
//    form.append('chunk', blob, `chunk_${String(index).padStart(6,'0')}.webm`);
//
//    console.log(`[Compositor] uploading chunk #${index} size=${blob.size} final=${isFinal}`);
//
//    let attempt = 0;
//    let uploaded = false;
//
//    while (attempt <= 3) {
//      try {
//        const r = await fetch(
//          `${_apiUrl}/api/v1/live-sessions/${_sessionId}/recording-chunk`,
//          { method: 'POST', headers: { Authorization: _authToken }, body: form }
//        );
//        if (r.ok) {
//          console.log(`[Compositor] chunk #${index} OK`);
//          uploaded = true;
//          break;
//        }
//        const body = await r.text().catch(() => '(unreadable)');
//        console.error(`[Compositor] chunk #${index} REJECTED status=${r.status} body=${body.slice(0,300)}`);
//        if (r.status >= 400 && r.status < 500) break; // don't retry 4xx
//      } catch (e) {
//        console.warn(`[Compositor] chunk #${index} network error attempt ${attempt}:`, e);
//      }
//      attempt++;
//      if (attempt <= 3) await new Promise(res => setTimeout(res, 1000 * (1 << attempt)));
//    }
//
//    if (!uploaded) console.error(`[Compositor] chunk #${index} FAILED after ${attempt} attempts`);
//
//    _pendingUploads--;
//
//    // Only signal done when BOTH stopping AND all uploads are complete.
//    // If _stopping is false we are mid-session — never signal done early.
//    if (_stopping && _pendingUploads === 0) {
//      console.log('[Compositor] all chunks uploaded — done');
//      window._ElFaheemCompositorDone = true;
//    }
//  }
//
//  // ── Compositor API ─────────────────────────────────────────────────────────
//
//  const compositor = {
//
//    start(sessionId, apiUrl, authToken) {
//      // If a recorder is still active from a previous session, refuse.
//      if (_recorder && _recorder.state !== 'inactive') {
//        console.warn('[Compositor] start() ignored — recorder still active');
//        return;
//      }
//
//      // ── Full state reset for this session ─────────────────────────────────
//      // Stop any leftover draw loop
//      if (_rafId) { cancelAnimationFrame(_rafId); _rafId = null; }
//      // Clear leftover sources
//      Object.keys(_sources).forEach(k => compositor.removeStream(k));
//      // Reset ALL flags — critical: _stopping must be false here
//      _chunkIndex       = 0;
//      _pendingUploads   = 0;
//      _stopping         = false;
//      _nextChunkIsFinal = false;
//      window._ElFaheemCompositorDone = false;
//
//      _sessionId = sessionId;
//      _apiUrl    = apiUrl.replace(/\/$/, '');
//      _authToken = authToken;
//
//      console.log(`[Compositor] start() sessionId=${sessionId} apiUrl=${_apiUrl}`);
//
//      // Canvas
//      _canvas        = document.createElement('canvas');
//      _canvas.width  = CANVAS_W;
//      _canvas.height = CANVAS_H;
//      _ctx           = _canvas.getContext('2d');
//
//      // AudioContext
//      _audioCtx = new (window.AudioContext || window.webkitAudioContext)();
//      _audioCtx.resume().catch(() => {});
//      _dest = _audioCtx.createMediaStreamDestination();
//
//      // Composite stream
//      const canvasStream = _canvas.captureStream(30);
//      const audioTrack   = _dest.stream.getAudioTracks()[0];
//      if (audioTrack) canvasStream.addTrack(audioTrack);
//
//      const mime = _bestMime();
//      console.log(`[Compositor] using mime: ${mime}`);
//
//      _recorder = new MediaRecorder(canvasStream, {
//        mimeType: mime,
//        videoBitsPerSecond: VIDEO_BITRATE,
//      });
//
//      _recorder.ondataavailable = (e) => {
//        if (!e.data || e.data.size === 0) return;
//        const idx     = _chunkIndex++;
//        const isFinal = _nextChunkIsFinal;
//        _nextChunkIsFinal = false;
//        console.log(`[Compositor] ondataavailable size=${e.data.size} final=${isFinal}`);
//        _uploadChunk(e.data, idx, isFinal);
//      };
//
//      _recorder.onerror = (e) => console.error('[Compositor] MediaRecorder error:', e);
//
//      _recorder.start(CHUNK_INTERVAL_MS);
//      console.log(`[Compositor] MediaRecorder started timeslice=${CHUNK_INTERVAL_MS}ms`);
//
//      _drawFrame();
//      console.log('[Compositor] fully started');
//    },
//
//    addStream(stream, label) {
//      if (!stream) return;
//      if (_sources[label]) compositor.removeStream(label);
//      const videoEl   = _makeVideoEl(stream);
//      const audioNode = _connectAudio(stream, label);
//      _sources[label] = { stream, videoEl, audioNode };
//      console.log(`[Compositor] addStream: ${label} | video=${stream.getVideoTracks().length} audio=${stream.getAudioTracks().length}`);
//    },
//
//    removeStream(label) {
//      const src = _sources[label];
//      if (!src) return;
//      if (src.videoEl)   src.videoEl.srcObject = null;
//      if (src.audioNode) try { src.audioNode.disconnect(); } catch (_) {}
//      delete _sources[label];
//      console.log(`[Compositor] removeStream: ${label}`);
//    },
//
//    async stop() {
//      // Guard: if already stopping or nothing ever started, signal done and return.
//      if (_stopping) {
//        console.warn('[Compositor] stop() called while already stopping — ignored');
//        return;
//      }
//      if (!_recorder || _recorder.state === 'inactive') {
//        console.warn('[Compositor] stop() called but recorder not active — signalling done');
//        window._ElFaheemCompositorDone = true;
//        return;
//      }
//
//      console.log('[Compositor] stop() called');
//      _stopping = true;
//
//      // Stop draw loop
//      if (_rafId) { cancelAnimationFrame(_rafId); _rafId = null; }
//
//      // Mark NEXT ondataavailable blob as final, then flush + stop recorder
//      _nextChunkIsFinal = true;
//      _recorder.requestData();                    // fires ondataavailable synchronously (or very soon)
//      await new Promise(r => setTimeout(r, 500)); // let ondataavailable fire
//      _recorder.stop();
//      await new Promise(r => setTimeout(r, 300)); // let state settle to 'inactive'
//
//      // Stop all media tracks
//      Object.values(_sources).forEach(src => {
//        if (src.stream) src.stream.getTracks().forEach(t => { try { t.stop(); } catch(_){} });
//      });
//      try { if (_audioCtx) await _audioCtx.close(); } catch (_) {}
//
//      // Wait for all in-flight uploads (max 5 min)
//      if (_pendingUploads === 0) {
//        console.log('[Compositor] no pending uploads — done immediately');
//        window._ElFaheemCompositorDone = true;
//      } else {
//        console.log(`[Compositor] waiting for ${_pendingUploads} pending uploads…`);
//        const deadline = Date.now() + 5 * 60 * 1000;
//        while (_pendingUploads > 0 && Date.now() < deadline) {
//          await new Promise(r => setTimeout(r, 300));
//        }
//        if (!window._ElFaheemCompositorDone) {
//          window._ElFaheemCompositorDone = true;
//        }
//        console.log('[Compositor] stopped — uploads complete');
//      }
//
//      // Reset _stopping so start() can be called again for a new session
//      // without the idempotency guard blocking the next stop().
//      _stopping = false;
//    },
//
//    isActive() {
//      return !!_recorder && _recorder.state !== 'inactive';
//    },
//  };
//
//  window._ElFaheemCompositor     = compositor;
//  window._ElFaheemCompositorDone = false;
//
//  // Single dispatcher — dart:js_interop @JS() can only bind top-level globals
//  window._elfaheemCompositor = function(cmd, a1, a2, a3) {
//    switch (cmd) {
//      case 'start':        return compositor.start(a1, a2, a3);
//      case 'addStream':    return compositor.addStream(a1, a2);
//      case 'removeStream': return compositor.removeStream(a1);
//      case 'stop':         return compositor.stop();
//      case 'isActive':     return compositor.isActive();
//      default: console.warn('[Compositor] unknown cmd:', cmd);
//    }
//  };
//
//  console.log('[Compositor] loaded — version 4');
//})();

// recorder_compositor.js
// Place this file in your Flutter project's web/ directory.
// Loaded by index.html: <script src="recorder_compositor.js"></script>

(function () {
  'use strict';

  const CHUNK_INTERVAL_MS = 10_000;   // native timeslice — recorder auto-flushes every 10s
  const CANVAS_W = 1280;
  const CANVAS_H = 720;
  const VIDEO_BITRATE = 2_000_000;    // 2 Mbps — ~2.5MB/10s chunk, leaves headroom
                                       // on slower connections/tunnels so uploads can
                                       // keep up with the recorder in real time. Raise
                                       // this only once you've confirmed the target
                                       // network can sustain it — see the upload
                                       // queueing note in ondataavailable below for
                                       // what happens when it can't.

  // ── Per-session state ──────────────────────────────────────────
  let _canvas, _ctx, _audioCtx, _dest, _recorder;
  let _rafId          = null;   // now holds a setInterval id (see start())
  let _safetyFlushId  = null;   // periodic requestData() safety-net interval
  let _sessionId, _apiUrl, _authToken;
  let _chunkIndex     = 0;
  let _pendingUploads = 0;
  let _stopping       = false;
  let _nextChunkIsFinal = false;
  let _visibleContainer = null;   // ← visible but tiny container
  let _hadRealData    = false;    // true once ANY non-empty chunk was captured
  let _chunksUploaded = 0;        // count of chunks that actually reached the server
  let _silentSource   = null;     // keeps _dest "alive" when no real audio is ever connected
  let _silentGain      = null;
  let _uploadChain     = Promise.resolve(); // serializes chunk uploads — see _uploadChunk below
  let _queueDepth      = 0;       // chunks waiting-or-uploading, for backpressure diagnostics

  const _sources = {};

  // ── Visible 1px container (prevents browser from suspending video decoding) ──
  function _ensureVisibleContainer() {
    if (!_visibleContainer) {
      _visibleContainer = document.createElement('div');
      // Position absolute, 1x1 pixel, transparent – but VISIBLE in the DOM tree
      _visibleContainer.style.position = 'fixed';
      _visibleContainer.style.bottom = '0';
      _visibleContainer.style.right = '0';
      _visibleContainer.style.width = '1px';
      _visibleContainer.style.height = '1px';
      _visibleContainer.style.opacity = '0';
      _visibleContainer.style.pointerEvents = 'none';
      _visibleContainer.style.zIndex = '-9999';
      document.body.appendChild(_visibleContainer);
    }
    return _visibleContainer;
  }

  // ── Helpers ────────────────────────────────────────────────────

  function _bestMime() {
    // TEMP DIAGNOSTIC: set window._ElFaheemForceMime = 'video/webm;codecs=vp8,opus'
    // in the browser console BEFORE starting a session to force a specific
    // codec and isolate whether VP9 is the problem in this environment.
    if (window._ElFaheemForceMime && MediaRecorder.isTypeSupported(window._ElFaheemForceMime)) {
      console.log(`[Compositor] using FORCED mime override: ${window._ElFaheemForceMime}`);
      return window._ElFaheemForceMime;
    }
    const candidates = [
      // NOTE: 'video/webm;codecs=h264,opus' used to be tried first here.
      // H.264 is not a standard WebM video codec (WebM is built around
      // VP8/VP9/AV1); some Chrome builds report isTypeSupported()=true for
      // it anyway but then silently produce empty (0-byte) blobs when
      // actually asked to encode a canvas.captureStream()-sourced stream in
      // that combination — this was the root cause of every "ondataavailable
      // fired but chunk was empty" we kept seeing, regardless of what was
      // actually drawn on the canvas. VP9/VP8 in WebM is the well-tested
      // combination for MediaRecorder + canvas capture, so it's tried first.
      'video/webm;codecs=vp9,opus',
      'video/webm;codecs=vp8,opus',
      'video/webm',
    ];
    return candidates.find(m => MediaRecorder.isTypeSupported(m)) || 'video/webm';
  }

  function _canvasDiag() {
    try {
      // Sample a small region instead of the whole canvas (cheap) and
      // report whether it's non-uniform/non-black at this instant.
      const sample = _ctx.getImageData(CANVAS_W / 2 - 5, CANVAS_H / 2 - 5, 10, 10).data;
      let nonZero = 0;
      for (let i = 0; i < sample.length; i += 4) {
        if (sample[i] || sample[i + 1] || sample[i + 2]) nonZero++;
      }
      console.log(`[Compositor][diag] pre-flush: canvas center sample nonZeroPixels=${nonZero}/100, recorder.state=${_recorder ? _recorder.state : 'n/a'}`);
    } catch (e) {
      console.warn('[Compositor][diag] canvas sample failed:', e);
    }
  }

  let _diagCounter = 0;
  function _drawFrame() {
    if (!_ctx) return;

    const screen = _sources['screen'];
    const camera = _sources['camera'];
    const screenReady = !!(screen && screen.videoEl && screen.videoEl.readyState >= 2);
    const cameraReady = !!(camera && camera.videoEl && camera.videoEl.readyState >= 2);

    // DIAGNOSTIC: log source state ~every 2s (interval fires every 33ms,
    // so every 60th call) so we can see in the logs whether the screen
    // video element is ever actually reaching a paintable readyState,
    // and what its reported dimensions are.
    _diagCounter++;
    if (_diagCounter % 60 === 0) {
      console.log(
        `[Compositor][diag] screen: present=${!!screen} readyState=${screen && screen.videoEl ? screen.videoEl.readyState : 'n/a'} ` +
        `dims=${screen && screen.videoEl ? screen.videoEl.videoWidth + 'x' + screen.videoEl.videoHeight : 'n/a'} ` +
        `paused=${screen && screen.videoEl ? screen.videoEl.paused : 'n/a'} | ` +
        `camera: present=${!!camera} readyState=${camera && camera.videoEl ? camera.videoEl.readyState : 'n/a'}`
      );
    }

    if (!screenReady && !cameraReady) {
      // Nothing to show yet (no screen share, no camera/mic). Draw a
      // branded placeholder instead of leaving the canvas solid black —
      // this guarantees the recording always has real, meaningful content
      // from t=0, even if screen share is never started or camera/mic
      // never becomes available during the session.
      _drawPlaceholder();
      return;
    }

    _ctx.fillStyle = '#000';
    _ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);

    if (screenReady) {
      _ctx.drawImage(screen.videoEl, 0, 0, CANVAS_W, CANVAS_H);
    }

    if (cameraReady) {
      if (screenReady) {
        // PiP: 320×180 bottom-right
        _ctx.drawImage(camera.videoEl, CANVAS_W - 340, CANVAS_H - 200, 320, 180);
        // PiP border
        _ctx.strokeStyle = '#00D4FF';
        _ctx.lineWidth = 3;
        _ctx.strokeRect(CANVAS_W - 340, CANVAS_H - 200, 320, 180);
      } else {
        _ctx.drawImage(camera.videoEl, 0, 0, CANVAS_W, CANVAS_H);
      }
    }
    // NOTE: drawing is driven by a setInterval (see start()), not by
    // requestAnimationFrame. rAF is throttled/paused by browsers when the
    // tab is hidden or loses focus — which happens routinely right when a
    // teacher opens the getDisplayMedia() screen-picker dialog or switches
    // to another app to share it. That left the canvas frozen/blank for the
    // whole session in practice, so MediaRecorder had nothing real to
    // encode and flushed an empty (0-byte) blob on stop().
  }

  function _drawPlaceholder() {
    _ctx.fillStyle = '#1A1A1A';
    _ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);

    _ctx.fillStyle = '#F4C542';
    _ctx.font = 'bold 56px sans-serif';
    _ctx.textAlign = 'center';
    _ctx.textBaseline = 'middle';
    _ctx.direction = 'rtl';
    _ctx.fillText('في انتظار مشاركة الشاشة أو الكاميرا', CANVAS_W / 2, CANVAS_H / 2);
  }

  function _connectAudio(stream, label) {
    if (!_audioCtx || !_dest) return null;
    try {
      const audioTracks = stream.getAudioTracks();
      if (!audioTracks.length) return null;
      const audioStream = new MediaStream(audioTracks);
      const node = _audioCtx.createMediaStreamSource(audioStream);
      node.connect(_dest);
      return node;
    } catch (e) {
      console.warn('[Compositor] audio connect error', label, e);
      return null;
    }
  }

  // Create a video element that actually plays (visible container + retry logic)
  function _makeVideoEl(stream) {
    const tracks = stream.getVideoTracks();
    if (!tracks.length) return null;
    const el = document.createElement('video');
    el.srcObject = new MediaStream(tracks);
    el.muted = true;
    el.autoplay = true;
    el.playsInline = true;
    // Small size helps with layout, but any size works
    el.style.width = '1px';
    el.style.height = '1px';

    // Append to the VISIBLE container (not off-screen)
    _ensureVisibleContainer().appendChild(el);

    // Start playback and handle errors
    const playPromise = el.play();
    if (playPromise !== undefined) {
      playPromise.catch(e => {
        console.warn('[Compositor] video play failed, retrying:', e);
        // Retry after a short delay
        setTimeout(() => {
          if (el && el.srcObject) el.play().catch(() => {});
        }, 500);
      });
    }

    // Force a "playing" check every second to ensure decoding isn't suspended
    const interval = setInterval(() => {
      if (!el || !el.srcObject) {
        clearInterval(interval);
        return;
      }
      if (el.paused && el.readyState >= 2) {
        el.play().catch(() => {});
      } else if (el.readyState < 2) {
        // If still not ready, reload the stream
        try {
          const stream = el.srcObject;
          if (stream && stream.active) {
            el.srcObject = null;
            el.srcObject = stream;
            el.play().catch(() => {});
          }
        } catch (e) {}
      }
    }, 1000);

    // Clean interval when video is removed
    el._keepAliveInterval = interval;
    return el;
  }

  async function _uploadChunk(blob, index, isFinal) {
    _pendingUploads++;
    const form = new FormData();
    form.append('chunk_index', String(index));
    form.append('is_final',    isFinal ? '1' : '0');
    form.append('chunk', blob, `chunk_${String(index).padStart(6,'0')}.webm`);

    console.log(`[Compositor] uploading chunk #${index} size=${blob.size} final=${isFinal}`);

    let attempt = 0;
    let uploaded = false;

    while (attempt <= 3) {
      try {
        const r = await fetch(
          `${_apiUrl}/api/v1/live-sessions/${_sessionId}/recording-chunk`,
          { method: 'POST', headers: { Authorization: _authToken }, body: form }
        );
        if (r.ok) {
          console.log(`[Compositor] chunk #${index} OK`);
          uploaded = true;
          _chunksUploaded++;
          window._ElFaheemCompositorChunksUploaded = _chunksUploaded;
          break;
        }
        const body = await r.text().catch(() => '(unreadable)');
        console.error(`[Compositor] chunk #${index} REJECTED status=${r.status} body=${body.slice(0,300)}`);
        if (r.status >= 400 && r.status < 500) break;
      } catch (e) {
        console.warn(`[Compositor] chunk #${index} network error attempt ${attempt}:`, e);
      }
      attempt++;
      if (attempt <= 3) await new Promise(res => setTimeout(res, 1000 * (1 << attempt)));
    }

    if (!uploaded) console.error(`[Compositor] chunk #${index} FAILED after ${attempt} attempts`);

    _pendingUploads--;
    _queueDepth--;

    if (_stopping && _queueDepth === 0) {
      console.log('[Compositor] all chunks uploaded — done');
      window._ElFaheemCompositorDone = true;
    }
  }

  // ── Compositor API ─────────────────────────────────────────────

  const compositor = {

    async start(sessionId, apiUrl, authToken) {
      if (_recorder && _recorder.state !== 'inactive') {
        console.warn('[Compositor] start() ignored — recorder still active');
        return;
      }

      if (_rafId)         { clearInterval(_rafId); _rafId = null; }
      if (_safetyFlushId) { clearInterval(_safetyFlushId); _safetyFlushId = null; }
      Object.keys(_sources).forEach(k => compositor.removeStream(k));
      _chunkIndex       = 0;
      _pendingUploads   = 0;
      _stopping         = false;
      _nextChunkIsFinal = false;
      _hadRealData      = false;
      _chunksUploaded   = 0;
      _silentSource     = null;
      _silentGain       = null;
      _uploadChain      = Promise.resolve();
      _queueDepth       = 0;
      window._ElFaheemCompositorDone        = false;
      window._ElFaheemCompositorHadRealData = false;
      window._ElFaheemCompositorChunksUploaded = 0;

      _sessionId = sessionId;
      _apiUrl    = apiUrl.replace(/\/$/, '');
      _authToken = authToken;

      console.log(`[Compositor] start() sessionId=${sessionId} apiUrl=${_apiUrl}`);

      _canvas        = document.createElement('canvas');
      _canvas.width  = CANVAS_W;
      _canvas.height = CANVAS_H;
      _ctx           = _canvas.getContext('2d');

      _audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      // IMPORTANT: actually wait for + verify resume(), and log the result.
      // A suspended AudioContext's MediaStreamDestination track never
      // advances its timestamps. Muxing that "frozen" audio track together
      // with the (perfectly fine) video track into one WebM can make Chrome
      // emit genuinely empty blobs on every flush for the whole session —
      // this reproduces even though the video content is changing normally.
      try { await _audioCtx.resume(); } catch (e) { console.warn('[Compositor] audioCtx.resume() rejected:', e); }
      console.log(`[Compositor] audioCtx.state after resume attempt: ${_audioCtx.state}`);
      _dest = _audioCtx.createMediaStreamDestination();

      // Keep _dest "alive" with a real, continuously-running silent source.
      // If _dest never gets ANY node connected to it (e.g. this session:
      // no mic, and the screen share has no audio track either), its
      // output track is technically "live" but — in some Chromium builds —
      // never actually produces properly-timestamped samples. Muxing that
      // effectively-dead audio track together with the (perfectly fine)
      // canvas video track into one WebM is what makes MediaRecorder flush
      // a completely empty 0-byte blob for the WHOLE session, even though
      // the video content itself was being drawn and encoded normally.
      // A silent oscillator connected through a zero-gain node gives the
      // destination continuous real samples from t=0, independent of
      // whether any real mic/screen audio ever shows up.
      _silentSource = _audioCtx.createConstantSource();
      _silentGain   = _audioCtx.createGain();
      _silentGain.gain.value = 0; // inaudible
      _silentSource.connect(_silentGain);
      _silentGain.connect(_dest);
      _silentSource.start();

      const canvasStream = _canvas.captureStream(30);
      const audioTrack   = _dest.stream.getAudioTracks()[0];
      // Only attach the destination audio track if the context is actually
      // running. Attaching a track from a suspended context is what was
      // corrupting the mux; safer to record video-only than to risk empty
      // output. We keep retrying resume() in the safety-flush interval
      // below in case it recovers mid-session, but we do NOT hot-swap the
      // track into an already-started recorder (MediaRecorder doesn't
      // support that) — so a context stuck suspended for a whole session
      // means that session is recorded without audio, not silently dropped.
      if (audioTrack && _audioCtx.state === 'running') {
        canvasStream.addTrack(audioTrack);
        console.log('[Compositor] audio track attached (audioCtx running)');
      } else {
        console.warn(`[Compositor] SKIPPING audio track — audioCtx.state="${_audioCtx.state}". Recording video-only to avoid corrupting the mux.`);
      }

      const mime = _bestMime();
      console.log(`[Compositor] using mime: ${mime}`);

      _recorder = new MediaRecorder(canvasStream, {
        mimeType: mime,
        videoBitsPerSecond: VIDEO_BITRATE,
      });

      _recorder.ondataavailable = (e) => {
        if (!e.data || e.data.size === 0) {
          console.log('[Compositor] ondataavailable fired but chunk was empty (0 bytes) — skipping upload');
          return;
        }
        _hadRealData = true;
        window._ElFaheemCompositorHadRealData = true;
        const idx     = _chunkIndex++;
        const isFinal = _nextChunkIsFinal;
        _nextChunkIsFinal = false;
        console.log(`[Compositor] ondataavailable size=${e.data.size} final=${isFinal}`);
        // IMPORTANT: chain uploads instead of firing each one the moment its
        // chunk is ready. At high bitrate a single 10s chunk can be several
        // MB; if one upload is still in flight when the next chunk's timer
        // fires, firing a second concurrent fetch() for it means both now
        // compete for the same bandwidth, a third stacks on top 10s later,
        // and so on — on a slow/constrained connection (e.g. a temporary
        // tunnel) this compounds almost immediately and every chunk after
        // the first one or two starts timing out even though the recorder
        // itself is working fine. Chaining onto _uploadChain guarantees at
        // most one chunk is ever being uploaded at a time, in order, no
        // matter how far behind the network falls.
        _uploadChain = _uploadChain.then(() => _uploadChunk(e.data, idx, isFinal));
        _queueDepth++;
        if (_queueDepth > 1) {
          console.warn(`[Compositor] ⚠ upload queue backing up: ${_queueDepth} chunk(s) `
            + `waiting behind the one currently uploading — the network can't keep up `
            + `with the recording bitrate. Consider lowering VIDEO_BITRATE/resolution.`);
        }
      };

      _recorder.onerror = (e) => console.error('[Compositor] MediaRecorder error:', e);

      // CRITICAL ORDERING: paint the canvas BEFORE the recorder is started.
      // canvas.captureStream() + MediaRecorder attached to a still-blank
      // (never-painted) canvas has been observed to get "stuck" producing
      // 0-byte blobs on every subsequent requestData() for the rest of the
      // session in some Chrome builds — even after real content (screen
      // share, placeholder text) is being drawn every frame afterwards.
      // Painting at least one real frame first gives the encoder a valid
      // keyframe to start from. Then keep drawing via setInterval (~30fps)
      // — a plain interval (unlike requestAnimationFrame) keeps firing even
      // when the tab is hidden/backgrounded, so short/interrupted sessions
      // still get real, encodable video content.
      _drawFrame();
      _rafId = setInterval(_drawFrame, 33);

      _recorder.start(CHUNK_INTERVAL_MS);
      console.log(`[Compositor] MediaRecorder started timeslice=${CHUNK_INTERVAL_MS}ms`);

      // NOTE: we intentionally do NOT call _recorder.requestData() manually
      // anywhere mid-session anymore. Mixing a timeslice passed to start()
      // with manual requestData() calls is a known-fragile combination for
      // canvas-sourced MediaRecorder streams in Chromium: the manual call
      // can corrupt the encoder's internal muxer state, after which every
      // subsequent flush — including the "real" final one at stop() — comes
      // back as an empty 0-byte blob. The native 10s timeslice above now
      // handles periodic chunking entirely on its own via automatic
      // ondataavailable events.
      //
      // We keep a lightweight interval purely to nudge/log the AudioContext
      // state in case it was suspended at start() and later recovers — it
      // does NOT touch the recorder.
      _safetyFlushId = setInterval(() => {
        if (_audioCtx && _audioCtx.state !== 'running') {
          _audioCtx.resume().catch(() => {});
          console.log(`[Compositor] periodic check: audioCtx.state=${_audioCtx.state}`);
        }
      }, 10_000);

      console.log('[Compositor] fully started (draw loop via setInterval — survives background tabs)');
    },

    addStream(stream, label) {
      if (!stream) return;
      if (_sources[label]) compositor.removeStream(label);
      const videoEl   = _makeVideoEl(stream);
      const audioNode = _connectAudio(stream, label);
      _sources[label] = { stream, videoEl, audioNode };
      console.log(`[Compositor] addStream: ${label} | video=${stream.getVideoTracks().length} audio=${stream.getAudioTracks().length}`);
    },

    removeStream(label) {
      const src = _sources[label];
      if (!src) return;
      if (src.videoEl) {
        if (src.videoEl._keepAliveInterval) {
          clearInterval(src.videoEl._keepAliveInterval);
        }
        if (src.videoEl.parentNode) {
          src.videoEl.parentNode.removeChild(src.videoEl);
        }
        src.videoEl.srcObject = null;
      }
      if (src.audioNode) try { src.audioNode.disconnect(); } catch (_) {}
      delete _sources[label];
      console.log(`[Compositor] removeStream: ${label}`);
    },

    async stop() {
      if (_stopping) {
        console.warn('[Compositor] stop() called while already stopping — ignored');
        return;
      }
      if (!_recorder || _recorder.state === 'inactive') {
        console.warn('[Compositor] stop() called but recorder not active — signalling done');
        window._ElFaheemCompositorDone = true;
        return;
      }

      console.log('[Compositor] stop() called');
      _stopping = true;

      if (_rafId)         { clearInterval(_rafId); _rafId = null; }
      if (_safetyFlushId) { clearInterval(_safetyFlushId); _safetyFlushId = null; }

      _nextChunkIsFinal = true;

      // Per the MediaRecorder spec, calling stop() itself automatically
      // fires one final 'dataavailable' event (with whatever data has been
      // encoded so far) before 'stop' fires — we don't need to (and must
      // not) manually call requestData() right before this. Doing so was
      // the actual root cause of the empty-blob issue: a manual
      // requestData() immediately followed by stop() corrupted the
      // canvas+VP9 encoder's internal muxer state on this pipeline, so
      // both the manually-forced chunk AND stop()'s own automatic final
      // chunk came back as empty 0-byte blobs.
      _canvasDiag();
      await new Promise((resolve) => {
        let settled = false;
        const finish = () => { if (!settled) { settled = true; resolve(); } };
        const originalHandler = _recorder.ondataavailable;
        _recorder.ondataavailable = (e) => {
          originalHandler(e);
          finish();
        };
        _recorder.onstop = finish;
        try { _recorder.stop(); } catch (_) { finish(); }
        setTimeout(finish, 3000); // safety timeout in case no event arrives
      });

      await new Promise(r => setTimeout(r, 300));

      Object.values(_sources).forEach(src => {
        if (src.stream) src.stream.getTracks().forEach(t => { try { t.stop(); } catch(_){} });
      });
      try { if (_silentSource) _silentSource.stop(); } catch (_) {}
      try { if (_silentSource) _silentSource.disconnect(); } catch (_) {}
      try { if (_silentGain) _silentGain.disconnect(); } catch (_) {}
      _silentSource = null;
      _silentGain   = null;
      try { if (_audioCtx) await _audioCtx.close(); } catch (_) {}

      if (_queueDepth === 0) {
        console.log('[Compositor] no pending uploads — done immediately');
        window._ElFaheemCompositorDone = true;
      } else {
        console.log(`[Compositor] waiting for ${_queueDepth} pending upload(s)…`);
        const deadline = Date.now() + 5 * 60 * 1000;
        while (_queueDepth > 0 && Date.now() < deadline) {
          await new Promise(r => setTimeout(r, 300));
        }
        if (!window._ElFaheemCompositorDone) {
          window._ElFaheemCompositorDone = true;
        }
        console.log('[Compositor] stopped — uploads complete');
      }

      if (_visibleContainer && _visibleContainer.parentNode) {
        _visibleContainer.parentNode.removeChild(_visibleContainer);
        _visibleContainer = null;
      }

      if (_chunksUploaded === 0) {
        console.error(
          '[Compositor] ⚠️ Session ended with ZERO chunks uploaded — ' +
          'nothing was recorded. No camera/mic and no usable screen-share ' +
          'frames were ever captured before stop() was called.'
        );
      }

      _stopping = false;
    },

    isActive() {
      return !!_recorder && _recorder.state !== 'inactive';
    },
  };

  window._ElFaheemCompositor     = compositor;
  window._ElFaheemCompositorDone = false;
  window._ElFaheemCompositorHadRealData    = false;
  window._ElFaheemCompositorChunksUploaded = 0;

  window._elfaheemCompositor = function(cmd, a1, a2, a3) {
    switch (cmd) {
      case 'start':        return compositor.start(a1, a2, a3);
      case 'addStream':    return compositor.addStream(a1, a2);
      case 'removeStream': return compositor.removeStream(a1);
      case 'stop':         return compositor.stop();
      case 'isActive':     return compositor.isActive();
      default: console.warn('[Compositor] unknown cmd:', cmd);
    }
  };

  console.log('[Compositor] loaded — version 9 (VP9/VP8-first mime selection, placeholder frame when idle, setInterval draw loop, periodic safety-flush, real-data/upload tracking)');
})();