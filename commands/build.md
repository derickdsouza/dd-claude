---
name: build
aliases: [build-parallel, bp, parallel-build]
description: Unified build orchestration with sequential and parallel execution modes. NEVER implements code - that is handled by implement. Use when: project compilation needed OR build artifacts required OR deployment preparation needed
---

# /build - Unified Build Orchestration Workflow

**Purpose**: Coordinate multiple specialized agents for intelligent build execution with sequential and parallel modes, supporting development, production, and testing builds across different project types.

## Command Syntax

```bash
# Basic build (auto-detect mode and type)
/build

# Execution mode selection
/build --mode sequential        # Traditional sequential build
/build --mode parallel         # Wave-based parallel execution (default)

# Build type specification
/build --type dev              # Development build with debug symbols
/build --type prod             # Production build with optimizations
/build --type test             # Test build with coverage instrumentation

# Advanced options
/build --clean                 # Clean build artifacts before building
/build --optimize              # Enable all optimization features
/build --complexity simple     # Build complexity: simple|standard|complex|enterprise
/build --focus security        # Build focus: security|performance|quality
/build --parallel-agents 6     # Number of parallel agents (parallel mode only)
/build --dry-run              # Preview build plan without execution
```

## Agent Orchestration by Mode

### Sequential Mode (--mode sequential)
```yaml
sequential_workflow:
  pre_build_analysis:
    - code-analyzer: "Assess project structure and build requirements"
    - dependency-analyzer: "Validate dependencies and build order"
    - config-builder: "Verify build configuration files"

  build_execution:
    - general-purpose: "Execute build steps in order"
    - performance-engineer: "Monitor build performance and optimization"

  post_build_validation:
    - test-automation-specialist: "Run post-build validation tests"
    - security-engineer: "Perform security validation of build artifacts"

  execution_pattern: linear
  parallelization: none
  agent_coordination: sequential_handoff
```

### Parallel Mode (--mode parallel, default)
```yaml
parallel_workflow:
  phase_1_analysis:
    agents:
      - spec-decomposer: "Analyze build requirements and break down into atomic tasks with rule-based agent assignments"
      - task-manager: "Initialize tracking system and coordinate dependency-aware parallel execution"
      - code-analyzer: "Assess project complexity and build patterns"
      - dependency-analyzer: "Create build dependency graph"

  phase_2_preparation:
    wave_1:
      - config-builder: "Prepare build configurations"
      - file-operations: "Clean and prepare build directories"
    wave_2:
      - dependency-analyzer: "Resolve and validate all dependencies"
      - performance-engineer: "Set up build performance monitoring"

  phase_3_parallel_execution:
    wave_1_compilation:
      - frontend-developer: "Build frontend assets and components"
      - backend-architect: "Compile backend services and APIs"
      - database-builder: "Prepare database schemas and migrations"

    wave_2_optimization:
      - performance-engineer: "Apply build optimizations and bundling"
      - security-engineer: "Security scanning and validation"
      - test-automation-specialist: "Compile test suites"

    wave_3_integration:
      - deployment-engineer: "Prepare deployment artifacts"
      - documentation-specialist: "Generate build documentation"

  phase_4_validation:
    - implementation-verifier: "Validate all build artifacts against specifications"
    - qa-specialist: "Quality assurance validation"
    - test-automation-specialist: "Execute build verification tests"

  execution_pattern: wave_based
  parallelization: high
  performance_improvement: "3-5x faster than sequential"
```

## Build Type Configurations

### Development Build (--type dev)
```yaml
development_build:
  optimization_level: minimal
  debug_symbols: enabled
  source_maps: enabled
  hot_reload: enabled
  minification: disabled
  compression: disabled

  agents_focus:
    - frontend-developer: "Fast compilation with hot reload support"
    - backend-architect: "Development server setup with auto-restart"
    - test-automation-specialist: "Development test runner setup"

  validation_level: basic
  security_scanning: essential_only
  performance_profiling: disabled

  expected_time: "30-90 seconds"
  artifacts: "Development binaries with debug info"
```

### Production Build (--type prod)
```yaml
production_build:
  optimization_level: maximum
  debug_symbols: stripped
  source_maps: disabled
  minification: enabled
  compression: enabled
  tree_shaking: enabled

  agents_focus:
    - frontend-developer: "Optimized frontend bundle with code splitting"
    - backend-architect: "Optimized backend compilation with dead code elimination"
    - performance-engineer: "Advanced optimization and bundle analysis"
    - security-engineer: "Comprehensive security scanning and validation"

  validation_level: comprehensive
  security_scanning: full_suite
  performance_profiling: enabled

  expected_time: "2-5 minutes"
  artifacts: "Optimized production-ready binaries"
```

### Test Build (--type test)
```yaml
test_build:
  optimization_level: minimal
  debug_symbols: enabled
  code_coverage: enabled
  test_instrumentation: enabled
  mock_services: enabled

  agents_focus:
    - test-automation-specialist: "Test runner compilation with coverage"
    - backend-architect: "Test database and service setup"
    - frontend-developer: "Test environment UI compilation"

  validation_level: test_focused
  security_scanning: test_environment_only
  performance_profiling: test_performance_only

  expected_time: "1-3 minutes"
  artifacts: "Test binaries with coverage instrumentation"
```

## Build Focus Areas

### Security Focus (--focus security)
```yaml
security_focused_build:
  primary_agents:
    - security-engineer: "Lead security validation and scanning"
    - dependency-analyzer: "Security vulnerability scanning"
    - code-analyzer: "Security pattern analysis"

  security_validations:
    - dependency_vulnerabilities: "Scan all dependencies for known vulnerabilities"
    - static_analysis: "SAST scanning for security issues"
    - secrets_detection: "Scan for hardcoded secrets and credentials"
    - compliance_check: "Validate against security compliance requirements"

  build_modifications:
    - security_headers: "Add security headers to web builds"
    - certificate_validation: "Validate SSL/TLS certificates"
    - signature_verification: "Code signing and signature verification"
```

### Performance Focus (--focus performance)
```yaml
performance_focused_build:
  primary_agents:
    - performance-engineer: "Lead performance optimization"
    - code-analyzer: "Performance pattern analysis"
    - frontend-developer: "Frontend performance optimization"

  performance_optimizations:
    - bundle_optimization: "Advanced bundling and code splitting"
    - compression: "Maximum compression algorithms"
    - caching_strategies: "Build-time caching optimization"
    - dead_code_elimination: "Aggressive unused code removal"

  performance_validation:
    - bundle_size_analysis: "Monitor and report bundle sizes"
    - build_time_profiling: "Profile and optimize build performance"
    - runtime_performance: "Validate runtime performance characteristics"
```

### Quality Focus (--focus quality)
```yaml
quality_focused_build:
  primary_agents:
    - qa-specialist: "Lead quality assurance"
    - code-reviewer: "Code quality validation"
    - test-automation-specialist: "Comprehensive testing"

  quality_validations:
    - code_quality_metrics: "Validate code quality scores"
    - test_coverage: "Ensure minimum test coverage thresholds"
    - linting_validation: "Comprehensive linting and style checking"
    - documentation_validation: "Validate documentation completeness"

  quality_enhancements:
    - static_analysis: "Advanced static code analysis"
    - complexity_analysis: "Code complexity measurement and validation"
    - maintainability_assessment: "Maintainability score calculation"
```

## Project Type Detection and Optimization

### Frontend Projects
```yaml
frontend_build_optimization:
  detection_patterns:
    - package_json: "contains react, vue, angular, or svelte"
    - build_tools: "webpack, vite, rollup, or parcel configuration"
    - asset_directories: "src/, public/, assets/ directories"

  specialized_agents:
    - frontend-developer: "Lead frontend compilation and optimization"
    - ui-component-specialist: "Component library building"
    - performance-engineer: "Frontend performance optimization"

  build_optimizations:
    - code_splitting: "Intelligent code splitting for optimal loading"
    - asset_optimization: "Image and media optimization"
    - css_optimization: "CSS purging and optimization"
    - service_worker: "Service worker generation for PWA"
```

### Backend Projects
```yaml
backend_build_optimization:
  detection_patterns:
    - server_frameworks: "express, fastify, django, spring, etc."
    - api_definitions: "OpenAPI specs, GraphQL schemas"
    - database_configs: "Database configuration files"

  specialized_agents:
    - backend-architect: "Lead backend compilation and architecture"
    - api-builder: "API documentation and contract generation"
    - database-builder: "Database migration and schema compilation"

  build_optimizations:
    - api_documentation: "Automatic API documentation generation"
    - database_migrations: "Database schema compilation and validation"
    - service_containerization: "Docker image optimization"
```

### Full-Stack Projects
```yaml
fullstack_build_optimization:
  detection_patterns:
    - monorepo_structure: "Frontend and backend in same repository"
    - shared_dependencies: "Shared libraries and utilities"
    - deployment_configs: "Full-stack deployment configurations"

  specialized_agents:
    - backend-architect: "Backend service compilation"
    - frontend-developer: "Frontend application building"
    - api-builder: "API contract validation and documentation"
    - deployment-engineer: "Integrated deployment artifact preparation"

  build_coordination:
    - dependency_resolution: "Resolve shared dependencies across stack"
    - api_contract_validation: "Validate frontend-backend API contracts"
    - integrated_testing: "Full-stack integration testing"
```

## Advanced Build Features

### Wave-Based Parallel Execution
```yaml
wave_execution_strategy:
  wave_1_foundation:
    description: "Independent foundational tasks"
    agents: ["config-builder", "file-operations", "dependency-analyzer"]
    dependencies: none
    estimated_time: "10-30 seconds"

  wave_2_compilation:
    description: "Core compilation tasks"
    agents: ["frontend-developer", "backend-architect", "database-builder"]
    dependencies: ["wave_1_foundation"]
    estimated_time: "30-120 seconds"

  wave_3_optimization:
    description: "Optimization and validation"
    agents: ["performance-engineer", "security-engineer", "test-automation-specialist"]
    dependencies: ["wave_2_compilation"]
    estimated_time: "30-90 seconds"

  wave_4_finalization:
    description: "Final artifacts and documentation"
    agents: ["deployment-engineer", "documentation-specialist", "implementation-verifier"]
    dependencies: ["wave_3_optimization"]
    estimated_time: "15-45 seconds"
```

### Intelligent Build Caching
```yaml
caching_strategy:
  dependency_caching:
    - cache_key: "package.json + lock files hash"
    - invalidation: "dependency changes"
    - storage: "local + distributed cache"

  compilation_caching:
    - cache_key: "source file hash + compiler version"
    - invalidation: "source file changes or compiler updates"
    - granularity: "file-level caching"

  artifact_caching:
    - cache_key: "build configuration + source hash"
    - invalidation: "configuration or source changes"
    - optimization: "incremental builds"
```

### Build Quality Gates
```yaml
quality_gates:
  compilation_gates:
    - zero_compilation_errors: "Build must compile without errors"
    - warning_threshold: "Maximum 5 compilation warnings"
    - dependency_resolution: "All dependencies must resolve"

  security_gates:
    - vulnerability_scan: "No high or critical vulnerabilities"
    - secrets_detection: "No hardcoded secrets detected"
    - license_compliance: "All dependencies have compatible licenses"

  performance_gates:
    - bundle_size_limit: "Frontend bundles under size threshold"
    - build_time_limit: "Build must complete within time threshold"
    - memory_usage_limit: "Build memory usage under limit"

  quality_gates:
    - test_coverage: "Minimum test coverage percentage"
    - code_quality_score: "Minimum code quality threshold"
    - documentation_coverage: "API documentation completeness"
```

## Error Handling and Recovery

### Build Failure Recovery
```yaml
failure_recovery_strategies:
  dependency_failures:
    detection: "dependency resolution errors"
    recovery_actions:
      - clear_cache: "Clear dependency cache and retry"
      - fallback_registry: "Try alternative package registries"
      - version_rollback: "Attempt with previous working versions"

  compilation_failures:
    detection: "compilation errors or timeouts"
    recovery_actions:
      - incremental_build: "Attempt incremental compilation"
      - memory_optimization: "Increase build memory allocation"
      - parallel_reduction: "Reduce parallel build workers"

  resource_exhaustion:
    detection: "out of memory or disk space"
    recovery_actions:
      - cleanup_artifacts: "Clean temporary build artifacts"
      - reduce_parallelism: "Reduce concurrent build processes"
      - chunk_size_reduction: "Reduce build chunk sizes"
```

### Rollback Mechanisms
```yaml
rollback_strategies:
  configuration_rollback:
    trigger: "build configuration errors"
    action: "restore previous working configuration"
    validation: "test with known good configuration"

  dependency_rollback:
    trigger: "dependency compatibility issues"
    action: "restore previous dependency versions"
    validation: "verify functionality with rolled-back dependencies"

  artifact_rollback:
    trigger: "build artifact corruption or validation failure"
    action: "restore previous successful build artifacts"
    validation: "comprehensive artifact integrity check"
```

## Integration with Development Workflow

### Pre-Build Validation
```bash
# Validate build requirements before starting
Use dependency-analyzer to "validate all dependencies are available and compatible"
Use config-builder to "verify build configuration completeness and correctness"
Use code-analyzer to "check for obvious compilation issues"
```

### Post-Build Actions
```bash
# After successful build
Use test-automation-specialist to "execute post-build test suite"
Use security-engineer to "perform security validation of build artifacts"
Use deployment-engineer to "prepare artifacts for deployment"
Use documentation-specialist to "update build documentation and changelogs"
```

### Continuous Integration Integration
```yaml
ci_integration:
  build_triggers:
    - push_to_main: "trigger production build"
    - pull_request: "trigger test build with validation"
    - nightly: "trigger comprehensive build with full validation"

  build_matrix:
    - environment: ["dev", "staging", "production"]
    - node_version: ["16", "18", "20"]
    - optimization: ["debug", "release"]

  artifact_management:
    - artifact_retention: "keep last 10 successful builds"
    - artifact_distribution: "distribute to staging and production environments"
    - artifact_validation: "comprehensive integrity and security validation"
```

## Performance Metrics and Monitoring

### Build Performance Tracking
```yaml
performance_metrics:
  build_time_tracking:
    - total_build_time: "end-to-end build duration"
    - phase_breakdown: "time spent in each build phase"
    - agent_performance: "individual agent execution times"

  resource_utilization:
    - cpu_usage: "CPU utilization during build"
    - memory_consumption: "Peak and average memory usage"
    - disk_io: "Disk read/write operations"
    - network_usage: "Network bandwidth for dependency downloads"

  build_efficiency:
    - cache_hit_rate: "percentage of cached artifacts used"
    - parallelization_efficiency: "actual vs theoretical parallel speedup"
    - resource_efficiency: "resource utilization effectiveness"
```

### Quality Metrics
```yaml
quality_metrics:
  build_reliability:
    - success_rate: "percentage of successful builds"
    - failure_recovery_rate: "percentage of automatic failure recoveries"
    - consistency: "build reproducibility across environments"

  artifact_quality:
    - security_score: "security validation results"
    - performance_score: "performance benchmark results"
    - code_quality_score: "static analysis quality metrics"

  process_quality:
    - automation_coverage: "percentage of automated build steps"
    - validation_coverage: "percentage of validated build outputs"
    - documentation_completeness: "build process documentation coverage"
```

## Deterministic Triggers

### Use build when:
- Project compilation and artifact generation is needed
- Deployment preparation requires build artifacts
- Testing requires compiled test binaries
- Development environment setup needs build outputs
- CI/CD pipeline requires automated building

### Do NOT use build when:
- Only source code implementation is needed (use implement)
- Only task planning and decomposition required (use decompose-tasks)
- Only committing source code changes (use commit)
- Only running tests on existing builds (use test command)

## Advanced Configuration Options

### Custom Build Profiles
```yaml
build_profiles:
  microservices_profile:
    parallel_service_builds: true
    service_dependency_resolution: true
    container_optimization: true
    service_mesh_preparation: true

  monorepo_profile:
    shared_dependency_optimization: true
    incremental_builds: true
    workspace_aware_caching: true
    cross_package_validation: true

  enterprise_profile:
    comprehensive_security_scanning: true
    compliance_validation: true
    audit_trail_generation: true
    enterprise_quality_gates: true
```

### Environment-Specific Optimizations
```yaml
environment_optimizations:
  development:
    fast_compilation: true
    hot_reload_support: true
    debug_symbol_preservation: true
    minimal_optimization: true

  staging:
    production_like_optimization: true
    performance_validation: true
    security_scanning: true
    integration_testing: true

  production:
    maximum_optimization: true
    comprehensive_validation: true
    security_hardening: true
    performance_monitoring: true
```