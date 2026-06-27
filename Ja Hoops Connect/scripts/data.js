// HoopsConnect Wireframe — data fixtures (mock JBA data)
// Mirrors the structure of the real Firestore models for fidelity.

window.HC_DATA = (function () {
  const TEAMS = [
    { id: 'titans',  name: 'Kingston Titans',     short: 'KIN', record: '18-4',  color: '#EA580C', division: 'NBL Premier' },
    { id: 'storm',   name: 'Montego Bay Storm',   short: 'MBS', record: '15-7',  color: '#1e40af', division: 'NBL Premier' },
    { id: 'heat',    name: 'Spanish Town Heat',   short: 'STH', record: '12-10', color: '#b91c1c', division: 'NBL Premier' },
    { id: 'thunder', name: 'Portmore Thunder',    short: 'PMT', record: '10-12', color: '#7c3aed', division: 'NBL Premier' },
    { id: 'magic',   name: 'Mandeville Magic',    short: 'MND', record: '8-14',  color: '#047857', division: 'NBL Premier' },
    { id: 'waves',   name: 'Ocho Rios Waves',     short: 'OCR', record: '5-17',  color: '#0891b2', division: 'NBL Premier' },
    { id: 'royals',  name: 'Half-Way-Tree Royals',short: 'HWT', record: '14-8',  color: '#be185d', division: "Women's Premier" },
    { id: 'cavs',    name: 'May Pen Cavaliers',   short: 'MPC', record: '11-11', color: '#ca8a04', division: "Women's Premier" },
  ];

  const PLAYERS_HOME = [
    { id: 'p1',  num: 5,  name: 'Devon Clarke',    pos: 'PG', starter: true },
    { id: 'p2',  num: 12, name: 'Kyle Roberts',    pos: 'SG', starter: true },
    { id: 'p3',  num: 24, name: 'Marcus Williams', pos: 'SF', starter: true },
    { id: 'p4',  num: 7,  name: 'Andre Thompson',  pos: 'PF', starter: true },
    { id: 'p5',  num: 33, name: 'Damian Stewart',  pos: 'C',  starter: true },
    { id: 'p6',  num: 10, name: 'Ryan Bennett',    pos: 'G' },
    { id: 'p7',  num: 15, name: 'Jordan Palmer',   pos: 'F' },
    { id: 'p8',  num: 21, name: 'Tariq Henry',     pos: 'F' },
  ];
  const PLAYERS_AWAY = [
    { id: 'a1',  num: 11, name: 'Andre Brown',     pos: 'PG', starter: true },
    { id: 'a2',  num: 23, name: 'Trevor Simpson',  pos: 'SG', starter: true },
    { id: 'a3',  num: 8,  name: 'Kevin Grant',     pos: 'SF', starter: true },
    { id: 'a4',  num: 3,  name: 'Shawn Davis',     pos: 'PF', starter: true },
    { id: 'a5',  num: 44, name: 'Brian Taylor',    pos: 'C',  starter: true },
    { id: 'a6',  num: 6,  name: 'Chris Morgan',    pos: 'G' },
    { id: 'a7',  num: 19, name: 'Jermaine Reid',   pos: 'F' },
  ];

  const POSTS = [
    {
      id: 'p-001',
      author: 'JBA Admin', authorRole: 'admin', team: null, when: '2 hours ago', type: 'announcement',
      title: 'Roster Lock Deadline — March 31, 11:59 PM',
      body: 'All Premier Division teams must finalize their season rosters by March 31. Any additions or releases after this date require a written waiver request.',
      ack: { required: true, deadline: 'Mar 31 · 11:59 PM', total: 24, done: 18 },
      urgent: true,
    },
    {
      id: 'p-002',
      author: 'JBA Admin', authorRole: 'admin', team: null, when: '4 hours ago', type: 'announcement',
      title: 'Venue Change — Saturday Premier Games',
      body: 'All Saturday Premier Division games will now be held at the National Indoor Sports Centre. Catherine Hall is closed for floor refinishing.',
      ack: { required: true, deadline: 'Sat 6:00 PM', total: 24, done: 11 },
    },
    {
      id: 'p-003',
      author: 'Coach Thompson', authorRole: 'rep', team: 'Kingston Titans', when: 'Yesterday', type: 'team',
      title: 'Titans roster update — Marcus Williams added',
      body: 'Marcus Williams has been added to our roster for the remainder of the season. Jersey #24. Welcome to the Titans family.',
    },
    {
      id: 'p-004',
      author: 'JBA Admin', authorRole: 'admin', team: null, when: '3 days ago', type: 'announcement',
      title: 'All-Star Weekend — March 28–29',
      body: 'The 2026 JBA All-Star Weekend will be held March 28-29 at the National Indoor Sports Centre. Voting opens Monday for fans, reps, and media.',
    },
  ];

  const SCHEDULE = [
    { id: 'g-101', date: 'Tonight', time: '7:00 PM', home: 'titans',  away: 'storm',   venue: 'National Indoor Sports Centre', status: 'pending', statsStatus: 'not_started' },
    { id: 'g-102', date: 'Tonight', time: '8:30 PM', home: 'heat',    away: 'thunder', venue: 'National Indoor Sports Centre', status: 'pending', statsStatus: 'not_started' },
    { id: 'g-103', date: 'Mar 12',  time: '7:00 PM', home: 'titans',  away: 'thunder', venue: 'National Indoor Sports Centre', status: 'final',   statsStatus: 'approved', homeScore: 87, awayScore: 72 },
    { id: 'g-104', date: 'Mar 11',  time: '8:00 PM', home: 'storm',   away: 'heat',    venue: 'Catherine Hall',                status: 'final',   statsStatus: 'submitted', homeScore: 78, awayScore: 81 },
    { id: 'g-105', date: 'Mar 10',  time: '7:30 PM', home: 'magic',   away: 'waves',   venue: 'Manchester Centre',             status: 'final',   statsStatus: 'pending', homeScore: 74, awayScore: 68 },
    { id: 'g-106', date: 'Mar 16',  time: '7:00 PM', home: 'thunder', away: 'magic',   venue: 'Portmore HEART Centre',         status: 'pending', statsStatus: 'not_started' },
  ];

  const LEADERS = {
    PPG: [
      { rank: 1, name: 'Devon Clarke',     team: 'Kingston Titans',     gp: 22, val: 22.5, badge: 'Career-high' },
      { rank: 2, name: 'Andre Brown',      team: 'Montego Bay Storm',   gp: 20, val: 19.3 },
      { rank: 3, name: 'Marcus Johnson',   team: 'Spanish Town Heat',   gp: 21, val: 18.7, badge: 'DD streak' },
      { rank: 4, name: 'Tyrone Williams',  team: 'Portmore Thunder',    gp: 19, val: 17.2 },
      { rank: 5, name: 'Kyle Roberts',     team: 'Kingston Titans',     gp: 22, val: 16.8 },
      { rank: 6, name: 'Brian Taylor',     team: 'Montego Bay Storm',   gp: 20, val: 15.4 },
    ],
    RPG: [
      { rank: 1, name: 'Marcus Johnson',   team: 'Spanish Town Heat',   gp: 21, val: 10.2 },
      { rank: 2, name: 'Damian Stewart',   team: 'Kingston Titans',     gp: 22, val: 9.6 },
      { rank: 3, name: 'Brian Taylor',     team: 'Montego Bay Storm',   gp: 20, val: 8.9 },
    ],
    APG: [
      { rank: 1, name: 'Kyle Roberts',     team: 'Kingston Titans',     gp: 22, val: 7.8 },
      { rank: 2, name: 'Andre Brown',      team: 'Montego Bay Storm',   gp: 20, val: 6.4 },
      { rank: 3, name: 'Devon Clarke',     team: 'Kingston Titans',     gp: 22, val: 5.2 },
    ],
    SPG: [
      { rank: 1, name: 'Devon Clarke',     team: 'Kingston Titans',     gp: 22, val: 2.4 },
      { rank: 2, name: 'Trevor Simpson',   team: 'Montego Bay Storm',   gp: 20, val: 2.1 },
    ],
    BPG: [
      { rank: 1, name: 'Damian Stewart',   team: 'Kingston Titans',     gp: 22, val: 1.9 },
      { rank: 2, name: 'Marcus Johnson',   team: 'Spanish Town Heat',   gp: 21, val: 1.6 },
    ],
  };

  const PLAYER_LOG = [
    { date: 'Mar 12', opp: 'vs PMT', res: 'W', score: '87-72', pts: 25, reb: 8, ast: 4 },
    { date: 'Mar 5',  opp: 'vs MBS', res: 'W', score: '92-85', pts: 28, reb: 6, ast: 5 },
    { date: 'Feb 28', opp: '@ STH',  res: 'W', score: '81-77', pts: 19, reb: 7, ast: 3 },
    { date: 'Feb 21', opp: 'vs MND', res: 'W', score: '94-71', pts: 22, reb: 5, ast: 6 },
    { date: 'Feb 14', opp: '@ MBS',  res: 'L', score: '78-83', pts: 24, reb: 9, ast: 4 },
    { date: 'Feb 7',  opp: 'vs OCR', res: 'W', score: '99-68', pts: 17, reb: 4, ast: 7 },
  ];

  const ROLES = {
    superAdmin: { name: 'Kali McCarthy', initials: 'KM', label: 'Super Admin', color: '#0e0e0c', team: null,
      caps: { board: true, admin: true, press: true, statsEntry: true, approve: true, divisions: true, invites: true } },
    admin:      { name: 'JBA Admin',     initials: 'JB', label: 'Admin',       color: '#EA580C', team: null,
      caps: { board: true, admin: true, press: false, statsEntry: true, approve: true, divisions: false, invites: true } },
    statistician: { name: 'Sasha Brown', initials: 'SB', label: 'Statistician',color: '#1e40af', team: null,
      caps: { board: true, admin: false, press: false, statsEntry: true, approve: false, divisions: false, invites: false } },
    rep:        { name: 'Coach Thompson',initials: 'CT', label: 'Team Rep',    color: '#047857', team: 'Kingston Titans',
      caps: { board: true, admin: false, press: false, statsEntry: false, approve: false, divisions: false, invites: false } },
    press:      { name: 'Michael Chen',  initials: 'MC', label: 'Press',       color: '#7c3aed', team: null,
      caps: { board: true, admin: false, press: true,  statsEntry: false, approve: false, divisions: false, invites: false } },
    fan:        { name: 'Camille Reid',  initials: 'CR', label: 'Fan',         color: '#0891b2', team: null,
      caps: { board: false,admin: false, press: false, statsEntry: false, approve: false, divisions: false, invites: false } },
  };

  return { TEAMS, PLAYERS_HOME, PLAYERS_AWAY, POSTS, SCHEDULE, LEADERS, PLAYER_LOG, ROLES };
})();
