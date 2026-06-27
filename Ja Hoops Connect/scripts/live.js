// HoopsConnect — live stats overlay (court-side stat-taker)
window.HC_LIVE = (function () {
  const D = window.HC_DATA;

  let state = {
    phase: 'setup', // setup | game
    selectedPlayer: null,
    homeScore: 0,
    awayScore: 0,
    quarter: 1,
    clockSec: 600,
    clockRunning: false,
    homePlayers: D.PLAYERS_HOME.map(p => ({ ...p, pts: 0, reb: 0, ast: 0, fls: 0, oncourt: p.starter || false })),
    awayPlayers: D.PLAYERS_AWAY.map(p => ({ ...p, pts: 0, reb: 0, ast: 0, fls: 0, oncourt: p.starter || false })),
    log: [],
  };

  function open() {
    state.phase = 'setup';
    document.getElementById('liveOverlay').classList.add('on');
    render();
  }
  function close() {
    document.getElementById('liveOverlay').classList.remove('on');
  }

  function render() {
    const el = document.getElementById('liveOverlay');
    if (state.phase === 'setup') el.innerHTML = renderSetup();
    else el.innerHTML = renderGame();
  }

  function renderSetup() {
    const home = D.TEAMS.find(t => t.id === 'titans');
    const away = D.TEAMS.find(t => t.id === 'storm');
    function card(team, players, isAway) {
      return `
        <div class="roster-col ${isAway ? 'away' : 'home'}">
          <h4>${team.name}</h4>
          <div class="pcount">Pick 5 starters · <span id="${isAway?'awayCount':'homeCount'}">${players.filter(p=>p.starter).length}/5</span></div>
          ${players.map(p => `
            <div class="pp ${p.starter ? (isAway ? 'starter away-starter' : 'starter') : ''}" onclick="HCLive.toggleStarter('${isAway?'away':'home'}','${p.id}', this)">
              <div class="jr">#${p.num}</div>
              <div class="nm">${p.name}</div>
              <div class="star">★</div>
            </div>`).join('')}
        </div>`;
    }

    return `
      <div class="live-topbar">
        <button class="x" onclick="HCLive.close()">← Back</button>
        <h2>Game Setup</h2>
        <span></span>
      </div>
      <div class="setup">
        <div class="max">
          <div class="game-strip">
            <div>
              <div class="ttl">Kingston Titans vs Montego Bay Storm</div>
              <div class="meta">Tonight 7:00 PM · National Indoor Sports Centre</div>
            </div>
            <div style="text-align:right">
              <div style="font-size:10px;color:#a5a39c;letter-spacing:0.1em;text-transform:uppercase">Mode</div>
              <select style="background:#2b2a26;color:white;border:1px solid #4a4844;border-radius:6px;padding:5px 8px;font-size:12px;margin-top:4px">
                <option>Stats only</option>
                <option>Stats + Clock</option>
              </select>
            </div>
          </div>
          <div class="roster-2col">
            ${card(home, state.homePlayers, false)}
            ${card(away, state.awayPlayers, true)}
          </div>
          <div style="display:flex;gap:10px;margin-top:18px">
            <button class="btn ghost" style="flex:1" onclick="HCLive.close()">Cancel</button>
            <button class="btn orange lg" style="flex:2" onclick="HCLive.startGame()">🏀 Start game</button>
          </div>
          <div style="margin-top:14px;padding:12px 14px;background:var(--bg);border:1px solid var(--line);border-radius:10px;font-size:11.5px;color:var(--ink-2);line-height:1.5">
            <b style="color:var(--ink)">Tip:</b> Once you start, every action auto-saves to Firestore. You can substitute, adjust the clock, or reverse a play at any time. Foul-outs are detected automatically.
          </div>
        </div>
      </div>`;
  }

  function renderGame() {
    const sel = state.selectedPlayer;
    const all = [...state.homePlayers, ...state.awayPlayers];
    const selPlayer = all.find(p => p.id === sel);

    function playerRow(p, side) {
      const cls = state.selectedPlayer === p.id ? 'selected' : '';
      const foulCls = p.fls >= 5 ? 'danger' : (p.fls === 4 ? 'warn' : '');
      const color = side === 'home' ? '#EA580C' : '#1e40af';
      return `
        <div class="live-player-row ${cls}" onclick="HCLive.selectPlayer('${p.id}')">
          <div class="jr" style="background:${color}">${p.num}</div>
          <div class="info">
            <div class="n">${p.name}</div>
            <div class="l">${p.pos} · ${p.pts} PTS · ${p.reb} REB · ${p.ast} AST</div>
          </div>
          ${p.fls > 0 ? `<div class="foul-badge ${foulCls}">${p.fls}F</div>` : ''}
        </div>`;
    }

    const homeOn = state.homePlayers.filter(p => p.oncourt);
    const homeBench = state.homePlayers.filter(p => !p.oncourt);
    const awayOn = state.awayPlayers.filter(p => p.oncourt);
    const awayBench = state.awayPlayers.filter(p => !p.oncourt);

    function fmtClock(s) {
      const m = Math.floor(s / 60);
      const sec = (s % 60).toString().padStart(2, '0');
      return `${m}:${sec}`;
    }

    return `
      <div class="live-topbar">
        <button class="x" onclick="HCLive.close()">← Exit</button>
        <h2>Live · Q${state.quarter} · Auto-saving</h2>
        <button class="x" onclick="HCLive.endGame()">End Game</button>
      </div>
      <div class="live-scoreboard">
        <div class="t-block">
          <div class="lbl">Kingston Titans</div>
          <div class="nm">Titans</div>
          <div class="pts" id="liveHomePts">${state.homeScore}</div>
        </div>
        <div class="clk">
          <div class="q">Quarter ${state.quarter}</div>
          <div class="t">${fmtClock(state.clockSec)}</div>
          <div class="ctrl">
            <button onclick="HCLive.toggleClock()">${state.clockRunning ? '⏸' : '▶'}</button>
            <button onclick="HCLive.nextQuarter()">Q+</button>
          </div>
        </div>
        <div class="t-block">
          <div class="lbl">Montego Bay Storm</div>
          <div class="nm">Storm</div>
          <div class="pts" id="liveAwayPts" style="color:#60a5fa">${state.awayScore}</div>
        </div>
      </div>

      <div class="live-3col">
        <div class="live-rcol">
          <div class="header"><span>Titans · On Court</span><span>${homeOn.length}/5</span></div>
          ${homeOn.map(p => playerRow(p, 'home')).join('')}
          <div class="live-bench-divider">Bench</div>
          <div class="live-bench">${homeBench.map(p => playerRow(p, 'home')).join('')}</div>
        </div>

        <div class="live-action-pad">
          <div class="live-action-selected ${sel ? '' : 'empty'}">
            <div class="lbl">Selected player</div>
            <div class="nm">${selPlayer ? `#${selPlayer.num} ${selPlayer.name}` : 'Tap a player to record action'}</div>
            ${sel ? '<div style="font-size:11px;color:var(--muted)">Press Esc to deselect</div>' : ''}
          </div>

          <div class="act-section-label">Score</div>
          <div class="act-row three">
            <button class="act-btn make ${sel?'':'disabled'}" onclick="HCLive.score(2,true)"><span class="v">+2</span><span>2PT Make</span></button>
            <button class="act-btn make ${sel?'':'disabled'}" onclick="HCLive.score(3,true)"><span class="v">+3</span><span>3PT Make</span></button>
            <button class="act-btn make ${sel?'':'disabled'}" onclick="HCLive.score(1,true)"><span class="v">+1</span><span>FT Make</span></button>
          </div>
          <div class="act-row three">
            <button class="act-btn miss ${sel?'':'disabled'}" onclick="HCLive.score(2,false)"><span class="v">2</span><span>2PT Miss</span></button>
            <button class="act-btn miss ${sel?'':'disabled'}" onclick="HCLive.score(3,false)"><span class="v">3</span><span>3PT Miss</span></button>
            <button class="act-btn miss ${sel?'':'disabled'}" onclick="HCLive.score(1,false)"><span class="v">1</span><span>FT Miss</span></button>
          </div>

          <div class="act-section-label">Stats</div>
          <div class="act-row three">
            <button class="act-btn stat ${sel?'':'disabled'}" onclick="HCLive.stat('reb')">REB</button>
            <button class="act-btn stat ${sel?'':'disabled'}" onclick="HCLive.stat('ast')">AST</button>
            <button class="act-btn stat ${sel?'':'disabled'}" onclick="HCLive.stat('stl')">STL</button>
          </div>
          <div class="act-row three">
            <button class="act-btn stat ${sel?'':'disabled'}" onclick="HCLive.stat('blk')">BLK</button>
            <button class="act-btn stat ${sel?'':'disabled'}" onclick="HCLive.stat('to')">TO</button>
            <button class="act-btn stat ${sel?'':'disabled'}" onclick="HCLive.foul()">FOUL</button>
          </div>

          <div class="act-section-label">Game</div>
          <div class="act-row">
            <button class="act-btn" onclick="HCApp.toast('Substitution panel →')">Sub</button>
            <button class="act-btn" onclick="HCLive.undo()">↶ Undo</button>
          </div>
        </div>

        <div class="live-rcol">
          <div class="header"><span>Storm · On Court</span><span>${awayOn.length}/5</span></div>
          ${awayOn.map(p => playerRow(p, 'away')).join('')}
          <div class="live-bench-divider">Bench</div>
          <div class="live-bench">${awayBench.map(p => playerRow(p, 'away')).join('')}</div>
          <div class="header" style="border-top:1px solid var(--line);background:var(--paper)"><span>Last plays</span></div>
          ${state.log.slice(-6).reverse().map(l => `
            <div style="padding:8px 14px;font-size:11.5px;border-bottom:1px solid var(--line);display:flex;gap:8px">
              <span style="font-family:var(--mono);color:var(--muted);font-size:10px;min-width:38px">Q${l.q} ${l.t}</span>
              <span style="flex:1">${l.text}</span>
              ${l.pts ? `<span style="font-family:var(--serif);color:var(--orange);font-weight:700">+${l.pts}</span>` : ''}
            </div>
          `).join('') || '<div style="padding:12px;font-size:11.5px;color:var(--muted);text-align:center">No plays yet · select a player &amp; tap an action</div>'}
        </div>
      </div>`;
  }

  function toggleStarter(side, id, el) {
    const players = side === 'home' ? state.homePlayers : state.awayPlayers;
    const p = players.find(x => x.id === id);
    if (!p) return;
    const count = players.filter(x => x.starter).length;
    if (!p.starter && count >= 5) return; // max 5
    p.starter = !p.starter;
    p.oncourt = p.starter;
    render();
  }

  function startGame() {
    const homeOk = state.homePlayers.filter(p => p.starter).length === 5;
    const awayOk = state.awayPlayers.filter(p => p.starter).length === 5;
    if (!homeOk || !awayOk) {
      HCApp.toast('Pick exactly 5 starters per team');
      return;
    }
    state.phase = 'game';
    render();
  }

  function selectPlayer(id) {
    state.selectedPlayer = state.selectedPlayer === id ? null : id;
    render();
  }

  function findPlayer(id) {
    return state.homePlayers.find(p => p.id === id) || state.awayPlayers.find(p => p.id === id);
  }
  function isHome(id) { return !!state.homePlayers.find(p => p.id === id); }

  function score(pts, made) {
    if (!state.selectedPlayer) return;
    const p = findPlayer(state.selectedPlayer);
    if (made) {
      p.pts += pts;
      if (isHome(p.id)) state.homeScore += pts; else state.awayScore += pts;
    }
    state.log.push({ q: state.quarter, t: '7:42', text: `${p.name} ${made ? `made ${pts}-pointer` : `missed ${pts}-pt`}`, pts: made ? pts : 0 });
    render();
  }
  function stat(kind) {
    if (!state.selectedPlayer) return;
    const p = findPlayer(state.selectedPlayer);
    if (kind === 'reb') p.reb++;
    if (kind === 'ast') p.ast++;
    state.log.push({ q: state.quarter, t: '7:30', text: `${p.name} ${kind.toUpperCase()}` });
    render();
  }
  function foul() {
    if (!state.selectedPlayer) return;
    const p = findPlayer(state.selectedPlayer);
    p.fls++;
    state.log.push({ q: state.quarter, t: '7:18', text: `${p.name} foul (${p.fls}F)${p.fls>=5?' · FOUL OUT':''}` });
    if (p.fls >= 5) {
      p.oncourt = false;
      HCApp.toast(`${p.name} fouled out — pick a substitute`);
    }
    render();
  }
  function undo() { state.log.pop(); render(); }
  function nextQuarter() {
    if (state.quarter < 4) state.quarter++;
    state.clockSec = 600;
    render();
  }
  function toggleClock() { state.clockRunning = !state.clockRunning; render(); }

  function endGame() {
    if (!confirm('End game and submit for approval?')) return;
    HCApp.toast('Submitted to admin for approval');
    close();
  }

  return { open, close, render, toggleStarter, startGame, selectPlayer, score, stat, foul, undo, nextQuarter, toggleClock, endGame };
})();
