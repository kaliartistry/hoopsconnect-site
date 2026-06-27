// HoopsConnect — main app shell, role switching, screen routing
window.HCApp = (function () {
  const D = window.HC_DATA;
  const S = window.HC_SCREENS;

  let role = 'admin';
  let activeTab = 'board';
  let leaderStat = 'PPG';
  let modalScreen = null; // sub-screen overlay e.g. player-card, stat-entry, ack-tracker

  // ─── Role switcher ───
  function setRole(r) {
    role = r;
    activeTab = D.ROLES[r].caps.board ? 'board' : 'standings';
    modalScreen = null;
    render();
  }
  function go(tab) { activeTab = tab; modalScreen = null; render(); }

  function openPlayer(name) { modalScreen = { kind: 'player', name }; render(); }
  function openBoxScore(id) { modalScreen = { kind: 'box', id }; render(); }
  function openStatEntry(id, mode) { modalScreen = { kind: 'statEntry', id, mode }; render(); }
  function openStatGameSelect() { modalScreen = { kind: 'gameSelect' }; render(); }
  function openAckTracker(id) { modalScreen = { kind: 'ack', id }; render(); }
  function openInvites() { modalScreen = { kind: 'invites' }; render(); }
  function openCreatePost() { modalScreen = { kind: 'createPost' }; render(); }
  function openGameSummary(id) { modalScreen = { kind: 'box', id }; render(); }
  function openJoin() { modalScreen = { kind: 'join' }; render(); }
  function openLive(id) { window.HCLive.open(); }

  function back() { modalScreen = null; render(); }

  function ackPost(id) {
    const acked = new Set(JSON.parse(localStorage.getItem('hc.acked') || '[]'));
    acked.add(id);
    localStorage.setItem('hc.acked', JSON.stringify([...acked]));
    toast('✓ Acknowledged · admin notified');
    render();
  }

  function approveStats() { toast('✓ Stats approved · standings & leaderboards rebuilding'); modalScreen = null; render(); }
  function submitStats() { toast('Submitted to admin for approval'); modalScreen = null; render(); }

  function switchLeaderStat(s) { leaderStat = s; render(); }

  function toast(msg) {
    let t = document.getElementById('hcToast');
    if (!t) {
      t = document.createElement('div');
      t.id = 'hcToast';
      t.style.cssText = 'position:fixed;bottom:80px;left:50%;transform:translateX(-50%);background:#0e0e0c;color:#efece4;padding:12px 22px;border-radius:10px;font-size:13.5px;font-weight:500;z-index:300;opacity:0;transition:opacity .25s;pointer-events:none;font-family:var(--sans);';
      document.body.appendChild(t);
    }
    t.textContent = msg;
    requestAnimationFrame(() => { t.style.opacity = '1'; });
    clearTimeout(t._h);
    t._h = setTimeout(() => { t.style.opacity = '0'; }, 2400);
  }

  // ─── Render the phone UI for the active role/tab ───
  function renderPhone() {
    const r = D.ROLES[role];
    const tabs = buildTabs(r);

    // Tab body
    let body = '';
    let title = 'HoopsConnect';
    let showBack = false;

    if (modalScreen) {
      showBack = true;
      switch (modalScreen.kind) {
        case 'player': body = S.renderPlayerCard(modalScreen.name); title = 'Player Card'; break;
        case 'box': body = S.renderBoxScore(); title = 'Box Score'; break;
        case 'statEntry': body = S.renderStatEntry(modalScreen.mode); title = modalScreen.mode === 'review' ? 'Review Stats' : 'Stat Entry'; break;
        case 'ack': body = S.renderAckTracker(); title = 'Ack Tracker'; break;
        case 'invites': body = S.renderInvites(); title = 'Invite Codes'; break;
        case 'gameSelect':
          body = renderGameSelect(); title = 'Pick a game'; break;
        case 'createPost':
          body = renderCreatePost(); title = 'New Post'; break;
        case 'join':
          body = S.renderJoin(); title = 'Join'; break;
      }
    } else {
      switch (activeTab) {
        case 'board': body = S.renderBoard(role); title = 'Board'; break;
        case 'standings': body = S.renderStandings(); title = 'Standings'; break;
        case 'stats': body = S.renderLeaderboard(leaderStat); title = 'Stats'; break;
        case 'schedule': body = S.renderSchedule(role); title = 'Schedule'; break;
        case 'admin': body = S.renderAdmin(role); title = 'Admin'; break;
        case 'media': body = S.renderPress(); title = 'Media'; break;
      }
    }

    // App bar
    const appbar = `
      <div class="phone-appbar">
        ${showBack ? `<button class="back" onclick="HCApp.back()">‹</button>` : `
          <div style="width:32px;height:32px;border-radius:50%;background:${r.color};color:white;display:flex;align-items:center;justify-content:center;font-size:11.5px;font-weight:700">${r.initials}</div>`}
        <h2>${title}</h2>
        <div class="actions">
          <button class="iconbtn" style="position:relative">🔔<div class="dot"></div></button>
          <button class="iconbtn">⋯</button>
        </div>
      </div>`;

    const statusBar = `
      <div class="phone-statusbar">
        <span>9:41</span>
        <span class="right"><span>●●●</span> <span>📶</span> <span>🔋</span></span>
      </div>
      <div class="phone-notch"></div>`;

    const tabBar = !modalScreen ? `
      <div class="phone-tabbar">
        ${tabs.map(t => `
          <button class="${activeTab === t.id ? 'on' : ''}" onclick="HCApp.go('${t.id}')">
            <span class="ic">${t.ic}</span>
            <span>${t.label}</span>
            ${t.badge ? `<span class="badge">${t.badge}</span>` : ''}
          </button>`).join('')}
      </div>` : '';

    return `
      ${statusBar}
      ${appbar}
      <div class="phone-body" id="phoneBody">
        ${body}
      </div>
      ${tabBar}
    `;
  }

  function buildTabs(r) {
    const tabs = [];
    if (r.caps.board) tabs.push({ id: 'board', label: 'Board', ic: '📋', badge: r === D.ROLES.rep ? '2' : '' });
    tabs.push({ id: 'standings', label: 'Standings', ic: '🏆' });
    tabs.push({ id: 'stats', label: 'Stats', ic: '📊' });
    tabs.push({ id: 'schedule', label: 'Schedule', ic: '🗓' });
    if (r.caps.press) tabs.push({ id: 'media', label: 'Media', ic: '📰' });
    if (r.caps.admin) {
      const inboxCount = D.SCHEDULE.filter(g => g.statsStatus === 'submitted').length + D.POSTS.filter(p => p.ack && p.ack.done < p.ack.total).length;
      tabs.push({ id: 'admin', label: 'Admin', ic: '⚙', badge: inboxCount > 0 ? String(inboxCount) : '' });
    }
    return tabs;
  }

  function renderGameSelect() {
    const games = D.SCHEDULE.filter(g => g.status !== 'pending' || g.statsStatus !== 'not_started');
    return `
      <div style="padding:14px 12px">
        <div style="font-size:11px;color:var(--muted);letter-spacing:0.08em;text-transform:uppercase">Stats Dashboard</div>
        <div style="font-family:var(--serif);font-size:22px;letter-spacing:-0.01em">Pick a game to enter or review</div>
      </div>

      <div class="tabs-bar">
        <button class="on">All</button>
        <button>Submitted</button>
        <button>Drafts</button>
        <button>Approved</button>
      </div>

      ${D.SCHEDULE.map(g => {
        const home = D.TEAMS.find(t => t.id === g.home);
        const away = D.TEAMS.find(t => t.id === g.away);
        const chip = g.statsStatus === 'approved' ? '<span class="chip chip-approved">Approved</span>' :
                     g.statsStatus === 'submitted' ? '<span class="chip chip-submitted">Awaiting approval</span>' :
                     g.statsStatus === 'pending' ? '<span class="chip chip-pending">Draft</span>' :
                     '<span class="chip chip-pending">Not started</span>';
        return `
          <div class="p-card" style="cursor:pointer" onclick="HCApp.openStatEntry('${g.id}','${g.statsStatus==='submitted'?'review':'edit'}')">
            <div style="display:flex;align-items:center;justify-content:space-between">
              <div>
                <div style="font-size:13px;font-weight:600">${away.name} @ ${home.name}</div>
                <div style="font-size:11px;color:var(--muted)">${g.date} · ${g.time} · ${g.venue}</div>
              </div>
              ${chip}
            </div>
          </div>`;
      }).join('')}
    `;
  }

  function renderCreatePost() {
    return `
      <div style="padding:14px 12px">
        <div style="font-size:11px;color:var(--muted);letter-spacing:0.08em;text-transform:uppercase;margin-bottom:6px">Type</div>
        <div class="tabs-bar" style="margin:0">
          <button class="on">Announcement</button>
          <button>Team update</button>
          <button>Urgent</button>
        </div>
      </div>

      <div class="p-card" style="padding:16px">
        <input style="width:100%;padding:10px;border:1px solid var(--line);border-radius:8px;font-size:14px;font-weight:600;margin-bottom:8px" placeholder="Title (e.g. Roster Lock Deadline)" value="">
        <textarea style="width:100%;padding:10px;border:1px solid var(--line);border-radius:8px;font-size:13px;line-height:1.5;min-height:120px;font-family:inherit;resize:vertical" placeholder="Write your post body…"></textarea>
      </div>

      <div class="p-card" style="padding:14px">
        <div style="font-weight:600;font-size:13px;margin-bottom:8px">Audience</div>
        <div style="display:flex;gap:6px;flex-wrap:wrap">
          <span class="chip chip-approved">All Leagues</span>
          <span class="chip" style="background:var(--bg-2);color:var(--ink-2)">+ NBL Premier</span>
          <span class="chip" style="background:var(--bg-2);color:var(--ink-2)">+ Women's Premier</span>
          <span class="chip" style="background:var(--bg-2);color:var(--ink-2)">+ Specific teams</span>
        </div>
      </div>

      <div class="p-card" style="padding:14px">
        <label style="display:flex;align-items:center;gap:10px;cursor:pointer">
          <input type="checkbox" checked style="width:18px;height:18px;accent-color:var(--orange)">
          <div>
            <div style="font-size:13px;font-weight:600">Require acknowledgment from team reps</div>
            <div style="font-size:11px;color:var(--muted)">Sends FCM push, tracks who has and hasn't ack'd</div>
          </div>
        </label>
        <div style="margin-top:10px;padding-left:28px">
          <div style="font-size:11px;color:var(--muted);margin-bottom:4px">Deadline</div>
          <input style="padding:8px;border:1px solid var(--line);border-radius:6px;font-size:12px" value="Mar 31 · 11:59 PM">
        </div>
      </div>

      <div style="padding:12px">
        <button class="btn orange lg" style="width:100%" onclick="HCApp.toast('Posted · 24 reps notified'); HCApp.back()">Post &amp; notify reps</button>
      </div>
    `;
  }

  function render() {
    const phoneEl = document.getElementById('phoneScreen');
    if (phoneEl) phoneEl.innerHTML = renderPhone();

    // Update role buttons
    document.querySelectorAll('[data-role-btn]').forEach(b => {
      b.classList.toggle('on', b.dataset.roleBtn === role);
    });
    const roleEl = document.getElementById('roleSummary');
    if (roleEl) {
      const r = D.ROLES[role];
      roleEl.innerHTML = `
        <div style="display:flex;align-items:center;gap:12px;padding:14px;background:var(--paper);border:1px solid var(--line);border-radius:12px">
          <div style="width:40px;height:40px;border-radius:50%;background:${r.color};color:white;display:flex;align-items:center;justify-content:center;font-weight:700">${r.initials}</div>
          <div style="flex:1">
            <div style="font-size:13px;font-weight:700">${r.name}</div>
            <div style="font-size:11.5px;color:var(--muted)">${r.label}${r.team ? ' · ' + r.team : ''}</div>
          </div>
        </div>
        <div style="margin-top:10px;padding:12px;background:var(--bg);border:1px solid var(--line);border-radius:10px;font-size:11.5px;line-height:1.55;color:var(--ink-2)">
          <b>What ${r.label} can do:</b><br>
          ${capList(r.caps).join(' · ')}
        </div>`;
    }
  }

  function capList(caps) {
    const items = [];
    if (caps.board) items.push('Board'); else items.push('No board (fan)');
    items.push('Standings');
    items.push('Stats');
    items.push('Schedule');
    if (caps.press) items.push('Media tools');
    if (caps.statsEntry) items.push('Live stats entry');
    if (caps.approve) items.push('Approve stats');
    if (caps.admin) items.push('Admin');
    if (caps.invites) items.push('Invite codes');
    if (caps.divisions) items.push('Divisions / users');
    return items;
  }

  // ─── Section nav (left rail) ───
  function setSection(id) {
    document.querySelectorAll('.sectnav button').forEach(b => b.classList.toggle('on', b.dataset.sec === id));
    document.querySelectorAll('.stage > section').forEach(s => s.classList.toggle('on', s.id === 'sec-' + id));
    window.scrollTo({ top: 0, behavior: 'instant' });
  }

  // ─── Init ───
  function init() {
    render();
    setSection('proto');
    document.querySelectorAll('[data-role-btn]').forEach(b => {
      b.addEventListener('click', () => setRole(b.dataset.roleBtn));
    });
    document.querySelectorAll('.sectnav button').forEach(b => {
      b.addEventListener('click', () => setSection(b.dataset.sec));
    });

    const copyBtn = document.querySelector('.handoff .promptbox button.copy');
    if (copyBtn) copyBtn.addEventListener('click', () => {
      const txt = document.getElementById('handoffPrompt').innerText;
      navigator.clipboard.writeText(txt).then(() => {
        copyBtn.textContent = '✓ Copied';
        setTimeout(() => copyBtn.textContent = 'Copy', 2000);
      });
    });
  }

  return {
    init, setRole, go, render, openPlayer, openBoxScore, openStatEntry, openStatGameSelect,
    openAckTracker, openInvites, openCreatePost, openGameSummary, openJoin, openLive,
    back, ackPost, approveStats, submitStats, switchLeaderStat, toast,
  };
})();

document.addEventListener('DOMContentLoaded', () => HCApp.init());
