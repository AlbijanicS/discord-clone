// THROWAWAY PROTOTYPE — three close refinements of the existing channel UI.
const icons = {
  chat: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M7 17.5 3.5 20v-5.2A8 8 0 0 1 3 12c0-4.4 4-8 9-8s9 3.6 9 8-4 8-9 8c-1.8 0-3.5-.5-5-1.3Z"/><path d="M8 11h.01M12 11h.01M16 11h.01"/></svg>',
  bell: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9ZM10 21h4"/></svg>',
  plus: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 5v14M5 12h14"/></svg>',
  hash: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m10 3-2 18M16 3l-2 18M4 9h16M3 15h16"/></svg>',
  volume: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M11 5 6 9H3v6h3l5 4V5ZM15 9a4 4 0 0 1 0 6M18 6a8 8 0 0 1 0 12"/></svg>',
  logout: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M10 17l5-5-5-5M15 12H3M15 4h4a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2h-4"/></svg>',
  left: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m15 18-6-6 6-6"/></svg>',
  right: '<svg class="icon" viewBox="0 0 24 24" aria-hidden="true"><path d="m9 18 6-6-6-6"/></svg>'
};

const variant = document.body.dataset.variant;
const variants = {
  a: { title: "A — Balanced", note: "Inter · measured 8px rhythm · familiar density", prev: "c", next: "a-graphite" },
  "a-graphite": { title: "A — Modern Graphite", note: "Balanced spacing · neutral gray surfaces · flatter geometry · no violet", prev: "a", next: "a-mission" },
  "a-mission": { title: "A — Mission Dusk", note: "Warm stone gray · cobalt blue · adobe orange · plaster and coral details", prev: "a-graphite", next: "a-light" },
  "a-light": { title: "A — Balanced Light", note: "The same Inter typography and spacing, translated to a warm white theme", prev: "a-mission", next: "b" },
  b: { title: "B — Comfortable", note: "DM Sans · softer shapes · more breathing room", prev: "a-light", next: "c" },
  c: { title: "C — Precise", note: "IBM Plex Sans · tighter utility rhythm · widest reading area", prev: "b", next: "a" }
};
const current = variants[variant];

document.querySelector("#prototype-root").innerHTML = `
  <main class="app-shell" aria-label="Discord Clone typography and spacing prototype">
    <aside class="rail" aria-label="Global destinations">
      <button class="rail-button active" aria-label="Direct messages">${icons.chat}</button>
      <button class="rail-button" aria-label="Activity">${icons.bell}</button>
      <div class="rail-divider"></div>
      <button class="rail-button workspace" aria-label="Open New workspace">N</button>
      <div class="rail-spacer"></div>
      <button class="rail-button rail-add" aria-label="Create workspace">${icons.plus}</button>
    </aside>

    <aside class="channels" aria-label="Channels">
      <div class="sidebar-scroll">
        <header class="workspace-heading">
          <h1 class="workspace-name">new</h1>
          <button class="icon-button" aria-label="Workspace actions">•••</button>
        </header>

        <section class="nav-section">
          <div class="section-heading"><p class="section-label">Channels</p><button class="icon-button" aria-label="Create channel">${icons.plus}</button></div>
          <button class="nav-item active">${icons.hash}<span>general</span><span class="more">•••</span></button>
          <button class="nav-item">${icons.hash}<span>design-review</span><span class="unread">3</span></button>
          <button class="nav-item">${icons.hash}<span>backend</span></button>
        </section>

        <section class="nav-section">
          <div class="section-heading"><p class="section-label">Voice channels</p><button class="icon-button" aria-label="Create voice channel">${icons.plus}</button></div>
          <button class="nav-item">${icons.volume}<span>zzz</span><span class="more">•••</span></button>
          <button class="nav-item">${icons.volume}<span>Pairing room</span></button>
        </section>
      </div>

      <footer class="user-panel">
        <span class="avatar">S</span>
        <div class="user-copy"><p class="user-name">stex</p><p class="user-meta">stele123@gmail.com</p></div>
        <button class="icon-button" aria-label="Log out">${icons.logout}</button>
      </footer>
    </aside>

    <section class="conversation" aria-label="Messages in general">
      <header class="conversation-header">
        <h2 class="channel-title"><span>#</span>general</h2>
      </header>

      <div class="messages">
        <div class="message-column">
          <div class="date-divider">Today</div>
          <article class="message">
            <span class="avatar large">S</span>
            <div class="message-copy"><div class="message-meta"><strong class="message-author">stex</strong><time class="message-time">09:42</time></div><p class="message-text">Morning! I tightened the workspace invite flow and pushed the last copy updates.</p></div>
          </article>
          <article class="message compact"><div class="message-copy"><p class="message-text">The happy path feels much clearer now.</p></div></article>
          <article class="message">
            <span class="avatar large">M</span>
            <div class="message-copy"><div class="message-meta"><strong class="message-author">mira</strong><time class="message-time">09:48</time></div><p class="message-text">Nice. I’ll review it after stand-up. Could we also check how the longer channel names behave?</p></div>
          </article>
          <article class="message compact reaction"><div class="message-copy"><p class="message-text">Everything else looked solid on mobile.</p><span class="reaction-chip" aria-label="Thumbs up reaction, two">👍 <b>2</b></span></div></article>
          <article class="message">
            <span class="avatar large">S</span>
            <div class="message-copy"><div class="message-meta"><strong class="message-author">stex</strong><time class="message-time">10:03</time></div><p class="message-text">Absolutely — I’ll add a few realistic names and verify truncation at the narrow breakpoint.</p></div>
          </article>
        </div>
      </div>

      <div class="composer-wrap">
        <div class="composer">
          <textarea aria-label="Message general" placeholder="Message #general"></textarea>
        </div>
      </div>
    </section>

    <aside class="members" aria-label="Workspace members">
      <header class="members-header"><p class="section-label">Members — 4</p></header>
      <div class="members-scroll">
        <p class="role-label">Owner — 1</p>
        <div class="member-row"><span class="avatar small">S</span><div class="user-copy"><p class="user-name">stex</p><p class="member-status"><span class="status-dot"></span>Online</p></div></div>
        <p class="role-label" style="margin-top: 24px">Members — 3</p>
        <div class="member-row"><span class="avatar small">M</span><div class="user-copy"><p class="user-name">mira</p><p class="member-status"><span class="status-dot"></span>Online</p></div></div>
        <div class="member-row"><span class="avatar small">A</span><div class="user-copy"><p class="user-name">alex</p><p class="user-meta">Away</p></div></div>
        <div class="member-row"><span class="avatar small">N</span><div class="user-copy"><p class="user-name">nina</p><p class="user-meta">Offline</p></div></div>
      </div>
    </aside>
  </main>

  <aside class="variant-note"><strong>${current.title}</strong>${current.note}</aside>
  <nav class="prototype-switcher" aria-label="Prototype variants">
    <a href="variant-${current.prev}.html" aria-label="Previous variant">${icons.left}</a>
    <span class="variant-name">${current.title}</span>
    <a href="variant-${current.next}.html" aria-label="Next variant">${icons.right}</a>
  </nav>`;

document.addEventListener("keydown", (event) => {
  const tag = document.activeElement?.tagName;
  if (["INPUT", "TEXTAREA"].includes(tag) || document.activeElement?.isContentEditable) return;
  if (event.key === "ArrowLeft") window.location.href = `variant-${current.prev}.html`;
  if (event.key === "ArrowRight") window.location.href = `variant-${current.next}.html`;
});
