// recorder_compositor.js
// Injected into the Flutter Web page at startup.
// Provides window._ElFaheemCompositor — a JS object that:
//   1. Draws all active video sources (camera + screen) onto a canvas at 30fps
//   2. Mixes all audio sources (mic + system audio) via AudioContext
//   3. Records the composite canvas stream with MediaRecorder
//   4. Uploads chunks to the server via fetch
//
// Usage from Dart (via dart:js_interop callMethod):
//   window._ElFaheemCompositor.start(sessionId, apiUrl, authToken)
//   window._ElFaheemCompositor.addStream(stream, label)   // 'camera'|'screen'|'mic'
//   window._ElFaheemCompositor.removeStream(label)
//   window._ElFaheemCompositor.stop()

(function () {
  'use strict';

  const CHUNK_INTERVAL_MS = 30_000;   // upload every 30 seconds
  const CANVAS_W = 1920;
  const CANVAS_H = 1080;
  const VIDEO_BITRATE = 8_000_000;    // 8 Mbps

  let _canvas, _ctx, _audioCtx, _dest, _recorder;
  let _rafId = null;
  let _sessionId, _apiUrl, _authToken;
  let _chunkIndex = 0;
  let _pendingUploads = 0;
  let _stopping = false;

  // Map of label → { stream, videoEl, audioNode }
  const _sources = {};

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

    // Draw screen share full-canvas first (if active)
    const screen = _sources['screen'];
    if (screen && screen.videoEl && screen.videoEl.readyState >= 2) {
      _ctx.drawImage(screen.videoEl, 0, 0, CANVAS_W, CANVAS_H);
    }

    // Draw camera as PiP bottom-right (only when screen share is active)
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
        // Camera only: full canvas
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

  function _makeVideoEl(stream) {
    const videoTracks = stream.getVideoTracks();
    if (!videoTracks.length) return null;
    const el = document.createElement('video');
    el.srcObject = new MediaStream(videoTracks);
    el.muted = true;
    el.autoplay = true;
    el.playsInline = true;
    el.play().catch(() => {});
    return el;
  }

  async function _uploadChunk(blob, index, isFinal) {
    _pendingUploads++;
    const form = new FormData();
    form.append('chunk_index', index);
    form.append('is_final', isFinal ? 'true' : 'false');
    form.append('chunk', blob, `chunk_${String(index).padStart(6, '0')}.webm`);
    let attempt = 0;
    while (attempt <= 3) {
      try {
        const r = await fetch(`${_apiUrl}/api/v1/live-sessions/${_sessionId}/recording-chunk`, {
          method: 'POST',
          headers: { Authorization: _authToken },
          body: form,
        });
        if (r.ok) break;
      } catch (e) {
        console.warn('[Compositor] chunk upload attempt', attempt, e);
      }
      attempt++;
      if (attempt <= 3) await new Promise(r => setTimeout(r, 1000 * (1 << attempt)));
    }
    _pendingUploads--;
    if (_stopping && _pendingUploads === 0) {
      console.log('[Compositor] all chunks uploaded');
      window._ElFaheemCompositorDone = true;
    }
  }

  const compositor = {
    // ── start ─────────────────────────────────────────────────────────────────
    start(sessionId, apiUrl, authToken) {
      _sessionId   = sessionId;
      _apiUrl      = apiUrl.replace(/\/$/, '');
      _authToken   = authToken;
      _chunkIndex  = 0;
      _stopping    = false;
      window._ElFaheemCompositorDone = false;

      // Canvas
      _canvas = document.createElement('canvas');
      _canvas.width  = CANVAS_W;
      _canvas.height = CANVAS_H;
      _ctx = _canvas.getContext('2d');

      // AudioContext mixer
      _audioCtx = new AudioContext();
      _dest = _audioCtx.createMediaStreamDestination();

      // Composite stream = canvas video + mixed audio
      const canvasStream = _canvas.captureStream(30);
      const audioTrack   = _dest.stream.getAudioTracks()[0];
      if (audioTrack) canvasStream.addTrack(audioTrack);

      // MediaRecorder
      const mime = _bestMime();
      _recorder = new MediaRecorder(canvasStream, {
        mimeType: mime,
        videoBitsPerSecond: VIDEO_BITRATE,
      });
      _recorder.ondataavailable = (e) => {
        if (e.data && e.data.size > 0) {
          const idx   = _chunkIndex++;
          const final = _stopping && idx === _chunkIndex - 1;
          _uploadChunk(e.data, idx, final);
        }
      };
      _recorder.start(CHUNK_INTERVAL_MS);

      // Start draw loop
      _drawFrame();
      console.log('[Compositor] started mime=' + mime);
    },

    // ── addStream ─────────────────────────────────────────────────────────────
    // label: 'camera' | 'screen' | 'mic'
    addStream(stream, label) {
      if (!stream) return;
      if (_sources[label]) compositor.removeStream(label);

      const videoEl   = _makeVideoEl(stream);
      const audioNode = _connectAudio(stream, label);
      _sources[label] = { stream, videoEl, audioNode };
      console.log('[Compositor] addStream:', label,
        'video tracks:', stream.getVideoTracks().length,
        'audio tracks:', stream.getAudioTracks().length);
    },

    // ── removeStream ──────────────────────────────────────────────────────────
    removeStream(label) {
      const src = _sources[label];
      if (!src) return;
      if (src.videoEl) { src.videoEl.srcObject = null; }
      if (src.audioNode) { try { src.audioNode.disconnect(); } catch (_) {} }
      delete _sources[label];
      console.log('[Compositor] removeStream:', label);
    },

    // ── stop ──────────────────────────────────────────────────────────────────
    async stop() {
      _stopping = true;
      if (_rafId) { cancelAnimationFrame(_rafId); _rafId = null; }

      // Request final data and stop recorder
      if (_recorder && _recorder.state !== 'inactive') {
        _recorder.requestData();
        await new Promise(r => setTimeout(r, 300));
        _recorder.stop();
      }

      // Stop all source tracks
      Object.values(_sources).forEach(src => {
        if (src.stream) src.stream.getTracks().forEach(t => { try { t.stop(); } catch(_){} });
      });

      // Close audio context
      try { if (_audioCtx) await _audioCtx.close(); } catch (_) {}

      // Wait for pending uploads (max 5 min)
      const deadline = Date.now() + 5 * 60 * 1000;
      while (_pendingUploads > 0 && Date.now() < deadline) {
        await new Promise(r => setTimeout(r, 500));
      }
      window._ElFaheemCompositorDone = true;
      console.log('[Compositor] stopped');
    },

    isActive() {
      return !!_recorder && _recorder.state !== 'inactive';
    },
  };

  window._ElFaheemCompositor = compositor;
  console.log('[Compositor] loaded');
})();
