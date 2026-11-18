// Herdr-style sidebar for cmux: Spaces tree with nested tabs, an Agents list
// grouped by status, and a status footer. Matches the Herdr "cmux-style"
// layout (graphite theme) while staying cheap: no spinners or pulsing dots,
// ages update once a minute.

const C = {
  chrome: "#101114",
  selected: "#262629",
  hover: "#1c1d21",
  border: "#222326",
  text: "#ffffff",
  muted: "#a7a8aa",
  dim: "#747578",
  accent: "#a7b4c6",
  working: "#e5a54b",
  blocked: "#e5534b",
  done: "#6fbf73",
  claude: "#d97757",
};

// Sidebar height on the full-screen window: 1130pt minus the top strip and cmux's own bottom icon row.
const SIDEBAR_MIN_HEIGHT = 1052;

// Herdr's space badge palette, in the order new spaces receive colours.
const PALETTE = ["#22a99a", "#e3814f", "#5b8def", "#8b7cf6", "#3fae6a", "#d9649a"];

// Keep the colours each space had in Herdr.
const NAMED = [
  ["externiture", "#22a99a"],
  ["passenger", "#22a99a"],
  ["automation", "#e3814f"],
  ["gcs audit", "#8b7cf6"],
  ["gcs", "#5b8def"],
  ["drawio", "#3fae6a"],
];

function badgeColor(w) {
  if (!w) return PALETTE[0];
  if (w.color) return w.color;
  const t = (w.title || "").toLowerCase();
  for (const [k, c] of NAMED) if (t.startsWith(k) || t.includes(k)) return c;
  let h = 0;
  for (const ch of w.id || t) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  return PALETTE[h % PALETTE.length];
}

const letter = (w) => ((w && w.title) || "?").trim().charAt(0).toUpperCase() || "?";

// Like Herdr: "folder · branch", each part only when it says something the name doesn't.
function gitTail(w) {
  if (!w) return "";
  // A long name leaves only a sliver, which reads as a stray letter: skip the tail.
  if ((w.title || "").length > 16) return w.dirty ? "●" : "";
  const name = (w.title || "").toLowerCase();
  const folder = (w.directory || "").replace(/\/+$/, "").split("/").pop() || "";
  const parts = [];
  if (folder && folder.toLowerCase() !== name && folder !== "~" && folder !== "hassanjan") parts.push(folder);
  const b = w.branch;
  if (b && b !== "main" && b !== "master" && b.toLowerCase() !== name) parts.push(b);
  return parts.join(" · ") + (w.dirty ? " ●" : "");
}

// --- state -------------------------------------------------------------------
const folded = new Set();
const [foldTick, setFoldTick] = signal(0);
const isFolded = (id) => (foldTick(), folded.has(id));
function toggleFold(id) {
  if (folded.has(id)) folded.delete(id);
  else folded.add(id);
  setFoldTick(foldTick() + 1);
}

let selectOverride = null;
const [selTick, setSelTick] = signal(0);
function isSelected(w) {
  selTick();
  if (!w) return false;
  if (selectOverride) {
    if (data.selectedId() === selectOverride) selectOverride = null;
    else return w.id === selectOverride;
  }
  return !!w.selected;
}
function selectSpace(id) {
  selectOverride = id;
  setSelTick(selTick() + 1);
  cmux("workspace.select", { workspace_id: id });
}
function focusTab(w, t) {
  if (!t || !t.surfaceId) return selectSpace(w.id);
  selectOverride = w.id;
  setSelTick(selTick() + 1);
  cmux("surface.focus", { surface_id: t.surfaceId, workspace_id: w.id });
}

const [editingId, setEditingId] = signal(null);

const workspaces = () => data.workspaces() ?? [];
const findWs = (id) => workspaces().find((w) => w.id === id);

// Minute bucket so ages re-render once a minute, not every second.
const minute = computed(() => Math.floor(((data.clock() ?? {}).epoch ?? 0) / 60));

function age(epoch) {
  const now = minute() * 60;
  if (!epoch || !now) return "";
  const t = epoch > 1e12 ? epoch / 1000 : epoch;
  const s = Math.max(0, now - t);
  if (s < 60) return "<1m";
  if (s < 3600) return Math.floor(s / 60) + "m";
  if (s < 86400) return Math.floor(s / 3600) + "h";
  return Math.floor(s / 86400) + "d";
}

// --- agents ------------------------------------------------------------------
const RANK = { needs_input: 0, working: 1, idle: 2 };
const GROUP = {
  needs_input: { label: "Needs you", color: C.blocked },
  working: { label: "Working", color: C.working },
  idle: { label: "Idle", color: C.dim },
};

const allAgents = computed(() => {
  const out = [];
  for (const w of workspaces()) {
    for (const a of w.agents ?? []) {
      if (a.status === "ended") continue;
      const tab = (w.tabs ?? []).find((t) => t.id === a.panelId);
      out.push({ ...a, wsId: w.id, wsTitle: w.title, tabTitle: tab ? tab.title : "", tabSurface: tab ? tab.surfaceId : null });
    }
  }
  out.sort((x, y) => (RANK[x.status] ?? 3) - (RANK[y.status] ?? 3) || (y.lastActivityAt ?? 0) - (x.lastActivityAt ?? 0));
  return out;
});

const agentStatusOfTab = (w, t) => {
  const a = (w.agents ?? []).find((x) => x.panelId === t.id && x.status !== "ended");
  return a ? a.status : null;
};

// Flat agent list: group headers, agent rows, running sub-agent rows.
const agentEntries = computed(() => {
  const list = allAgents();
  const out = [];
  for (const st of ["needs_input", "working", "idle"]) {
    const inGroup = list.filter((a) => a.status === st);
    if (!inGroup.length) continue;
    out.push({ kind: "group", id: "g:" + st, status: st, count: inGroup.length });
    for (const a of inGroup) {
      out.push({ kind: "agent", id: "a:" + a.id, agent: a });
      for (const c of a.children ?? []) {
        if (c.running) out.push({ kind: "child", id: "c:" + a.id + ":" + c.id, agent: a, child: c });
      }
    }
  }
  return out;
});

// --- spaces ------------------------------------------------------------------
const spaceEntries = computed(() => {
  const editing = editingId();
  const out = [];
  for (const w of workspaces()) {
    out.push({ kind: "space", id: "s:" + w.id + (editing === w.id ? ":edit" : ""), wsId: w.id, editing: editing === w.id });
    if (isFolded(w.id)) continue;
    for (const t of w.tabs ?? []) out.push({ kind: "tab", id: "t:" + w.id + ":" + t.id, wsId: w.id, tabId: t.id });
  }
  return out;
});

function handleMove(id, index) {
  const entries = spaceEntries();
  const moved = entries.find((e) => e.id === id);
  if (!moved || moved.kind !== "space") return;
  const rest = entries.filter((e) => e.wsId !== moved.wsId);
  let target = 0;
  for (let i = 0; i < Math.min(index, rest.length); i++) if (rest[i].kind === "space") target++;
  cmux("workspace.reorder", { workspace_id: moved.wsId, index: target });
}

// --- small parts ---------------------------------------------------------------
function iconButton(symbol, size, onTap) {
  return Image(symbol)
    .font(size).color(C.dim)
    .frame({ width: 18, height: 18 })
    .cornerRadius(4)
    .hoverBackground("#ffffff14")
    .onTap(onTap);
}

function badge(w) {
  return ZStack({}, [
    RoundedRectangle()
      .fill(() => badgeColor(w()))
      .frame({ width: 18, height: 18 })
      .cornerRadius(5),
    Text(() => letter(w())).font(10.5).bold().color(C.text),
  ]).frame({ width: 18, height: 18 }).layoutPriority(4);
}

function sectionHeader(title, trailing) {
  return HStack({ spacing: 0 }, [
    Text(title).font(11.5).weight("medium").color(C.dim),
    Spacer(),
    ...trailing,
  ])
    .paddingLeading(16)
    .paddingTrailing(10)
    .frame({ maxWidth: "infinity", height: 31 });
}

function statusGlyph(status) {
  // Static marks only: an animated spinner keeps the GPU awake.
  return ZStack({}, [
    Image(() => (status() === "idle" ? "circle" : "circle.fill"))
      .font(7)
      .color(() => { const s = status(); return s === "working" ? C.working : s === "done" ? C.done : s === "needs_input" ? "#00000000" : C.dim; }),
    Text(() => (status() === "needs_input" ? "Needs you" : ""))
      .font(10).weight("semibold").color(C.blocked)
      .paddingHorizontal(() => (status() === "needs_input" ? 6 : 0))
      .paddingVertical(() => (status() === "needs_input" ? 1 : 0))
      .background(() => (status() === "needs_input" ? C.blocked + "26" : null))
      .cornerRadius(5),
  ]).layoutPriority(2);
}

// --- rows ----------------------------------------------------------------------
function spaceMenu(w) {
  return [
    Button("Rename", () => setEditingId(w().id)),
    Button("New Tab", () => cmux("surface.create", { workspace_id: w().id })),
    Button(() => (isFolded(w()?.id) ? "Show Tabs" : "Hide Tabs"), () => toggleFold(w().id)),
    Divider(),
    Button(() => (w()?.pinned ? "Unpin" : "Pin"), () => cmux("workspace.action", { action: w()?.pinned ? "unpin" : "pin", workspace_id: w().id })),
    Divider(),
    Button("Close", () => cmux("workspace.close", { workspace_id: w().id })).destructive(),
  ];
}

function spaceRow(w) {
  return HStack({ spacing: 9 }, [
    badge(w),
    // Herdr caps the name at 150pt so the folder tail always keeps some room.
    Text(() => w()?.title ?? "")
      .font(13).color(C.text)
      .lineLimit(1).truncation("tail")
      .frame({ maxWidth: 140 })
      .layoutPriority(3),
    Text(() => gitTail(w()))
      .font(11.5).color(C.dim)
      .lineLimit(1).truncation("tail")
      .frame({ maxWidth: "infinity", alignment: "leading" })
      .layoutPriority(0),
    HStack({ spacing: 0 }, [
      iconButton("plus", 11, () => cmux("surface.create", { workspace_id: w().id })),
      iconButton(() => (isFolded(w()?.id) ? "chevron.right" : "chevron.down"), 11, () => toggleFold(w().id)),
    ]).layoutPriority(4),
  ])
    .paddingHorizontal(8)
    .frame({ maxWidth: "infinity", height: 30 })
    .cornerRadius(8)
    .background(() => (isSelected(w()) ? C.selected : null))
    .hoverBackground(() => (isSelected(w()) ? C.selected : C.hover))
    .block(() => "s:" + (w()?.id ?? ""))
    .onTap(() => selectSpace(w().id))
    .onDoubleTap(() => setEditingId(w().id))
    .contextMenu(spaceMenu(w));
}

function spaceEditRow(w) {
  return HStack({ spacing: 9 }, [
    badge(w),
    TextField(() => w()?.title ?? "", {
      placeholder: "Space name",
      onSubmit: (t) => {
        const title = (t ?? "").trim();
        cmux("workspace.action", title ? { action: "rename", workspace_id: w().id, title } : { action: "clear_name", workspace_id: w().id });
        setEditingId(null);
      },
      onCancel: () => setEditingId(null),
    }).font(13),
  ])
    .paddingHorizontal(8)
    .frame({ maxWidth: "infinity", height: 30 })
    .cornerRadius(8)
    .background(C.selected)
    .fixed();
}

function tabRow(wsId, tabId) {
  const w = () => findWs(wsId);
  const t = () => (w()?.tabs ?? []).find((x) => x.id === tabId);
  const active = () => isSelected(w()) && !!t()?.focused;
  const status = () => (w() && t() ? agentStatusOfTab(w(), t()) : null);
  const dotColor = () => (t()?.hasUnread ? C.done : status() === "working" ? C.working : status() === "needs_input" ? C.blocked : "#00000000");
  return HStack({ spacing: 0 }, [
    Rectangle().fill(() => (active() ? C.accent : C.border)).frame({ width: 2, height: 26 }),
    HStack({ spacing: 7 }, [
      Text(() => t()?.title || "Terminal")
        .font(12.5)
        .weight(() => (t()?.hasUnread ? "semibold" : "regular"))
        .color(() => (active() || t()?.hasUnread ? C.text : C.muted))
        .lineLimit(1).truncation("tail"),
      Spacer({ minLength: 0 }),
      Circle({ size: 7 }).fill(dotColor),
      Image("xmark")
        .font(9).color(C.dim)
        .padding(3).cornerRadius(4)
        .hoverBackground("#ffffff14")
        .opacity(() => (active() ? 1 : 0))
        .onTap(() => t()?.surfaceId && cmux("surface.close", { surface_id: t().surfaceId })),
    ])
      .paddingLeading(12)
      .paddingTrailing(6)
      .frame({ maxWidth: "infinity", height: 26 })
      .background(() => (active() ? C.selected : null))
      .hoverBackground(() => (active() ? C.selected : C.hover))
      .cornerRadius(6),
  ])
    .marginLeading(17)
    .frame({ maxWidth: "infinity" })
    .fixed()
    .block("s:" + wsId)
    .onTap(() => focusTab(w(), t()));
}

function agentGroupRow(e) {
  return HStack({ spacing: 6 }, [
    Text(() => GROUP[e().status]?.label ?? "").font(11).weight("medium").color(() => GROUP[e().status]?.color ?? C.dim),
    Text(() => String(e().count)).font(11).color(C.dim),
    Spacer(),
  ])
    .paddingLeading(16)
    .frame({ maxWidth: "infinity", height: 30 });
}

function agentRow(e) {
  const a = () => e().agent;
  const focus = () => cmux("surface.focus", { surface_id: a().surfaceId ?? a().tabSurface, workspace_id: a().wsId });
  const detail = () => a().tabTitle || a().title || a().name || "";
  return HStack({ spacing: 9 }, [
    Text("✻").font(14).bold().color(C.claude).frame({ width: 16, height: 16 }),
    HStack({ spacing: 0 }, [
      Text(() => a().wsTitle ?? "")
        .font(13)
        .color(() => (a().status === "idle" ? C.muted : C.text))
        .lineLimit(1).truncation("tail"),
      Text(() => (detail() ? " · " + detail() : ""))
        .font(11.5).color(C.dim)
        .lineLimit(1).truncation("tail"),
    ]).layoutPriority(1),
    Spacer({ minLength: 4 }),
    Text(() => age(a().sinceEpoch ?? a().lastActivityAt)).font(11).color(C.dim).layoutPriority(2),
    statusGlyph(() => a().status),
  ])
    .paddingHorizontal(8)
    .frame({ maxWidth: "infinity", height: 30 })
    .cornerRadius(8)
    .hoverBackground(C.hover)
    .onTap(focus);
}

function childRow(e) {
  const c = () => e().child;
  return HStack({ spacing: 8 }, [
    Rectangle().fill(C.border).frame({ width: 1.5, height: 26 }),
    Circle({ size: 6 }).fill(C.working),
    Text(() => c().label || "Sub-agent").font(12.5).color(C.muted).lineLimit(1).truncation("tail"),
    Spacer({ minLength: 0 }),
  ])
    .marginLeading(24)
    .paddingTrailing(8)
    .frame({ maxWidth: "infinity", height: 26 });
}

// --- root ----------------------------------------------------------------------
sidebar(() =>
  VStack({ spacing: 0 }, [
    sectionHeader("Spaces", [iconButton("plus", 14, () => cmux("workspace.create", {}))]),
    Reorderable(
      { items: spaceEntries, key: (e) => e.id, spacing: 2, onMove: handleMove },
      (e) => {
        const entry = e();
        if (entry.kind === "tab") return tabRow(entry.wsId, entry.tabId);
        const w = () => findWs(entry.wsId);
        return entry.editing ? spaceEditRow(w) : spaceRow(w);
      }
    ).paddingHorizontal(8).paddingBottom(14),

    Spacer({ minLength: 8 }),

    Rectangle().fill(C.border).frame({ maxWidth: "infinity", height: 1 }),
    sectionHeader("Agents", []).paddingTop(8),
    Text(() => (allAgents().length ? "" : "No agents running"))
      .font(11.5).color(C.dim)
      .paddingLeading(16)
      .frame({ maxWidth: "infinity", alignment: "leading" }),
    ForEach({ items: agentEntries, key: (e) => e.id }, (e) => {
      const kind = e().kind;
      if (kind === "group") return agentGroupRow(e);
      if (kind === "child") return childRow(e);
      return agentRow(e);
    }).paddingHorizontal(8).paddingBottom(8),

    Rectangle().fill(C.border).frame({ maxWidth: "infinity", height: 1 }),
    HStack({ spacing: 7 }, [
      Image("desktopcomputer").font(11).color(C.muted),
      Text(() => {
        const n = allAgents().length;
        const need = allAgents().filter((a) => a.status === "needs_input").length;
        const sel = workspaces().find((w) => w.selected);
        const branch = sel && sel.branch ? sel.branch + " · " : "";
        return "This computer · " + branch + n + (n === 1 ? " agent" : " agents") + (need ? " · " + need + " need you" : "");
      }).font(11.8).color(C.muted).lineLimit(1).truncation("tail"),
      Spacer(),
    ])
      .paddingHorizontal(16)
      .frame({ maxWidth: "infinity", height: 28 }),
  ])
    .background(C.chrome)
    // The host scrolls the sidebar, so a Spacer only pins Agents to the bottom
    // when the content is at least as tall as the window's sidebar.
    .frame({ maxWidth: "infinity", minHeight: SIDEBAR_MIN_HEIGHT })
)
