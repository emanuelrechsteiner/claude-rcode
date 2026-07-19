# Context Preservation System

> **Note:** this is a design document for a checkpoint/restore system. Some of it (e.g. the `~/.claude/context-checkpoints/` store) is aspirational rather than currently wired into the shipped hooks — the closest live equivalent today is `/handoff` + `PROJECT-STATUS.md` for cross-session continuity, and `rules/context-engineering.md` for in-session context budgeting. May be superseded.

## Overview
Addresses critical context loss issues observed between sessions where agents misunderstood requirements after session gaps, requiring 5+ minutes of re-clarification and causing scope confusion.

## Core Problem Analysis
**From Global Ledger Observations:**
- "context_loss_between_sessions_causes_requirement_misunderstandings"
- "requirement_clarification_after_context_recovery" caused 5-minute delays
- "initial_interpretation_was_individual_profiles_not_industry_aggregation"

## Solution Architecture

### 1. Automatic Checkpoint Creation
```yaml
checkpoint_triggers:
  time_based:
    - every_30_minutes_active_development
    - before_session_end_detected
    - after_major_milestone_completion
    
  event_based:
    - before_context_switching_between_features
    - after_requirement_clarification_sessions  
    - when_pivoting_implementation_approach
    - before_multi_agent_handoffs
    
  user_initiated:
    - manual_checkpoint_creation_command
    - before_complex_task_sequences
    - strategic_development_pause_points
```

### 2. Checkpoint Content Structure
```typescript
interface ContextCheckpoint {
  metadata: {
    checkpointId: string;
    timestamp: string;
    sessionId: string;
    createdBy: 'auto' | 'manual' | 'agent';
    contextType: 'requirement' | 'implementation' | 'coordination' | 'complete';
  };
  
  requirementContext: {
    originalUserRequest: string;
    clarifiedRequirements: string[];
    scopeDefinition: string;
    deliverableExpectations: string[];
    userFeedbackHistory: string[];
    pivotDecisions: Array<{
      from: string;
      to: string;
      reason: string;
      timestamp: string;
    }>;
  };
  
  implementationContext: {
    currentFeatureState: string;
    completedTasks: string[];
    inProgressTasks: string[];
    plannedTasks: string[];
    technicalDecisions: Record<string, string>;
    architecturalChoices: string[];
    dependencyMap: Record<string, string[]>;
  };
  
  agentCoordination: {
    activeAgents: string[];
    agentTaskAssignments: Record<string, string[]>;
    completedHandoffs: Array<{
      from: string;
      to: string;
      task: string;
      completionStatus: string;
    }>;
    pendingCoordination: string[];
  };
  
  codeContext: {
    modifiedFiles: string[];
    createdFiles: string[];
    deletedFiles: string[];
    keyImplementationPatterns: string[];
    criticalCodeDecisions: string[];
  };
}
```

### 3. Checkpoint Storage System
```yaml
storage_architecture:
  location: "~/.claude/context-checkpoints/"
  organization:
    by_project: "checkpoints/{project-id}/"
    by_session: "checkpoints/{project-id}/{session-id}/"
    by_timestamp: "checkpoints/{project-id}/{session-id}/{timestamp}.json"
  
  retention_policy:
    active_session: "keep_all_checkpoints"
    completed_session: "keep_final_and_milestone_checkpoints"
    archived_project: "keep_completion_checkpoint_only"
    
  compression:
    format: "gzipped_json"
    indexing: "timestamp_and_content_hash"
    search_capability: "full_text_search_on_requirements"
```

### 4. Session Restoration Protocol

#### Automatic Session Continuity
```yaml
session_start_protocol:
  automatic_actions:
    1. detect_previous_session_checkpoints
    2. load_most_recent_checkpoint
    3. present_context_summary_to_user
    4. validate_continuation_intent
    
  context_presentation:
    format: |
      ## Session Continuity Detected
      
      **Last Session**: {last_session_timestamp}
      **Project**: {project_name}
      **Last Checkpoint**: {checkpoint_summary}
      
      ### Requirements Understanding
      - **Original Request**: {original_request}
      - **Clarified Scope**: {clarified_scope}
      - **Last Deliverables**: {recent_deliverables}
      
      ### Implementation Progress
      - **Completed**: {completed_tasks}
      - **In Progress**: {current_tasks}  
      - **Next Planned**: {planned_tasks}
      
      ### Confirmation Required
      - Continue with previous understanding? [Y/N]
      - Any requirement changes since last session? [Details]
      - Proceed with planned next steps? [Y/N]
```

#### Requirement Validation Before Proceeding
```yaml
validation_protocol:
  mandatory_confirmations:
    - "Is my understanding of the requirements still accurate?"
    - "Have there been any scope changes since last session?"
    - "Should I proceed with the planned implementation approach?"
    - "Are the technical decisions from last session still valid?"
    
  validation_questions:
    scope_confirmation:
      - "The last session focused on: {scope_summary}. Is this still correct?"
      - "Previous decisions included: {key_decisions}. Are these still valid?"
      - "The implementation approach was: {approach}. Should I continue with this?"
    
    requirement_changes:
      - "Any new requirements since last session?"
      - "Any removed or modified requirements?"
      - "Any priority changes in the deliverables?"
      
  proceed_conditions:
    - user_confirms_understanding_accuracy
    - no_major_scope_changes_identified
    - technical_approach_remains_valid
    - agent_demonstrates_context_comprehension
```

### 5. Context Recovery Framework

#### Smart Context Loading
```typescript
interface ContextRecovery {
  loadStrategy: 'complete' | 'incremental' | 'selective';
  
  complete: {
    description: "Load full context from all checkpoints";
    use_case: "After long session gaps or complex pivots";
    performance: "slower_but_comprehensive";
  };
  
  incremental: {
    description: "Load recent context with historical summary";
    use_case: "Normal session continuation";
    performance: "balanced_speed_and_completeness";
  };
  
  selective: {
    description: "Load specific context areas as needed";
    use_case: "Focused task continuation";
    performance: "fastest_targeted_recovery";
  };
}
```

#### Context Gap Analysis
```yaml
gap_detection:
  temporal_gaps:
    - identify_time_since_last_checkpoint
    - assess_potential_context_degradation
    - flag_high_risk_continuation_points
    
  requirement_drift:
    - compare_current_vs_checkpointed_understanding
    - identify_assumption_changes
    - detect_scope_evolution_patterns
    
  implementation_divergence:
    - validate_current_code_vs_checkpointed_plan
    - identify_unplanned_changes
    - assess_architectural_consistency
```

### 6. Agent-Specific Context Protocols

#### Improvement Agent Context
```yaml
improvement_agent_context:
  specialized_checkpoints:
    - analysis_scope_and_focus_area
    - existing_ledger_structure_understanding
    - meta_vs_technical_analysis_distinction
    - observation_vs_improvement_task_clarity
    
  restoration_validation:
    - confirm_meta_analysis_scope_understanding
    - validate_ledger_preservation_requirements
    - verify_process_vs_code_focus_clarity
```

#### Control Agent Context
```yaml
control_agent_context:
  orchestration_checkpoints:
    - active_agent_coordination_state
    - task_distribution_and_dependencies
    - quality_gate_status_tracking
    - multi_agent_synchronization_status
    
  restoration_validation:
    - confirm_orchestration_responsibilities
    - validate_delegation_vs_execution_understanding
    - verify_agent_coordination_requirements
```

### 7. Integration with Existing Systems

#### Observation Ledger Integration
```yaml
ledger_integration:
  checkpoint_recording:
    - record_checkpoint_creation_events
    - track_context_recovery_effectiveness
    - monitor_requirement_clarification_reduction
    - measure_session_continuity_success
    
  pattern_analysis:
    - identify_common_context_loss_scenarios
    - track_recovery_time_improvements
    - analyze_checkpoint_usage_patterns
    - measure_user_steering_reduction
```

#### Agent Workflow Integration
```yaml
workflow_integration:
  pre_task_context_check:
    - load_relevant_checkpoint_before_starting
    - validate_understanding_against_historical_context
    - confirm_no_context_gaps_detected
    
  mid_task_context_updates:
    - create_incremental_checkpoints_during_work
    - update_requirement_understanding_evolution
    - track_implementation_decision_history
    
  post_task_context_capture:
    - create_completion_checkpoint_with_outcomes
    - document_lessons_learned_and_decisions
    - prepare_handoff_context_for_next_agent
```

## Success Metrics

### Context Preservation Effectiveness
- **Session Continuity Success Rate**: Target >95%
- **Requirement Clarification Time**: Target <2 minutes (down from 5+ minutes)
- **Context Recovery Accuracy**: Target >90%
- **Scope Misunderstanding Prevention**: Target >80% reduction

### User Experience Improvement  
- **Session Startup Time**: Target <1 minute for context loading
- **Requirement Re-clarification**: Target >70% reduction
- **Implementation Pivot Time**: Target >50% reduction
- **User Satisfaction**: Clear context understanding demonstration

### Agent Performance Enhancement
- **Context-Related Errors**: Target >85% reduction  
- **Task Scope Understanding**: Target >95% accuracy
- **Implementation Consistency**: Target >90% alignment with checkpoints
- **Agent Confidence**: Measurable improvement in task approach certainty

This system directly addresses the critical context loss failures documented in the global ledger, particularly an industry satisfaction feature in an example legacy TS/React project where context loss led to requirement misunderstanding and 5-minute re-clarification delays.