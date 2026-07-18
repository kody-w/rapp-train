# The RAPP Train PLAYBOOK — choose your own adventure

Every scenario on the RAPP release train, written for humans *and* AI agents.
If you are an AI: read this file top to bottom once, then jump by scenario.
Machine entry point: [`llms.txt`](https://kody-w.github.io/rapp-train/llms.txt).
Deep operator detail lives in the hub
[RUNBOOK](https://github.com/kody-w/rapp-canary/blob/main/.ring/RUNBOOK.md);
this playbook routes you to the right motion.

**The map** (train topology is law — [`train.json`](https://github.com/kody-w/rapp-canary/blob/main/.ring/train.json)):

```
Canary → Nightly → Alpha → Beta ──(human gate)──► Grail ──tagged releases──► aibast (PR wall)
                             │                                          └──► RAPP main (lts pin)
                             ├──shape siding──► RAPP `shape/next` branch   (distro shape, in the wild)
                             └──shape siding──► kody-w/rapp-shape-aibast   (aibast shape, staging twin)
```

**Three iron rules before anything else:**
1. **Nothing pushes to the Grail** (`kody-w/rapp-installer`) except a human's
   conscious release act (Scenario 9). Tooling is structurally incapable of it.
2. **Everything enters at Canary.** Outer rings only ever receive promotions.
3. **Ring repos' `raw.githubusercontent.com` installers carry GRAIL identity by
   design** — they install the wrong repo. The ONLY correct ring one-liners are
   the GitHub Pages copies (`kody-w.github.io/rapp-<ring>/...`).

---

## What are you trying to do?

| You want to… | Go to |
|---|---|
| Try a pre-release build safely on this machine | **Scenario 1** |
| Make this machine run a ring for real | **Scenario 2** |
| Ship a fix or feature into the train | **Scenario 3** |
| Your change touches grail URLs and CI says "rewrite count drift" | **Scenario 4** |
| A hotfix landed directly on the Grail | **Scenario 5** |
| Move a soaked build outward (promote) | **Scenario 6** |
| Certify the whole train (qualification) | **Scenario 7** |
| Run/refresh the live soak | **Scenario 8** |
| Cut a Grail release (human only) | **Scenario 9** |
| Production broke after a release | **Scenario 10** |
| Test a downstream SHAPE (RAPP distro / aibast) without touching production | **Scenario 11** |
| Sync the Grail into Microsoft's aibast for real | **Scenario 12** |
| You are an AI agent orienting yourself | **Scenario 13** |

---

## Scenario 1 — Test-fly a ring or a feature (sandboxed, anyone, any machine)

No signup, no VPN, nothing touched. Flights live in `~/.rapp-flight/`, port 7075.

```bash
curl -fsSL https://kody-w.github.io/rapp-train/flight.sh | bash -s -- canary      # or nightly|alpha|beta
curl -fsSL https://kody-w.github.io/rapp-train/flight.sh | bash -s -- canary <branch>   # one feature
```

Done when: `✅ ... is flying: http://localhost:7075`. Stop/wipe commands are printed.
If it prints `render refused this flight` — that's a real finding (Scenario 4 upstream), report it.

## Scenario 2 — Join a ring (this machine's real install)

Pick a ring on the deck ([kody-w.github.io/rapp-train](https://kody-w.github.io/rapp-train/)) and run its **Pages** one-liner:

```bash
curl -fsSL https://kody-w.github.io/rapp-<ring>/install.sh | bash     # macOS/Linux
irm https://kody-w.github.io/rapp-<ring>/install.ps1 | iex            # Windows
```

Switching rings: wipe `~/.brainstem` first, then join the other ring.
Back to stable: wipe, then install from [kody-w.github.io/rapp-installer](https://kody-w.github.io/rapp-installer/).

## Scenario 3 — Ship a fix or feature (the canonical ride)

All work starts on a canary branch; the train carries it outward. Worked example
with real evidence: the six-steps tutorial fix rode branch `fix/tutorial-step-count`
through preflight run 29658467909 → promotion → qualification → grail gate.

```bash
cd ~/Documents/GitHub/rapp-canary
git checkout -b fix/thing origin/main
# edit … then:
git push -u origin fix/thing      # preflight: static + 7-VM e2e matrix, every push
gh run watch                      # ALL legs green or it does not merge
git checkout main && git pull && git merge --no-ff fix/thing && git push
```

Then: promote when soaked (Scenario 6) → qualify (Scenario 7) → human gate (Scenario 9).
Done when: your change is on canary main with a green run URL you can cite.

## Scenario 4 — "rewrite count drift" (you touched grail-URL surfaces)

The render oracle counts every `kody-w/rapp-installer`, `kody-w.github.io/rapp-installer`,
and `kody-w/rapp-support` occurrence in the payload. Add or remove one and every
render (CI, flights, Pages publish) refuses until the books balance. Deliberate.

Fix: recount and bump `expected_count` in **all four** rings' `.ring/ring.json`
(payload is identical across rings, so one number set fits all), same cycle as
your change. The RUNBOOK documents the recount ritual.

## Scenario 5 — A hotfix landed directly on the Grail

Re-seed Canary IMMEDIATELY or the next promotion silently reverts the hotfix
(the oldest staged-train failure there is):

```bash
cd ~/Documents/GitHub/rapp-canary && git checkout main
git fetch https://github.com/kody-w/rapp-installer.git main
git merge FETCH_HEAD -m "reseed: grail hotfix" && git push origin main
```

## Scenario 6 — Promote (one edge at a time, operator-run)

`promote_ring.py` moves shared payload blobs only; each ring's `.ring/` overlay
survives. Every target-main push triggers that ring's own preflight — a broken
promotion is a red X in minutes. Exact commands: RUNBOOK §2.
Done when: all promoted ring preflights are green.

## Scenario 7 — Qualify the whole train

Dispatch `test-pre-grail-rings.yml` on the hub with the four EXACT current main
SHAs (it refuses anything else). Green = tooling tests, per-ring source oracles,
rendered smoke, and a deterministic attestation chain artifact. Then archive the
evidence into git before CI expires it:

```bash
.ring/tools/archive_attestations.sh <run-id>    # commit on canary main
```

## Scenario 8 — Soak (the honest crash signal)

```bash
.ring/tools/soak.sh start|status|refresh    # canary bytes, real Copilot auth, :7073
```

Soak = days of real usage on ring bytes. Dashboards prove tests pass; soak
proves the thing lives.

## Scenario 9 — Release to the Grail (HUMAN ONLY)

The gate verifies the attestation chain against Beta's live tip, re-derives the
payload digest from a fresh clone, and stages the EXACT qualified bytes onto a
grail release branch. It never commits, never pushes:

```bash
python3 .ring/tools/grail_gate.py verify --run-id <qualification-run> --export-to <fresh-grail-clone-on-a-release-branch>
```

Then: version bump, mirror sync, release branch push (full grail preflight),
human merge + immutable `brainstem-vX.Y.Z` tag with the run URL embedded —
RUNBOOK §5 has every command. Post-release: smoke, bump RAPP's `KERNEL_PIN`
(or record a skip), rehearse the downgrade lever once.

**First ring-driven release only**: rehearse release-day mechanics first on an
EPHEMERAL twin — clone grail main into a scratch repo, run the whole §5 ritual
against it (merge, tag, Pages), verify, then delete the repo. Rehearses the
only motion nothing else covers (tags + release merge). Do not keep a standing
grail twin: Beta already plays that role for payload, and every standing
surface is another thing to keep unbroken.

## Scenario 10 — Production broke after a release

Two independent levers (grail `RELEASING.md` §8):
1. `git revert -m 1 <merge>` on grail main (force-pushes are blocked; revert
   needs none) — fixes all future installs.
2. Any broken machine pins back NOW:
   `BRAINSTEM_VERSION=<prev> bash -c "$(curl -fsSL https://kody-w.github.io/rapp-installer/install.sh)"`.
Tags are immutable rollback points forever.

## Scenario 11 — Test a downstream SHAPE (isolated from ALL production)

Rings test the payload; **sidings test the deliveries** into differently-shaped
downstreams. Neither grail, nor microsoft/aibast, nor RAPP `main` is touched.

**RAPP distro shape** — branch `shape/next` on kody-w/RAPP mirrors the current
QUALIFIED Beta per the Mirror Spec (three frozen files byte-identical,
`KERNEL_PIN.json` stamped `channel: next` with commit + digests). RAPP `main`
stays lts on the tagged grail pin. Refresh after Beta moves:
copy the three files from beta, restamp the pin, push the branch.

**aibast shape** — staging twin `kody-w/rapp-shape-aibast` (seeded from
microsoft main, `upstream` remote intact). Rehearse the REAL sync:

```bash
RAPP_SYNC_ALLOW_NONGRAIL=1 RAPP_SYNC_ALLOW_NO_PATCHES=1 \
  bash <beta-checkout>/tools/sync-to-aibast.sh <staging-checkout>
# then run the target's own tests; commit findings or green result on a shape/ branch
```

Findings here are the payoff: the maiden rehearsal caught two real breaks
(a rewrite-invisible test assertion and an orphaned soul-manifest hash) that
would otherwise have surfaced mid-production-sync. Fix findings UPSTREAM in
canary (Scenario 3) — never patch them only in the siding.

**Why this is the hero scenario of the whole train**: a distro's shape —
its README, its disclaimers, its compliance files, its identity — belongs
to its distributor, and honoring that is the promise that makes distros
possible at all. AIBAST's shape is Microsoft's just as RAPP's is its
maintainer's. Every delivery from the kernel arrives as a good guest:
it brings the kernel's best and changes nothing the host owns. The
manifest-driven sync, the report-never-touch rule, and the yard rehearsals
exist to keep that promise on every single crossing — which is why a red
shape-guard here outranks every deadline. Keep this promise and every
distributor can build on the kernel with total confidence; that confidence
is the ecosystem.

## Scenario 12 — Sync the Grail into Microsoft's aibast (production)

Only from a TAGGED grail release, only after Scenario 11 is green, per grail
`RELEASING.md` §9: `tools/sync-to-aibast.sh` from the tag checkout into the
real aibast fork checkout, run its tests, push `sync/brainstem-vX.Y.Z` to the
kody-w fork, open the PR **manually in the browser** (SAML wall — tooling
cannot and must not). The guards will hard-refuse a non-grail source without
the rehearsal override — that is correct behavior.

## Scenario 13 — You are an AI agent orienting yourself

Read order: this file → the hub
[RUNBOOK](https://raw.githubusercontent.com/kody-w/rapp-canary/main/.ring/RUNBOOK.md)
→ [`train.json`](https://raw.githubusercontent.com/kody-w/rapp-canary/main/.ring/train.json)
→ grail [`RELEASING.md`](https://raw.githubusercontent.com/kody-w/rapp-installer/main/RELEASING.md).

Non-negotiables encoded for you: never push to `kody-w/rapp-installer` or
`microsoft/aibast-agents-library`; never trigger anything from a `pull_request`
context onto real hardware; never hand a user a ring's raw-URL installer; all
payload changes enter at canary; if an oracle (rewrite counts, attestation
chain, preflight) goes red, the red is the system working — diagnose upstream,
never bypass. Evidence beats claims: cite run URLs and SHAs for every "done."

*This playbook is itself versioned in [kody-w/rapp-train](https://github.com/kody-w/rapp-train) — improve it via PR like anything else.*
