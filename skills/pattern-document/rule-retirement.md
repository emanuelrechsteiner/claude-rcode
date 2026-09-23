# Rule Retirement Protocol

## Pattern Document Headers

When creating new rules via `/pattern-document`, always include:

```markdown
<!--
Created: YYYY-MM-DD
Expires: YYYY-MM-DD (6 months from creation)
Status: ACTIVE | DEPRECATED | SUPERSEDED
Supersedes: rule-name.md (if replacing an older rule)
-->
```

## Retirement Workflow

1. **Monthly audit**: Check rules older than 6 months
2. **Validation check**: Is this pattern still relevant?
3. **Actions**:
   - Still valid → Extend expiry by 6 months
   - Outdated → Move to `~/.claude/rules/archive/`
   - Replaced → Update with `Supersedes:` header

## Auto-detection

Add to SessionStart hook:
```bash
find ~/.claude/rules -name "*.md" -exec grep -l "Expires:" {} \; | while read rule; do
  expiry=$(grep "Expires:" "$rule" | cut -d' ' -f2)
  if [[ $(date -j -f "%Y-%m-%d" "$expiry" +%s) -lt $(date +%s) ]]; then
    echo "⚠️ Expired rule detected: $(basename $rule)"
  fi
done
```
