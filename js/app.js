// ── Config ────────────────────────────────────────────────────
// Replace these two values with your Supabase project details.
// Supabase Dashboard → Settings → API
const SUPABASE_URL      = window._ENV?.SUPABASE_URL      || 'https://YOUR_PROJECT.supabase.co';
const SUPABASE_ANON_KEY = window._ENV?.SUPABASE_ANON_KEY || 'YOUR_ANON_KEY';

const supabase = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { autoRefreshToken: true, persistSession: true, detectSessionInUrl: true }
});

// ── Theme ─────────────────────────────────────────────────────
const Theme = {
  init() {
    document.documentElement.setAttribute('data-theme', localStorage.getItem('tc_theme') || 'dark');
  },
  toggle() {
    const next = document.documentElement.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
    document.documentElement.setAttribute('data-theme', next);
    localStorage.setItem('tc_theme', next);
  }
};
Theme.init();

// ── Toast ─────────────────────────────────────────────────────
const Toast = {
  show(msg, type = 'info', ms = 3200) {
    let box = document.getElementById('tc-toasts');
    if (!box) {
      box = document.createElement('div');
      box.id = 'tc-toasts';
      box.className = 'toast-container';
      document.body.appendChild(box);
    }
    const t = document.createElement('div');
    t.className = `toast toast-${type}`;
    t.textContent = msg;
    box.appendChild(t);
    setTimeout(() => { t.style.opacity = '0'; t.style.transform = 'translateY(8px)'; t.style.transition = '.3s'; setTimeout(() => t.remove(), 300); }, ms);
  },
  success(m) { this.show(m, 'success'); },
  error(m)   { this.show(m, 'error');   },
  info(m)    { this.show(m, 'info');    }
};

// ── Auth helpers ──────────────────────────────────────────────
const Auth = {
  async session()  { return (await supabase.auth.getSession()).data.session; },
  async user()     { return (await supabase.auth.getUser()).data.user; },
  async requireAuth(to = 'auth.html') {
    const s = await this.session();
    if (!s) { window.location.href = to; return null; }
    return s;
  },
  async redirectIfAuth(to = 'messages.html') {
    const s = await this.session();
    if (s) window.location.href = to;
  },
  async logout() {
    await supabase.auth.signOut();
    window.location.href = 'auth.html';
  }
};

// ── Inactivity auto-logout (30 min) ──────────────────────────
const Idle = {
  t: null,
  LIMIT: 30 * 60 * 1000,
  reset() { clearTimeout(this.t); this.t = setTimeout(() => Auth.logout(), this.LIMIT); },
  init()  {
    ['mousemove','keydown','click','touchstart'].forEach(e =>
      document.addEventListener(e, () => this.reset(), { passive: true }));
    this.reset();
  }
};

// ── PIN helpers (bcryptjs from CDN) ──────────────────────────
const PIN = {
  hash(p)      { return dcodeIO.bcrypt.hash(p, 10); },
  verify(p, h) { return dcodeIO.bcrypt.compare(p, h); }
};

// ── Image compression ─────────────────────────────────────────
function compressImage(file, maxW = 1200, q = 0.82) {
  return new Promise(res => {
    const r = new FileReader();
    r.onload = e => {
      const img = new Image();
      img.onload = () => {
        const canvas = document.createElement('canvas');
        let { width: w, height: h } = img;
        if (w > maxW) { h = h * maxW / w; w = maxW; }
        canvas.width = w; canvas.height = h;
        canvas.getContext('2d').drawImage(img, 0, 0, w, h);
        canvas.toBlob(res, 'image/jpeg', q);
      };
      img.src = e.target.result;
    };
    r.readAsDataURL(file);
  });
}

// ── Avatar HTML ───────────────────────────────────────────────
function avatar(profile, size = 44) {
  if (profile?.profile_photo_url)
    return `<img src="${profile.profile_photo_url}" class="avatar" width="${size}" height="${size}" style="object-fit:cover">`;
  const ini = (profile?.display_name || '?')[0].toUpperCase();
  return `<div class="avatar-placeholder" style="width:${size}px;height:${size}px;font-size:${Math.floor(size*.38)}px">${ini}</div>`;
}

// ── Time formatting ───────────────────────────────────────────
function timeAgo(ts) {
  const d = new Date(ts), now = new Date(), diff = now - d;
  if (diff < 60000)   return 'just now';
  if (diff < 3600000) return Math.floor(diff/60000) + 'm ago';
  if (new Date(ts).toDateString() === now.toDateString())
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  if (diff < 172800000) return 'Yesterday';
  if (diff < 604800000) return d.toLocaleDateString([], { weekday: 'short' });
  return d.toLocaleDateString([], { month: 'short', day: 'numeric' });
}
function chatTime(ts) {
  return new Date(ts).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

// ── HTML escape ───────────────────────────────────────────────
function esc(s = '') {
  return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\n/g,'<br>');
}

// ── Lightbox ──────────────────────────────────────────────────
function openLightbox(src) {
  const lb = document.createElement('div');
  lb.className = 'lightbox';
  lb.innerHTML = `<img src="${src}" alt="">`;
  lb.onclick = () => lb.remove();
  document.body.appendChild(lb);
}

// ── Modal ─────────────────────────────────────────────────────
function openModal(html, onClose) {
  const ov = document.createElement('div');
  ov.className = 'modal-overlay';
  ov.innerHTML = html;
  ov.addEventListener('click', e => { if (e.target === ov) { ov.remove(); onClose?.(); } });
  document.body.appendChild(ov);
  return ov;
}

// ── Nav badge update ──────────────────────────────────────────
async function updateBadges() {
  const u = await Auth.user();
  if (!u) return;
  const [{ count: mc }, { count: nc }] = await Promise.all([
    supabase.from('messages').select('id', { count: 'exact', head: true }).eq('receiver_id', u.id).eq('is_read', false),
    supabase.from('notifications').select('id', { count: 'exact', head: true }).eq('user_id', u.id).eq('is_read', false)
  ]);
  document.querySelectorAll('.badge-msg').forEach(el => {
    el.textContent = mc > 99 ? '99+' : mc;
    el.classList.toggle('hidden', !mc);
  });
  document.querySelectorAll('.badge-notif').forEach(el => {
    el.textContent = nc > 99 ? '99+' : nc;
    el.classList.toggle('hidden', !nc);
  });
}

// ── Bottom nav active state ───────────────────────────────────
function setActiveNav() {
  const page = location.pathname.split('/').pop();
  document.querySelectorAll('.bottom-nav a').forEach(a => {
    a.classList.toggle('active', a.getAttribute('href') === page);
  });
}

// ── Shared nav HTML ───────────────────────────────────────────
function topNav(title = 'Techychat', backHref = null) {
  return `<nav class="top-nav">
    ${backHref
      ? `<button class="nav-icon-btn" onclick="location.href='${backHref}'" style="color:var(--text2)"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="15 18 9 12 15 6"/></svg></button>`
      : `<span class="logo">Techychat</span>`}
    <span class="logo" style="${backHref ? '' : 'display:none'}">${title}</span>
    <div class="nav-icons">
      <button class="nav-icon-btn" onclick="location.href='notifications.html'" style="position:relative">
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>
        <span class="badge badge-notif hidden" style="position:absolute;top:6px;right:6px"></span>
      </button>
      <button class="nav-icon-btn" onclick="Theme.toggle()">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="5"/><path d="M12 1v2M12 21v2M4.22 4.22l1.42 1.42M18.36 18.36l1.42 1.42M1 12h2M21 12h2M4.22 19.78l1.42-1.42M18.36 5.64l1.42-1.42"/></svg>
      </button>
    </div>
  </nav>`;
}

function bottomNav() {
  return `<nav class="bottom-nav">
    <a href="messages.html">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/></svg>
      <span class="badge badge-msg hidden" style="position:absolute;top:4px;right:8px"></span>
      Chats
    </a>
    <a href="posts.html">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 9h6M9 13h6M9 17h4"/></svg>
      Posts
    </a>
    <a href="friends.html">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>
      Friends
    </a>
    <a href="notifications.html">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 8A6 6 0 0 0 6 8c0 7-3 9-3 9h18s-3-2-3-9"/><path d="M13.73 21a2 2 0 0 1-3.46 0"/></svg>
      <span class="badge badge-notif hidden" style="position:absolute;top:4px;right:8px"></span>
      Alerts
    </a>
    <a href="profile.html">
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M20 21v-2a4 4 0 0 0-4-4H8a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
      Me
    </a>
  </nav>`;
}

// ── PIN keypad renderer ───────────────────────────────────────
function renderKeypad(containerId, onKey) {
  const el = document.getElementById(containerId);
  if (!el) return;
  el.innerHTML = ['1','2','3','4','5','6','7','8','9','','0','⌫'].map(k =>
    k === '' ? '<div></div>'
             : `<button class="pin-key" data-k="${k}">${k}</button>`
  ).join('');
  el.addEventListener('click', e => {
    const btn = e.target.closest('.pin-key');
    if (btn) onKey(btn.dataset.k);
  });
}

function updatePinDots(containerId, count) {
  document.querySelectorAll(`#${containerId} .pin-dot`).forEach((d, i) =>
    d.classList.toggle('filled', i < count));
}
