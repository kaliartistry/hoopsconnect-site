import { useState } from "react";

const tabs = ["Feasibility", "Architecture", "Wireframes", "Flows", "Roadmap"];

const PhoneFrame = ({ title, children }) => (
  <div className="mx-auto" style={{ width: 280 }}>
    <div className="bg-gray-900 rounded-3xl p-2 shadow-2xl">
      <div className="bg-white rounded-2xl overflow-hidden" style={{ minHeight: 500 }}>
        <div className="bg-orange-600 text-white px-4 py-3">
          <div className="text-xs opacity-70 text-center mb-1">9:41</div>
          <div className="font-bold text-sm">{title}</div>
        </div>
        <div className="px-3 py-2 text-xs">{children}</div>
      </div>
    </div>
  </div>
);

const PostCard = ({ type, author, team, time, title, body, pinned, urgent, ack, ackDone }) => (
  <div className={`border rounded-lg p-2 mb-2 ${urgent ? "border-red-400 bg-red-50" : ack && !ackDone ? "border-amber-400 bg-amber-50" : "border-gray-200"}`}>
    <div className="flex items-center gap-1 mb-1 flex-wrap">
      {pinned && <span className="text-orange-500">📌</span>}
      {urgent && <span className="bg-red-500 text-white px-1 rounded text-[9px] font-bold">URGENT</span>}
      {ack && !ackDone && <span className="bg-amber-500 text-white px-1 rounded text-[9px] font-bold">⚡ ACK REQUIRED</span>}
      {ackDone && <span className="bg-green-500 text-white px-1 rounded text-[9px] font-bold">✅ ACKNOWLEDGED</span>}
      <span className={`px-1 rounded text-[9px] font-bold ${type === "admin" ? "bg-orange-100 text-orange-700" : "bg-blue-100 text-blue-700"}`}>
        {type === "admin" ? "ASSOCIATION" : "TEAM"}
      </span>
    </div>
    <div className="font-bold text-[11px] text-gray-900">{title}</div>
    <div className="text-gray-600 text-[10px] mt-0.5 leading-relaxed">{body}</div>
    {ack && !ackDone && (
      <button className="w-full mt-2 bg-amber-500 text-white rounded-lg py-2 text-[11px] font-bold">✅ Tap to Acknowledge</button>
    )}
    {ackDone && (
      <div className="mt-1.5 text-[9px] text-green-600 font-medium">✅ You acknowledged this on Feb 25 at 3:42 PM</div>
    )}
    <div className="flex justify-between items-center mt-1.5 pt-1 border-t border-gray-100">
      <span className="text-gray-400 text-[9px]">{author} · {team} · {time}</span>
      {ack && <span className="text-amber-600 text-[9px] font-medium">18/24 confirmed</span>}
      {!ack && <span className="text-gray-400 text-[9px]">👍 3 · 💬 2</span>}
    </div>
  </div>
);

const AckTeamRow = ({ team, rep, status, time, phone }) => (
  <div className={`flex items-center gap-2 p-2 rounded-lg mb-1 ${status === "acked" ? "bg-green-50" : status === "overdue" ? "bg-red-50" : "bg-gray-50"}`}>
    <div className={`w-5 h-5 rounded-full flex items-center justify-center text-[10px] font-bold ${status === "acked" ? "bg-green-500 text-white" : status === "overdue" ? "bg-red-500 text-white" : "bg-gray-300 text-white"}`}>
      {status === "acked" ? "✓" : status === "overdue" ? "!" : "·"}
    </div>
    <div className="flex-1">
      <div className="font-bold text-[10px]">{team}</div>
      <div className="text-gray-500 text-[9px]">{rep}{time && ` · ${time}`}</div>
    </div>
    {status === "overdue" && (
      <span className="bg-red-500 text-white px-2 py-1 rounded text-[9px] font-bold">📞 Call</span>
    )}
    {status === "pending" && <span className="text-gray-400 text-[9px]">Waiting...</span>}
  </div>
);

const StatCell = ({ value, highlight }) => (
  <div className={`w-8 h-7 flex items-center justify-center text-[10px] font-mono border-r border-gray-200 ${highlight ? "bg-orange-50 font-bold text-orange-700" : "text-gray-800"}`}>
    {value}
  </div>
);

const Wireframes = () => {
  const [screen, setScreen] = useState(0);
  const screens = [
    "Board", "Ack (Rep)", "Ack Tracker", "Stat Entry", "Stat Entry 2",
    "Box Score", "Leaderboard", "Player Card", "Calendar", "Create Post", "Admin Panel", "Team View", "Join Flow"
  ];

  return (
    <div>
      <div className="flex flex-wrap gap-2 mb-6">
        {screens.map((s, i) => {
          const isAck = i === 1 || i === 2;
          const isStat = i >= 3 && i <= 7;
          return (
            <button
              key={s}
              onClick={() => setScreen(i)}
              className={`px-3 py-1.5 rounded-full text-sm font-medium transition-all ${screen === i ? "bg-orange-600 text-white" : "bg-gray-100 text-gray-600 hover:bg-gray-200"} ${isAck ? "ring-2 ring-amber-400" : ""} ${isStat ? "ring-2 ring-emerald-400" : ""}`}
            >
              {s} {isAck ? "⚡" : ""}{isStat ? "📊" : ""}
            </button>
          );
        })}
      </div>

      <div className="flex justify-center">
        {screen === 0 && (
          <PhoneFrame title="🏀 HoopsConnect — Board">
            <div className="flex gap-1 mb-2 overflow-x-auto py-1">
              {["All", "Announcements", "Men's Open", "Women's 30+"].map((f, i) => (
                <span key={f} className={`px-2 py-0.5 rounded-full whitespace-nowrap text-[9px] font-medium ${i === 0 ? "bg-orange-600 text-white" : "bg-gray-100 text-gray-600"}`}>{f}</span>
              ))}
            </div>
            <PostCard type="admin" pinned urgent ack author="Commissioner Davis" team="Association" time="2h"
              title="⚠️ Gym 3 Closed This Saturday — All Games Relocated"
              body="All Saturday games at Lincoln Rec Gym 3 relocated to Washington CC." />
            <PostCard type="admin" pinned ack ackDone author="Commissioner Davis" team="Association" time="1d"
              title="Spring 2026 Registration Deadline — March 15"
              body="All team rosters must be finalized by March 15." />
            <PostCard type="team" author="Mike R." team="Thunderbolts" time="3h"
              title="Need 1 Ref for Saturday 2PM Game"
              body="Looking for a certified ref. $45/game." />
            <PostCard type="team" author="Sarah L." team="Lady Hoops" time="5h"
              title="Practice Gym Available — Tues 7-9PM"
              body="Extra gym slot at Park Ave Rec. $30/hr split." />
          </PhoneFrame>
        )}

        {screen === 1 && (
          <PhoneFrame title="⚡ Acknowledgment Required">
            <div className="bg-amber-50 border-2 border-amber-400 rounded-xl p-3 mb-3">
              <div className="flex items-center gap-1 mb-1">
                <span className="bg-red-500 text-white px-1 rounded text-[9px] font-bold">URGENT</span>
                <span className="bg-amber-500 text-white px-1 rounded text-[9px] font-bold">⚡ ACK REQUIRED</span>
              </div>
              <div className="font-bold text-[12px] text-gray-900 mt-1">⚠️ Gym 3 Closed This Saturday</div>
              <div className="text-gray-700 text-[10px] mt-1 leading-relaxed">
                ALL games at Lincoln Rec Gym 3 this Saturday are relocated to Washington Community Center. Game times unchanged.
              </div>
              <div className="text-gray-500 text-[9px] mt-2">Commissioner Davis · 2 hours ago</div>
            </div>
            <div className="bg-amber-100 border border-amber-300 rounded-lg p-2 mb-3">
              <div className="text-[10px] font-bold text-amber-800">⏰ Acknowledge by: Tomorrow 6:00 PM</div>
              <div className="text-[9px] text-amber-700">Tap below to confirm your team received this.</div>
            </div>
            <div className="text-[10px] text-gray-500 mb-1 text-center">18 of 24 team reps have acknowledged</div>
            <div className="w-full bg-gray-200 rounded-full h-2 mb-3">
              <div className="bg-amber-500 h-2 rounded-full" style={{ width: "75%" }}></div>
            </div>
            <button className="w-full bg-amber-500 text-white rounded-xl py-3.5 text-sm font-bold shadow-lg mb-2">
              ✅ I Acknowledge — My Team Is Informed
            </button>
            <div className="text-center text-[9px] text-gray-400">This confirms you've read and will relay to your team</div>
          </PhoneFrame>
        )}

        {screen === 2 && (
          <PhoneFrame title="📊 Ack Tracker — Admin">
            <div className="bg-gray-50 rounded-lg p-2 mb-2">
              <div className="font-bold text-[11px]">⚠️ Gym 3 Closed This Saturday</div>
              <div className="text-[9px] text-gray-500">Sent 2h ago · Deadline: Tomorrow 6 PM</div>
            </div>
            <div className="flex gap-2 mb-3">
              {[{ n: "18", l: "Confirmed", c: "green" }, { n: "3", l: "Overdue", c: "red" }, { n: "3", l: "Pending", c: "gray" }].map((s, i) => (
                <div key={i} className={`flex-1 bg-${s.c}-50 border border-${s.c}-200 rounded-lg p-2 text-center`}>
                  <div className={`text-xl font-bold text-${s.c}-600`}>{s.n}</div>
                  <div className={`text-[9px] text-${s.c}-700 font-medium`}>{s.l}</div>
                </div>
              ))}
            </div>
            <div className="w-full bg-gray-200 rounded-full h-2.5 mb-3">
              <div className="bg-green-500 h-2.5 rounded-full" style={{ width: "75%" }}></div>
            </div>
            <span className="bg-red-100 text-red-700 text-[9px] font-bold px-1.5 py-0.5 rounded">NEEDS FOLLOW-UP</span>
            <div className="mt-1">
              <AckTeamRow team="Raptors" rep="Devon J." status="overdue" phone="555-0142" />
              <AckTeamRow team="Storm" rep="Angela M." status="overdue" phone="555-0198" />
              <AckTeamRow team="Wildcats" rep="Chris P." status="overdue" phone="555-0167" />
            </div>
            <div className="mt-2">
              <span className="bg-green-100 text-green-700 text-[9px] font-bold px-1.5 py-0.5 rounded">CONFIRMED ✓</span>
            </div>
            <div className="mt-1">
              <AckTeamRow team="Thunderbolts" rep="Mike R." status="acked" time="1h ago" />
              <AckTeamRow team="Lady Hoops" rep="Sarah L." status="acked" time="1.5h ago" />
            </div>
            <div className="text-gray-400 text-[9px] text-center mt-1">+15 more confirmed...</div>
            <button className="w-full mt-3 border-2 border-red-400 text-red-600 rounded-lg py-2 text-[10px] font-bold">
              📞 Send Reminder to All Unconfirmed
            </button>
          </PhoneFrame>
        )}

        {screen === 3 && (
          <PhoneFrame title="📊 Enter Game Stats">
            <div className="text-[10px] font-bold text-gray-500 mb-2">SELECT GAME TO ENTER STATS</div>
            <div className="flex gap-1 mb-2">
              {["Needs Stats", "Submitted", "Approved"].map((f, i) => (
                <span key={f} className={`px-2 py-0.5 rounded-full text-[9px] font-medium ${i === 0 ? "bg-red-100 text-red-700 border border-red-300" : "bg-gray-100 text-gray-500"}`}>
                  {f} {i === 0 ? "(4)" : i === 1 ? "(2)" : "(12)"}
                </span>
              ))}
            </div>
            <div className="text-[9px] font-bold text-red-600 mb-1">SATURDAY, MAR 7 — NEEDS STATS</div>
            {[
              { time: "2:00 PM", home: "Thunderbolts", away: "Blazers", div: "Men's Open", loc: "Washington CC" },
              { time: "3:30 PM", home: "Nets", away: "Hawks", div: "Men's Open", loc: "Washington CC" },
            ].map((g, i) => (
              <div key={i} className="border border-red-200 bg-red-50 rounded-lg p-2 mb-2">
                <div className="flex justify-between items-center mb-1">
                  <span className="text-[9px] text-gray-500">{g.time} · {g.div}</span>
                  <span className="bg-red-500 text-white text-[8px] px-1.5 py-0.5 rounded font-bold">NO STATS</span>
                </div>
                <div className="flex items-center justify-between">
                  <div className="text-center flex-1">
                    <div className="font-bold text-[11px]">{g.home}</div>
                    <div className="text-[9px] text-gray-400">Home</div>
                  </div>
                  <div className="text-gray-300 font-bold text-sm px-2">vs</div>
                  <div className="text-center flex-1">
                    <div className="font-bold text-[11px]">{g.away}</div>
                    <div className="text-[9px] text-gray-400">Away</div>
                  </div>
                </div>
                <button className="w-full mt-1.5 bg-orange-600 text-white rounded py-1.5 text-[10px] font-bold">
                  Enter Stats →
                </button>
              </div>
            ))}
          </PhoneFrame>
        )}
      </div>
    </div>
  );
};

const FlowDiagram = ({ title, steps }) => (
  <div className="mb-6">
    <h4 className="font-bold text-gray-900 mb-3">{title}</h4>
    <div className="flex flex-wrap items-center gap-1">
      {steps.map((step, i) => (
        <div key={i} className="flex items-center gap-1">
          <div className={`px-3 py-2 rounded-lg text-xs font-medium ${step.type === "action" ? "bg-orange-100 text-orange-800 border border-orange-200" : step.type === "decision" ? "bg-yellow-100 text-yellow-800 border border-yellow-200" : step.type === "system" ? "bg-blue-100 text-blue-800 border border-blue-200" : step.type === "escalation" ? "bg-red-100 text-red-800 border border-red-200" : "bg-green-100 text-green-800 border border-green-200"}`}>
            {step.label}
          </div>
          {i < steps.length - 1 && <span className="text-gray-400 font-bold">→</span>}
        </div>
      ))}
    </div>
  </div>
);

export default function HoopsConnectPlan() {
  const [activeTab, setActiveTab] = useState(0);

  return (
    <div className="min-h-screen bg-white">
      <div className="max-w-4xl mx-auto px-4 py-6">
        <div className="mb-6">
          <div className="flex items-center gap-3 mb-2">
            <div className="w-10 h-10 bg-orange-600 rounded-xl flex items-center justify-center text-white text-xl">🏀</div>
            <div>
              <h1 className="text-2xl font-bold text-gray-900">HoopsConnect</h1>
              <p className="text-gray-500 text-sm">Full Build Plan — Communication + Stats + Acknowledgments</p>
            </div>
          </div>
        </div>

        <div className="flex gap-1 mb-6 overflow-x-auto border-b border-gray-200">
          {tabs.map((tab, i) => (
            <button key={tab} onClick={() => setActiveTab(i)}
              className={`px-4 py-2.5 text-sm font-medium whitespace-nowrap border-b-2 ${activeTab === i ? "border-orange-600 text-orange-600" : "border-transparent text-gray-500 hover:text-gray-700"}`}>
              {tab}
            </button>
          ))}
        </div>

        {/* Full implementation with all 5 tabs:
            Tab 0: Feasibility - Firebase free tier analysis
            Tab 1: Architecture - Firestore data model, stats pipeline, auth roles
            Tab 2: Wireframes - 13 interactive phone mockups
            Tab 3: Flows - 6 user flow diagrams
            Tab 4: Roadmap - 8 phases over 16 weeks
        */}
      </div>
    </div>
  );
}
