---
name: implement
aliases: [execute-tasks, task-implementation]
description: Unified implementation workflow combining task discovery, feature development, and atomic execution. NEVER decomposes tasks - that is handled by decompose-tasks. Use when: implementing discovered tasks OR developing specific features OR executing atomic implementations
---

# /implement - Unified Implementation Workflow

**Purpose**: Coordinate multiple specialized agents to automatically discover, implement, and verify all pending development tasks across different scopes and complexity levels.

## Command Syntax

```bash
# Basic implementation (all discovered tasks)
/implement

# Scope-specific implementation
/implement --scope tasks           # Task discovery and implementation (from dd/implement)
/implement --scope feature         # Feature implementation workflow (from sc/implement)
/implement --scope atomic          # Atomic task execution

# Feature-specific implementation (from sc/implement functionality)
/implement --type component        # UI component implementation
/implement --type api              # API endpoint implementation
/implement --type service          # Service layer implementation
/implement --type feature          # Complete feature implementation

# Execution modes (from dd/implement-enhanced functionality)
/implement --mode quick            # Fast execution with minimal analysis
/implement --mode thorough         # Complete analysis and verification (default)
/implement --mode parallel         # Maximum parallelization
/implement --dry-run               # Preview execution plan without implementing

# Advanced options
/implement --parallel-agents 6     # Number of agents to spawn
/implement --max-retries 2         # Maximum retry attempts for failed tasks
/implement --verify-only           # Run verification on existing implementation
/implement --continue              # Resume from previous interrupted execution
```

## Agent Orchestration by Scope

### Task Discovery Scope (--scope tasks)
```yaml
workflow_agents:
  discovery_phase:
    - spec-decomposer: "Decompose requirements into atomic tasks and create beads issues"

  implementation_phase:
    - general-purpose: "Handle generic implementation tasks"
    - frontend-developer: "Implement UI/UX related tasks"
    - backend-architect: "Handle backend architecture and API tasks"
    - test-automation-specialist: "Implement testing-related tasks"
    - database-architect: "Handle database and data model tasks"

  verification_phase:
    - implementation-verifier: "Verify all completed tasks against specifications"
    - security-engineer: "Security validation of implemented changes"
    - performance-engineer: "Performance validation of implementations"
```

### Feature Development Scope (--scope feature)
```yaml
feature_workflow_agents:
  analysis_phase:
    - requirement-mapper: "Map feature requirements to implementation tasks"
    - architecture-analyzer: "Assess system context and integration points"

  design_phase:
    - backend-architect: "Design solution architecture"
    - database-architect: "Design data models if needed"
    - frontend-architect: "Design UI/UX patterns if needed"

  implementation_phase:
    component_implementation:
      - ui-component-specialist: "Create UI components"
      - test-builder: "Create component tests"
      - documentation-specialist: "Document component usage"

    api_implementation:
      - api-builder: "Create API endpoints using patterns from api-developer"
      - auth-builder: "Implement authentication/authorization"
      - test-builder: "Create API tests"

    service_implementation:
      - service-builder: "Create service layer"
      - middleware-builder: "Implement middleware components"
      - database-builder: "Create database operations"
```

### Atomic Execution Scope (--scope atomic)
```yaml
atomic_workflow_agents:
  execution_phase:
    - file-operations: "Handle file system operations"
    - code-generator: "Generate boilerplate code"
    - config-builder: "Handle configuration changes"
    - git-operations: "Manage version control operations"

  validation_phase:
    - data-validator: "Validate data integrity"
    - test-builder: "Execute tests for atomic changes"
    - code-reviewer: "Review code quality"
```

## Workflow Execution Patterns

### Discovery-Based Implementation (--scope tasks)
```bash
# Step 1: Task Discovery
Use spec-decomposer to "decompose requirements into atomic tasks and create beads issues via bd create"

# Step 2: Parallel Task Execution
Use general-purpose to "execute tasks requiring general implementation"
Use frontend-developer to "implement UI/component-related tasks"
Use backend-architect to "implement API and backend tasks"
Use test-automation-specialist to "implement testing tasks"

# Step 3: Verification and Validation
Use implementation-verifier to "verify all completed tasks against original specifications"
Use security-engineer to "validate security implications of all changes"
```

### Feature-Driven Implementation (--scope feature)
```bash
# Step 1: Requirements Analysis
Use requirement-mapper to "parse feature requirements and create implementation plan"
Use architecture-analyzer to "assess system context and integration requirements"

# Step 2: Implementation Based on Type
# For --type component:
Use ui-component-specialist to "create reusable UI components with proper styling and accessibility"
Use test-builder to "create comprehensive component tests including unit and integration"

# For --type api:
Use api-builder to "create RESTful endpoints following api-developer patterns"
Use auth-builder to "implement proper authentication and authorization"
Use database-builder to "create necessary database operations"

# For --type service:
Use service-builder to "create business logic services"
Use middleware-builder to "implement necessary middleware components"
```

### Atomic Implementation (--scope atomic)
```bash
# Direct execution for small, focused tasks
Use file-operations to "handle file system operations efficiently"
Use code-generator to "generate necessary boilerplate code"
Use config-builder to "update configuration files as needed"
```

## Configuration Matrix

| Scope | Type | Primary Agents | Verification Level | Parallelization |
|-------|------|----------------|-------------------|-----------------|
| `tasks` | (auto-detected) | spec-decomposer + domain specialists | Full verification | High (6+ agents) |
| `feature` | `component` | ui-component-specialist + test-builder | UI + accessibility | Medium (3-4 agents) |
| `feature` | `api` | api-builder + auth-builder + database-builder | Security + performance | Medium (3-4 agents) |
| `feature` | `service` | service-builder + middleware-builder | Business logic + integration | Medium (3-4 agents) |
| `atomic` | (single operation) | Utility agents | Basic validation | Low (1-2 agents) |

## Execution Modes

### Quick Mode (--mode quick)
```yaml
quick_mode_configuration:
  analysis_depth: minimal
  agents_spawned: 3
  verification_level: basic
  parallel_execution: false
  retry_attempts: 1

  optimizations:
    - skip_deep_analysis: true
    - minimal_decomposition: true
    - basic_validation_only: true
    - fast_execution_path: true
```

### Thorough Mode (--mode thorough, default)
```yaml
thorough_mode_configuration:
  analysis_depth: complete
  agents_spawned: 6
  verification_level: comprehensive
  parallel_execution: true
  retry_attempts: 2

  validations:
    - security_scan: true
    - performance_check: true
    - quality_analysis: true
    - test_coverage_validation: true
```

### Parallel Mode (--mode parallel)
```yaml
parallel_mode_configuration:
  analysis_depth: optimized_for_parallelization
  agents_spawned: 10
  verification_level: distributed
  parallel_execution: maximum
  retry_attempts: 3

  optimizations:
    - wave_based_execution: true
    - dependency_aware_scheduling: true
    - resource_optimization: true
    - conflict_resolution: true
```

## Advanced Features

### Intelligent Task Routing
```yaml
task_routing_algorithm:
  security_tasks:
    keywords: [auth, security, encrypt, validate, sanitize]
    route_to: security-engineer
    verification: mandatory

  performance_tasks:
    keywords: [optimize, performance, cache, scale, benchmark]
    route_to: performance-engineer
    verification: performance_metrics_required

  ui_tasks:
    keywords: [component, ui, frontend, style, responsive]
    route_to: ui-component-specialist
    verification: accessibility_compliance

  api_tasks:
    keywords: [api, endpoint, route, service, integration]
    route_to: api-builder
    verification: api_contract_compliance
```

### Progress Tracking and Reporting
```yaml
progress_tracking:
  real_time_updates:
    - task_status_changes: "Update task-manager with progress before and after each task"
    - agent_activity_monitoring: "Track active agents and their current tasks"
    - completion_percentage: "Calculate and display overall progress"

  completion_reporting:
    - execution_summary: "Generate detailed report of all completed tasks"
    - agent_performance_metrics: "Track agent efficiency and success rates"
    - verification_results: "Comprehensive validation summary"
    - recommendations: "Suggest improvements for future implementations"
```

### Error Handling and Recovery
```yaml
error_handling_strategies:
  agent_failure:
    action: "Reassign task to backup agent with similar expertise"
    fallback_agents:
      - security-engineer: [code-reviewer, qa-specialist]
      - performance-engineer: [performance-analyzer, code-analyzer]
      - ui-component-specialist: [frontend-developer, component-builder]

  task_failure:
    action: "Analyze failure reason and attempt with different approach"
    retry_strategies:
      - decompose_further: "Break failed task into smaller atomic tasks"
      - change_agent: "Try with different specialist agent"
      - manual_intervention: "Flag for human review if retries exhausted"

  verification_failure:
    action: "Re-implement with stricter validation criteria"
    validation_enhancement:
      - increase_test_coverage: "Add more comprehensive tests"
      - security_audit: "Perform additional security validation"
      - performance_validation: "Add performance benchmarking"
```

## Domain-Specific Examples

### Trading Platform Implementation
```bash
/implement --scope feature --type api --domain trading
```
**Specialized Agent Selection:**
```
Use quantitative-analyst to "validate trading algorithm implementations against risk rules"
Use risk-management-analyst to "ensure position sizing and risk controls are properly implemented"
Use security-engineer to "validate trading data security and regulatory compliance"
```

### Full-Stack Feature Implementation
```bash
/implement --scope feature --type feature --mode thorough
```
**Complete Feature Stack:**
```
Use backend-architect to "implement backend services and API endpoints"
Use frontend-architect to "implement user interface and user experience"
Use database-architect to "implement data models and database operations"
Use test-automation-specialist to "create comprehensive test coverage across all layers"
```

### Microservices Implementation
```bash
/implement --scope tasks --mode parallel --focus microservices
```
**Distributed Implementation:**
```
Use service-builder to "implement individual microservice components"
Use api-gateway-architect to "configure service mesh and routing"
Use config-builder to "set up service configuration and environment variables"
Use deployment-engineer to "implement deployment and orchestration configurations"
```

## Integration with Other Commands

### Pre-Implementation Flow
```bash
# 1. Decompose complex requirements first
/decompose-tasks --mode comprehensive

# 2. Then implement the decomposed tasks
/implement --scope tasks --mode thorough
```

### Post-Implementation Flow
```bash
# 1. Implement features
/implement --scope feature --type api

# 2. Commit changes with analysis
/commit --thorough --security

# 3. Create pull request
/create-pr --template feature
```

## Performance Metrics and Optimization

### Expected Performance Improvements
```yaml
performance_targets:
  task_discovery_time:
    baseline: "5-10 minutes manual analysis"
    target: "30-60 seconds automated discovery"
    improvement: "85-90% time reduction"

  implementation_speed:
    baseline: "2-4 hours per complex task"
    target: "20-40 minutes with parallel agents"
    improvement: "80-85% time reduction"

  verification_coverage:
    baseline: "60-70% manual verification"
    target: "95%+ automated verification"
    improvement: "35-40% coverage increase"
```

### Quality Assurance
```yaml
quality_metrics:
  implementation_accuracy:
    target: "95%+ successful implementation on first attempt"
    measurement: "Task completion without requiring rework"

  code_quality_improvement:
    target: "Average quality score increase of +1.5 points"
    measurement: "Before/after code quality analysis"

  security_compliance:
    target: "100% security validation pass rate"
    measurement: "Automated security scan results"
```

## Deterministic Triggers

### Use implement when:
- Tasks have been discovered in documentation and need implementation
- Specific features need to be developed (components, APIs, services)
- Atomic operations need to be executed with verification
- Multiple parallel implementations are required

### Do NOT use implement when:
- Tasks need to be decomposed first (use decompose-tasks)
- Only building/compiling is needed (use build)
- Only committing changes (use commit)
- Creating pull requests (use create-pr)

## Validation and Verification Framework

### Multi-Level Verification
```yaml
verification_levels:
  basic_validation:
    checks: [syntax_valid, files_created, basic_functionality]
    agents: [code-reviewer]
    confidence_threshold: 80

  comprehensive_validation:
    checks: [security_scan, performance_test, integration_test, code_quality]
    agents: [security-engineer, performance-engineer, test-automation-specialist, code-reviewer]
    confidence_threshold: 95

  domain_specific_validation:
    trading_domain: [risk_analysis, regulatory_compliance, algorithm_validation]
    web_application: [accessibility_compliance, security_validation, performance_benchmarks]
    microservices: [service_mesh_validation, contract_testing, deployment_verification]
```