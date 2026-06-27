// HoopsConnect — phone screens (renderers)
// Builds inner HTML for each screen, given the active role.

window.HC_SCREENS = (function () {
  const D = window.HC_DATA;

  function teamById(id) { return D.TEAMS.find(t => t.id === id); }

  function teamLogo(team, size = 40) {
    const t = typeof team === 'string' ? teamById(team) : team;
    if (!t) return '';
    return `<div class="logo" style="background:${t.color};width:${size}px;height:${size}px">${t.short.slice(0,3)}</div>`;
  }

  // ─── BOARD ───
  function renderBoard(role) {
    const role_ = D.ROLES[role];
    const isAdmin = role_.caps.admin;
    const isRep = role === 'rep';

    const acked = new Set(JSON.parse(localStorage.getItem('hc.acked') || '[]'));

    return `
      <div class="scope-bar">
        <span class="dot"></span>
        <span class="lbl">League</span>
        <span class="val">All Leagues</span>
        <span class="chev">▾</span>
      </div>

      <div class="section-h">
        <span class="t">Filter</span>
      </div>
      <div class="tabs-bar" style="margin-top:0">
        <button class="on">All</button>
        <button>Announcements</button>
        <button>My Team</button>
        ${isAdmin ? '<button>Drafts</button>' : ''}
      </div>

      ${D.POSTS.map(p => renderPost(p, isRep, acked)).join('')}

      ${isAdmin || isRep ? `
        <div style="padding: 14px 12px 0;">
          <button class="btn orange" style="width:100%" onclick="HCApp.openCreatePost()">＋ New Post</button>
        </div>` : ''}
    `;
  }

  function renderPost(p, isRep, acked) {
    const isAcked = acked.has(p.id);
    const ackPct = p.ack ? Math.round((p.ack.done / p.ack.total) * 100) : 0;

    const flagClass = p.urgent ? 'flag-urgent' : (p.ack && isRep && !isAcked ? 'flag-ack' : (isAcked && p.ack && isRep ? 'flag-acked' : ''));

    const flags = [
      p.urgent ? '<span class="chip chip-urgent">Urgent</span>' : '',
      p.ack && isRep && !isAcked ? '<span class="chip chip-pending">Ack required</span>' : '',
      p.ack && isRep && isAcked ? '<span class="chip chip-approved">✓ Acknowledged</span>' : '',
      p.type === 'announcement' && !p.urgent && !(p.ack && isRep) ? '<span class="chip" style="background:var(--bg-2);color:var(--ink-2)">Announcement</span>' : '',
    ].filter(Boolean).join('');

    const ackUI = p.ack && isRep && !isAcked ? `
      <div class="ack-bar">
        <button onclick="HCApp.ackPost('${p.id}')">Tap to acknowledge</button>
      </div>
      <div class="ack-status">
        <span>${p.ack.done}/${p.ack.total} confirmed</span>
        <span style="color:var(--pending);font-weight:600">Due ${p.ack.deadline}</span>
      </div>
      <div class="ack-progress"><div class="fill" style="width:${ackPct}%"></div></div>
    ` : (p.ack && isRep && isAcked ? `
      <div class="ack-status" style="margin-top:10px">
        <span style="color:var(--approved);font-weight:600">✓ You acknowledged this</span>
        <span>${p.ack.done}/${p.ack.total} confirmed</span>
      </div>
    ` : (p.ack ? `
      <div class="ack-status" style="margin-top:10px">
        <span>Ack: ${p.ack.done}/${p.ack.total}</span>
        <span>Due ${p.ack.deadline}</span>
      </div>
      <div class="ack-progress"><div class="fill" style="width:${ackPct}%"></div></div>
    ` : ''));

    return `
      <div class="post ${flagClass}">
        <div class="head">
          <div class="av ${p.team ? 'team' : ''}">${p.author.split(' ').map(s => s[0]).slice(0,2).join('')}</div>
          <div style="flex:1;min-width:0">
            <div class="who">${p.author}${p.team ? ' · ' + p.team : ''}</div>
            <div class="when">${p.when}</div>
          </div>
        </div>
        ${flags ? `<div class="flags">${flags}</div>` : ''}
        <h4>${p.title}</h4>
        <div class="body">${p.body}</div>
        ${ackUI}
      </div>
    `;
  }

  // ─── STANDINGS ───
  function renderStandings() {
    const premier = D.TEAMS.filter(t => t.division === 'NBL Premier');
    const womens = D.TEAMS.filter(t => t.division === "Women's Premier");

    return `
      <div class="scope-bar">
        <span class="dot"></span>
        <span class="lbl">League</span>
        <span class="val">All Leagues</span>
        <span class="chev">▾</span>
      </div>

      <div class="section-h"><span class="t">NBL Premier · Top 4 = Playoffs</span></div>

      <div class="p-card tight">
        <table class="standings">
          <thead><tr><th></th><th></th><th>W</th><th>L</th><th>PCT</th><th>GB</th><th>STRK</th></tr></thead>
          <tbody>
            ${premier.map((t, i) => {
              const inPlayoff = i < 4;
              const [w, l] = t.record.split('-');
              const pct = (parseInt(w)/(parseInt(w)+parseInt(l))).toFixed(3).replace(/^0/, '');
              const strk = ['W5','W2','L1','L3','W1','L4'][i] || '—';
              return `
                <tr>
                  <td class="team-cell ${inPlayoff ? 'in-playoff' : ''}">
                    <span class="num">${i+1}</span>
                    <span class="name">${t.name}</span>
                  </td>
                  <td>${teamLogo(t, 24)}</td>
                  <td class="w">${w}</td>
                  <td class="l">${l}</td>
                  <td>${pct}</td>
                  <td>${i === 0 ? '—' : (parseInt(premier[0].record.split('-')[0]) - parseInt(w))}</td>
                  <td class="${strk.startsWith('W') ? 'strk-w' : 'strk-l'}">${strk}</td>
                </tr>`;
            }).join('')}
            <tr class="div-line"><td colspan="7">Women's Premier</td></tr>
            ${womens.map((t, i) => {
              const [w, l] = t.record.split('-');
              const pct = (parseInt(w)/(parseInt(w)+parseInt(l))).toFixed(3).replace(/^0/, '');
              return `
                <tr>
                  <td class="team-cell"><span class="num">${i+1}</span><span class="name">${t.name}</span></td>
                  <td>${teamLogo(t, 24)}</td>
                  <td class="w">${w}</td>
                  <td class="l">${l}</td>
                  <td>${pct}</td>
                  <td>${i===0 ? '—' : '3'}</td>
                  <td class="${i===0?'strk-w':'strk-l'}">${i===0?'W3':'L1'}</td>
                </tr>`;
            }).join('')}
          </tbody>
        </table>
      </div>
    `;
  }

  // ─── STATS / LEADERBOARD ───
  function renderLeaderboard(activeStat = 'PPG') {
    const stats = ['PPG','RPG','APG','SPG','BPG'];
    const data = D.LEADERS[activeStat] || D.LEADERS.PPG;

    return `
      <div class="scope-bar">
        <span class="dot"></span>
        <span class="lbl">League</span>
        <span class="val">NBL Premier</span>
        <span class="chev">▾</span>
      </div>

      <div class="tabs-bar">
        ${stats.map(s => `<button class="${s===activeStat?'on':''}" onclick="HCApp.switchLeaderStat('${s}')">${s}</button>`).join('')}
      </div>

      <div class="section-h">
        <span class="t">${activeStat} Leaders · Min 10 GP</span>
        <span class="a">Export ↓</span>
      </div>

      <div class="p-card tight">
        ${data.map((p, i) => {
          const rkCls = i === 0 ? 'gold' : (i === 1 ? 'silver' : (i === 2 ? 'bronze' : 'plain'));
          return `
            <div class="leader-row" onclick="HCApp.openPlayer('${p.name}')">
              <div class="rk ${rkCls}">${p.rank}</div>
              <div class="info">
                <div class="n">${p.name}</div>
                <div class="t">${p.team} · ${p.gp} GP${p.badge ? ' · ' + p.badge : ''}</div>
              </div>
              <div class="stat">${p.val.toFixed(1)}</div>
            </div>`;
        }).join('')}
      </div>
    `;
  }

  // ─── SCHEDULE ───
  function renderSchedule(role) {
    const canEnter = D.ROLES[role].caps.statsEntry;
    const canApprove = D.ROLES[role].caps.approve;

    const groups = {
      'Tonight': D.SCHEDULE.filter(g => g.date === 'Tonight'),
      'Recent': D.SCHEDULE.filter(g => g.status === 'final'),
      'Upcoming': D.SCHEDULE.filter(g => g.date !== 'Tonight' && g.status === 'pending'),
    };

    function renderGame(g) {
      const home = teamById(g.home), away = teamById(g.away);
      const isFinal = g.status === 'final';
      const homeWon = isFinal && g.homeScore > g.awayScore;

      const statusChip = (() => {
        if (g.statsStatus === 'approved') return '<span class="chip chip-approved">Approved</span>';
        if (g.statsStatus === 'submitted') return '<span class="chip chip-submitted">Awaiting approval</span>';
        if (g.statsStatus === 'pending') return '<span class="chip chip-pending">Stats in progress</span>';
        if (g.date === 'Tonight') return '<span class="chip chip-pending">Needs stats</span>';
        return '';
      })();

      const cta = (() => {
        if (g.date === 'Tonight' && canEnter) return `<button class="cta orange" onclick="HCApp.openLive('${g.id}')">▶ Take Live Stats</button>`;
        if (isFinal && g.statsStatus === 'submitted' && canApprove) return `<button class="cta" onclick="HCApp.openStatEntry('${g.id}', 'review')">Review &amp; Approve →</button>`;
        if (isFinal && g.statsStatus === 'pending' && canEnter) return `<button class="cta" onclick="HCApp.openStatEntry('${g.id}', 'edit')">Continue stat entry →</button>`;
        if (isFinal) return `<button class="cta ghost" onclick="HCApp.openBoxScore('${g.id}')" style="background:var(--paper);color:var(--ink);border-top:1px solid var(--line)">View Box Score →</button>`;
        return '';
      })();

      return `
        <div class="p-card game-card ${isFinal ? 'final' : ''}">
          <div class="row1">
            <div class="team away ${isFinal ? (homeWon ? 'loser' : 'winner') : ''}">
              ${teamLogo(away, 40)}
              <div>
                <div class="name">${away.name}</div>
                ${isFinal ? `<div class="rec">${away.record}</div>` : `<div class="rec">${away.record}</div>`}
              </div>
              ${isFinal ? `<div class="score">${g.awayScore}</div>` : ''}
            </div>
            <div class="vs">${isFinal ? '·' : 'vs'}</div>
            <div class="team ${isFinal ? (homeWon ? 'winner' : 'loser') : ''}">
              ${teamLogo(home, 40)}
              <div>
                <div class="name">${home.name}</div>
                <div class="rec">${home.record}</div>
              </div>
              ${isFinal ? `<div class="score">${g.homeScore}</div>` : ''}
            </div>
          </div>
          <div class="row2">
            <span>${g.time} · ${g.venue}</span>
            <span class="right">${statusChip}</span>
          </div>
          ${cta}
        </div>
      `;
    }

    return `
      <div class="scope-bar">
        <span class="dot"></span>
        <span class="lbl">League</span>
        <span class="val">All Leagues</span>
        <span class="chev">▾</span>
      </div>

      <div class="section-h"><span class="t">Tonight · March 14</span><span class="a">Calendar ▢</span></div>
      ${groups.Tonight.map(renderGame).join('')}

      <div class="section-h"><span class="t">Recent</span></div>
      ${groups.Recent.map(renderGame).join('')}

      <div class="section-h"><span class="t">Upcoming</span></div>
      ${groups.Upcoming.map(renderGame).join('')}
    `;
  }

  // ─── ADMIN ───
  function renderAdmin(role) {
    const role_ = D.ROLES[role];
    const isSuper = role === 'superAdmin';

    const ackPosts = D.POSTS.filter(p => p.ack);
    const overdueAck = ackPosts.filter(p => p.ack.done < p.ack.total);
    const pendingStats = D.SCHEDULE.filter(g => g.status === 'final' && g.statsStatus !== 'approved');
    const submittedStats = D.SCHEDULE.filter(g => g.statsStatus === 'submitted');

    return `
      <div class="scope-bar">
        <span class="dot"></span>
        <span class="lbl">League</span>
        <span class="val">All Leagues</span>
        <span class="chev">▾</span>
      </div>

      <div class="workflow-card">
        <div class="lbl">Inbox · Needs your action</div>
        <div class="ttl">${submittedStats.length + overdueAck.length} items waiting</div>

        ${submittedStats.map(g => {
          const home = teamById(g.home), away = teamById(g.away);
          return `
          <div class="row" onclick="HCApp.openStatEntry('${g.id}', 'review')" style="cursor:pointer">
            <div>
              <div class="name">📊 Approve stats: ${away.short} @ ${home.short}</div>
              <div class="meta">Submitted by Statistician · ${g.date}</div>
            </div>
            <span class="chip chip-submitted">Review</span>
          </div>`;
        }).join('')}

        ${overdueAck.map(p => `
          <div class="row" onclick="HCApp.openAckTracker('${p.id}')" style="cursor:pointer">
            <div>
              <div class="name">⚡ Ack tracker: ${p.title.slice(0,32)}…</div>
              <div class="meta">${p.ack.done}/${p.ack.total} confirmed · Due ${p.ack.deadline}</div>
            </div>
            <span class="chip chip-pending">${p.ack.total - p.ack.done} left</span>
          </div>
        `).join('')}
      </div>

      <div class="section-h"><span class="t">Stats &amp; Approval</span></div>
      ${tile('📊', 'Stats Dashboard', 'Approve, edit, and unlock game stats', 'HCApp.openStatGameSelect()')}
      ${tile('▶', 'Take Live Stats', 'Court-side, real-time stat entry', 'HCApp.openLive()')}

      <div class="section-h"><span class="t">Communication</span></div>
      ${tile('✅', 'Ack Tracker', 'Track post acknowledgments from reps', 'HCApp.openAckTracker()')}
      ${tile('✏️', 'New Post', 'Announcement, urgent notice, or roster update', 'HCApp.openCreatePost()')}

      <div class="section-h"><span class="t">League Setup</span></div>
      ${tile('🏆', 'Teams', '8 teams · 2 divisions', 'HCApp.toast(\"Teams →\")')}
      ${tile('📅', 'Schedule Generator', 'Auto-generate round-robin season', 'HCApp.toast(\"Schedule generator →\")')}
      ${isSuper ? tile('🔑', 'Invite Codes', '12 active · 4 expired', 'HCApp.openInvites()') : ''}
      ${isSuper ? tile('👥', 'Users &amp; Roles', '47 users · 6 roles', 'HCApp.toast(\"User mgmt →\")') : ''}
      ${isSuper ? tile('🏷', 'Divisions &amp; Seasons', 'Active: 2025-26', 'HCApp.toast(\"Divisions →\")') : ''}
    `;
  }

  function tile(icon, title, sub, onclick) {
    return `
      <div class="p-card" style="display:flex;align-items:center;gap:12px;cursor:pointer" onclick="${onclick}">
        <div style="width:42px;height:42px;border-radius:10px;background:var(--bg);display:flex;align-items:center;justify-content:center;font-size:18px;border:1px solid var(--line)">${icon}</div>
        <div style="flex:1;min-width:0">
          <div style="font-size:13.5px;font-weight:700">${title}</div>
          <div style="font-size:11.5px;color:var(--muted)">${sub}</div>
        </div>
        <div style="color:var(--muted)">›</div>
      </div>
    `;
  }

  // ─── PRESS ───
  function renderPress() {
    return `
      <div style="padding:14px 12px 0">
        <div style="background:linear-gradient(135deg, #0e0e0c 0%, #2b2a26 100%);color:var(--paper);border-radius:14px;padding:18px;position:relative;overflow:hidden">
          <div style="font-family:var(--mono);font-size:9.5px;letter-spacing:0.14em;text-transform:uppercase;color:#a5a39c;margin-bottom:6px">Accredited Press</div>
          <div style="font-family:var(--serif);font-size:22px;letter-spacing:-0.01em">Michael Chen</div>
          <div style="font-size:11.5px;color:#a5a39c;margin-top:2px">Jamaica Basketball Association · Season 2025-26</div>
          <div style="margin-top:14px;padding-top:14px;border-top:1px solid #2b2a26;display:flex;justify-content:space-between;align-items:center">
            <div style="font-family:var(--mono);font-size:10px;color:#a5a39c">ID · PRESS-2026-0042</div>
            <div style="background:var(--orange);font-size:9.5px;font-weight:800;letter-spacing:0.1em;padding:3px 8px;border-radius:4px">VALID</div>
          </div>
          <div style="position:absolute;right:-20px;bottom:-20px;font-family:var(--serif);font-size:120px;color:rgba(234,88,12,0.2);font-weight:600;line-height:1">🏀</div>
        </div>
      </div>

      <div class="section-h"><span class="t">Today's Slate</span><span class="a">Schedule →</span></div>
      ${D.SCHEDULE.filter(g => g.date === 'Tonight').map(g => {
        const home = teamById(g.home), away = teamById(g.away);
        return `
          <div class="p-card" style="display:flex;align-items:center;gap:10px">
            <div style="font-family:var(--mono);font-size:11px;color:var(--orange);font-weight:700;min-width:60px">${g.time}</div>
            <div style="flex:1">
              <div style="font-size:13px;font-weight:600">${away.name} @ ${home.name}</div>
              <div style="font-size:11px;color:var(--muted)">${g.venue}</div>
            </div>
          </div>`;
      }).join('')}

      <div class="section-h"><span class="t">Recent Final · Auto Recaps</span></div>
      ${D.SCHEDULE.filter(g => g.status === 'final' && g.statsStatus === 'approved').map(g => {
        const home = teamById(g.home), away = teamById(g.away);
        return `
          <div class="p-card" onclick="HCApp.openGameSummary('${g.id}')" style="cursor:pointer">
            <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px">
              <div style="font-size:13px;font-weight:700">${home.short} ${g.homeScore} – ${g.awayScore} ${away.short}</div>
              <span class="chip chip-approved">Recap ready</span>
            </div>
            <div style="font-size:12px;color:var(--ink-2);line-height:1.5">Devon Clarke led all scorers with 25 points as the Kingston Titans defeated the Portmore Thunder 87-72 at the National Indoor Sports Centre…</div>
            <div style="display:flex;gap:6px;margin-top:10px">
              <button class="btn ghost sm">Copy Recap</button>
              <button class="btn ghost sm">Box Score</button>
              <button class="btn ghost sm">Export CSV</button>
            </div>
          </div>`;
      }).join('')}

      <div class="section-h"><span class="t">Tools</span></div>
      ${tile('⚖️', 'Head-to-Head', 'Compare teams or players side-by-side', 'HCApp.toast(\"Head-to-Head →\")')}
      ${tile('📈', 'Season Leaders', 'PPG · RPG · APG · SPG · BPG', 'HCApp.go(\"stats\")')}
    `;
  }

  // ─── PLAYER CARD (modal-style screen) ───
  function renderPlayerCard(name) {
    return `
      <div class="player-hero">
        <div class="jersey">5</div>
        <div class="small">Kingston Titans · PG · 6'2"</div>
        <h1>${name || 'Devon Clarke'}</h1>
        <div class="meta">2025–26 · 22 GP · 17.4 MPG</div>
      </div>

      <div class="stat-grid">
        <div class="cell"><div class="v">22.5</div><div class="l">PPG</div></div>
        <div class="cell"><div class="v">5.8</div><div class="l">RPG</div></div>
        <div class="cell"><div class="v">5.2</div><div class="l">APG</div></div>
        <div class="cell"><div class="v">2.4</div><div class="l">SPG</div></div>
      </div>

      <div class="section-h"><span class="t">Game Log · Last 6</span><span class="a">Full season →</span></div>
      <div class="gamelog">
        <div class="row head"><div>Date</div><div>Opp</div><div class="num">PTS</div><div class="num">REB</div><div class="num">AST</div></div>
        ${D.PLAYER_LOG.map(g => `
          <div class="row">
            <div class="opp">${g.date}</div>
            <div><span class="res ${g.res === 'W' ? 'w' : 'l'}">${g.res}</span> ${g.opp} · ${g.score}</div>
            <div class="num">${g.pts}</div>
            <div class="num">${g.reb}</div>
            <div class="num">${g.ast}</div>
          </div>`).join('')}
      </div>

      <div style="padding:14px 12px">
        <button class="btn ghost" style="width:100%">Share player card</button>
      </div>
    `;
  }

  // ─── STAT ENTRY (post-game grid) ───
  function renderStatEntry(mode = 'edit') {
    const isReview = mode === 'review';

    function row(p, isHome) {
      const seed = p.id.charCodeAt(1) || 1;
      const pts = isHome ? (12 + seed * 3) % 28 : (8 + seed * 2) % 22;
      return `
        <tr>
          <td class="player">
            <span class="jr" style="background:${isHome ? '#EA580C' : '#1e40af'}">${p.num}</span>
            ${p.name}
          </td>
          <td><input class="cell" value="${20 + (seed % 18)}" ${isReview ? 'readonly' : ''}></td>
          <td><input class="cell" value="${pts}" ${isReview ? 'readonly' : ''}></td>
          <td><input class="cell" value="${seed % 4}" ${isReview ? 'readonly' : ''}></td>
          <td><input class="cell" value="${(seed * 2) % 6}" ${isReview ? 'readonly' : ''}></td>
          <td><input class="cell" value="${seed % 5}" ${isReview ? 'readonly' : ''}></td>
          <td><input class="cell" value="${seed % 3}" ${isReview ? 'readonly' : ''}></td>
          <td><input class="cell" value="${(seed + 1) % 3}" ${isReview ? 'readonly' : ''}></td>
          <td><input class="cell" value="${(seed * 2) % 5}" ${isReview ? 'readonly' : ''}></td>
        </tr>`;
    }

    return `
      <div style="padding:12px">
        <div style="display:flex;gap:8px;align-items:center;margin-bottom:10px">
          <span class="chip ${isReview ? 'chip-submitted' : 'chip-pending'}">${isReview ? 'Submitted · Review' : 'Draft'}</span>
          <span style="font-size:11px;color:var(--muted)">Auto-saved 2s ago</span>
          <span style="margin-left:auto;font-size:11px;color:var(--muted)">Q1 · Q2 · Q3 · Q4 ▾</span>
        </div>
        <div style="font-family:var(--serif);font-size:18px;letter-spacing:-0.01em">Kingston Titans <span style="color:var(--muted)">vs</span> Portmore Thunder</div>
        <div style="font-size:11px;color:var(--muted);margin-bottom:10px">Mar 12 · NISC · 87 – 72 final</div>
      </div>

      <div style="overflow-x:auto;margin:0 12px;border:1px solid var(--line);border-radius:10px">
        <table class="stat-entry-table">
          <thead><tr><th class="player" style="text-align:left;padding-left:10px">Player</th><th>MIN</th><th>PTS</th><th>OREB</th><th>DREB</th><th>AST</th><th>STL</th><th>BLK</th><th>FLS</th></tr></thead>
          <tbody>
            <tr class="team-divider"><td colspan="9">Kingston Titans</td></tr>
            ${D.PLAYERS_HOME.map(p => row(p, true)).join('')}
            <tr class="total"><td class="player" style="text-align:right;padding-right:10px">Team total</td><td>240</td><td>87</td><td>11</td><td>26</td><td>21</td><td>7</td><td>4</td><td>16</td></tr>
            <tr class="team-divider"><td colspan="9">Portmore Thunder</td></tr>
            ${D.PLAYERS_AWAY.map(p => row(p, false)).join('')}
            <tr class="total"><td class="player" style="text-align:right;padding-right:10px">Team total</td><td>240</td><td>72</td><td>9</td><td>22</td><td>14</td><td>5</td><td>3</td><td>20</td></tr>
          </tbody>
        </table>
      </div>

      <div style="padding:14px 12px;display:flex;gap:8px;flex-direction:column">
        ${isReview ? `
          <button class="btn orange lg" style="width:100%" onclick="HCApp.approveStats()">✓ Approve &amp; publish</button>
          <button class="btn ghost" style="width:100%">Send back to statistician with notes</button>
        ` : `
          <button class="btn ghost" style="width:100%">Save Draft</button>
          <button class="btn orange lg" style="width:100%" onclick="HCApp.submitStats()">Submit for approval →</button>
        `}
        <div style="font-size:11px;color:var(--muted);text-align:center;margin-top:6px">
          Validation: PTS = sum(2PT·2 + 3PT·3 + FT) · MIN ≤ 240 per team · No negatives
        </div>
      </div>
    `;
  }

  // ─── BOX SCORE ───
  function renderBoxScore() {
    return `
      <div style="background:#0e0e0c;color:white;padding:18px 16px">
        <div style="display:flex;align-items:center;justify-content:space-around">
          <div style="text-align:center">
            <div style="font-size:11px;color:#a5a39c;letter-spacing:0.1em;text-transform:uppercase">Kingston Titans</div>
            <div style="font-family:var(--serif);font-size:46px;font-weight:600;letter-spacing:-0.02em;color:var(--orange);line-height:1.05">87</div>
          </div>
          <div style="font-family:var(--mono);font-size:11px;color:#a5a39c">FINAL</div>
          <div style="text-align:center">
            <div style="font-size:11px;color:#a5a39c;letter-spacing:0.1em;text-transform:uppercase">Portmore Thunder</div>
            <div style="font-family:var(--serif);font-size:46px;font-weight:600;letter-spacing:-0.02em;color:white;line-height:1.05;opacity:0.55">72</div>
          </div>
        </div>
        <div style="text-align:center;font-size:11px;color:#a5a39c;margin-top:10px">Mar 12 · NISC · Approved by JBA Admin</div>
      </div>

      <div class="section-h"><span class="t">Top Performers</span></div>
      ${[
        { pts: 25, name: 'Devon Clarke', team: 'Kingston Titans', line: '8 REB · 4 AST · 2 STL', clr: 'var(--orange)' },
        { pts: 20, name: 'Tyrone Williams', team: 'Portmore Thunder', line: '11 REB · 3 AST', clr: '#7c3aed', dd: true },
        { pts: 18, name: 'Kyle Roberts', team: 'Kingston Titans', line: '3 REB · 8 AST', clr: 'var(--ink)' },
      ].map(p => `
        <div class="p-card" style="display:flex;align-items:center;gap:12px">
          <div style="width:44px;height:44px;border-radius:10px;background:${p.clr};color:white;display:flex;align-items:center;justify-content:center;font-family:var(--serif);font-size:20px;font-weight:600">${p.pts}</div>
          <div style="flex:1">
            <div style="font-size:13.5px;font-weight:700">${p.name} ${p.dd ? '<span class="chip chip-approved" style="margin-left:4px">DD</span>' : ''}</div>
            <div style="font-size:11px;color:var(--muted)">${p.team}</div>
            <div style="font-size:11.5px;color:var(--ink-2);margin-top:2px">${p.line}</div>
          </div>
        </div>
      `).join('')}

      <div class="section-h"><span class="t">Quarter Scores</span></div>
      <div class="p-card tight" style="overflow:hidden">
        <table class="standings" style="font-size:12px">
          <thead><tr><th></th><th>Q1</th><th>Q2</th><th>Q3</th><th>Q4</th><th>F</th></tr></thead>
          <tbody>
            <tr><td class="team-cell"><span class="name">Titans</span></td><td>22</td><td>20</td><td>26</td><td>19</td><td class="w">87</td></tr>
            <tr><td class="team-cell"><span class="name">Thunder</span></td><td>16</td><td>21</td><td>17</td><td>18</td><td>72</td></tr>
          </tbody>
        </table>
      </div>

      <div style="padding:12px;display:flex;gap:8px">
        <button class="btn ghost" style="flex:1">Full Box Score</button>
        <button class="btn ghost" style="flex:1">Share Recap</button>
      </div>
    `;
  }

  // ─── ACK TRACKER ───
  function renderAckTracker() {
    const post = D.POSTS.find(p => p.ack);
    const reps = [
      { team: 'Kingston Titans', rep: 'Coach Thompson', status: 'acked', when: 'Mar 13 · 2:14 PM' },
      { team: 'Montego Bay Storm', rep: 'Coach Smith', status: 'acked', when: 'Mar 13 · 4:01 PM' },
      { team: 'Spanish Town Heat', rep: 'Coach Reid', status: 'acked', when: 'Mar 13 · 6:33 PM' },
      { team: 'Portmore Thunder', rep: 'Coach Lewis', status: 'overdue', when: '' },
      { team: 'Mandeville Magic', rep: 'Coach Brown', status: 'pending', when: '' },
      { team: 'Ocho Rios Waves', rep: 'Coach Daley', status: 'pending', when: '' },
    ];

    return `
      <div style="padding:14px 12px">
        <div style="font-size:11px;color:var(--muted);letter-spacing:0.08em;text-transform:uppercase;margin-bottom:4px">Ack Tracker</div>
        <div style="font-family:var(--serif);font-size:18px;letter-spacing:-0.01em;line-height:1.25">${post.title}</div>
        <div style="display:flex;gap:6px;margin-top:8px">
          <span class="chip chip-pending">${post.ack.total - post.ack.done} of ${post.ack.total} pending</span>
          <span class="chip chip-urgent">Overdue</span>
        </div>
      </div>

      <div class="section-h"><span class="t">By team rep</span><span class="a">Send reminder all →</span></div>
      <div class="p-card tight">
        ${reps.map(r => `
          <div style="padding:10px 14px;border-bottom:1px solid var(--line);display:flex;align-items:center;gap:10px">
            <div style="width:24px;height:24px;border-radius:50%;display:flex;align-items:center;justify-content:center;font-size:11px;font-weight:800;background:${r.status==='acked'?'var(--approved-bg)':r.status==='overdue'?'var(--urgent-bg)':'var(--bg-2)'};color:${r.status==='acked'?'var(--approved)':r.status==='overdue'?'var(--urgent)':'var(--muted)'}">${r.status==='acked'?'✓':r.status==='overdue'?'!':'·'}</div>
            <div style="flex:1">
              <div style="font-size:12.5px;font-weight:600">${r.team}</div>
              <div style="font-size:10.5px;color:var(--muted)">${r.rep}${r.when ? ' · ' + r.when : ''}</div>
            </div>
            ${r.status === 'overdue' ? '<button class="btn sm danger">Call</button>' : r.status === 'pending' ? '<button class="btn sm ghost">Remind</button>' : ''}
          </div>
        `).join('')}
      </div>
    `;
  }

  // ─── INVITE CODES ───
  function renderInvites() {
    const codes = [
      { code: 'TIT-REP-9X4', role: 'Team Rep', team: 'Kingston Titans', uses: '0/1', exp: 'Apr 1', status: 'active' },
      { code: 'STM-REP-K3M', role: 'Team Rep', team: 'Montego Bay Storm', uses: '1/1', exp: 'Used', status: 'used' },
      { code: 'STAT-J7H',    role: 'Statistician', team: 'Any', uses: '2/5', exp: 'Apr 30', status: 'active' },
      { code: 'PRESS-2026',  role: 'Press', team: 'Any', uses: '3/25', exp: 'Season end', status: 'active' },
      { code: 'ADMIN-OLD',   role: 'Admin', team: 'Any', uses: '0/1', exp: 'Mar 1', status: 'expired' },
    ];

    return `
      <div style="padding:14px 12px">
        <div style="font-size:11px;color:var(--muted);letter-spacing:0.08em;text-transform:uppercase">Super-admin only</div>
        <div style="font-family:var(--serif);font-size:22px;letter-spacing:-0.01em">Invite Codes</div>
        <div style="font-size:12px;color:var(--muted);margin-top:4px">Generate, distribute, revoke</div>
      </div>

      <div style="padding:0 12px">
        <button class="btn orange" style="width:100%">＋ Generate Code</button>
      </div>

      <div class="section-h"><span class="t">Active &amp; Recent</span></div>
      ${codes.map(c => `
        <div class="p-card" style="padding:12px">
          <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px">
            <div style="font-family:var(--mono);font-size:14px;font-weight:700;letter-spacing:0.05em">${c.code}</div>
            <span class="chip ${c.status==='active'?'chip-approved':c.status==='used'?'chip-submitted':'chip-urgent'}">${c.status}</span>
          </div>
          <div style="font-size:12px;color:var(--ink-2)">${c.role} · ${c.team}</div>
          <div style="display:flex;justify-content:space-between;font-size:11px;color:var(--muted);margin-top:6px">
            <span>Uses: ${c.uses}</span>
            <span>Expires: ${c.exp}</span>
          </div>
        </div>
      `).join('')}
    `;
  }

  // ─── JOIN / SIGN-UP ───
  function renderJoin() {
    return `
      <div style="padding:24px 16px;text-align:center">
        <img src="assets/jba_logo.png" style="height:56px;margin-bottom:14px" alt="JBA">
        <div style="font-family:var(--serif);font-size:26px;letter-spacing:-0.02em">Join HoopsConnect</div>
        <div style="font-size:12.5px;color:var(--muted);margin-top:4px">Have an invite code? Enter it to be assigned a team and role.</div>
      </div>

      <div class="p-card" style="padding:18px">
        <div style="font-size:11px;color:var(--muted);letter-spacing:0.08em;text-transform:uppercase;margin-bottom:6px">Step 1 · Invite code</div>
        <input style="width:100%;padding:12px;border:1px solid var(--line);border-radius:8px;font-family:var(--mono);font-size:16px;letter-spacing:0.1em;text-align:center" placeholder="TIT-REP-9X4" value="TIT-REP-9X4">
        <div style="margin-top:8px;padding:8px;background:var(--approved-bg);color:var(--approved);font-size:12px;border-radius:6px;text-align:center">✓ Valid · Team Rep · Kingston Titans</div>
      </div>

      <div class="p-card" style="padding:18px">
        <div style="font-size:11px;color:var(--muted);letter-spacing:0.08em;text-transform:uppercase;margin-bottom:6px">Step 2 · Your details</div>
        <input style="width:100%;padding:11px;border:1px solid var(--line);border-radius:8px;font-size:13px;margin-bottom:8px" placeholder="Full name" value="Coach Thompson">
        <input style="width:100%;padding:11px;border:1px solid var(--line);border-radius:8px;font-size:13px;margin-bottom:8px" placeholder="Email" value="thompson@titans.jm">
        <input style="width:100%;padding:11px;border:1px solid var(--line);border-radius:8px;font-size:13px" placeholder="Password" type="password" value="password">
      </div>

      <div style="padding:12px">
        <button class="btn orange lg" style="width:100%">Create account</button>
        <div style="text-align:center;font-size:11.5px;color:var(--muted);margin-top:10px">Or join as a fan — no code needed</div>
      </div>
    `;
  }

  return {
    renderBoard, renderStandings, renderLeaderboard, renderSchedule, renderAdmin, renderPress,
    renderPlayerCard, renderStatEntry, renderBoxScore, renderAckTracker, renderInvites, renderJoin,
  };
})();
