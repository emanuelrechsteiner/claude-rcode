<!--
Status: ARCHIVED
Last Updated: 2026-09-24
Purpose: Belege, Vorfälle und Messungen, die am 2026-09-24 (IMP-217) wörtlich aus rules/release-cli-discipline.md ausgelagert wurden — die Regel selbst bleibt dort; hier steht das „Warum" in voller Länge.
-->
# Belege zu `rules/release-cli-discipline.md`

> Ausgelagert 2026-09-24 (IMP-217). Jeder Block steht unter der Überschrift, unter der er in der Regel stand, und ist unverändert übernommen.

## 1. Local-First Deploy

Observed: 4 failed cloud deploys cost ~12 minutes; a single local `<tool> build` + direct import of the compiled function (e.g. `import('.vercel/output/functions/.../index.js')` or the platform equivalent) would have caught all four bugs in <5 seconds.
