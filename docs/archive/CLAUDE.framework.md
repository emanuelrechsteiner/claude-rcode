<!--
Status: ARCHIVED
Last Updated: 2026-08-22
Purpose: Predecessor of today's rules/foundation.md (5-phase workflow). Archived 2026-08-22: named the retired ux-agent and a frontend-agent that never existed, and nothing referenced it.
-->

# Project Development Framework

## Automatic Development Recognition

When the user asks to "build", "create", "develop", or "implement" an application, feature, or project, ALWAYS follow the orchestrated development workflow below.

## Development Workflow Phases

### Phase 1: Research & Planning (Parallel)
**IMMEDIATELY spawn these sub-agents in parallel:**
- `research-agent`: Research technologies, APIs, best practices
- `planning-agent`: Create architecture and task breakdown

**Wait for both to complete before proceeding.**

### Phase 2: Design
**Spawn sequentially:**
- `ux-agent`: Create user flows, wireframes, accessibility requirements
- `ui-agent`: Define component architecture, styling patterns

### Phase 3: Implementation
**Spawn based on project needs:**
- `backend-agent`: APIs, database, server logic
- `frontend-agent`: UI components, state management, styling

**These can run in parallel if there are no blocking dependencies.**

### Phase 4: Quality Assurance
**After implementation:**
- `testing-agent`: Write and run tests
- `documentation-agent`: Create documentation

### Phase 5: Version Control
**Throughout all phases:**
- `version-control-agent`: Monitors commit frequency, ensures commits every 30-60 minutes

## Sub-Agent Spawning Rules

1. **ALWAYS use the Task tool** to spawn sub-agents - never try to do their work directly
2. **Specify the sub-agent type** using `subagent_type` parameter
3. **Provide clear, detailed prompts** with all context needed
4. **Wait for completion** before moving to dependent phases
5. **Run independent agents in parallel** when possible for efficiency

## Quality Gates

Before moving to the next phase, verify:
- [ ] All sub-agents reported completion
- [ ] Deliverables exist and are valid
- [ ] No blocking issues reported

## Commit Frequency

Ensure commits happen at least every 60 minutes during active development. The version-control-agent monitors this.

## Error Handling

If a sub-agent reports a blocker:
1. Assess the issue
2. Spawn appropriate agent to resolve
3. Resume blocked work after resolution

## Key Principle

**You orchestrate, sub-agents execute.** Never write code, create designs, or run tests directly when a specialized sub-agent exists for that task.
