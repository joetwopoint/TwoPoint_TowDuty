const loginView = document.getElementById('loginView');
const dutyView = document.getElementById('dutyView');
const supervisorView = document.getElementById('supervisorView');

const loginSubtitle = document.getElementById('loginSubtitle');
const loginModeTabs = document.getElementById('loginModeTabs');
const driverModeBtn = document.getElementById('driverModeBtn');
const supervisorModeBtn = document.getElementById('supervisorModeBtn');
const driverLoginForm = document.getElementById('driverLoginForm');
const supervisorLoginForm = document.getElementById('supervisorLoginForm');
const loginBackBtn = document.getElementById('loginBackBtn');

const companyInput = document.getElementById('companyInput');
const passwordInput = document.getElementById('passwordInput');
const loginBtn = document.getElementById('loginBtn');
const loginError = document.getElementById('loginError');

const supervisorCompanyInput = document.getElementById('supervisorCompanyInput');
const supervisorPasswordInput = document.getElementById('supervisorPasswordInput');
const supervisorLoginBtn = document.getElementById('supervisorLoginBtn');
const supervisorLoginError = document.getElementById('supervisorLoginError');

const logoutBtn = document.getElementById('logoutBtn');
const manageBtn = document.getElementById('manageBtn');
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

const supervisorCompanyTitle = document.getElementById('supervisorCompanyTitle');
const supervisorDutyBtn = document.getElementById('supervisorDutyBtn');
const supervisorLogoutBtn = document.getElementById('supervisorLogoutBtn');
const managedCompanyNameInput = document.getElementById('managedCompanyNameInput');
const managedPasswordInput = document.getElementById('managedPasswordInput');
const managedPasswordConfirmInput = document.getElementById('managedPasswordConfirmInput');
const saveCompanyBtn = document.getElementById('saveCompanyBtn');
const supervisorFeedback = document.getElementById('supervisorFeedback');

let state = { onDuty: false, calls: [], companyManagementEnabled: true };
let supervisorState = { authenticated: false, enabled: true };
let activeOfferId = null;
let busy = false;
let currentView = 'login';
let loginMode = 'driver';
let initialized = false;

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

function showView(view) {
    currentView = view;
    loginView.classList.toggle('hidden', view !== 'login');
    dutyView.classList.toggle('hidden', view !== 'duty');
    supervisorView.classList.toggle('hidden', view !== 'supervisor');
}

function managementEnabled() {
    return state.companyManagementEnabled !== false && supervisorState.enabled !== false;
}

function setMessage(element, message, type = 'error') {
    element.textContent = message || '';
    element.classList.toggle('hidden', !message);
    element.classList.toggle('success', type === 'success');
}

function clearLoginMessages() {
    setMessage(loginError, '');
    setMessage(supervisorLoginError, '');
}

function setLoginMode(mode) {
    if (mode === 'supervisor' && !managementEnabled()) mode = 'driver';
    loginMode = mode;

    const supervisorMode = mode === 'supervisor';
    driverModeBtn.classList.toggle('active', !supervisorMode);
    supervisorModeBtn.classList.toggle('active', supervisorMode);
    driverLoginForm.classList.toggle('hidden', supervisorMode);
    supervisorLoginForm.classList.toggle('hidden', !supervisorMode);
    loginSubtitle.textContent = supervisorMode
        ? 'Use your company authorization. A password is only needed when required by the company.'
        : 'Sign in with a private company password or the default on-the-fly password.';

    loginBackBtn.classList.toggle('hidden', !state.onDuty && !supervisorState.authenticated);
    clearLoginMessages();
}

function updateDriverState(nextState = {}) {
    state = nextState || {};
    busy = !!state.busy;

    companyTitle.textContent = state.companyName || 'Tow';
    phoneOnlyToggle.checked = !!state.phoneOnlyMode;
    phoneOnlyToggle.disabled = !!state.forcePhoneOnlyMode;

    const showManagement = managementEnabled();
    loginModeTabs.classList.toggle('hidden', !showManagement);
    supervisorModeBtn.classList.toggle('hidden', !showManagement);
    manageBtn.classList.toggle('hidden', !showManagement);

    if (!state.onDuty) {
        activeOfferId = null;
        offerCard.classList.add('hidden');
        renderQueue([]);
    } else {
        const calls = state.calls || [];
        const activeOffer = state.activeOffer || calls.find(call => call.offeredToMe);
        renderOffer(activeOffer);
        renderQueue(calls);
    }

    supervisorDutyBtn.textContent = state.onDuty ? 'Tow duty' : 'Driver sign in';
    loginBackBtn.classList.toggle('hidden', !state.onDuty && !supervisorState.authenticated);

    if (initialized && currentView === 'duty' && !state.onDuty) {
        showView(supervisorState.authenticated ? 'supervisor' : 'login');
    }
}

function updateSupervisorState(nextState = {}) {
    supervisorState = nextState || { authenticated: false, enabled: true };

    const showManagement = managementEnabled();
    loginModeTabs.classList.toggle('hidden', !showManagement);
    supervisorModeBtn.classList.toggle('hidden', !showManagement);
    manageBtn.classList.toggle('hidden', !showManagement);

    if (supervisorState.authenticated) {
        supervisorCompanyTitle.textContent = supervisorState.companyName || 'Company';
        managedCompanyNameInput.disabled = supervisorState.canRename === false;
        managedPasswordInput.disabled = supervisorState.canChangePassword === false;
        managedPasswordConfirmInput.disabled = supervisorState.canChangePassword === false;

        if (document.activeElement !== managedCompanyNameInput) {
            managedCompanyNameInput.value = supervisorState.companyName || '';
        }
    }

    supervisorDutyBtn.textContent = state.onDuty ? 'Tow duty' : 'Driver sign in';
    loginBackBtn.classList.toggle('hidden', !state.onDuty && !supervisorState.authenticated);

    if (initialized && currentView === 'supervisor' && !supervisorState.authenticated) {
        if (state.onDuty) showView('duty');
        else {
            setLoginMode('supervisor');
            showView('login');
        }
    }
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
        if (rejectBtn) rejectBtn.addEventListener('click', () => respondToOffer(call.id, false));
        queueList.appendChild(div);
    }
}

async function refreshAllState() {
    try {
        const [driverResult, supervisorResult] = await Promise.all([
            nui('phoneGetState'),
            nui('supervisorGetState')
        ]);

        updateDriverState(driverResult || {});
        updateSupervisorState(supervisorResult || {});

        if (!initialized) {
            initialized = true;
            if (state.onDuty) showView('duty');
            else if (supervisorState.authenticated) showView('supervisor');
            else showView('login');
            setLoginMode('driver');
        }
    } catch (error) {
        console.error(error);
    }
}

async function login() {
    setMessage(loginError, '');
    const companyName = companyInput.value.trim() || 'Tow';
    const password = passwordInput.value;

    loginBtn.disabled = true;
    try {
        const result = await nui('phoneLogin', { companyName, password });
        if (!result || !result.ok) {
            setMessage(loginError, result && result.error ? result.error : 'Unable to sign in.');
            return;
        }

        passwordInput.value = '';
        updateDriverState(result.state || await nui('phoneGetState'));
        showView('duty');
    } catch (error) {
        setMessage(loginError, 'Unable to sign in.');
        console.error(error);
    } finally {
        loginBtn.disabled = false;
    }
}

async function supervisorLogin() {
    setMessage(supervisorLoginError, '');
    const companyName = supervisorCompanyInput.value.trim();
    const password = supervisorPasswordInput.value;

    if (!companyName) {
        setMessage(supervisorLoginError, 'Enter the company you supervise.');
        return;
    }

    supervisorLoginBtn.disabled = true;
    try {
        const result = await nui('supervisorLogin', { companyName, password });
        if (!result || !result.ok) {
            setMessage(supervisorLoginError, result && result.error ? result.error : 'Unable to open supervisor panel.');
            return;
        }

        supervisorPasswordInput.value = '';
        updateSupervisorState(result.state || await nui('supervisorGetState'));
        setMessage(supervisorFeedback, '');
        showView('supervisor');
    } catch (error) {
        setMessage(supervisorLoginError, 'Unable to open supervisor panel.');
        console.error(error);
    } finally {
        supervisorLoginBtn.disabled = false;
    }
}

async function logout() {
    await nui('phoneLogout');
    updateDriverState({
        onDuty: false,
        calls: [],
        companyManagementEnabled: state.companyManagementEnabled
    });
    if (supervisorState.authenticated) showView('supervisor');
    else showView('login');
}

async function supervisorLogout() {
    await nui('supervisorLogout');
    updateSupervisorState({ authenticated: false, enabled: supervisorState.enabled !== false });
    setMessage(supervisorFeedback, '');
    if (state.onDuty) showView('duty');
    else {
        setLoginMode('supervisor');
        showView('login');
    }
}

async function saveCompanySettings() {
    setMessage(supervisorFeedback, '');

    const companyName = managedCompanyNameInput.value.trim();
    const password = managedPasswordInput.value;
    const confirmation = managedPasswordConfirmInput.value;

    if (password !== confirmation) {
        setMessage(supervisorFeedback, 'The new driver passwords do not match.');
        return;
    }

    saveCompanyBtn.disabled = true;
    try {
        const result = await nui('supervisorUpdateCompany', { companyName, password });
        if (!result || !result.ok) {
            setMessage(supervisorFeedback, result && result.error ? result.error : 'Unable to save company settings.');
            return;
        }

        managedPasswordInput.value = '';
        managedPasswordConfirmInput.value = '';
        updateSupervisorState(result.state || await nui('supervisorGetState'));
        const updatedDriverState = await nui('phoneGetState');
        updateDriverState(updatedDriverState || {});
        setMessage(supervisorFeedback, result.message || 'Company settings updated.', 'success');
    } catch (error) {
        setMessage(supervisorFeedback, 'Unable to save company settings.');
        console.error(error);
    } finally {
        saveCompanyBtn.disabled = false;
    }
}

async function setPhoneOnlyMode(enabled) {
    const result = await nui('phoneSetPhoneOnlyMode', { enabled });
    if (result && result.state) updateDriverState(result.state);
}

async function acceptCall(callId, offeredToMe = false) {
    const result = offeredToMe
        ? await nui('phoneRespondToOffer', { callId, accept: true })
        : await nui('phoneAcceptCall', { callId });

    if (result && result.state) updateDriverState(result.state);
    else refreshAllState();
}

async function respondToOffer(callId, accept) {
    const result = await nui('phoneRespondToOffer', { callId, accept });
    if (result && result.state) updateDriverState(result.state);
    else refreshAllState();
}

driverModeBtn.addEventListener('click', () => setLoginMode('driver'));
supervisorModeBtn.addEventListener('click', () => setLoginMode('supervisor'));
loginBackBtn.addEventListener('click', () => {
    if (state.onDuty) showView('duty');
    else if (supervisorState.authenticated) showView('supervisor');
});

loginBtn.addEventListener('click', login);
passwordInput.addEventListener('keydown', event => {
    if (event.key === 'Enter') login();
});
companyInput.addEventListener('keydown', event => {
    if (event.key === 'Enter') passwordInput.focus();
});

supervisorLoginBtn.addEventListener('click', supervisorLogin);
supervisorPasswordInput.addEventListener('keydown', event => {
    if (event.key === 'Enter') supervisorLogin();
});
supervisorCompanyInput.addEventListener('keydown', event => {
    if (event.key === 'Enter') supervisorPasswordInput.focus();
});

logoutBtn.addEventListener('click', logout);
manageBtn.addEventListener('click', () => {
    if (supervisorState.authenticated) showView('supervisor');
    else {
        supervisorCompanyInput.value = state.companyName || '';
        setLoginMode('supervisor');
        showView('login');
    }
});
refreshBtn.addEventListener('click', refreshAllState);
phoneOnlyToggle.addEventListener('change', () => setPhoneOnlyMode(phoneOnlyToggle.checked));
acceptOfferBtn.addEventListener('click', () => {
    if (activeOfferId) respondToOffer(activeOfferId, true);
});
rejectOfferBtn.addEventListener('click', () => {
    if (activeOfferId) respondToOffer(activeOfferId, false);
});

supervisorDutyBtn.addEventListener('click', () => {
    if (state.onDuty) showView('duty');
    else {
        setLoginMode('driver');
        showView('login');
    }
});
supervisorLogoutBtn.addEventListener('click', supervisorLogout);
saveCompanyBtn.addEventListener('click', saveCompanySettings);
managedPasswordConfirmInput.addEventListener('keydown', event => {
    if (event.key === 'Enter') saveCompanySettings();
});

window.addEventListener('message', event => {
    const data = event.data || {};
    if (data.action === 'state') updateDriverState(data.state || {});
    if (data.action === 'supervisorState') updateSupervisorState(data.state || {});
});

refreshAllState();
setInterval(refreshAllState, 5000);
