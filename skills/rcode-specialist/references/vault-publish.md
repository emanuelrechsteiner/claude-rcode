<!--
Status: ACTIVE
Last Updated: 2026-10-03
Purpose: Vault, gates, public-release chain, scrub-check, ops decisions, known gaps - exact procedure
Source: dossier 12-vault-publish, ADR 0003/0005, scripts re-read 2026-10-03; anchors path:line, legend below -->
# Vault and publish chain — reference
Legend: P=scripts/publish.sh S=scripts/scrub-check.sh V=scripts/vault/vault.sh L=scripts/vault/lib.sh G=hooks/vault-write-gate.sh
H=scripts/git-hooks/pre-commit I=scripts/install-git-hooks.sh M=publish-manifest.txt A=scripts/scrub-allowlist.txt PUB=docs/PUBLISHING.md
ADR3,ADR5=docs/adr/0003-*,0005-*; C=CHANGELOG.md (private); D1..D4=ops/decisions files; nn:line = publish-transforms.d/nn-*.sh
## 1. Threat model, invariant (ADR3 lines)
Threat 27-31: names must not leave the machine THROUGH THE FRAMEWORK (commit, public clone, submitted improvement); writer = LLM (22-25).
INVARIANT 35-40: no versioned byte holds a project/company/account name, machine path (user folder, volume, project root), personal id
(email, session, trigger, Notion id) or identifying phrase; real values live only in the gitignored vault, code carries tokens.
Layers 44-48,67-72: Vault (store, block-list), Gate (write hook, pre-commit, CI), Tokenizer; one matcher L; no CRITICAL floor (137-142).
## 2. Vault (V, L, scripts/vault/public-names.txt)
Data, not in repo: ${CLAUDE_VAULT_DIR:-~/.claude/vault}/{secret,map.tsv}; dir 0700, secret 0600 (L:22-24; V:92-100).
Row = kind,term,token,group; one group = one token (ADR3:59-65). Kinds: project account path user volume email id phrase (L:178).
Commands (V:35-79): init [--import-legacy f|--from-registry f]; add <kind> <term> [--group g, default term] [--token t] [--alias term]...; check [--structural-only]
[--stdin --as path|files]; tokenize [--in-place|--dry-run]; resolve; status; prune-public; token <kind> <value>; doctor.
Exit (V:76-77): check 0 clean/2 findings/1 error; doctor 0/1; rest 0/1; add exits 1 on conflict or public name (V:128).
Token = 6 hex of HMAC-SHA256(secret, "<kind>:<group>") (L:115-122), only for project/account/path (path hashes "project:<group>"; prefixes proj-/acct-); volume/email/user fixed tokens, id/phrase need --token (L:127-138): 24 bits, no collision check (L:175-205), per machine (ADR3:50-57).
Secret: made once, never overwritten (V:94-100); perl reads it from a FILE (env VAULT_SECRET_FILE), never argv/ps (L:97-122).
Public names (public-names.txt:41-44): claude-rcode, claude-code-config, R.Code, Cowork; whole-line, case-insensitive; enforced at add,
import, prune, every read (L:46-57,248-263; V:302-329). Also never vault: owner's public identity, pre-rebrand name (see MIGRATION.md).
Third parties = role; <private-layer> text REMOVED, not tokenized; <private-repo-url> from git remote/env (ADR3:98-112).
Matcher: project/account case-insensitive + alnum word boundaries, other kinds exact; longest term first (L:287-295,444-942,704,745).
Unicode: NFC/NFD, zero-width chars tolerated between letters (L:456-520).
Structural (no vault, also in public CI; L:607-660): path (/Users/ /home/ /Volumes/ + real segment, placeholders exempt),
email (documented exemptions), id (any-hex UUID shape, 32-hex, session_/trig_ ids, notion.so URL).
Allowlist A = path:line:signature: the vault matcher compares path + signature substring and IGNORES the line number (L:575-590),
so an entry exempts EVERY such line of that file (L:867,887); bash side (secrets only) needs file+line+sig (S:230-245,278).
Fixture marker "# vault-check: fixtures (<reason>)" (first 5 lines, /tests/ file): structural hits only, never vault terms (L:826-842).
Gates: (a) write hook G (settings.json:188,220,237,245): incoming text via check --stdin --as; repos with scripts/vault/lib.sh only
(G:13-18,134-177); exit 0/2; infra failure = loud fail-open (G:92-110,251). (b) pre-commit H + pre-merge-commit (I:48-57,327-349):
staged blobs; new gitignored path = BLOCK (H:127-174); then scrub --staged (H:188-196); NOT covered: cherry-pick, rebase (I:59-75);
pre-push = full scrub (I:280-301). (c) ledger: ledger-append-proposed.sh tokenizes, hit aborts (16-46). (d) CI: scrub-check.yml:10-24.
Bypasses (logged): CLAUDE_VAULT_GATE_OFF=1 -> G records decision=bypass (no term) in global-observation/vault-gate.log (G:36-60,199-203);
VAULT_PRECOMMIT_BYPASS="<reason>" -> <git-common-dir>/vault-bypass.log, blank refused, unwritable log aborts (H:72-96).
## 3. Publish chain (P, run order)
0. P:48-55 hard-disable FIRST: PUBLISH_DISABLED=1 prints DISABLED, exit 1, before arg parsing. 1. P:60-126 args: --dry-run (default),
--publish --version X, --public-dir (required). 2. P:138-146 abort on any `git status --porcelain` output. 3. P:165 `git archive HEAD`:
tracked files only (overlays, vault, env.local.sh cannot enter). 4. P:182 rsync --exclude-from=M. 5. P:187-209 transforms sorted,
executable, staging = $1, from the PRIVATE tree; failure aborts. 6. P:221-289 throwaway git init in staging; PRIVATE scrub-check.sh there
with --require-pseudonym-list; a finding aborts, public dir untouched. 7. Dry-run (default) P:313-329: file list + diff, stop. 8. --publish
P:334-369: rsync --delete (keeps .git/, ISSUE_TEMPLATE/); ONE commit "release: <version> (from private <sha>)"; public dir needs .git.
9. P:372-377 prints push + tag commands; a human pushes, never the script.
## 4. Manifest M (rsync --exclude-from; slash-less pattern = basename match at ANY depth, M:84-95)
Anchored on purpose: /vault/ (bare form drops scripts/vault/), /CHANGELOG.md (bare form drops public/CHANGELOG.md) (M:84-103,126-128).
Excludes: audit-reports/ work/ ops/ (M:19-28), runtime jsonl, personal tools, local settings, internal specs, plugin state,
root CHANGELOG, SOURCE of 30/45/70 (M:130-138,153-155; effect still runs). NOT excluded: improvement-ledger.json, stubbed by 10 (M:40-43).
## 5. PUBLISH_DISABLED (P:48; today 1 = closed)
Meaning: owner decision 2026-08-12 (OPT-014): publishing cut, private overlay layer must not leave the machine; no env bypass (P:34-47).
Open ONE run: edit P:48 to 0 and COMMIT (dirty tree refused, archive = HEAD: P:138-165); dry-run, --publish; set 1, commit (70:207-211).
History: D1 offered A hand-mirror + verify-public-mirror.sh (recommended), B one-run reopen, C drop list (D1:56-98); owner approved
B plan 2026-09-23 (C:74); v1.1.0..v1.6.1 (9 releases) each opened one run (lead brief; C:64: v1.1.0). D1:3 still says "open".
## 6. Transforms (sorted; $1 = staging; 60, 65 removed 2026-09-25, M:141-152)
10 ledger-stub: jq swaps improvement-ledger.json for a schema-valid empty stub; needs jq (10:28-62)
20 changelog: moves public/CHANGELOG.md to root CHANGELOG.md; ABORTS if missing (20:22-28)
30 placeholder-scan: NO-OP since 2026-09-25, superseded by 50 (30:3-44)
40 private-hooks: drops Cockpit/graphify hooks, subagentStatusLine, outputStyle; fixes statusLine; FAILS on missing script (40:106-253)
45 automode-cache: del(.autoMode) in settings.json (45:54-79)
50 pseudonymize: tokenizes every staging text file via L, all kinds, allowlist honored; skips S, A, itself; no vault = FATAL (50:51-135)
70 neutralize-private-layer-prose: rewrites overlay prose in staging P + rcode/README.md ONLY if one of the two German marker words
(see 70:95-97) is present (70:187,231); also normalizes PUBLISH_DISABLED=0 to 1 (70:212)
## 7. scrub-check (S)
Usage S:9-14: none = full tree; --staged (arg 1 only, S:104) = index; --require-pseudonym-list = vault mandatory; --redact.
Exit 0 clean/1 BLOCKED. Current tree only, never history (S:20-26). Checks in order: (1) SECRET key shapes (S:154-167);
(2) PII = every row of ONE vault.sh check (S:322-359); (3) tracked FILE NAMES, same check (S:379-415); (4) rebrand: pre-rebrand name,
case-insensitive, allowlist NOT consulted, --staged = ADDED lines only (S:417-585); (5) leak: with --require-pseudonym-list a missing
vault or empty <private-layer> group is FATAL (S:598-639). CI (GITHUB_ACTIONS/CI=true) or --redact: "[label] file:line (kind)" only (exception: NAME-PATH prints the full path, S:393-409),
plus ::add-mask::<value> in CI (S:125-148). REBRAND_CARVEOUT (S:435-443) = 7 files: MIGRATION.md, commands/rcode-upgrade.md
(owner 2026-09-23) + five chronicle files (owner 2026-10-01; ADR5:19-32): C, improvement-ledger.json, 2026-05-27 portability spec,
HANDOFF-coding-agent.json, D1. Accepted cost: a NEW old-name mention there goes unreported in both modes; a sixth file needs owner
decision + new ADR (ADR5:29-32). Allowlist entries (A:25-26,49): LICENSE:3, README.md:238, lib.sh pattern line.
## 8. Release procedure (PUB:46-81,242-261)
1 Add version entry to public/CHANGELOG.md, commit (20 aborts without). 2 Open a run. 3 publish.sh --dry-run --public-dir <clone>.
4 publish.sh --publish --public-dir <clone> --version vX.Y.Z. 5 Review the local commit; a HUMAN pushes HEAD + tag; optional GitHub Release.
6 Close the run. 7 Site: check `vercel whoami`/`teams ls`, then `vercel deploy --prod --yes` from site/.
## 9. Ops decisions (ops/ never published: M:28, ops/README.md:6-10; human steps marked -> DU)
- D1 2026-08-13-publisher-stilllegung: ways A/B/C (sec 5); dry run scrub clean; gaps: history, paraphrase (:20-54,100-106)
- D2 2026-09-27-directory-auslieferung: A nothing, B MCP connector (no), C own-marketplace plugin first, D + submission; open (:3,42)
- D3 2026-09-29-keine-bezahlte-werbung: decided; no LinkedIn boost, free plan; revisit when usage is measurable (:17-18)
- D4 2026-09-29-logo-system: accepted; "R." from blocks; assets local, unpublished; sign-off open (:3,23)
- Awesome list (ops/awesome-claude-code/PLAN.md:11-16,94-98): needs 14 days AND later commits; human-only form
## 10. Public/private split
Ships (M:139-141; P:343-346): tracked files minus M, tokenized (50); settings stripped (40,45); ledger stub (10); changelog (20);
vault tooling, S, A, P, transforms 10/20/40/50, PUB, docs/adr, site/, .github. Never: gitignored/untracked (vault, *.local.*,
env.local.sh), M exclusions, ledger history, real names. Visible on purpose: the 4 public names, A:25-26, owner's public account in
links, pre-rebrand name in MIGRATION.md + rcode-upgrade.md (S:420-426).
## 11. Fragilities (verified 2026-10-03 unless marked)
- 70 = SILENT NO-OP (lead-verified, re-grepped): its two marker words occur 0x in P and rcode/README.md -> no-op branch (70:187,231).
 Effects: the =0 -> =1 normalization (70:212) never runs, so a run committed with =0 ships =0;
 overlay prose stays public (P:34-45; rcode/README.md:167-168).
- scrub swallows vault.sh errors (2>/dev/null + || true, S:326,330,403): rc 1 (broken perl) reads "clean"; open item 3cad614 (unverified).
- History never scanned (S:20-26; D1:100-106). Paraphrase gap: verbatim only (D1:50-54; ADR3:133-137). Vault not backed up (ADR3:129-133).
- Stale allowlist coordinate: A:49 says lib.sh:421, pattern is L:621; works only because L:575 ignores lines.
- CLAUDE_SCRUB_PSEUDONYM_LIST: documented P:285-288, no code in S. PUB:3 dated 2026-08-06, silent on PUBLISH_DISABLED (hits exit 1 first).
Sources read: dossier 12, ADR3/5, M, 10-70, PUB, ops/*, P S V L A G H I, C:50-74; Not verified: 3cad614, vault contents, 1.1.1-1.6.1 runs
