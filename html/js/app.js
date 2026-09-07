/* ============================================================================
   BUCU Hotwire Ignition Minigame — Frontend Logic
   Delta-Time Precision Rotary Timing with Sound Synthesis & Direct Cancel
   ============================================================================ */

'use strict';

(function () {
    const RESOURCE_NAME = (window.GetParentResourceName ? window.GetParentResourceName() : 'bucu_vehiclekeys');

    // DOM Elements
    const appRoot          = document.getElementById('hotwire-app');
    const cardEl           = document.getElementById('hotwire-card');
    const dialTarget       = document.getElementById('dial-target');
    const needleGroup      = document.getElementById('needle-group');
    const dialWrapper      = document.getElementById('dial-wrapper');
    const strikeButton     = document.getElementById('strike-button');
    const headerCancelBtn  = document.getElementById('header-cancel-btn');
    const footerCancelBtn  = document.getElementById('footer-cancel-btn');
    const stageInfoText    = document.getElementById('stage-info-text');
    const stageHintText    = document.getElementById('stage-hint-text');
    const canvas           = document.getElementById('sparks-canvas');
    const ctx              = canvas ? canvas.getContext('2d') : null;

    // Wire Elements
    const wireItems = [
        document.getElementById('wire-1'),
        document.getElementById('wire-2'),
        document.getElementById('wire-3')
    ];
    const wireStatuses = [
        document.getElementById('wire-status-1'),
        document.getElementById('wire-status-2'),
        document.getElementById('wire-status-3')
    ];

    // State
    let isActive           = false;
    let currentStage       = 1;
    let totalStages        = 3;
    let currentPlate       = '';
    let lang               = 'id';
    let currentAngle       = 0;     // 0 to 360 degrees
    let targetStart        = 90;    // start angle of target zone (degrees)
    let targetSize         = 42;    // angular span of target zone (degrees)
    let degPerSec          = 160;   // degrees per second
    let direction          = 1;     // 1 = clockwise, -1 = counter-clockwise
    let animFrameId        = null;
    let lastTime           = 0;
    let isProcessingHit    = false;

    // Stage Labels
    const STAGE_CONFIGS = {
        id: [
            { title: 'Tahap 1: Sambung Kabel Starter', hint: 'Tekan SPASI atau KLIK saat jarum di zona hijau' },
            { title: 'Tahap 2: Hubungkan Jalur Aki 12V', hint: 'Arah putaran terbalik! Tekan saat di zona hijau' },
            { title: 'Tahap 3: Aktifkan Switch Kontak', hint: 'Putaran cepat! Sambung kontak untuk menyalakan mesin' }
        ],
        en: [
            { title: 'Stage 1: Connect Starter Wire', hint: 'Press SPACE or CLICK when needle hits green zone' },
            { title: 'Stage 2: Bypass 12V Battery Rail', hint: 'Reverse rotation! Hit the green zone' },
            { title: 'Stage 3: Engage Ignition Switch', hint: 'Fast spin! Connect ignition to start engine' }
        ]
    };

    // ── Web Audio API Synthesizer (Zero External Files) ───────────────────────
    let audioCtx = null;

    function getAudioContext() {
        try {
            if (!audioCtx) {
                const AudioClass = window.AudioContext || window.webkitAudioContext;
                if (AudioClass) audioCtx = new AudioClass();
            }
            if (audioCtx && audioCtx.state === 'suspended') {
                audioCtx.resume();
            }
            return audioCtx;
        } catch (e) {
            return null;
        }
    }

    function playSparkSound() {
        try {
            const ctxA = getAudioContext();
            if (!ctxA) return;
            const now = ctxA.currentTime;

            // Spark burst noise
            const bufSize = Math.floor(ctxA.sampleRate * 0.08);
            const buffer = ctxA.createBuffer(1, bufSize, ctxA.sampleRate);
            const data = buffer.getChannelData(0);
            for (let i = 0; i < bufSize; i++) data[i] = Math.random() * 2 - 1;

            const noise = ctxA.createBufferSource();
            noise.buffer = buffer;
            const filter = ctxA.createBiquadFilter();
            filter.type = 'bandpass';
            filter.frequency.value = 1800;

            const gain = ctxA.createGain();
            gain.gain.setValueAtTime(0.2, now);
            gain.gain.exponentialRampToValueAtTime(0.001, now + 0.08);

            noise.connect(filter);
            filter.connect(gain);
            gain.connect(ctxA.destination);
            noise.start(now);

            // Chime chord
            [523.25, 659.25, 783.99, 1046.50].forEach((freq, i) => {
                const osc = ctxA.createOscillator();
                const oGain = ctxA.createGain();
                osc.type = 'triangle';
                osc.frequency.setValueAtTime(freq, now + (i * 0.035));
                oGain.gain.setValueAtTime(0.12, now + (i * 0.035));
                oGain.gain.exponentialRampToValueAtTime(0.001, now + 0.35 + (i * 0.035));
                osc.connect(oGain);
                oGain.connect(ctxA.destination);
                osc.start(now + (i * 0.035));
                osc.stop(now + 0.35 + (i * 0.035));
            });
        } catch (e) {}
    }

    function playFailSound() {
        try {
            const ctxA = getAudioContext();
            if (!ctxA) return;
            const now = ctxA.currentTime;
            const osc = ctxA.createOscillator();
            const gain = ctxA.createGain();
            osc.type = 'sawtooth';
            osc.frequency.setValueAtTime(160, now);
            osc.frequency.exponentialRampToValueAtTime(45, now + 0.35);
            gain.gain.setValueAtTime(0.2, now);
            gain.gain.exponentialRampToValueAtTime(0.001, now + 0.35);
            osc.connect(gain);
            gain.connect(ctxA.destination);
            osc.start(now);
            osc.stop(now + 0.35);
        } catch (e) {}
    }

    // ── Particle Sparks Engine ────────────────────────────────────────────────
    let particles = [];

    function resizeCanvas() {
        if (!canvas) return;
        canvas.width = window.innerWidth || 1920;
        canvas.height = window.innerHeight || 1080;
    }
    window.addEventListener('resize', resizeCanvas);
    resizeCanvas();

    function spawnSparks(x, y, count = 35) {
        if (!ctx) return;
        for (let i = 0; i < count; i++) {
            const angle = Math.random() * Math.PI * 2;
            const speed = 2 + Math.random() * 8;
            particles.push({
                x: x,
                y: y,
                vx: Math.cos(angle) * speed,
                vy: Math.sin(angle) * speed,
                life: 1.0,
                decay: 0.02 + Math.random() * 0.035,
                size: 2 + Math.random() * 3.5,
                color: Math.random() > 0.35 ? '#10b981' : '#f59e0b'
            });
        }
    }

    function updateParticles() {
        if (!ctx) return;
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        for (let i = particles.length - 1; i >= 0; i--) {
            const p = particles[i];
            p.x += p.vx;
            p.y += p.vy;
            p.vy += 0.28;
            p.life -= p.decay;

            if (p.life <= 0) {
                particles.splice(i, 1);
            } else {
                ctx.save();
                ctx.globalAlpha = p.life;
                ctx.fillStyle = p.color;
                ctx.beginPath();
                ctx.arc(p.x, p.y, p.size, 0, Math.PI * 2);
                ctx.fill();
                ctx.restore();
            }
        }
        if (particles.length > 0 || isActive) {
            requestAnimationFrame(updateParticles);
        }
    }

    // ── SVG Dial Target Arc Calculations ──────────────────────────────────────
    const CIRCUMFERENCE = 2 * Math.PI * 85; // radius 85 ~= 534.0707

    function updateTargetArc(startDeg, sizeDeg) {
        if (!dialTarget) return;
        const strokeLength = (sizeDeg / 360) * CIRCUMFERENCE;
        dialTarget.setAttribute('stroke-dasharray', `${strokeLength} ${CIRCUMFERENCE}`);
        dialTarget.setAttribute('stroke-dashoffset', '0');
        dialTarget.setAttribute('transform', `rotate(${startDeg - 90}, 110, 110)`);
    }

    // ── Setup Stage ───────────────────────────────────────────────────────────
    function setupStage(stage) {
        currentStage = stage;
        isProcessingHit = false;

        // Random target start angle between 35° and 315°
        targetStart = Math.floor(35 + Math.random() * 280);

        if (stage === 1) {
            targetSize = 44; // Generous sweet spot
            degPerSec = 160;
            direction = 1;
            currentAngle = 0;
        } else if (stage === 2) {
            targetSize = 36;
            degPerSec = 195;
            direction = -1; // Counter-clockwise
            currentAngle = 360;
        } else {
            targetSize = 30;
            degPerSec = 230;
            direction = 1;
            currentAngle = 0;
        }

        updateTargetArc(targetStart, targetSize);

        // Update Text Info
        const configs = STAGE_CONFIGS[lang] || STAGE_CONFIGS['id'];
        const stageConfig = configs[stage - 1] || configs[0];
        if (stageInfoText) stageInfoText.textContent = stageConfig.title;
        if (stageHintText) stageHintText.textContent = stageConfig.hint;

        // Update Wire Status
        wireItems.forEach((wire, idx) => {
            if (!wire) return;
            wire.classList.remove('active');
            if (idx + 1 < stage) {
                wire.classList.add('connected');
                if (wireStatuses[idx]) wireStatuses[idx].textContent = (lang === 'id') ? 'TERHUBUNG' : 'CONNECTED';
                const chk = wire.querySelector('.wire-check');
                if (chk) chk.textContent = '✔';
            } else if (idx + 1 === stage) {
                wire.classList.add('active');
                if (wireStatuses[idx]) wireStatuses[idx].textContent = (lang === 'id') ? 'MENYAMBUNG...' : 'CONNECTING...';
                const chk = wire.querySelector('.wire-check');
                if (chk) chk.textContent = '●';
            } else {
                if (wireStatuses[idx]) wireStatuses[idx].textContent = (lang === 'id') ? 'MENUNGGU' : 'PENDING';
                const chk = wire.querySelector('.wire-check');
                if (chk) chk.textContent = '○';
            }
        });

        lastTime = performance.now();
    }

    // ── Main Animation Loop with DeltaTime ────────────────────────────────────
    function gameLoop(now) {
        if (!isActive) return;

        if (!lastTime) lastTime = now;
        const dt = Math.min((now - lastTime) / 1000, 0.05);
        lastTime = now;

        currentAngle = (currentAngle + (degPerSec * direction * dt)) % 360;
        if (currentAngle < 0) currentAngle += 360;

        if (needleGroup) {
            needleGroup.setAttribute('transform', `rotate(${currentAngle}, 110, 110)`);
        }

        animFrameId = requestAnimationFrame(gameLoop);
    }

    // ── Check Strike Precision ────────────────────────────────────────────────
    function handleStrike() {
        if (!isActive || isProcessingHit) return;
        isProcessingHit = true;

        const targetEnd = (targetStart + targetSize) % 360;
        let isHit = false;

        if (targetStart + targetSize <= 360) {
            isHit = (currentAngle >= targetStart && currentAngle <= (targetStart + targetSize));
        } else {
            isHit = (currentAngle >= targetStart || currentAngle <= targetEnd);
        }

        if (isHit) {
            // SUCCESSFUL STRIKE!
            playSparkSound();

            if (dialWrapper) {
                const dialRect = dialWrapper.getBoundingClientRect();
                spawnSparks(dialRect.left + dialRect.width / 2, dialRect.top + dialRect.height / 2, 40);
            }

            const activeWire = wireItems[currentStage - 1];
            if (activeWire) {
                activeWire.classList.remove('active');
                activeWire.classList.add('connected');
                if (wireStatuses[currentStage - 1]) {
                    wireStatuses[currentStage - 1].textContent = (lang === 'id') ? 'TERHUBUNG' : 'CONNECTED';
                }
                const chk = activeWire.querySelector('.wire-check');
                if (chk) chk.textContent = '✔';
            }

            if (cardEl) {
                cardEl.classList.add('success-flash');
                setTimeout(() => cardEl.classList.remove('success-flash'), 250);
            }

            if (currentStage >= totalStages) {
                if (stageInfoText) {
                    stageInfoText.textContent = (lang === 'id') ? 'Mesin Berhasil Dinyalakan!' : 'Engine Started!';
                }
                if (stageHintText) {
                    stageHintText.textContent = (lang === 'id') ? 'Kelistrikan terhubung' : 'Ignition connected';
                }
                setTimeout(() => {
                    closeMinigame(true, false);
                }, 500);
            } else {
                setTimeout(() => {
                    setupStage(currentStage + 1);
                }, 200);
            }
        } else {
            // FAILED STRIKE
            playFailSound();
            if (cardEl) {
                cardEl.classList.add('fail-shake');
                setTimeout(() => cardEl.classList.remove('fail-shake'), 400);
            }
            if (stageInfoText) {
                stageInfoText.textContent = (lang === 'id') ? 'Korsleting! Gagal Menyambung' : 'Short Circuit! Failed';
                stageInfoText.style.color = '#ef4444';
            }
            if (stageHintText) {
                stageHintText.textContent = (lang === 'id') ? 'Alarm mobil berbunyi!' : 'Vehicle alarm triggered!';
            }

            setTimeout(() => {
                closeMinigame(false, false);
            }, 600);
        }
    }

    // ── Start & Close Minigame ────────────────────────────────────────────────
    function startMinigame(data) {
        isActive = true;
        isProcessingHit = false;
        currentStage = 1;
        totalStages = data.stages || 3;
        currentPlate = data.plate || '';
        lang = data.lang || 'id';

        if (stageInfoText) stageInfoText.style.color = '#f8fafc';
        if (cardEl) cardEl.classList.remove('success-flash', 'fail-shake');

        if (appRoot) {
            appRoot.classList.add('active');
            appRoot.style.display = 'flex';
        }

        setupStage(1);

        window.focus();
        if (cardEl) cardEl.focus();

        cancelAnimationFrame(animFrameId);
        lastTime = performance.now();
        animFrameId = requestAnimationFrame(gameLoop);
        if (ctx) requestAnimationFrame(updateParticles);
    }

    function closeMinigame(isSuccess, isCancelled = false) {
        isActive = false;
        cancelAnimationFrame(animFrameId);

        if (appRoot) {
            appRoot.classList.remove('active');
            appRoot.style.display = 'none';
        }

        // Callback to client Lua
        fetch(`https://${RESOURCE_NAME}/hotwireResult`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify({
                success: isSuccess,
                cancelled: isCancelled,
                plate: currentPlate
            })
        }).catch(() => {});
    }

    // ── Input Handlers ────────────────────────────────────────────────────────
    // Keyboard inputs
    window.addEventListener('keydown', (e) => {
        if (!isActive) return;

        if (e.code === 'Space' || e.code === 'Enter') {
            e.preventDefault();
            handleStrike();
        } else if (e.key === 'Escape' || e.key === 'Backspace' || e.key === 'x' || e.key === 'X') {
            e.preventDefault();
            closeMinigame(false, true);
        }
    });

    // Strike button
    if (strikeButton) {
        strikeButton.addEventListener('click', (e) => {
            if (!isActive) return;
            e.preventDefault();
            handleStrike();
        });
    }

    // Dial click
    if (dialWrapper) {
        dialWrapper.addEventListener('mousedown', (e) => {
            if (!isActive) return;
            e.preventDefault();
            handleStrike();
        });
    }

    // Header Cancel Button
    if (headerCancelBtn) {
        headerCancelBtn.addEventListener('click', (e) => {
            if (!isActive) return;
            e.preventDefault();
            closeMinigame(false, true);
        });
    }

    // Footer Cancel Button
    if (footerCancelBtn) {
        footerCancelBtn.addEventListener('click', (e) => {
            if (!isActive) return;
            e.preventDefault();
            closeMinigame(false, true);
        });
    }

    // FiveM NUI Message Listener
    window.addEventListener('message', (event) => {
        const msg = event.data;
        if (!msg || !msg.action) return;

        if (msg.action === 'START_HOTWIRE') {
            startMinigame(msg);
        } else if (msg.action === 'CANCEL_HOTWIRE') {
            closeMinigame(false, true);
        }
    });
})();
