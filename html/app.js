const hud           = document.getElementById('hud');
const hudTitle      = document.getElementById('hudTitle');

const hudWaiting    = document.getElementById('hudWaiting');
const waitingStatus = document.getElementById('waitingStatus');

const hudCall       = document.getElementById('hudCall');
const callLabel     = document.getElementById('callLabel');
const callModel     = document.getElementById('callModel');
const callPlate     = document.getElementById('callPlate');
const callReason    = document.getElementById('callReason');
const phaseLabel    = document.getElementById('phaseLabel');
const phaseValue    = document.getElementById('phaseValue');

const brandVersion  = document.getElementById('brandVersion');
const brandLink     = document.getElementById('brandLink');

function formatTime(seconds) {
    const s = Math.max(0, Math.floor(Number(seconds) || 0));
    const m = Math.floor(s / 60);
    const r = s % 60;
    return `${m}:${r.toString().padStart(2, '0')}`;
}

function applyState(data) {
    if (!data) return;

    if (!data.onDuty) {
        hud.classList.add('hidden');
        return;
    }

    hud.classList.remove('hidden');

    if (data.version) brandVersion.textContent = `v${data.version}`;
    if (data.repo) {
        brandLink.href = data.repo;
        brandLink.style.display = '';
    } else {
        brandLink.style.display = 'none';
    }

    if (data.hasCall) {
        hudTitle.textContent = 'Active Call';
        hudWaiting.classList.add('hidden');
        hudCall.classList.remove('hidden');

        callLabel.textContent  = data.callLabel  || '—';
        callModel.textContent  = data.callModel  || '—';
        callPlate.textContent  = data.callPlate  || '—';
        callReason.textContent = data.callReason || '—';

        if (data.pickedUp) {
            phaseLabel.textContent = 'Phase';
            phaseValue.textContent = 'Deliver to Yard';
            phaseValue.classList.add('gold');
        } else {
            phaseLabel.textContent = 'Phase';
            phaseValue.textContent = 'Locate & Hook';
            phaseValue.classList.remove('gold');
        }
    } else {
        hudTitle.textContent = 'Standing By';
        hudCall.classList.add('hidden');
        hudWaiting.classList.remove('hidden');
        waitingStatus.textContent = 'Awaiting call…';
        waitingStatus.classList.remove('countdown');
    }
}

// ─── Equipment spawner ───────────────────────────────────────────

const spawner       = document.getElementById('spawner');
const spawnerGrid   = document.getElementById('spawnerGrid');
const spawnerClose  = document.getElementById('spawnerClose');

function postNui(name, data) {
    return fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    }).then((r) => r.json()).catch(() => ({}));
}

function openSpawner(items) {
    spawnerGrid.innerHTML = '';

    (items || []).forEach((item) => {
        const card = document.createElement('div');
        card.className = 'spawner-card';
        card.innerHTML = `
            <span class="spawner-card-icon">${item.icon || '🚧'}</span>
            <span class="spawner-card-label">${item.label}</span>
        `;
        card.addEventListener('click', () => {
            postNui('selectSpawnItem', { id: item.id });
        });
        spawnerGrid.appendChild(card);
    });

    spawner.classList.remove('hidden');
}

function closeSpawner() {
    spawner.classList.add('hidden');
}

spawnerClose.addEventListener('click', () => {
    postNui('closeSpawner');
});

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && !spawner.classList.contains('hidden')) {
        postNui('closeSpawner');
    }
});

// ─── Dispatch audio ───────────────────────────────────────────────

const chirpOpen  = document.getElementById('chirpOpen');
const chirpClose = document.getElementById('chirpClose');

function pickVoice(prefer) {
    const voices = window.speechSynthesis ? speechSynthesis.getVoices() : [];
    if (!voices.length) return null;
    if (Array.isArray(prefer)) {
        for (const frag of prefer) {
            const v = voices.find(v =>
                (v.name && v.name.toLowerCase().includes(frag.toLowerCase())) ||
                (v.lang && v.lang.toLowerCase().includes(frag.toLowerCase()))
            );
            if (v) return v;
        }
    }
    return voices.find(v => v.lang && v.lang.startsWith('en')) || voices[0];
}

function fillTemplate(tpl, vars) {
    return (tpl || '').replace(/\{(\w+)\}/g, (_, key) => vars[key] != null ? vars[key] : '');
}

function playChirp(audioEl, src, volume) {
    if (!audioEl || !src) return Promise.resolve();
    if (audioEl.src.indexOf(src) === -1) audioEl.src = src;
    audioEl.volume = (typeof volume === 'number') ? volume : 0.55;
    try { audioEl.currentTime = 0; } catch (e) {}
    return audioEl.play().catch(() => {});
}

function speak(text, opts) {
    if (!('speechSynthesis' in window) || !text) return;
    speechSynthesis.cancel();
    const utter = new SpeechSynthesisUtterance(text);
    utter.rate   = opts.rate   != null ? opts.rate   : 0.95;
    utter.pitch  = opts.pitch  != null ? opts.pitch  : 0.85;
    utter.volume = opts.volume != null ? opts.volume : 0.90;
    const voice  = pickVoice(opts.prefer);
    if (voice) utter.voice = voice;
    if (opts.onend) utter.onend = opts.onend;
    speechSynthesis.speak(utter);
}

function playDispatchAudio(data) {
    if (!data) return;

    const text = fillTemplate(data.template, {
        location: data.location,
        model:    data.model,
        plate:    data.plate,
        reason:   data.reason,
    });

    const speakNow = () => {
        if (!data.voice) return;
        speak(text, {
            rate:   data.voiceRate,
            pitch:  data.voicePitch,
            volume: data.voiceVolume,
            prefer: data.voicePrefer,
            onend:  () => {
                if (data.chirps) {
                    playChirp(chirpClose, data.chirpClose, data.chirpVolume);
                }
            },
        });
    };

    if (data.chirps) {
        playChirp(chirpOpen, data.chirpOpen, data.chirpVolume);
        setTimeout(speakNow, 350);
    } else {
        speakNow();
    }
}

// Some CEF builds populate voices asynchronously — warm them up.
if ('speechSynthesis' in window) {
    speechSynthesis.onvoiceschanged = () => { /* triggers voice list cache */ };
}

window.addEventListener('message', (event) => {
    const payload = event.data;
    if (!payload || !payload.action) return;

    if (payload.action === 'show')          applyState(payload.data);
    if (payload.action === 'update')        applyState(payload.data);
    if (payload.action === 'hide')          hud.classList.add('hidden');
    if (payload.action === 'dispatchAudio') playDispatchAudio(payload.data);
    if (payload.action === 'openSpawner')   openSpawner(payload.data && payload.data.items);
    if (payload.action === 'closeSpawner')  closeSpawner();
});
