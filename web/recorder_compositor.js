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

  const CHUNK_INTERVAL_MS = 30_000;   // upload every 30 seconds
  const CANVAS_W = 1920;
  const CANVAS_H = 1080;
  const VIDEO_BITRATE = 8_000_000;    // 8 Mbps

  // ── Per-session state ──────────────────────────────────────────
  let _canvas, _ctx, _audioCtx, _dest, _recorder;
  let _rafId          = null;
  let _sessionId, _apiUrl, _authToken;
  let _chunkIndex     = 0;
  let _pendingUploads = 0;
  let _stopping       = false;
  let _nextChunkIsFinal = false;
  let _visibleContainer = null;   // ← visible but tiny container

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
    const candidates = [
      'video/webm;codecs=h264,opus',
      'video/webm;codecs=vp9,opus',
      'video/webm;codecs=vp8,opus',
      'video/webm',
    ];
    return candidates.find(m => MediaRecorder.isTypeSupported(m)) || 'video/webm';
  }

  function _drawFrame() {
    if (!_ctx) return;
    _ctx.fillStyle = '#000';
    _ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);

    const screen = _sources['screen'];
    if (screen && screen.videoEl && screen.videoEl.readyState >= 2) {
      _ctx.drawImage(screen.videoEl, 0, 0, CANVAS_W, CANVAS_H);
    }

    const camera = _sources['camera'];
    if (camera && camera.videoEl && camera.videoEl.readyState >= 2) {
      if (screen && screen.videoEl) {
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

    _rafId = requestAnimationFrame(_drawFrame);
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

    if (_stopping && _pendingUploads === 0) {
      console.log('[Compositor] all chunks uploaded — done');
      window._ElFaheemCompositorDone = true;
    }
  }

  // ── Compositor API ─────────────────────────────────────────────

  const compositor = {

    start(sessionId, apiUrl, authToken) {
      if (_recorder && _recorder.state !== 'inactive') {
        console.warn('[Compositor] start() ignored — recorder still active');
        return;
      }

      if (_rafId) { cancelAnimationFrame(_rafId); _rafId = null; }
      Object.keys(_sources).forEach(k => compositor.removeStream(k));
      _chunkIndex       = 0;
      _pendingUploads   = 0;
      _stopping         = false;
      _nextChunkIsFinal = false;
      window._ElFaheemCompositorDone = false;

      _sessionId = sessionId;
      _apiUrl    = apiUrl.replace(/\/$/, '');
      _authToken = authToken;

      console.log(`[Compositor] start() sessionId=${sessionId} apiUrl=${_apiUrl}`);

      _canvas        = document.createElement('canvas');
      _canvas.width  = CANVAS_W;
      _canvas.height = CANVAS_H;
      _ctx           = _canvas.getContext('2d');

      _audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      _audioCtx.resume().catch(() => {});
      _dest = _audioCtx.createMediaStreamDestination();

      const canvasStream = _canvas.captureStream(30);
      const audioTrack   = _dest.stream.getAudioTracks()[0];
      if (audioTrack) canvasStream.addTrack(audioTrack);

      const mime = _bestMime();
      console.log(`[Compositor] using mime: ${mime}`);

      _recorder = new MediaRecorder(canvasStream, {
        mimeType: mime,
        videoBitsPerSecond: VIDEO_BITRATE,
      });

      _recorder.ondataavailable = (e) => {
        if (!e.data || e.data.size === 0) return;
        const idx     = _chunkIndex++;
        const isFinal = _nextChunkIsFinal;
        _nextChunkIsFinal = false;
        console.log(`[Compositor] ondataavailable size=${e.data.size} final=${isFinal}`);
        _uploadChunk(e.data, idx, isFinal);
      };

      _recorder.onerror = (e) => console.error('[Compositor] MediaRecorder error:', e);

      _recorder.start(CHUNK_INTERVAL_MS);
      console.log(`[Compositor] MediaRecorder started timeslice=${CHUNK_INTERVAL_MS}ms`);

      _drawFrame();
      console.log('[Compositor] fully started');
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

      if (_rafId) { cancelAnimationFrame(_rafId); _rafId = null; }

      _nextChunkIsFinal = true;
      _recorder.requestData();
      await new Promise(r => setTimeout(r, 500));
      _recorder.stop();
      await new Promise(r => setTimeout(r, 300));

      Object.values(_sources).forEach(src => {
        if (src.stream) src.stream.getTracks().forEach(t => { try { t.stop(); } catch(_){} });
      });
      try { if (_audioCtx) await _audioCtx.close(); } catch (_) {}

      if (_pendingUploads === 0) {
        console.log('[Compositor] no pending uploads — done immediately');
        window._ElFaheemCompositorDone = true;
      } else {
        console.log(`[Compositor] waiting for ${_pendingUploads} pending uploads…`);
        const deadline = Date.now() + 5 * 60 * 1000;
        while (_pendingUploads > 0 && Date.now() < deadline) {
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

      _stopping = false;
    },

    isActive() {
      return !!_recorder && _recorder.state !== 'inactive';
    },
  };

  window._ElFaheemCompositor     = compositor;
  window._ElFaheemCompositorDone = false;

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

  console.log('[Compositor] loaded — version 6 (visible container + keep-alive)');
})();