const loginView = document.getElementById('loginView');
const dutyView = document.getElementById('dutyView');
const companyInput = document.getElementById('companyInput');
const passwordInput = document.getElementById('passwordInput');
const loginBtn = document.getElementById('loginBtn');
const loginError = document.getElementById('loginError');
const logoutBtn = document.getElementById('logoutBtn');
const companyTitle = document.getElementById('companyTitle');
const phoneOnlyToggle = document.getElementById('phoneOnlyToggle');
const queueCount = document.getElementById('queueCount');
const queueList = document.getElementById('queueList');
const refreshBtn = document.getElementById('refreshBtn');
const offerCard = document.getElementById('offerCard');
const offerTitle = document.getElementById('offerTitle');
const offerMeta = document.getElementById('offerMeta');
const acceptOfferBtn = document.getElementById('acceptOfferBtn');
const rejectOfferBtn = document.getElementById('rejectOfferBtn');

let state = { onDuty: false, calls: [] };
let activeOfferId = null;
let busy = false;

function parentResource() {
    if (globalThis.resourceName) return globalThis.resourceName;
    if (typeof GetParentResourceName === 'function') return GetParentResourceName();
    return 'TwoPoint_TowDuty';
}

async function nui(name, data = {}) {
    if (typeof globalThis.fetchNui === 'function') {
        return await globalThis.fetchNui(name, data);
    }

    const response = await fetch(`https://${parentResource()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    });

    return await response.json();
}

function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>'"]/g, char => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        "'": '&#39;',
        '"': '&quot;'
    }[char]));
}

function formatDistance(distance) {
    if (typeof distance !== 'number' || distance < 0) return 'N/A';
    if (distance >= 1000) return `${(distance / 1000).toFixed(1)} km`;
    return `${distance.toFixed(0)} m`;
}

function formatAge(seconds) {
    seconds = Math.max(0, Math.floor(Number(seconds) || 0));
    const minutes = Math.floor(seconds / 60);
    if (minutes < 1) return `${seconds}s`;
    if (minutes < 60) return `${minutes}m`;
    return `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
}

function setError(message) {
    loginError.textContent = message || '';
    loginError.classList.toggle('hidden', !message);
}

function updateState(nextState = {}) {
    state = nextState || {};
    busy = !!state.busy;

    loginView.classList.toggle('hidden', !!state.onDuty);
    dutyView.classList.toggle('hidden', !state.onDuty);

    if (!state.onDuty) {
        activeOfferId = null;
        offerCard.classList.add('hidden');
        renderQueue([]);
        return;
    }

    companyTitle.textContent = state.companyName || 'Tow';
    phoneOnlyToggle.checked = !!state.phoneOnlyMode;
    phoneOnlyToggle.disabled = !!state.forcePhoneOnlyMode;

    const calls = state.calls || [];
    const activeOffer = state.activeOffer || calls.find(call => call.offeredToMe);
    renderOffer(activeOffer);
    renderQueue(calls);
}

function renderOffer(call) {
    if (!call) {
        activeOfferId = null;
        offerCard.classList.add('hidden');
        return;
    }

    activeOfferId = call.id;
    offerTitle.textContent = `#${call.id} - ${call.requesterName || 'Unknown'}`;
    offerMeta.textContent = `${formatDistance(call.distance)} away • ${formatAge(call.ageSeconds)} old`;
    offerCard.classList.remove('hidden');
}

function renderQueue(calls) {
    queueList.innerHTML = '';
    queueCount.textContent = `${calls.length} ${calls.length === 1 ? 'call' : 'calls'}`;

    if (!calls.length) {
        queueList.innerHTML = '<div class="empty">No tow calls waiting right now.</div>';
        return;
    }

    for (const call of calls) {
        const canAccept = !!call.canAccept;
        const canReject = !!call.canReject;
        const div = document.createElement('article');
        div.className = 'call-card';
        div.innerHTML = `
            <div class="call-top">
                <div class="call-title">#${escapeHtml(call.id)} - ${escapeHtml(call.requesterName || 'Unknown')}</div>
                <div class="status">${escapeHtml(call.status || 'queued')}</div>
            </div>
            <div class="meta">
                <div>Company: ${escapeHtml(call.companyName || 'Any')}</div>
                <div>Distance: ${escapeHtml(formatDistance(call.distance))}</div>
                <div>Age: ${escapeHtml(formatAge(call.ageSeconds))}</div>
                <div>Driver: ${escapeHtml(call.assignedDriver || 'None')}</div>
            </div>
            <div class="call-actions ${canReject ? 'two' : ''}">
                <button class="primary accept-call" type="button" ${canAccept ? '' : 'disabled'}>${canAccept ? 'Accept' : busy ? 'Busy' : 'Unavailable'}</button>
                ${canReject ? '<button class="danger reject-call" type="button">Reject</button>' : ''}
            </div>
        `;

        div.querySelector('.accept-call').addEventListener('click', () => {
            if (canAccept) acceptCall(call.id, call.offeredToMe);
        });

        const rejectBtn = div.querySelector('.reject-call');
        if (rejectBtn) {
            rejectBtn.addEventListener('click', () => respondToOffer(call.id, false));
        }

        queueList.appendChild(div);
    }
}

async function refreshState() {
    try {
        updateState(await nui('phoneGetState'));
    } catch (error) {
        console.error(error);
    }
}

async function login() {
    setError('');
    const companyName = companyInput.value.trim() || 'Tow';
    const password = passwordInput.value;

    loginBtn.disabled = true;
    try {
        const result = await nui('phoneLogin', { companyName, password });
        if (!result || !result.ok) {
            setError(result && result.error ? result.error : 'Unable to sign in.');
            return;
        }

        passwordInput.value = '';
        updateState(result.state || await nui('phoneGetState'));
    } catch (error) {
        setError('Unable to sign in.');
        console.error(error);
    } finally {
        loginBtn.disabled = false;
    }
}

async function logout() {
    await nui('phoneLogout');
    updateState({ onDuty: false, calls: [] });
}

async function setPhoneOnlyMode(enabled) {
    const result = await nui('phoneSetPhoneOnlyMode', { enabled });
    if (result && result.state) updateState(result.state);
}

async function acceptCall(callId, offeredToMe = false) {
    const result = offeredToMe
        ? await nui('phoneRespondToOffer', { callId, accept: true })
        : await nui('phoneAcceptCall', { callId });

    if (result && result.state) updateState(result.state);
    else refreshState();
}

async function respondToOffer(callId, accept) {
    const result = await nui('phoneRespondToOffer', { callId, accept });
    if (result && result.state) updateState(result.state);
    else refreshState();
}

loginBtn.addEventListener('click', login);
passwordInput.addEventListener('keydown', event => {
    if (event.key === 'Enter') login();
});
companyInput.addEventListener('keydown', event => {
    if (event.key === 'Enter') passwordInput.focus();
});
logoutBtn.addEventListener('click', logout);
refreshBtn.addEventListener('click', refreshState);
phoneOnlyToggle.addEventListener('change', () => setPhoneOnlyMode(phoneOnlyToggle.checked));
acceptOfferBtn.addEventListener('click', () => {
    if (activeOfferId) respondToOffer(activeOfferId, true);
});
rejectOfferBtn.addEventListener('click', () => {
    if (activeOfferId) respondToOffer(activeOfferId, false);
});

window.addEventListener('message', event => {
    const data = event.data || {};
    if (data.action === 'state') {
        updateState(data.state || {});
    }
});

refreshState();
setInterval(refreshState, 5000);
