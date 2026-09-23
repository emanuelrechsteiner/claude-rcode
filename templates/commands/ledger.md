---
description: Global observation ledger health check and improvement metrics analysis
argument-hint: [--check | --metrics | --export | --repair] [--verbose]
model: claude-sonnet-4-20250514
allowed-tools: ["*"]
---

# Claude Code — Global Observation Ledger Health Check

Import @~/.claude/agents/control-agent.md
Import @~/.claude/agents/research-agent.md

Parse flags from $ARGUMENTS:
- --check → Validate ledger structure and integrity
- --metrics → Analyze improvement patterns and metrics
- --export → Export observations in various formats
- --repair → Fix corrupted entries and optimize structure
- --verbose → Detailed diagnostic information

## Context (auto-collected)
- Repo root: !`git rev-parse --show-toplevel || pwd`
- Branch: !`git branch --show-current || echo '(detached/none)'`
- Global ledger path: ~/.claude/global-observation/
- Total observations: !`find ~/.claude/global-observation -name "*.json" | wc -l` entries
- Last ledger update: !`ls -la ~/.claude/global-observation/observation-ledger.json | awk '{print $6" "$7" "$8}' || echo 'Not found'`

## OPERATING PRINCIPLES

### Mission: Maintain Global Learning System Health
- **Target**: Ensure observation ledger integrity for cross-project improvement
- **Approach**: Systematic health checks with automated repair capabilities  
- **Outcome**: Validated observation system enabling continuous learning
- **Integration**: Verify compatibility with improvement-agent workflows

### Health Check Categories
1. **Structural Integrity**: JSON validation, schema compliance, corruption detection
2. **Content Quality**: Observation completeness, timestamp accuracy, classification
3. **Performance Metrics**: Token usage tracking, improvement trend analysis
4. **System Integration**: Vector database sync, MCP server compatibility
5. **Storage Optimization**: Duplicate removal, archival management, indexing

## LEDGER STRUCTURE VALIDATION

### Critical File Inventory
```
~/.claude/global-observation/
├── observation-ledger.json          # Main observation database
├── improvement-patterns.json        # Pattern recognition data
├── token-counter.json              # 100k token usage tracking
├── agent-performance.json          # Agent coordination metrics
├── project-insights/              # Per-project observation summaries
│   ├── project-a-observations.json
│   └── project-b-observations.json
├── archived/                      # Historical observations
│   └── YYYY-MM-DD/
└── meta-improvements.json         # Self-improvement observations
```

### Schema Validation Patterns
```json
{
  "observation_id": "uuid-v4",
  "timestamp": "ISO-8601",
  "project_context": "string",
  "observation_type": "improvement|pattern|error|success",
  "agent_involved": "agent-name",
  "description": "string",
  "impact_score": "1-10",
  "implementation_status": "pending|active|completed|archived",
  "related_observations": ["uuid-list"],
  "tokens_used": "integer",
  "improvement_applied": "boolean"
}
```

## HEALTH CHECK WORKFLOW

### Phase 1: Structural Analysis (Research Agent)
**Objective**: Validate ledger file integrity and structure

**Core Validation Tasks**:
- **JSON Syntax Check**: Parse all .json files for syntax errors
- **Schema Compliance**: Validate required fields and data types
- **File Permissions**: Ensure proper read/write access
- **Corruption Detection**: Identify truncated or malformed entries
- **Index Integrity**: Verify observation cross-references

**Analysis Pattern**:
```
Research-Agent Tasks:
1. Scan ~/.claude/global-observation/ for all JSON files
2. Validate JSON syntax and schema compliance
3. Check file modification timestamps vs observation timestamps
4. Verify observation ID uniqueness and cross-reference integrity
5. Identify corrupted, duplicate, or orphaned entries
6. Calculate storage usage and optimization opportunities
```

### Phase 2: Content Quality Assessment (Research Agent)
**Objective**: Analyze observation quality and completeness

**Quality Metrics**:
- **Observation Completeness**: Required fields populated, meaningful descriptions
- **Temporal Consistency**: Timestamp accuracy, chronological ordering
- **Classification Accuracy**: Proper observation type assignment
- **Impact Assessment**: Realistic impact scores, outcome validation
- **Context Richness**: Adequate project context and technical details

### Phase 3: Performance Analysis (Control Agent)
**Objective**: Evaluate improvement system effectiveness

**Performance Indicators**:
- **Token Efficiency**: Cost per improvement vs impact delivered
- **Implementation Rate**: Observations converted to actual improvements
- **Pattern Recognition**: Recurring issues and successful solution patterns
- **Agent Coordination**: Multi-agent workflow success rates
- **Cross-Project Learning**: Knowledge transfer between projects

### Phase 4: System Integration Check (Control Agent)
**Objective**: Verify integration with broader Claude Code ecosystem

**Integration Points**:
1. **Vector Database Sync**: Observations indexed for semantic search
2. **MCP Server Health**: Memory server storing observation data
3. **Agent Communication**: Proper observation recording in workflows
4. **Hook Integration**: Automated observation capture from hooks
5. **Improvement Agent**: Meta-layer system using observations

## DIAGNOSTIC PROCEDURES

### Health Score Calculation
```
Ledger Health Score = (
  Structural Integrity (25%) +
  Content Quality (30%) +
  Performance Metrics (20%) +
  Integration Status (15%) +
  Optimization Level (10%)
)

🟢 90-100%: Excellent health
🟡 70-89%: Good with minor issues
🟠 50-69%: Needs attention
🔴 <50%: Critical issues requiring immediate repair
```

### Automated Repair Capabilities
- **JSON Repair**: Fix syntax errors, restore from backups
- **Deduplication**: Remove duplicate observations, merge related entries
- **Schema Migration**: Update observations to current schema version
- **Index Rebuilding**: Recreate cross-reference indices
- **Archive Management**: Move old observations to archived directories

## METRICS ANALYSIS SYSTEM

### Improvement Pattern Recognition
```
Pattern Analysis Categories:
├── Code Quality Improvements (frequency, impact, success rate)
├── Architecture Decisions (patterns, trade-offs, outcomes)
├── Tool Usage Optimization (efficiency gains, adoption rates)
├── Agent Coordination (successful patterns, failure modes)
├── Cross-Project Learning (knowledge transfer success)
└── Meta-Improvements (system self-enhancement patterns)
```

### Token Usage Analytics
```
Token Tracking Metrics:
- Total tokens consumed per improvement cycle
- Cost efficiency: tokens per successful improvement
- Model usage patterns: Opus vs Sonnet distribution  
- Trend analysis: usage optimization over time
- Budget predictions: projected costs for improvement goals
```

### ROI Calculation Framework
```
Improvement ROI = (
  (Development Time Saved + Bug Prevention Value + 
   Code Quality Improvement + Learning Acceleration) 
  / 
  (Token Costs + Agent Coordination Time + System Overhead)
)
```

## EXPORT AND REPORTING

### Report Generation Formats
- **Executive Summary**: High-level health metrics and recommendations
- **Technical Report**: Detailed diagnostics with specific issues
- **Trend Analysis**: Historical performance and improvement patterns
- **Integration Status**: MCP servers, agents, and system connectivity
- **Action Plan**: Prioritized recommendations for system optimization

### Export Formats
```
Supported Export Types:
- JSON: Raw data for programmatic analysis
- CSV: Metrics for spreadsheet analysis
- Markdown: Human-readable reports
- HTML: Interactive dashboard format
- PDF: Formal documentation output
```

## EXECUTION WORKFLOW

### Step 1: Initialization & Discovery
```
Control-Agent: "🔍 Initializing global ledger health check"
1. Validate command flags and determine check scope
2. Verify access to ~/.claude/global-observation/
3. Assess system load and available resources
4. Activate research-agent for detailed analysis
```

### Step 2: Comprehensive Health Analysis
```
Research-Agent: "📊 Analyzing observation ledger health"
1. Structural validation (25% progress)
2. Content quality assessment (50% progress)
3. Performance metric calculation (75% progress)
4. Integration status verification (100% progress)
5. Report findings to Control-Agent
```

### Step 3: Issue Resolution & Optimization
```
Control-Agent: "🔧 Processing health check results"
1. Prioritize identified issues by severity
2. Execute automated repairs where safe
3. Generate optimization recommendations
4. Update system health metrics
5. Schedule follow-up checks if needed
```

### Step 4: Reporting & Recommendations
```
Final Health Report Format:
🏥 Global Ledger Health Check Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 Overall Health Score: 94% (🟢 Excellent)
├── Structure: 98% (✅ Clean)
├── Content: 92% (✅ High Quality)
├── Performance: 89% (✅ Efficient)
├── Integration: 96% (✅ Connected)
└── Optimization: 91% (✅ Well-Tuned)

📈 Key Metrics:
- Total observations: 1,247
- Average impact score: 7.2/10
- Implementation rate: 73%
- Token efficiency: 2.3 improvements/1000 tokens
- Cross-project learning: 89% knowledge transfer

🔧 Recommendations:
1. Archive observations older than 90 days (reduce by 15%)
2. Improve agent coordination documentation (impact +12%)
3. Enhance pattern recognition algorithms (efficiency +8%)
4. Update 23 observations with missing context fields

📊 Trend Analysis:
- Improvement velocity: +23% over last month
- Cost efficiency: +15% token optimization
- Agent coordination: +31% success rate
- System stability: 99.2% uptime
```

## AUTOMATION INTEGRATION

### Scheduled Health Checks
```
Recommended Schedule:
- Daily: Basic integrity check (structure validation)
- Weekly: Content quality assessment
- Monthly: Full performance analysis with optimization
- Quarterly: Comprehensive system integration review
```

### Alert Thresholds
```
Critical Alerts (Immediate Action):
- Health score drops below 50%
- JSON corruption detected
- Token budget exceeded by 200%
- Integration failures with core MCP servers

Warning Alerts (Schedule Review):
- Health score between 50-70%
- Performance degradation >15%
- Observation backlog >100 unprocessed entries
- Integration latency >500ms
```

## ERROR HANDLING & RECOVERY

### Common Issues & Solutions
- **Corrupted JSON Files**: Restore from automatic backups, rebuild indices
- **Schema Version Conflicts**: Automated migration with validation
- **Performance Degradation**: Archive old data, optimize queries
- **Integration Failures**: Repair MCP connections, restart services

### Backup and Recovery
- **Automatic Backups**: Daily snapshots with 30-day retention
- **Point-in-Time Recovery**: Restore specific observation states
- **Disaster Recovery**: Full system rebuild from distributed backups
- **Data Validation**: Post-recovery integrity verification

## INTEGRATION WITH IMPROVEMENT SYSTEM

### Two-Layer Architecture Support
- **Project Layer (Sonnet)**: Validate project-specific observations
- **Meta Layer (Opus)**: Analyze cross-project improvement patterns
- **Feedback Loop**: Health metrics inform improvement agent priorities
- **Quality Gates**: Ensure observation quality before improvement processing

### Agent Coordination Health
- **Control-Agent Performance**: Coordination success rates and efficiency
- **Specialized Agent Metrics**: Individual agent contribution to improvements
- **Multi-Agent Workflows**: Complex task completion rates and quality
- **Communication Protocols**: Agent reporting compliance and effectiveness

---

**Note**: This command maintains the health and effectiveness of the global observation ledger system, ensuring that the Claude Code Agent System can continuously learn and improve across all projects and interactions.