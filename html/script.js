const tablet = document.getElementById('tablet');
const dragBar = document.getElementById('dragBar');
const closeBtn = document.getElementById('closeBtn');
const refreshBtn = document.getElementById('refreshBtn');
const queue = document.getElementById('queue');
const subtitle = document.getElementById('subtitle');
const busyBanner = document.getElementById('busyBanner');

let busy = false;
let dragging = false;
let dragOffsetX = 0;
let dragOffsetY = 0;
let movedOnce = false;

function post(name, data = {}) {
    return fetch(`https://${GetParentResourceName()}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data)
    }).catch(() => null);
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
    return `${distance.toFixed(1)}m`;
}

function formatAge(seconds) {
    seconds = Math.max(0, Math.floor(Number(seconds) || 0));
    const h = Math.floor(seconds / 3600).toString().padStart(2, '0');
    const m = Math.floor((seconds % 3600) / 60).toString().padStart(2, '0');
    const s = Math.floor(seconds % 60).toString().padStart(2, '0');
    return `${h}:${m}:${s}`;
}

function acceptCall(callId) {
    post('acceptCall', { callId });
}

function renderCalls(calls = []) {
    queue.innerHTML = '';
    busyBanner.classList.toggle('hidden', !busy);

    if (!calls.length) {
        queue.innerHTML = '<div class="empty">The queue is currently empty.</div>';
        return;
    }

    calls.forEach(call => {
        const canAccept = !!call.canAccept && !busy;
        const div = document.createElement('div');
        div.className = `call${canAccept ? ' clickable' : ''}`;
        div.innerHTML = `
            <div class="call-top">
                <div class="call-title">#${escapeHtml(call.id || 0)} - ${escapeHtml(call.requesterName || 'Unknown')}</div>
                <div class="status">${escapeHtml(call.status || 'unknown')}</div>
            </div>
            <div class="meta">
                <div><span>Company:</span> ${escapeHtml(call.companyName || 'Any Company')}</div>
                <div><span>Distance:</span> ${escapeHtml(formatDistance(call.distance))}</div>
                <div><span>Age:</span> ${escapeHtml(formatAge(call.ageSeconds))}</div>
                <div><span>Assigned:</span> ${escapeHtml(call.assignedDriver || 'Unassigned')}</div>
            </div>
            <button class="accept" ${canAccept ? '' : 'disabled'}>${canAccept ? 'Accept Call' : 'Unavailable'}</button>
        `;

        const button = div.querySelector('.accept');
        button.addEventListener('click', event => {
            event.stopPropagation();
            if (canAccept) acceptCall(call.id);
        });

        div.addEventListener('click', () => {
            if (canAccept) acceptCall(call.id);
        });

        queue.appendChild(div);
    });
}

function openTablet(data) {
    busy = !!data.busy;
    subtitle.textContent = `${data.companyName || 'Tow'} • drag this bar to move`;
    tablet.classList.remove('hidden');

    if (!movedOnce) {
        tablet.style.left = '50%';
        tablet.style.top = '12vh';
        tablet.style.transform = 'translateX(-50%)';
    }

    renderCalls(data.calls || []);
}

function closeTablet() {
    tablet.classList.add('hidden');
}

window.addEventListener('message', event => {
    const data = event.data || {};

    if (data.action === 'open') {
        openTablet(data);
    } else if (data.action === 'close') {
        closeTablet();
    } else if (data.action === 'setQueue') {
        busy = !!data.busy;
        subtitle.textContent = `${data.companyName || 'Tow'} • drag this bar to move`;
        renderCalls(data.calls || []);
    }
});

closeBtn.addEventListener('click', () => post('close'));
refreshBtn.addEventListener('click', () => post('refresh'));

document.addEventListener('keydown', event => {
    if (event.key === 'Escape') post('close');
});

dragBar.addEventListener('mousedown', event => {
    if (event.target.closest('button')) return;

    dragging = true;
    movedOnce = true;

    const rect = tablet.getBoundingClientRect();
    tablet.style.transform = 'none';
    tablet.style.left = `${rect.left}px`;
    tablet.style.top = `${rect.top}px`;

    dragOffsetX = event.clientX - rect.left;
    dragOffsetY = event.clientY - rect.top;
});

document.addEventListener('mousemove', event => {
    if (!dragging) return;

    const maxLeft = window.innerWidth - tablet.offsetWidth;
    const maxTop = window.innerHeight - tablet.offsetHeight;
    const left = Math.min(Math.max(0, event.clientX - dragOffsetX), Math.max(0, maxLeft));
    const top = Math.min(Math.max(0, event.clientY - dragOffsetY), Math.max(0, maxTop));

    tablet.style.left = `${left}px`;
    tablet.style.top = `${top}px`;
});

document.addEventListener('mouseup', () => {
    dragging = false;
});
