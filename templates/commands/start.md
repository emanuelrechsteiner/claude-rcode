---
description: Deep codebase exploration achieving >95% understanding through multi-agent coordination
argument-hint: [--deep | --quick | --focus <area>] [notes]
model: claude-sonnet-4-20250514
allowed-tools: ["*"]
---

# Claude Code — Deep Codebase Understanding System

Import @~/.claude/agents/control-agent.md
Import @~/.claude/agents/research-agent.md

Parse flags from $ARGUMENTS:
- --deep → Comprehensive exploration with detailed architecture analysis
- --quick → Fast exploration focusing on high-level structure
- --focus <area> → Concentrate exploration on specific area (backend, frontend, database, etc.)

## Context (auto-collected)
- Repo root: !`git rev-parse --show-toplevel || pwd`
- Branch: !`git branch --show-current || echo '(detached/none)'`
- Status: !`git status -s`
- Recent commits: !`git log --oneline -10 || true`
- Codebase size: !`find . -type f -name "*.js" -o -name "*.ts" -o -name "*.tsx" -o -name "*.py" -o -name "*.java" -o -name "*.go" -o -name "*.rs" | wc -l` files

## OPERATING PRINCIPLES

### Mission: Achieve >95% Codebase Understanding
- **Target**: Complete architectural comprehension with confidence scoring
- **Approach**: Multi-agent coordination for parallel deep-dive exploration
- **Outcome**: Persistent knowledge base for subsequent commands
- **Validation**: Self-assessed confidence metrics and gap identification

### Multi-Agent Coordination Protocol
1. **Control-Agent Orchestration**: Coordinate all exploration activities
2. **Research-Agent Deployment**: Systematic codebase analysis
3. **Knowledge Integration**: Combine findings into unified understanding
4. **Confidence Assessment**: Measure understanding completeness

## EXPLORATION PHASES

### Phase 1: Architecture Discovery (Research Agent)
**Objective**: Map the complete system architecture

**Core Discovery Tasks**:
- **Tech Stack Identification**: Languages, frameworks, libraries, tools
- **Module Structure**: Services, packages, components, utilities
- **Data Flow Mapping**: Request lifecycles, state management, data persistence
- **Integration Points**: APIs, databases, external services, message queues
- **Build & Deploy**: CI/CD pipelines, containerization, environment configs

**Deep Analysis**:
```
Research-Agent Tasks:
1. Scan package.json, pyproject.toml, go.mod, Cargo.toml for dependencies
2. Analyze src/, lib/, app/, components/ for architectural patterns
3. Map database schemas from migrations/, models/, entities/
4. Identify API endpoints from routes/, controllers/, handlers/
5. Document build processes from scripts, Dockerfile, CI configs
6. Trace data flows through services and components
7. Catalog environment variables and configuration patterns
```

### Phase 2: Feature Analysis (Research Agent)
**Objective**: Understand all implemented features and capabilities

**Feature Discovery**:
- **User-Facing Features**: UI components, pages, user journeys
- **Business Logic**: Core algorithms, processing workflows, rule engines
- **Data Models**: Entity relationships, validation rules, constraints
- **Security Implementation**: Authentication, authorization, input validation
- **Performance Optimizations**: Caching, lazy loading, optimization patterns

**Analysis Pattern**:
```
For each major feature area:
1. Identify entry points (routes, components, CLI commands)
2. Trace execution paths through the system
3. Document data dependencies and side effects
4. Map error handling and edge cases
5. Assess test coverage and quality measures
```

### Phase 3: Code Quality Assessment (Research Agent)
**Objective**: Evaluate code quality, patterns, and technical debt

**Quality Metrics**:
- **Code Organization**: Directory structure, naming conventions, modularity
- **Design Patterns**: Architectural patterns, code reuse, abstractions
- **Error Handling**: Exception management, logging, monitoring
- **Testing Strategy**: Unit tests, integration tests, E2E coverage
- **Documentation**: Code comments, README files, API docs
- **Performance**: Algorithmic complexity, resource usage, bottlenecks

### Phase 4: Knowledge Integration (Control Agent)
**Objective**: Synthesize findings into unified understanding

**Integration Tasks**:
1. **Consolidate Findings**: Merge research from all phases
2. **Identify Relationships**: Connect components, features, and flows
3. **Assess Completeness**: Calculate understanding confidence score
4. **Document Gaps**: List areas needing deeper exploration
5. **Store Knowledge**: Persist findings in memory MCP server
6. **Update Vector DB**: Index exploration results for semantic search

## KNOWLEDGE PERSISTENCE

### Memory Storage Format
```json
{
  "exploration_id": "codebase-analysis-{timestamp}",
  "project_name": "{repo_name}",
  "confidence_score": 95.2,
  "architecture": {
    "tech_stack": [...],
    "modules": [...],
    "data_flow": {...},
    "integrations": [...]
  },
  "features": {
    "user_facing": [...],
    "business_logic": [...],
    "data_models": [...],
    "security": [...]
  },
  "quality": {
    "patterns": [...],
    "testing": {...},
    "documentation": {...},
    "technical_debt": [...]
  },
  "gaps": [...],
  "recommendations": [...]
}
```

### Vector Database Integration
- **Index exploration results** for semantic search
- **Enable cross-project pattern recognition**
- **Support improvement agent learning**
- **Facilitate documentation generation**

## CONFIDENCE SCORING SYSTEM

### Calculation Methodology
```
Confidence Score = (
  Architecture Understanding (25%) +
  Feature Comprehension (30%) +
  Code Quality Assessment (20%) +  
  Integration Knowledge (15%) +
  Gap Identification (10%)
)

Target: >95% overall confidence
Threshold: >90% to proceed with other commands
```

### Understanding Levels
- **🔴 <70%**: Insufficient - requires re-exploration
- **🟡 70-89%**: Partial - acceptable but limited
- **🟢 90-94%**: Good - ready for most operations
- **✅ 95%+**: Excellent - complete understanding achieved

## EXECUTION WORKFLOW

### Step 1: Initialization
```
Control-Agent: "🚀 Initiating deep codebase exploration"
1. Parse command flags and focus areas
2. Assess codebase size and complexity
3. Determine exploration strategy (quick vs deep)
4. Activate research-agent with specific mandate
```

### Step 2: Systematic Exploration
```
Research-Agent: "🔍 Beginning systematic codebase analysis"
1. Architecture Discovery Phase (25% progress)
2. Feature Analysis Phase (50% progress)  
3. Code Quality Assessment Phase (75% progress)
4. Report findings to Control-Agent
```

### Step 3: Integration & Storage
```
Control-Agent: "🧠 Integrating knowledge and calculating confidence"
1. Synthesize research findings
2. Calculate confidence scores by category
3. Identify knowledge gaps
4. Store results in memory MCP server
5. Update vector database with indexed content
6. Generate understanding report
```

### Step 4: Validation & Reporting
```
Final Report Format:
📊 Codebase Understanding Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 Overall Confidence: 95.2%
├── Architecture: 96% (✅ Complete)
├── Features: 94% (✅ Complete) 
├── Code Quality: 97% (✅ Complete)
├── Integrations: 93% (✅ Complete)
└── Gap Analysis: 98% (✅ Complete)

🏗️  Architecture Overview:
- Tech Stack: React + TypeScript + Node.js + PostgreSQL
- Pattern: Microservices with event-driven communication
- Scale: 47 services, 156 API endpoints, 23 data models

🚀 Ready for: /documentation, /testing, advanced development
💾 Knowledge stored in: memory MCP + vector database
```

## PROGRESS TRACKING

### Real-time Updates
- **Phase progress indicators** (Architecture: 23%... Feature Analysis: 67%...)
- **Live confidence scoring** as understanding develops
- **Gap identification** in real-time
- **ETA calculations** based on codebase complexity

### Observation Integration
- **Record exploration patterns** in global observation ledger
- **Track efficiency metrics** for improvement agent learning
- **Document successful exploration strategies**
- **Note areas requiring manual intervention**

## ERROR HANDLING & RECOVERY

### Common Scenarios
- **Large Codebase**: Implement chunking and progressive analysis
- **Complex Architecture**: Multi-pass exploration with increasing depth
- **Missing Documentation**: Infer patterns from code structure
- **Access Restrictions**: Graceful degradation with partial understanding

### Recovery Strategies
- **Confidence Below Threshold**: Trigger additional exploration phases
- **Knowledge Gaps**: Focus re-analysis on identified weak areas
- **Time Constraints**: Prioritize critical paths and core functionality
- **Tool Limitations**: Switch to alternative analysis approaches

## INTEGRATION WITH OTHER COMMANDS

### Knowledge Dependencies
- **/documentation**: Requires >90% confidence for quality docs
- **/testing**: Uses architecture knowledge for test strategy  
- **/meta**: Leverages exploration patterns for improvement
- **Development tasks**: Foundation for all code-related work

### Knowledge Sharing
- **Memory MCP Server**: Persistent cross-session knowledge
- **Vector Database**: Semantic search and pattern matching
- **Global Ledger**: Exploration patterns for system improvement
- **Agent Coordination**: Share findings with other specialists

---

**Remember**: This command creates the foundation for all subsequent agent work. Thorough exploration here enables excellent performance from documentation generation, testing strategies, and development tasks. Aim for >95% confidence before proceeding to other operations.