<div>
<style>
/* ── Flexoki tokens via light-dark() — single definition, no duplication ── */
.aidc {
  color-scheme: light dark;
  --f-bg:         light-dark(#FFFCF0, #1C1B1A);
  --f-bg-alt:     light-dark(#F2F0E5, #282726);
  --f-border:     light-dark(#E6E4D9, #343331);
  --f-head-bg:    light-dark(#282726, #100F0F);
  --f-head-fg:    #FFFCF0;
  --f-head-muted: light-dark(#9F9D96, #6F6E69);
  --f-tx:         light-dark(#100F0F, #FFFCF0);
  --f-tx-2:       light-dark(#6F6E69, #9F9D96);
  --f-tx-3:       light-dark(#9F9D96, #6F6E69);
  --f-bar-empty:  light-dark(#CECDC3, #343331);
  --f-bar-human:  light-dark(#D0A215, #AD8301);
  --f-bar-ai:     light-dark(#8B7EC8, #5E409D);
  --f-tag-bg:     light-dark(#F0EAEC, #261C39);
  --f-tag-fg:     light-dark(#5E409D, #8B7EC8);
  --f-link:       light-dark(#205EA6, #4385BE);
  /* Structure */
  font-family: system-ui, -apple-system, sans-serif;
  max-width: 560px;
  border: 1px solid var(--f-border);
  border-radius: 8px;
  overflow: hidden;
  box-shadow: 0 2px 8px rgba(0,0,0,.08);
  background: var(--f-bg);
  color: var(--f-tx);
  font-size: 14px;
}
.aidc[data-theme="light"] { color-scheme: light; }
.aidc[data-theme="dark"]  { color-scheme: dark; }
/* ── Component styles ──────────────────────────────────────────────────── */
.aidc-head { background: var(--f-head-bg); color: var(--f-head-fg); padding: 12px 16px; display: flex; justify-content: space-between; align-items: baseline; }
.aidc-head-title { font-size: 16px; font-weight: 600; }
.aidc-head-project { font-size: 13px; color: var(--f-head-muted); }
.aidc-section { padding: 12px 16px; border-bottom: 1px solid var(--f-border); background: var(--f-bg); }
.aidc-section:last-of-type { border-bottom: none; }
.aidc-lbl { font-size: 11px; font-weight: 600; letter-spacing: .06em; text-transform: uppercase; color: var(--f-tx-2); margin-bottom: 8px; }
.aidc-tools { list-style: none; margin: 0; padding: 0; }
.aidc-tools li { padding: 2px 0; font-size: 13px; }
.aidc-tag { display: inline-block; background: var(--f-tag-bg); color: var(--f-tag-fg); font-family: ui-monospace, monospace; font-size: 11px; padding: 1px 5px; border-radius: 3px; }
.aidc-legend { display: flex; gap: 12px; font-size: 12px; color: var(--f-tx-2); margin-bottom: 10px; }
.aidc-dot { display: inline-block; width: 8px; height: 8px; border-radius: 2px; margin-right: 3px; vertical-align: middle; }
.aidc-phase { margin-bottom: 10px; }
.aidc-phase:last-child { margin-bottom: 0; }
.aidc-phase-name { font-size: 13px; margin-bottom: 4px; color: var(--f-tx); }
.aidc-bar-row { display: flex; align-items: center; gap: 8px; }
.aidc-bar-track { flex: 1; height: 12px; border-radius: 3px; overflow: hidden; background: var(--f-bar-empty); display: flex; }
.aidc-bar-h { background: var(--f-bar-human); height: 100%; }
.aidc-bar-a { background: var(--f-bar-ai); height: 100%; }
.aidc-bar-pct { font-size: 12px; color: var(--f-tx-2); white-space: nowrap; min-width: 120px; text-align: right; }
.aidc-na { font-size: 12px; color: var(--f-tx-3); font-style: italic; }
.aidc-field-name { font-weight: 600; font-size: 13px; color: var(--f-tx); }
.aidc-field-val { font-size: 13px; color: var(--f-tx-2); margin-top: 2px; }
.aidc-text { font-size: 13px; color: var(--f-tx-2); line-height: 1.5; margin: 0; }
.aidc-intro { font-size: 13px; color: var(--f-tx-2); margin: 0 0 8px; }
.aidc-intro a { color: var(--f-link); }
.aidc-foot { background: var(--f-bg-alt); padding: 8px 16px; font-size: 12px; color: var(--f-tx-3); display: flex; justify-content: space-between; align-items: center; border-top: 1px solid var(--f-border); }
.aidc-foot a { color: var(--f-tx-3); text-decoration: none; }
.aidc-foot a:hover { text-decoration: underline; }
</style>
<div class="aidc">
  <div class="aidc-head">
    <span class="aidc-head-title">&#x1F916; AI Disclaimer</span>
    <span class="aidc-head-project">LocalMusic</span>
  </div>
  <div class="aidc-section">
    <p class="aidc-intro">This project uses AI-assisted development tools. See the <a href="https://j23n.com/public/posts/2026/my-ai-policy">AI usage policy</a> for details.</p>
    <ul class="aidc-tools">
<li>Claude Code (Anthropic) <span class="aidc-tag">claude-opus-4.7</span> &middot; Agentic</li>
</ul>
  </div>
  <div class="aidc-section">
    <div class="aidc-lbl">Contribution Profile</div>
    <div class="aidc-legend"><span><span class="aidc-dot" style="background:var(--f-bar-human)"></span>Human</span><span><span class="aidc-dot" style="background:var(--f-bar-ai)"></span>AI</span></div>
    <div class="aidc-phase"><div class="aidc-phase-name">Requirements &amp; Scope</div><div class="aidc-bar-row"><div class="aidc-bar-track"><div class="aidc-bar-h" style="width:85%"></div><div class="aidc-bar-a" style="width:15%"></div></div><span class="aidc-bar-pct">85% human &middot; 15% AI</span></div></div>
<div class="aidc-phase"><div class="aidc-phase-name">Architecture &amp; Design</div><div class="aidc-bar-row"><div class="aidc-bar-track"><div class="aidc-bar-h" style="width:50%"></div><div class="aidc-bar-a" style="width:50%"></div></div><span class="aidc-bar-pct">50% human &middot; 50% AI</span></div></div>
<div class="aidc-phase"><div class="aidc-phase-name">Implementation</div><div class="aidc-bar-row"><div class="aidc-bar-track"><div class="aidc-bar-h" style="width:5%"></div><div class="aidc-bar-a" style="width:95%"></div></div><span class="aidc-bar-pct">5% human &middot; 95% AI</span></div></div>
<div class="aidc-phase"><div class="aidc-phase-name">Testing</div><div class="aidc-bar-row"><div class="aidc-bar-track"><div class="aidc-bar-h" style="width:5%"></div><div class="aidc-bar-a" style="width:95%"></div></div><span class="aidc-bar-pct">5% human &middot; 95% AI</span></div></div>
<div class="aidc-phase"><div class="aidc-phase-name">Documentation</div><div class="aidc-bar-row"><div class="aidc-bar-track"><div class="aidc-bar-h" style="width:50%"></div><div class="aidc-bar-a" style="width:50%"></div></div><span class="aidc-bar-pct">50% human &middot; 50% AI</span></div></div>
  </div>
  <div class="aidc-section">
    <div class="aidc-lbl">Oversight</div>
    <div class="aidc-field-name">Supervised</div>
    <div class="aidc-field-val">AI works semi-autonomously; human reviews key checkpoints.</div>
  </div>
  <div class="aidc-section">
    <div class="aidc-lbl">Process</div>
    <p class="aidc-text">AI agent operated autonomously across multi-step tasks. Human reviewed diffs, resolved conflicts, and approved merges.</p>
  </div>
  <div class="aidc-section">
    <div class="aidc-lbl">Accountability</div>
    <p class="aidc-text">The human author(s) are solely responsible for the content, accuracy, and fitness-for-purpose of this project.</p>
  </div>
  <div class="aidc-foot"><span>Last updated: 2026-05-08</span><span>Generated with <a href="https://github.com/j23n/ai-disclaimer">ai-disclaimer</a></span></div>
</div>
</div>
