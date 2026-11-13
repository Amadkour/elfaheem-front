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
  const CANVAS_W = 1920;
  const CANVAS_H = 1080;
  // Drawing always happens in that 1920 × 1080 space; the context's scale maps it onto the real canvas, whose height
  // is the quality picked for the recording (meta.canvasHeight, D-319).
  let _canvasHeight = CANVAS_H;
  // Labels whose stream the recorder itself opened (its own getUserMedia in
  // recorder_web_impl.dart): the only ones stop() may end. Every other label
  // wraps a LiveKit track the room still uses ('screen', 'remote_<sid>').
  const OWNED_LABELS = ['camera'];
  const VIDEO_BITRATE = 3_500_000;    // 3.5 Mbps — ~4.4MB/10s chunk.
                                       // Chunk uploads are serialized and queue-depth
                                       // tracked (see ondataavailable/_uploadChunk below),
                                       // so a slow network can no longer LOSE chunks —
                                       // worst case they just arrive/queue up later,
                                       // logged as "upload queue backing up". If you see
                                       // that warning constantly on your target network,
                                       // lower this before raising it further; going much
                                       // past this on a constrained connection (e.g. a
                                       // temporary tunnel) trades a bit of image quality
                                       // for a recording that's ready sooner after stop().

  // ── Per-session state ──────────────────────────────────────────
  let _canvas, _ctx, _audioCtx, _dest, _recorder;
  let _rafId          = null;   // now holds a setInterval id (see start())
  let _safetyFlushId  = null;   // periodic requestData() safety-net interval
  let _sessionId, _apiUrl, _authToken;
  let _uploadUrl      = '';   // meeting recordings: their own chunk route (meta.uploadUrl); '' = the session route
  let _epoch          = '';   // this start's id (meta.epoch), sent with every chunk as `epoch` (R1)
  let _assembled      = false; // the server answered 409 recording_assembled: nothing more to upload
  let _videoBitrate   = VIDEO_BITRATE; // meta.videoBitsPerSecond (the picked quality), else the constant
  let _audioOnly      = false; // meta.audioOnly: no canvas at all — the mixed audio stream is recorded alone
  let _chunkExt       = 'webm'; // the uploaded chunk's extension (from the mime the recorder actually uses)
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
  // Placeholder metadata (teacher/session/participants), shown on the
  // recorded canvas whenever there's no screen share or camera to draw.
  let _teacherName      = '';
  let _sessionTitle     = '';
  let _participantCount = 0;
  let _sessionStartMs   = 0;      // Date.now() at start() — drives the placeholder's live clock
  let _isPaused          = false; // true between pause() and resume() — drives the placeholder's badge

  const _sources = {};

  // ── D-306: the room's layout (lib/features/shared/live/live_recording_layout.dart) ──────────────
  // setLayout(json) hands the canvas a list of tiles {l: source label, k: camera|screen|board, x, y, w, h (px on
  // the 1920×1080 canvas), f: contain|auto, n: name, m: main, s: speaking, o: an overlay source drawn over the fitted
  // picture — the drawing on a shared screen, D-811} and `more` (cameras that did not fit).
  // While a layout has tiles, _drawFrame draws them instead of the legacy "screen, else my camera" pair: the
  // stage letterboxed in its own shape, each camera cropped when its shape is close to its cell (letterboxed when
  // not: a phone held upright), an initials card while a source has no frame yet, a name pill and a ring on the
  // one speaking. An empty layout (nothing on) falls back to the legacy drawing / the branded placeholder.
  let _layout = null;

  function _tileReady(src) {
    if (!src) return null;
    if (src.canvasEl) return src.canvasEl;
    if (src.videoEl && src.videoEl.readyState >= 2 && src.videoEl.videoWidth > 0) return src.videoEl;
    return null;
  }

  // Returns the rectangle the picture filled ([x, y, w, h]; null when nothing was drawn).
  function _drawFitted(el, x, y, w, h, fit) {
    const sw = el.videoWidth || el.width, sh = el.videoHeight || el.height;
    if (!sw || !sh || w <= 0 || h <= 0) return null;
    const ratio = (sw / sh) / (w / h);
    const cover = fit === 'cover' || (fit === 'auto' && ratio > 0.72 && ratio < 1.39);
    if (cover) {
      // Crop the source to the cell's shape, about its centre.
      let cw = sw, ch = sh;
      if (sw / sh > w / h) cw = sh * (w / h); else ch = sw / (w / h);
      _ctx.drawImage(el, (sw - cw) / 2, (sh - ch) / 2, cw, ch, x, y, w, h);
      return [x, y, w, h];
    }
    const s = Math.min(w / sw, h / sh);
    const dw = sw * s, dh = sh * s;
    _ctx.drawImage(el, x + (w - dw) / 2, y + (h - dh) / 2, dw, dh);
    return [x + (w - dw) / 2, y + (h - dh) / 2, dw, dh];
  }

  function _drawLayout() {
    const L = _layout;
    _ctx.fillStyle = '#0B1220';
    _ctx.fillRect(0, 0, CANVAS_W, CANVAS_H);
    const fullBleed = (t) => t.x <= 0 && t.y <= 0 && t.w >= CANVAS_W && t.h >= CANVAS_H;
    for (const t of L.tiles) {
      const el = _tileReady(_sources[t.l]);
      const bleed = fullBleed(t);
      const r = bleed ? 0 : (t.m ? 18 : 14);
      _ctx.save();
      _roundRectPath(t.x, t.y, t.w, t.h, r);
      _ctx.clip();
      _ctx.fillStyle = t.k === 'board' && el ? '#FFFFFF' : '#111A2E'; // a page letterboxes on paper
      _ctx.fillRect(t.x, t.y, t.w, t.h);
      if (el) {
        let shown = null;
        try { shown = _drawFitted(el, t.x, t.y, t.w, t.h, t.f || 'contain'); } catch (_) { /* a frame not decodable yet */ }
        // D-811: the drawing on a shared screen (a transparent canvas in the share's shape) over the picture.
        const over = t.o ? _sources[t.o] : null;
        if (shown && over && over.canvasEl && over.canvasEl.width > 0) {
          try { _ctx.drawImage(over.canvasEl, shown[0], shown[1], shown[2], shown[3]); } catch (_) { /* skipped frame */ }
        }
      } else {
        // No frame yet (or a camera that just turned on): the person's initials.
        const cx = t.x + t.w / 2, cy = t.y + t.h / 2;
        const rad = Math.max(18, Math.min(t.w, t.h) * 0.2);
        _ctx.fillStyle = '#1E2B47';
        _ctx.beginPath();
        _ctx.arc(cx, cy, rad, 0, Math.PI * 2);
        _ctx.fill();
        _ctx.fillStyle = '#E2E8F0';
        _ctx.font = `600 ${Math.round(rad * 0.8)}px sans-serif`;
        _ctx.textAlign = 'center';
        _ctx.textBaseline = 'middle';
        _ctx.fillText(_initialsOf(t.n || ''), cx, cy + 1);
      }
      _ctx.restore();
      // The one speaking: a ring (cameras only, never around the stage).
      if (t.s && t.k === 'camera' && !bleed) {
        _ctx.save();
        _ctx.strokeStyle = '#22D3EE';
        _ctx.lineWidth = 4;
        _roundRectPath(t.x + 2, t.y + 2, t.w - 4, t.h - 4, Math.max(0, r - 2));
        _ctx.stroke();
        _ctx.restore();
      }
      // A name pill on every camera (bottom start corner).
      if (t.k === 'camera' && t.n) {
        const fs = t.w >= 900 ? 26 : 18;
        _ctx.save();
        _ctx.font = `600 ${fs}px sans-serif`;
        const name = t.n.length > 28 ? t.n.slice(0, 27) + '…' : t.n;
        const tw = Math.min(t.w - 24, _ctx.measureText(name).width + 24);
        const ph = fs + 14, px = L.rtl ? t.x + t.w - tw - 12 : t.x + 12, py = t.y + t.h - ph - 12;
        _ctx.fillStyle = 'rgba(2, 6, 23, 0.62)';
        _roundRectPath(px, py, tw, ph, ph / 2);
        _ctx.fill();
        _ctx.fillStyle = '#F8FAFC';
        _ctx.textAlign = 'center';
        _ctx.textBaseline = 'middle';
        _ctx.fillText(name, px + tw / 2, py + ph / 2 + 1, tw - 16);
        _ctx.restore();
      }
    }
    if (L.more > 0) {
      const last = L.tiles[L.tiles.length - 1];
      const label = '+' + L.more;
      _ctx.save();
      _ctx.font = '700 24px sans-serif';
      const w = _ctx.measureText(label).width + 36, h = 44;
      const x = last ? last.x + (last.w - w) / 2 : CANVAS_W - w - 24;
      const y = last ? Math.min(CANVAS_H - h - 8, last.y + last.h + 12) : CANVAS_H - h - 24;
      _ctx.fillStyle = 'rgba(30, 41, 59, 0.9)';
      _roundRectPath(x, y, w, h, h / 2);
      _ctx.fill();
      _ctx.fillStyle = '#F8FAFC';
      _ctx.textAlign = 'center';
      _ctx.textBaseline = 'middle';
      _ctx.fillText(label, x + w / 2, y + h / 2 + 1);
      _ctx.restore();
    }
  }

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

  // Audio-only recordings (meta.audioOnly): opus in WebM first (Chrome,
  // Edge, Firefox), then whatever isTypeSupported() accepts — Safari only
  // knows audio/mp4 (AAC). The server transcodes any of them to one .m4a.
  function _bestAudioMime() {
    const candidates = [
      'audio/webm;codecs=opus',
      'audio/webm',
      'audio/ogg;codecs=opus',
      'audio/mp4',
    ];
    return candidates.find(m => MediaRecorder.isTypeSupported(m)) || '';
  }

  function _chunkExtFor(mime) {
    const m = String(mime || '').toLowerCase();
    if (m.startsWith('audio/mp4')) return 'm4a';
    if (m.startsWith('audio/ogg')) return 'ogg';
    return 'webm';
  }

  function _canvasDiag() {
    if (!_ctx) return;
    try {
      // Sample a small region instead of the whole canvas (cheap) and
      // report whether it's non-uniform/non-black at this instant.
      const sample = _ctx.getImageData(_canvas.width / 2 - 5, _canvas.height / 2 - 5, 10, 10).data;
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
    if (_layout && _layout.tiles && _layout.tiles.length) { _drawLayout(); return; }

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
      // Nothing to show at all (no screen share, no camera/mic). Draw a
      // branded placeholder instead of leaving the canvas solid black —
      // this guarantees the recording always has real, meaningful content
      // from t=0, even if screen share is never started or camera/mic
      // never becomes available during the session. Stopping a screen
      // share mid-session does NOT trigger the placeholder on its own as
      // long as the camera is still on — it just falls back to a full-frame
      // camera view below.
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
        // PiP: 25% of canvas width/height, bottom-right, with a fixed-ratio
        // margin — scales automatically with CANVAS_W/CANVAS_H instead of
        // assuming 1280×720, so it stays the same relative size (and margin)
        // if the resolution changes.
        const pipW = Math.round(CANVAS_W * 0.25);
        const pipH = Math.round(CANVAS_H * 0.25);
        const pipMargin = Math.round(CANVAS_W * 0.0156); // ~20px at 1280 wide
        const pipX = CANVAS_W - pipW - pipMargin;
        const pipY = CANVAS_H - pipH - pipMargin;
        _ctx.drawImage(camera.videoEl, pipX, pipY, pipW, pipH);
        // PiP border
        _ctx.strokeStyle = '#00D4FF';
        _ctx.lineWidth = 3;
        _ctx.strokeRect(pipX, pipY, pipW, pipH);
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

  // ── Premium placeholder design tokens ──────────────────────────────────
  // Mirrors the in-app _PremiumWaitingPlaceholder palette (room.dart) so the
  // recorded video matches the live UI's branding exactly.
  const _PH = {
    bg:        '#060810',
    bgSurface: '#0E1120',
    cyan:      '#00D4FF',
    indigo:    '#6B6EF9',
    rose:      '#FF4F72',
    textHigh:  '#FFFFFF',
    textMid:   'rgba(255,255,255,0.70)',
    textLow:   'rgba(255,255,255,0.45)',
    glassBdr:  'rgba(255,255,255,0.18)',
    glass:     'rgba(255,255,255,0.08)',
  };

  function _initialsOf(name) {
    const trimmed = (name || '').trim();
    if (!trimmed) return '؟';
    const parts = trimmed.split(/\s+/).slice(0, 2);
    return parts.map(w => w[0]).join('').toUpperCase();
  }

  function _roundRectPath(x, y, w, h, r) {
    if (typeof _ctx.roundRect === 'function') {
      _ctx.beginPath();
      _ctx.roundRect(x, y, w, h, r);
      return;
    }
    // Fallback for engines without roundRect (older Chromium).
    const rr = Math.min(r, w / 2, h / 2);
    _ctx.beginPath();
    _ctx.moveTo(x + rr, y);
    _ctx.arcTo(x + w, y,     x + w, y + h, rr);
    _ctx.arcTo(x + w, y + h, x,     y + h, rr);
    _ctx.arcTo(x,     y + h, x,     y,     rr);
    _ctx.arcTo(x,     y,     x + w, y,     rr);
    _ctx.closePath();
  }

  function _drawPlaceholder() {
    const w = CANVAS_W, h = CANVAS_H;
    const cx = w / 2, cy = h / 2;
    const now = Date.now();
    const elapsedSec = Math.max(0, Math.floor((now - (_sessionStartMs || now)) / 1000));

    // ── Background: dark base + two soft brand-color glows (aurora-lite) ──
    _ctx.fillStyle = _PH.bg;
    _ctx.fillRect(0, 0, w, h);

    const glow1 = _ctx.createRadialGradient(w * 0.22, h * 0.18, 0, w * 0.22, h * 0.18, w * 0.5);
    glow1.addColorStop(0, 'rgba(0,212,255,0.16)');
    glow1.addColorStop(1, 'rgba(0,212,255,0)');
    _ctx.fillStyle = glow1;
    _ctx.fillRect(0, 0, w, h);

    const glow2 = _ctx.createRadialGradient(w * 0.8, h * 0.85, 0, w * 0.8, h * 0.85, w * 0.5);
    glow2.addColorStop(0, 'rgba(107,110,249,0.16)');
    glow2.addColorStop(1, 'rgba(107,110,249,0)');
    _ctx.fillStyle = glow2;
    _ctx.fillRect(0, 0, w, h);

    // ── REC / PAUSED indicator, top-right ──────────────────────────────────
    const recPadX = 18, recY = 28, recH = 40;
    const recLabel = _isPaused ? 'PAUSED' : 'REC';
    _ctx.font = '600 15px sans-serif';
    const recW = Math.max(118, _ctx.measureText(recLabel).width + recPadX + 40);
    const recX = w - recW - 32;
    _ctx.fillStyle = _PH.glass;
    _roundRectPath(recX, recY, recW, recH, recH / 2);
    _ctx.fill();
    _ctx.strokeStyle = _PH.glassBdr;
    _ctx.lineWidth = 1;
    _roundRectPath(recX, recY, recW, recH, recH / 2);
    _ctx.stroke();
    _ctx.fillStyle = _PH.textHigh;
    _ctx.font = '600 15px sans-serif';
    _ctx.textAlign = 'left';
    _ctx.textBaseline = 'middle';
    _ctx.direction = 'ltr';
    if (_isPaused) {
      // Matches controls.dart's _amber (0xFFFFB800) pause indicator, so the
      // recorded placeholder and the live pause UI agree visually.
      _ctx.fillStyle = '#FFB800';
      _ctx.beginPath();
      _ctx.rect(recX + recPadX - 5, recY + recH / 2 - 6, 4, 12);
      _ctx.rect(recX + recPadX + 3, recY + recH / 2 - 6, 4, 12);
      _ctx.fill();
      _ctx.fillStyle = _PH.textHigh;
      _ctx.fillText('PAUSED', recX + recPadX + 16, recY + recH / 2 + 1);
    } else {
      const pulse = 0.55 + 0.45 * Math.abs(Math.sin(now / 700));
      _ctx.fillStyle = `rgba(255,79,114,${pulse.toFixed(2)})`;
      _ctx.beginPath();
      _ctx.arc(recX + recPadX, recY + recH / 2, 6, 0, Math.PI * 2);
      _ctx.fill();
      _ctx.fillStyle = _PH.textHigh;
      _ctx.font = '600 16px sans-serif';
      _ctx.fillText('REC', recX + recPadX + 16, recY + recH / 2 + 1);
    }

    // ── Elapsed session clock, top-left ────────────────────────────────────
    const mm = String(Math.floor(elapsedSec / 60)).padStart(2, '0');
    const ss = String(elapsedSec % 60).padStart(2, '0');
    _ctx.fillStyle = _PH.textLow;
    _ctx.font = '600 15px sans-serif';
    _ctx.textAlign = 'left';
    _ctx.fillText(`${mm}:${ss}`, 32, recY + recH / 2 + 1);

    // ── Avatar with pulsing ring ───────────────────────────────────────────
    const avatarY   = cy - 120;
    const avatarR   = 56;
    const ringT     = (now / 2000) % 1;               // 0→1 loop, matches Flutter's 2s ring
    const ringScale = 1 + 0.55 * ringT;
    const ringAlpha = 0.45 * (1 - ringT);
    _ctx.strokeStyle = `rgba(0,212,255,${ringAlpha.toFixed(2)})`;
    _ctx.lineWidth = 2.5;
    _ctx.beginPath();
    _ctx.arc(cx, avatarY, (avatarR - 8) * ringScale, 0, Math.PI * 2);
    _ctx.stroke();

    const avatarGrad = _ctx.createLinearGradient(
      cx - avatarR, avatarY - avatarR, cx + avatarR, avatarY + avatarR,
    );
    avatarGrad.addColorStop(0, _PH.cyan);
    avatarGrad.addColorStop(1, _PH.indigo);
    _ctx.save();
    _ctx.shadowColor = 'rgba(0,212,255,0.35)';
    _ctx.shadowBlur = 28;
    _ctx.fillStyle = avatarGrad;
    _ctx.beginPath();
    _ctx.arc(cx, avatarY, avatarR, 0, Math.PI * 2);
    _ctx.fill();
    _ctx.restore();

    _ctx.fillStyle = _PH.textHigh;
    _ctx.font = '800 34px sans-serif';
    _ctx.textAlign = 'center';
    _ctx.textBaseline = 'middle';
    _ctx.fillText(_initialsOf(_teacherName), cx, avatarY + 2);

    // ── Teacher name ────────────────────────────────────────────────────────
    _ctx.direction = 'rtl';
    _ctx.fillStyle = _PH.textHigh;
    _ctx.font = '800 30px sans-serif';
    _ctx.textAlign = 'center';
    _ctx.fillText(_teacherName || 'المعلم', cx, avatarY + avatarR + 46);

    // ── Session title, as a glass pill ─────────────────────────────────────
    const title = _sessionTitle || 'حصة مباشرة';
    _ctx.font = '600 18px sans-serif';
    const titleWidth = _ctx.measureText(title).width;
    const pillW = Math.min(w - 120, titleWidth + 64);
    const pillH = 44;
    const pillY = avatarY + avatarR + 74;
    _ctx.fillStyle = 'rgba(0,212,255,0.12)';
    _roundRectPath(cx - pillW / 2, pillY, pillW, pillH, pillH / 2);
    _ctx.fill();
    _ctx.strokeStyle = 'rgba(0,212,255,0.35)';
    _ctx.lineWidth = 1;
    _roundRectPath(cx - pillW / 2, pillY, pillW, pillH, pillH / 2);
    _ctx.stroke();
    _ctx.fillStyle = _PH.cyan;
    _ctx.textAlign = 'center';
    _ctx.textBaseline = 'middle';
    _ctx.fillText(title, cx, pillY + pillH / 2 + 1);

    // ── Participant count chip ─────────────────────────────────────────────
    const chipLabel = `${_participantCount} مشارك`;
    _ctx.font = '600 17px sans-serif';
    const chipTextW = _ctx.measureText(chipLabel).width;
    const chipW = chipTextW + 64;
    const chipH = 40;
    const chipY = pillY + pillH + 22;
    _ctx.fillStyle = _PH.glass;
    _roundRectPath(cx - chipW / 2, chipY, chipW, chipH, chipH / 2);
    _ctx.fill();
    _ctx.strokeStyle = _PH.glassBdr;
    _ctx.lineWidth = 1;
    _roundRectPath(cx - chipW / 2, chipY, chipW, chipH, chipH / 2);
    _ctx.stroke();

    // Simple two-circle "people" glyph, drawn left of the chip's Arabic text
    // (canvas has no icon fonts available, so this is hand-drawn).
    const glyphCx = cx + chipW / 2 - 30;
    const glyphCy = chipY + chipH / 2;
    _ctx.fillStyle = _PH.textMid;
    _ctx.beginPath(); _ctx.arc(glyphCx - 6, glyphCy - 2, 5, 0, Math.PI * 2); _ctx.fill();
    _ctx.beginPath(); _ctx.arc(glyphCx + 6, glyphCy - 2, 5, 0, Math.PI * 2); _ctx.fill();
    _ctx.beginPath();
    _ctx.ellipse(glyphCx - 6, glyphCy + 7, 7, 5, 0, 0, Math.PI * 2);
    _ctx.fill();
    _ctx.beginPath();
    _ctx.ellipse(glyphCx + 6, glyphCy + 7, 7, 5, 0, 0, Math.PI * 2);
    _ctx.fill();

    _ctx.fillStyle = _PH.textHigh;
    _ctx.textAlign = 'center';
    _ctx.textBaseline = 'middle';
    _ctx.fillText(chipLabel, cx - 16, chipY + chipH / 2 + 1);

    // ── Bottom status line ──────────────────────────────────────────────────
    _ctx.fillStyle = _PH.textLow;
    _ctx.font = '500 16px sans-serif';
    _ctx.textAlign = 'center';
    _ctx.fillText('في انتظار مشاركة الشاشة أو الكاميرا', cx, h - 56);
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

  // Actively keeps a hidden/near-zero-size <video> element's decode running
  // by continuously registering requestVideoFrameCallback (rVFC) — the
  // purpose-built API for "tell the browser something is consuming this
  // video's frames." Chrome can throttle/suspend decode on video elements
  // that aren't visibly rendered at meaningful size (exactly what these
  // elements are, by design, since they only exist to feed drawImage()),
  // and unlike the screen-share video, the camera one has no independent
  // signal to the browser that it matters — this loop supplies that signal
  // every single frame, which is the documented purpose of rVFC and a much
  // more direct fix than periodically polling/reloading srcObject after
  // the fact. Falls back gracefully (no-op) on engines without rVFC; the
  // existing setInterval recovery below still applies as a second layer.
  function _pumpVideoFrames(el) {
    if (typeof el.requestVideoFrameCallback !== 'function') return;
    const tick = () => {
      if (!el || !el.srcObject) return; // stream cleared/element torn down — stop pumping
      try { el.requestVideoFrameCallback(tick); } catch (_) { /* element gone */ }
    };
    try { el.requestVideoFrameCallback(tick); } catch (_) {}
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

    _pumpVideoFrames(el);

    // Force a "playing" check every second to ensure decoding isn't suspended.
    // Secondary safety net behind _pumpVideoFrames above — on engines where
    // rVFC isn't available (or in case a track genuinely stalls), this still
    // catches and recovers a stuck element.
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
            _pumpVideoFrames(el); // re-arm — a new srcObject needs its own rVFC chain
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
    if (_epoch) form.append('epoch', _epoch);
    form.append('chunk', blob, `chunk_${String(index).padStart(6,'0')}.${_chunkExt}`);

    console.log(`[Compositor] uploading chunk #${index} size=${blob.size} final=${isFinal} ext=${_chunkExt}`);

    let attempt = 0;
    let uploaded = false;

    // The run's recording is already assembled (409 recording_assembled): stop uploading, it is done.
    if (_assembled) attempt = 4;

    while (attempt <= 3) {
      try {
        const r = await fetch(
          _uploadUrl || `${_apiUrl}/api/v1/live-sessions/${_sessionId}/recording-chunk`,
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
        if (r.status === 409 && body.indexOf('recording_assembled') >= 0) {
          // R4: assembled already — every later chunk would be refused too; the recording is done.
          console.log(`[Compositor] chunk #${index}: the recording is already assembled — no more uploads`);
          _assembled = true;
          window._ElFaheemCompositorAssembled = true;
          break;
        }
        console.error(`[Compositor] chunk #${index} REJECTED status=${r.status} body=${body.slice(0,300)}`);
        // 4xx: no retry (409 recording_assembling, a revoked / expired upload token, no live run, …)
        if (r.status >= 400 && r.status < 500) break;
      } catch (e) {
        console.warn(`[Compositor] chunk #${index} network error attempt ${attempt}:`, e);
      }
      attempt++;
      if (attempt <= 3) await new Promise(res => setTimeout(res, 1000 * (1 << attempt)));
    }

    if (!uploaded && !_assembled) console.error(`[Compositor] chunk #${index} FAILED after ${attempt} attempts`);

    _pendingUploads--;
    _queueDepth--;

    // NOTE: this does NOT set window._ElFaheemCompositorDone — that now
    // signals "the recorder itself has stopped, safe to end the session",
    // set immediately in stop() without waiting for uploads to drain (see
    // the comment there for why). This flag is purely informational: it
    // tells anyone polling it that every chunk — including ones still
    // queued/uploading when stop() was called — has now actually reached
    // the server, entirely in the background.
    if (_stopping && _queueDepth === 0) {
      console.log('[Compositor] background uploads complete — all chunks delivered ✅');
      window._ElFaheemCompositorUploadsDone = true;
    }
  }

  // ── Compositor API ─────────────────────────────────────────────

  const compositor = {

    async start(sessionId, apiUrl, authToken, meta) {
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
      window._ElFaheemCompositorUploadsDone = false;

      // meta is a JSON string: {"teacherName":"...","sessionTitle":"...","participantCount":N}
      // Parsed defensively — a missing/malformed meta must never block the
      // recording itself from starting; the placeholder just falls back to
      // generic labels.
      _teacherName      = '';
      _sessionTitle     = '';
      _participantCount = 0;
      _uploadUrl        = '';
      _epoch            = '';
      _assembled        = false;
      window._ElFaheemCompositorAssembled = false;
      _videoBitrate     = VIDEO_BITRATE;
      _audioOnly        = false;
      _canvasHeight     = CANVAS_H;
      _chunkExt         = 'webm';
      try {
        if (meta) {
          const parsed = JSON.parse(meta);
          _teacherName      = String(parsed.teacherName  || '');
          _sessionTitle     = String(parsed.sessionTitle || '');
          _participantCount = Number(parsed.participantCount) || 0;
          _uploadUrl        = String(parsed.uploadUrl || '');
          _epoch            = String(parsed.epoch || '').slice(0, 64);
          const bps = Number(parsed.videoBitsPerSecond) || 0;
          if (bps > 0) _videoBitrate = bps;
          _audioOnly        = parsed.audioOnly === true;
          _canvasHeight     = Number(parsed.canvasHeight) || CANVAS_H;
        }
      } catch (e) {
        console.warn('[Compositor] failed to parse start() meta — using defaults:', e);
      }
      _sessionStartMs = Date.now();
      if (!_epoch) _epoch = String(_sessionStartMs); // an older Dart side sent none: one id per start still
      _isPaused = false;

      _sessionId = sessionId;
      _apiUrl    = apiUrl.replace(/\/$/, '');
      _authToken = authToken;

      console.log(`[Compositor] start() sessionId=${sessionId} apiUrl=${_apiUrl} audioOnly=${_audioOnly}`);

      // Audio-only (meeting recordings with quality "audio"): no canvas is
      // ever created — _ctx stays null, so _drawFrame()/_canvasDiag() are
      // no-ops, setPlaceholderImage has nothing to draw on, and the only
      // thing recorded is the mixed audio of _dest below (the local mic
      // plus every remote participant added through addStream — that
      // mixing is exactly the same as in the video mode).
      _canvas = null;
      _ctx    = null;
      if (!_audioOnly) {
        _canvas        = document.createElement('canvas');
        _canvas.width  = Math.round(_canvasHeight * 16 / 9 / 2) * 2;
        _canvas.height = _canvasHeight;
        _ctx           = _canvas.getContext('2d');
        _ctx.setTransform(_canvasHeight / CANVAS_H, 0, 0, _canvasHeight / CANVAS_H, 0, 0);
      }

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

      const audioTrack = _dest.stream.getAudioTracks()[0];
      let recordStream, mime, recorderOptions;
      if (_audioOnly) {
        // The mixed audio track alone — no canvas capture, no video track.
        // A suspended AudioContext has nothing else to fall back to here,
        // so the track is attached regardless and the periodic resume()
        // below keeps nudging the context (an audio-only session cannot
        // be "recorded video-only" instead).
        if (!audioTrack) {
          console.error('[Compositor] audio-only start: the mixed audio destination has no track — nothing to record');
          return;
        }
        if (_audioCtx.state !== 'running') {
          console.warn(`[Compositor] audio-only: audioCtx.state="${_audioCtx.state}" — recording anyway, resume() is retried periodically`);
        }
        recordStream = new MediaStream([audioTrack]);
        mime = _bestAudioMime();
        recorderOptions = { audioBitsPerSecond: 128_000 };
        if (mime) recorderOptions.mimeType = mime;
        _chunkExt = _chunkExtFor(mime);
        console.log(`[Compositor] audio-only: using mime "${mime || '(browser default)'}" → .${_chunkExt} chunks`);
      } else {
        const canvasStream = _canvas.captureStream(30);
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
        recordStream = canvasStream;
        mime = _bestMime();
        recorderOptions = { mimeType: mime, videoBitsPerSecond: _videoBitrate };
        _chunkExt = 'webm';
        console.log(`[Compositor] using mime: ${mime}`);
      }

      _recorder = new MediaRecorder(recordStream, recorderOptions);

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
      if (!_audioOnly) {
        _drawFrame();
        _rafId = setInterval(_drawFrame, 33);
      }

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
      // Audio-only: no <video> element is ever created (a screen share's
      // frames have nowhere to go); its audio track is still mixed in.
      const videoEl   = _audioOnly ? null : _makeVideoEl(stream);
      const audioNode = _connectAudio(stream, label);
      _sources[label] = { stream, videoEl, audioNode };
      console.log(`[Compositor] addStream: ${label} | video=${stream.getVideoTracks().length} audio=${stream.getAudioTracks().length}`);
    },

    // D-306: the room's tiles (see _drawLayout); invalid JSON keeps the last layout.
    setLayout(json) {
      try {
        const L = typeof json === 'string' ? JSON.parse(json) : json;
        _layout = L && Array.isArray(L.tiles) ? L : null;
      } catch (e) {
        console.warn('[Compositor] setLayout: bad layout', e);
      }
    },

    // D-306: a <canvas> the app paints (the whiteboard page) as source [label]: drawn as it is, never stopped.
    addCanvas(label, canvas) {
      if (!label || !canvas) return;
      if (_sources[label]) compositor.removeStream(label);
      _sources[label] = { canvasEl: canvas };
      console.log(`[Compositor] addCanvas: ${label} ${canvas.width}x${canvas.height}`);
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
        window._ElFaheemCompositorUploadsDone = true;
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
      // By the time the await above resolves, the final chunk (if any) has
      // already been synchronously enqueued onto _uploadChain by the
      // ondataavailable handler — so _queueDepth already reflects it here.

      await new Promise(r => setTimeout(r, 300));

      // Stop only the tracks the recorder opened itself (its own
      // getUserMedia camera/mic stream, label 'camera'). 'screen' is the
      // share LiveKit is still publishing and 'remote_<sid>' are LiveKit's
      // remote audio tracks: stopping those killed the live share and every
      // remote voice when "Stop recording" was pressed mid-meeting. They are
      // only detached from the compositor.
      Object.keys(_sources).forEach(label => {
        const src = _sources[label];
        const owned = OWNED_LABELS.indexOf(label) !== -1;
        compositor.removeStream(label);
        if (owned && src && src.stream) {
          src.stream.getTracks().forEach(t => { try { t.stop(); } catch(_){} });
        }
      });
      try { if (_silentSource) _silentSource.stop(); } catch (_) {}
      try { if (_silentSource) _silentSource.disconnect(); } catch (_) {}
      try { if (_silentGain) _silentGain.disconnect(); } catch (_) {}
      _silentSource = null;
      _silentGain   = null;
      try { if (_audioCtx) await _audioCtx.close(); } catch (_) {}

      if (_visibleContainer && _visibleContainer.parentNode) {
        _visibleContainer.parentNode.removeChild(_visibleContainer);
        _visibleContainer = null;
      }

      // IMPORTANT: do NOT block here waiting for the upload queue to drain.
      // Previously this awaited every queued/in-flight chunk (up to a 5-
      // minute timeout) before signalling done, which meant ending a
      // session — and whatever the app does next (leaving the room, calling
      // the server's session-end endpoint, navigating away) — could stall
      // for however long uploads needed on a slow connection.
      //
      // The recorder itself is fully finished at this point: MediaRecorder
      // has stopped and the final chunk is already enqueued on
      // _uploadChain. Any chunks still queued/uploading (see the
      // "upload queue backing up" warning in ondataavailable) keep
      // uploading completely independently of this function returning —
      // they're driven by _uploadChain's own promise chain, not by anyone
      // awaiting it. As long as this browser tab/page stays open (it does;
      // ending a session navigates within the same Flutter Web app, it
      // doesn't reload the page), those fetch() calls run to completion in
      // the background and the server-side idle/assembly logic picks them
      // up whenever they land — see _uploadChunk above for the
      // "background uploads complete" log that fires once that's done.
      if (_queueDepth === 0) {
        console.log('[Compositor] no pending uploads — done immediately');
        window._ElFaheemCompositorUploadsDone = true;
      } else {
        console.log(
          `[Compositor] recorder stopped — ${_queueDepth} chunk(s) still ` +
          `uploading in the background (not blocking session end)`
        );
      }
      window._ElFaheemCompositorDone = true;

      // Diagnostic only — doesn't depend on network/upload completion.
      // _hadRealData is set synchronously the moment any genuine non-empty
      // chunk was captured, so this is accurate immediately, unlike
      // _chunksUploaded (which only updates once a chunk's upload — now
      // possibly still in flight — actually succeeds).
      if (!_hadRealData) {
        console.error(
          '[Compositor] ⚠️ Session ended with ZERO chunks captured — ' +
          'nothing was recorded. No camera/mic and no usable screen-share ' +
          'frames were ever captured before stop() was called.'
        );
      }

      _layout = null;
      _stopping = false;
    },

    isActive() {
      return !!_recorder && _recorder.state !== 'inactive';
    },

    // Pause/resume use MediaRecorder's own native pause()/resume() rather
    // than any manual chunk-gating logic. This is deliberate: a paused
    // MediaRecorder is GUARANTEED by spec to fire zero 'dataavailable'
    // events — automatic (timeslice) or otherwise — until resume() is
    // called, so "don't send future chunks until resume" falls directly
    // out of the browser's own behavior rather than something we have to
    // track and enforce ourselves. Chunk numbering (_chunkIndex) simply
    // continues where it left off once resumed — no gap-handling needed on
    // the server side. The draw loop keeps running while paused (cheap, and
    // keeps the camera/screen video elements actively decoding — see
    // _pumpVideoFrames — so there's no freeze/black-frame moment right
    // after resume); MediaRecorder just doesn't consume any of those frames
    // until it's resumed.
    pause() {
      if (!_recorder || _recorder.state !== 'recording') {
        console.warn(
          `[Compositor] pause() ignored — recorder not in 'recording' state `
          + `(state=${_recorder ? _recorder.state : 'none'})`
        );
        return;
      }
      try {
        _recorder.pause();
        _isPaused = true;
        console.log('[Compositor] paused — no new chunks will be generated until resume()');
      } catch (e) {
        console.error('[Compositor] pause() error:', e);
      }
    },

    resume() {
      if (!_recorder || _recorder.state !== 'paused') {
        console.warn(
          `[Compositor] resume() ignored — recorder not in 'paused' state `
          + `(state=${_recorder ? _recorder.state : 'none'})`
        );
        return;
      }
      try {
        _recorder.resume();
        _isPaused = false;
        console.log('[Compositor] resumed — chunk generation continues');
      } catch (e) {
        console.error('[Compositor] resume() error:', e);
      }
    },

    // Live participant count changes throughout a session (students join/
    // leave) — this lets the Dart side push updates without restarting the
    // compositor. Only affects the next placeholder frame drawn; harmless
    // to call whether or not the placeholder is currently on-screen.
    updateParticipants(count) {
      const n = Number(count);
      _participantCount = Number.isFinite(n) ? Math.max(0, Math.round(n)) : 0;
    },
  };

  window._ElFaheemCompositor     = compositor;
  window._ElFaheemCompositorDone = false;
  window._ElFaheemCompositorHadRealData    = false;
  window._ElFaheemCompositorChunksUploaded = 0;
  window._ElFaheemCompositorUploadsDone    = false;

  window._elfaheemCompositor = function(cmd, a1, a2, a3, a4) {
    switch (cmd) {
      case 'start':             return compositor.start(a1, a2, a3, a4);
      case 'addStream':         return compositor.addStream(a1, a2);
      case 'removeStream':      return compositor.removeStream(a1);
      case 'stop':              return compositor.stop();
      case 'isActive':          return compositor.isActive();
      case 'updateParticipants':return compositor.updateParticipants(a1);
      case 'pause':             return compositor.pause();
      case 'resume':            return compositor.resume();
      case 'setLayout':         return compositor.setLayout(a1);
      case 'addCanvas':         return compositor.addCanvas(a1, a2);
      default: console.warn('[Compositor] unknown cmd:', cmd);
    }
  };

  console.log('[Compositor] loaded — version 11 (D-306 room layout: cameras grid / stage + thumbnails, board canvas; premium branded placeholder w/ teacher+session+participant info, VP9/VP8-first mime selection, setInterval draw loop, periodic safety-flush, real-data/upload tracking)');
})();