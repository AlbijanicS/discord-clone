# Two-week portfolio delivery plan

This plan deliberately narrows the parent PRD to demo reliability and portfolio readiness. It changes delivery scope and order, not the semantics of the selected fixes. The large PRD is a backlog reference, not a release checklist. These local briefs were produced for direct agent dispatch; no agents have been started and no production actions are authorized by their creation.

## Scope update — 2026-09-11

The user explicitly removed email-change delivery from the app. Item 06 is
superseded: its implementation and the earlier self-service email-change
workflow are removed. Production has no Resend/key/sender requirement.
Accounts are provisioned by the operator over SSH. Step 07 no longer includes
mail provisioning or email-change acceptance; the other hosted checks remain.
The dated progress entries below are historical, including their mail setup
requirements. Step 05 username/password and session hardening remains active.

Removal revision: `fc8a643`. Precommit passed (99 JavaScript and 1,085 Elixir
tests); coverage passed at 86.79%. Both code reviews reported zero findings.

## Local progress — 2026-09-09

05–06 are implemented and reviewed; see
[their handoff](../../docs/code-health-hardening-05-06.md).
Final precommit passed (99 JavaScript and 1,100 Elixir tests), and coverage
passed at 86.89% against 85%. Earlier runs exposed two intermittent Voice
lifecycle test failures; both passed focused reruns and the final full gates.
The handoff records those findings without claiming a Voice fix.

The 05–06 commit `1d955a5` is scoped to this batch. Existing 01–04 changes remain
uncommitted and are required for integrated release acceptance. Production now
requires provisioned `RESEND_API_KEY` and `MAIL_FROM_ADDRESS` before startup;
provider provisioning, remote CI, and hosted inbox/audio verification remain
unobserved. Next is operator-assisted 07, followed by verified presentation
and integrated release acceptance (08/12). No optional item is selected.

## Local progress — 2026-09-08

01–02 remain implemented locally as described in
[their handoff](../../docs/code-health-hardening-01-02.md).
03–04 are now implemented and verified locally; see
[their handoff](../../docs/code-health-hardening-03-04.md).
The work remains uncommitted. Final checks passed: precommit (99 JavaScript and
1,089 Elixir tests), coverage (86.70% against 85%), and diff whitespace checks.
Remote CI and hosted acceptance remain unobserved.

Historical next steps at that point were 05 and 06; both are now implemented
as recorded above.

## Dispatch order

AFK means implementation can proceed without a product decision; it does not authorize automatic merge or deployment. HITL means completion requires real human input or observation. Optional issues are not dependencies unless explicitly selected. A ready status means the brief is specified; check its blockers before starting.

| Brief | Type | Priority | Blocked by |
| --- | --- | --- | --- |
| [01 — Automate the existing quality gates](issues/01-ci-baseline.md) | AFK | Core | None |
| [02 — Preserve Voice controls across connection transitions](issues/02-voice-control-state.md) | AFK | Core | 01 |
| [03 — Prevent missed updates during Channel and Workspace initialization](issues/03-liveview-mount-consistency.md) | AFK | Core | 01 |
| [04 — Handle malformed Workspace and Channel actions safely](issues/04-workspace-event-inputs.md) | AFK | Core | 03 |
| [05 — Handle stale authentication and malformed settings events](issues/05-settings-session-errors.md) | AFK | Core | 01 |
| [06 — Email changes removed at user request](issues/06-honest-email-delivery.md) | Superseded | Removed | — |
| [07 — Verify the hosted two-user demonstration](issues/07-hosted-demo-acceptance.md) | HITL | Core | 02, 03, 04, 05 |
| [08 — Make the project understandable and easy to evaluate](issues/08-portfolio-presentation.md) | HITL | Core | None for draft; 07 for verified final claims |
| [09 — Add one deterministic two-user browser Voice smoke test](issues/09-browser-voice-smoke.md) | AFK | Optional | 01, 02 |
| [10 — Stage complete releases and document tested rollback](issues/10-safe-release-switch.md) | AFK | Optional | 01; finish before final 07 run |
| [11 — Move packet diagnostics off Voice media owners](issues/11-bounded-voice-diagnostics.md) | AFK | Optional | 02; finish before final 07 run |
| [12 — Verify the integrated portfolio release and freeze scope](issues/12-release-handoff.md) | HITL | Core | 01–08; any explicitly selected optional issue |

## Recommended batches

1. Start 01. In parallel, 08 can draft presentation in a separate checkout; defer its final claims and recording until hosted evidence exists.
2. After 01 lands, run 02, 03, and 05 in separate worktrees if desired. They primarily own browser Voice, Channel/Workspace initialization, and account settings respectively.
3. Run 04 on top of 03. Item 06 has been removed. These dependencies also prevent conflicting edits to shared LiveViews. Integrate finished branches serially and rerun affected tests after integration.
4. Execute 07 on the integrated core changes; finalize 08 using those results. Arrange provider setup and a second-network participant early, while implementation proceeds.
5. Run 12 on the final revision. No optional item is required to start applying to jobs.

09–11 are alternatives for spare time, not an extra mandatory phase. Prefer 09 if browser setup is straightforward, 10 if releases are being changed frequently, or 11 if representative Voice measurements show a problem. Do not start all three to fill available agent slots. If 10 or 11 is selected, finish it before the final hosted run in 07. 09 and 10 may edit CI/operator docs shared with 01/08; coordinate those files explicitly.

## Time budget and stop rule

Reserve approximately days 1–5 for core engineering, 6–7 for hosted QA, 8–9 for presentation and explanation practice, and day 10 for integration buffer and final verification. These are budget boundaries, not estimates guaranteeing completion. Presentation drafting and human setup should begin early.

If a core issue grows beyond the available budget, report the concrete remaining behavior and recommend an explicit scope decision. Do not partially implement a consistency guarantee or silently skip its tests. Cut optional work first. The human may choose to disable an unavailable email-change capability instead of provisioning Resend, but that is an explicit alternative to issue 06, not an agent's implicit fallback. It requires honest unavailable UI and server enforcement, with tests, rather than a success message or silent local adapter.

## Shared implementation contract

- Read repository instructions and current code before editing. Preserve unrelated user changes. Use a separate worktree per concurrent agent and base dependent work on integrated prerequisite commits.
- Implement only the supplied issue. Do not execute the PRD's fixed full-program sequence. Do not delegate, merge, deploy, publish, provision accounts, or message other people unless separately authorized.
- Preserve authentication boundaries, current_scope, exact unread semantics, membership policy, Voice ownership, five-session capacity, and current public context contracts. No new routes are expected. Any necessary route change must explain its existing scope, pipeline, and live_session as required by AGENTS.md.
- Accepted Voice ADRs include historical phase-specific names; inspect current implementations and CONTEXT.md instead of restoring obsolete names. Surface substantive conflicts rather than rewriting ADRs opportunistically.
- For behavioral fixes, begin with a focused regression at an observable seam. Use deterministic synchronization, stable DOM IDs, supervised processes, and existing test seams. Do not add tests that only mirror implementation.
- Before completion of code/config changes, read task help, run mix precommit and the configured coverage command (currently mix test --cover), and resolve introduced failures. Record pre-existing/environment failures precisely. Do not lower thresholds. Pure documentation work requires link/content review rather than invented behavior tests.
- Do not introduce new credentials into files/logs or fetch real provider credentials for automated tests. Prepare operator steps without pretending external configuration exists.
- Handoff must include changed behavior, acceptance results, exact verification commands, revision if committed, remaining blockers, and out-of-scope discoveries. Keep each slice independently reviewable. Do not claim a deployment, real microphone test, or remote CI run from local tests alone.

## Prompt to send with each issue

> Read AGENTS.md, CONTEXT.md, .scratch/code-health-hardening/PRD.md, .scratch/code-health-hardening/PORTFOLIO_PLAN.md, and the attached issue. Implement only that issue on top of its completed prerequisites. The portfolio plan deliberately narrows the parent PRD; do not implement deferred or optional work unless this is its explicitly selected brief. Follow the issue's acceptance criteria and shared verification contract. Make the change independently reviewable and report verification plus any remaining human actions. Do not deploy or merge without authorization.

For HITL issues, the agent should prepare all independent artifacts and checks first, then request only the specific missing input or observation. Do not mark the issue complete while those acceptance items remain blocked.

## Deferred after the portfolio deadline

- Workspace participation serialization and the complete global lock-order audit: parent stories 1–14. This is a real authorization/concurrency gap. Keep the demonstration controlled; do not describe it as resolved or suitable for untrusted public use. A sender-only lock is not the full solution.
- Database-authoritative Timeout Reconciler: stories 15–22. Deadline checks already stop expired restrictions from authorizing denial, while restart recovery, durable audit, and UI reconciliation remain follow-ups.
- Set-based exact unread fanout: stories 44–49. Measure relevant recipient sizes before choosing this optimization.
- Chat/Workspaces context deepening: stories 50–56.
- Shared Conversation Timeline extraction: stories 57–60.
- Full browser recovery/takeover matrix beyond optional 09, and unselected optional diagnostics/deployment work.

Do not split these into ready implementation tasks during a portfolio slice. They need their own later planning and regression effort.
