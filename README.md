# 🚂 rapp-train — the RAPP release-train flight deck

**https://kody-w.github.io/rapp-train/** — every ring of the RAPP Brainstem
release train, joinable or sandbox-testable from any machine with one pasted
line. Feature branches on [rapp-canary](https://github.com/kody-w/rapp-canary)
appear automatically as individually flyable "flights".

- 📖 **[PLAYBOOK.md](https://kody-w.github.io/rapp-train/PLAYBOOK.md)** — every scenario, choose-your-own-adventure, for humans and AIs
- 🤖 **[llms.txt](https://kody-w.github.io/rapp-train/llms.txt)** — machine entry point
- 🛠 Operations: the hub **[RUNBOOK](https://github.com/kody-w/rapp-canary/blob/main/.ring/RUNBOOK.md)**

## Architecture

```mermaid
flowchart TB
    subgraph DEV["🔧 DEVELOP — everything enters at Canary"]
        BR["feature branch<br/>fix/whatever"] -->|"push → preflight<br/>static + 7-VM e2e"| CAN
    end

    subgraph TRAIN["🚂 THE PRE-GRAIL TRAIN (shared payload, grail identity)"]
        CAN["🐤 rapp-canary<br/><i>hub: .ring tools + workflows</i>"]
        NIG["🌙 rapp-nightly"]
        ALP["🅰️ rapp-alpha"]
        BET["🅱️ rapp-beta"]
        CAN -->|"promote_ring.py<br/>shared blobs only<br/>ring CI re-verifies"| NIG
        NIG -->|promote| ALP
        ALP -->|promote| BET
    end

    subgraph QUAL["✅ QUALIFICATION (read-only credentials)"]
        Q["test-pre-grail-rings<br/>4 exact main SHAs →<br/>oracles + rendered smoke +<br/>deterministic attestation chain"]
    end
    CAN -.-> Q
    NIG -.-> Q
    ALP -.-> Q
    BET -.-> Q
    Q -->|"evidence archived to git<br/>.ring/attestations/"| GATE

    GATE{{"🚧 grail_gate.py<br/>verifies chain + beta tip +<br/>fresh-clone digest —<br/><b>HUMAN MERGE ONLY</b>"}}
    GATE -->|"export exact qualified bytes<br/>→ release branch → full preflight<br/>→ Kody merges + immutable tag"| GRAIL

    GRAIL["🏆 kody-w/rapp-installer<br/><b>THE GRAIL — production</b><br/>main = what users install<br/>protected: no force-push,<br/>8 required checks"]

    subgraph DOWN["📦 DOWNSTREAMS (tagged releases only)"]
        AIB["microsoft/aibast-agents-library<br/>manifest-driven sync, PR wall"]
        RAPPM["kody-w/RAPP main<br/>lts distro, KERNEL_PIN on a tag"]
    end
    GRAIL -->|"brainstem-vX.Y.Z tags"| AIB
    GRAIL -->|"pin bump ritual"| RAPPM

    subgraph YARD["🏗️ SHAPE YARD — sidings off Beta (deliveries, not payload)"]
        SNEXT["kody-w/RAPP @ shape/next<br/>Mirror-Spec: 3 frozen files =<br/>qualified Beta, pin channel:next"]
        SAIB["kody-w/rapp-shape-aibast<br/>staging twin, rehearses the<br/>REAL sync-to-aibast.sh"]
    end
    BET -->|"deliver + rehearse"| SNEXT
    BET -->|"deliver + rehearse"| SAIB
    SAIB -.->|"findings fixed UPSTREAM<br/>in canary, never in the siding"| CAN

    subgraph PUB["🌍 PUBLIC SURFACES (per-ring Pages = RENDERED ring identity, drift-oracle gated)"]
        DECK["kody-w.github.io/rapp-train<br/>flight deck + PLAYBOOK + llms.txt"]
        JOIN["join: curl …/rapp-&lt;ring&gt;/install.sh | bash"]
        FLY["fly: …/rapp-train/flight.sh — sandboxed<br/>any ring or any canary branch, :7075"]
        SOAK["soak: canary bytes, real auth, :7073<br/>+ oneliner-test.yml on clean VMs"]
    end
    DECK --- JOIN
    DECK --- FLY
    DECK --- SOAK

    style GRAIL fill:#1a7f37,color:#fff
    style GATE fill:#b91c1c,color:#fff
    style CAN fill:#3b82f6,color:#fff
```

**The two laws the arrows encode:** every oracle going red (preflight, rewrite
drift, attestation chain, gate) is the system *working* — diagnose upstream,
never bypass; and nothing pushes to the Grail except a human's conscious
release act — the tooling is structurally incapable of it.

This repo is only the deck: the actual install endpoints are each ring repo's
own GitHub Pages (rendered ring identity — never the raw-URL copies, which
carry grail identity by design and install the wrong repo).
