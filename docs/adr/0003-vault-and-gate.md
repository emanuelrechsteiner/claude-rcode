# 0003 — Vault and gate: pseudonymized by design

- Status: accepted
- Date: 2026-09-25
- Translated: 2026-09-26 (English; decision unchanged)

## Context

The trigger was two verbatim user instructions (2026-09-25): "Is there a way
to make this pseudonymized by design? So that NO real name or real path
etc. ever ends up in the framework? On the developer's own machine, during
optimization, that's fine — but it really has no business being in the
framework itself." — and, on the mechanism: "In principle we'd need to
solve this the way a database handles it, with a vault for P2 data. We need
a layer that can read that back hashed. The real names and paths are, like
in a database, the P2 data — those may only be written into the vault, they
need to be hashed somehow."

Before this rework, spread across the whole codebase, was a mix of real
machine paths, account and project names, and personal identifiers in
versioned files — prose, comments, test fixtures, the improvement ledger.
An inventory before Wave 3 counted 326 hits across 64 files. The writer
that keeps extending these files is a language model: a convention alone
("please, no real names") has proven, in practice, not reliable enough to
carry an invariant (`rules/slop-prevention.md`).

**Threat model:** not "nobody may know the names" — they sit unchanged in
the projects on the very same disk anyway — but rather: the names never
leave the machine **through the framework**: not via a commit into this
repo, not via its publication as a public clone, not via an improvement
submitted from here.

## Decision

**Invariant:** No versioned byte of this repo contains a real project,
company, or account name, a machine-specific path (user folder, volume
name, project root), a personal identifier (email, session, trigger, Notion
ID), or an identifying phrase. These values live exclusively in the local
**vault** (`~/.claude/vault/`, gitignored, pure runtime data in the live
install). The framework refers to them via **tokens**.

**Three layers, because the writer is unreliable:**

| Layer | Job | Where |
|---|---|---|
| Vault | Stores the real values and doubles as the block-list | `~/.claude/vault/` (`map.tsv` + `secret`) |
| Gate | Refuses any write of a real value into a versioned file | PreToolUse hook, git `pre-commit`, public CI |
| Tokenizer | Substitutes at capture time — in scripts that themselves write into versioned files | `scripts/vault/vault.sh tokenize` |

**Hashing instead of a plaintext placeholder.** A token is an HMAC-SHA256
prefix keyed with a local secret (`hex6 = first 6 hex chars of
HMAC-SHA256(secret, "<kind>:<group>")`). A plain hash would be
dictionary-reversible — project and account names carry little entropy; an
HMAC without the secret does not. On the same machine a token is stable (a
series of measurements across multiple sessions stays legible together);
on a different machine the same plaintext value produces a different
token — the vaults of two developers cannot be linked against each other.

**The vault** lives under `${CLAUDE_VAULT_DIR:-$HOME/.claude/vault}`
(directory `0700`, `secret` `0600`, generated once and never overwritten
afterward). `map.tsv` carries, per line, `kind`, `term` (the real value),
`token`, and `group`: several `term`s sharing the same `group` — short
name, long name, alternate spelling, repo name, path alias — share ONE
token, so the same real-world entity stays recognizable as one entity
after substitution instead of fragmenting into several unconnected tokens.

**One matcher for every consumer** (`rules/testing-quality.md`, "Verify Via
the Same Code Path"): `scripts/vault/lib.sh` is sourced identically by
`vault.sh` (check/tokenize/resolve), `scripts/scrub-check.sh`,
`publish-transforms.d/50-pseudonymize.sh`, `hooks/vault-write-gate.sh`, and
`scripts/git-hooks/pre-commit` — no second, independently written
expression that could drift from the first over time.

**Structural patterns need no vault** and therefore also fire in the
public CI of a clone that never has a vault at all: user/volume paths
(`/Users/<seg>`, `/Volumes/<seg>` with no recognizable placeholder), email
addresses (except documented exceptions like `noreply@anthropic.com` or
`*@example.com`), UUIDs, and session/trigger identifier shapes. An IANA
time zone (`Europe/Berlin` and similar) is deliberately excluded from this
and is only a warning, not a hit — the value is too coarse-grained to
identify anyone on its own, but shows up often enough in genuine
configuration values that it should not block.

**Exceptions, each narrowly scoped:** a line-exact allowlist
(`scripts/scrub-allowlist.txt`, `path:line:snippet`) for places that
contain the pattern text itself as source code (the pattern definition in
`lib.sh` would otherwise match itself); a single-line fixture marker (`#
vault-check: fixtures (<reason>)`) for test files under `*/tests/*`, which
exempts only structural hits — a real vault term is still reported even in
a marked test file; gitignored files are never subject to the check.

**What this is NOT:** not a replacement for the hard gates
(`rules/agency-bands.md`, the bash gate and the MCP gate), and not
encryption of the vault itself — it sits on the same disk next to the
projects it names; encryption there would protect practically nothing
extra, as long as the machine itself counts as the trust boundary.

**Case-by-case decisions on edge cases**, made by the lead during
implementation and reported to the owner in the closing report (each
reversible with one line). **Confirmed by the owner on 2026-09-26**
(acceptance of PR #6, verbatim: "all decisions as you proposed them"):

| Category | Vault term? | Handling |
|---|---|---|
| Public framework names (the names this framework publishes itself under) | Never | `scripts/vault/public-names.txt`; `init`/`add` skip or refuse them, `vault.sh prune-public` removes them from an already-existing vault |
| Third-party product names (e.g. the identically named Anthropic product "Cowork") | Never | second category in `public-names.txt` — the legacy-list import had initially picked up the name as private by mistake |
| Owner's public identity (attribution, GitHub account) | Never | stays visible wherever it is already public anyway (license attribution, ownership of the public repo); still replaced by a synthetic name in test fixtures — test hygiene, not secrecy |
| Framework's former name (before the rebrand) | Never | it was itself a published name; `MIGRATION.md` needs it to orient legacy users — the separate rebrand topic (its occurrence in still-active documents) is unaffected by this |
| Private repository address(es) | `<private-repo-url>` | several spellings as aliases of the same group; never a hardcoded fallback in code — the value comes from `git remote get-url origin` or a named environment variable, otherwise a loud abort rather than a silent fallback |
| Marker for one specific private, local overlay layer | `<private-layer>` | stricter than every other category: references to it AND descriptions of its mechanics or quotes from its surroundings are **removed rather than tokenized** — an explicit owner directive for this one layer only |
| Names and identifying details of third parties (a beta tester, an incident involving sensitive third-party personal data) | None | reduced to a role or a generalized category, not tokenized — a token would still signal "there is a specific third person here"; a role does not even do that |
| Short session identifiers used as evidence pointers (e.g. in the ledger) | yes, `kind=id` | `vault.sh add id <value> --token "$(vault.sh token id <value>)"` — resolvable locally, then tokenized; distinguished by context from commit hashes and checksums in the same text, which stay unchanged (public and reproducible anyway) |

## Consequences

**Gets easier:** Publishing a clone becomes an act with no content review
of its own history — the source is already clean, and the existing
`publish-transforms.d` scripts are now only a second net. A third-party
contribution (`scripts/imp-submit.sh`) can be checked and turned into a
finished issue/PR text without the contributor giving up a real name,
path, or identifier from their machine. New scripts that need
machine-specific values now have a documented place for that —
`~/.claude/env.local.sh` and `vault.sh token` — instead of inventing their
own fallback value.

**Gets harder:** The improvement ledger and similar evidence files read as
tokens instead of real names after the rewrite — anyone wanting to trace
the context of an entry needs `vault.sh resolve` on the same machine where
the entry was created; on a different machine, or without a vault, the
token stays a token. The vault itself is not backed up anywhere
(deliberately — it sits next to the projects it names, see Decision), and
backing it up is the owner's responsibility alone; losing it makes older
tokens irreversibly unresolvable. A residual free-text gap remains in
principle — no pattern and no vault entry reliably catches every paraphrase
of a real fact, which is why two human counter-checkers are planned as an
additional, non-automatable layer (Wave 5 of this rework found several such
cases this way, which no pattern had caught). And: the gate is a hygiene
gate, not a CRITICAL floor — on an infrastructure failure (missing `jq`, a
broken `vault.sh`) it lets the write through loudly instead of silently
blocking it or silently letting it through (`rules/fail-loud.md`); anyone
who deliberately bypasses the check (`CLAUDE_VAULT_GATE_OFF=1`) does so
logged, but unimpeded.

**References:** `scripts/vault/` (core, matcher, public name list),
`hooks/vault-write-gate.sh` (PreToolUse gate), `scripts/git-hooks/pre-commit`
(second layer for bash-side writers), `scripts/imp-submit.sh` (checked
submission for third parties without network access), `docs/PUBLISHING.md`
(publishing chain against the same vault).
