# Agent-Agnostic Command Templates

**Version**: 1.0.0  
**Compatible With**: ChatGPT, Claude, Gemini, Custom Agents  
**Framework**: SSOT + Diátaxis Documentation

---

## Universal Prompt Structure

All prompts in this framework follow a standardized structure designed to work consistently across different AI agents:

```
CONTEXT: [Relevant background information and current state]
TASK: [Specific action or output required]
FORMAT: [Expected output format and structure]
CONSTRAINTS: [Limitations, requirements, and quality standards]
EXAMPLE: [Sample output or template if helpful]
```

### Prompt Structure Guidelines

1. **CONTEXT**: Provide sufficient background for the AI to understand the situation
2. **TASK**: Be specific about what you want the AI to produce
3. **FORMAT**: Specify exact output format (Markdown, YAML, JSON, etc.)
4. **CONSTRAINTS**: Include quality requirements, limits, and standards
5. **EXAMPLE**: Show sample output when the format is complex

---

## Core Documentation Generation Prompts

### 1. Purpose Specification Generation

#### Basic Purpose Prompt
```
CONTEXT: I'm starting a new project called [PROJECT_NAME]. The initial idea is [BRIEF_DESCRIPTION]. The target users are [USER_DESCRIPTION]. The main problem we're solving is [PROBLEM_DESCRIPTION].
TASK: Generate a complete purpose specification following the SSOT framework.
FORMAT: Markdown file with exact sections: Problem Statement, Target Users, Scope (Included/Excluded), Success Criteria (minimum 3), Key Assumptions, Context & Constraints.
CONSTRAINTS:
- Maximum 500 words total
- Minimum 3 quantifiable success metrics with numeric targets
- At least 5 scope inclusions and 5 exclusions
- All technical terms must be defined or avoided
- Include specific user counts and metrics
- Problem statement must be quantified with current impact
EXAMPLE: 
Problem Statement: Manual order processing currently averages 45 minutes per order, causing 70% of customers to abandon carts and contributing to $50K monthly revenue loss.
```

#### Advanced Purpose Prompt (with Research)
```
CONTEXT: Based on initial research documented in [RESEARCH_FILE], we've identified [KEY_FINDINGS]. The market analysis shows [MARKET_DATA]. Competitor analysis reveals [COMPETITOR_INSIGHTS].
TASK: Generate a comprehensive purpose specification that incorporates research findings.
FORMAT: Markdown with sections: Problem Statement (with research-backed metrics), Target Users (with personas and counts), Scope (research-validated boundaries), Success Criteria (SMART goals), Key Assumptions (with validation methods), Context & Constraints (business case).
CONSTRAINTS:
- All claims must be backed by research evidence
- Include specific market size and user segment data
- Success criteria must have baseline and target metrics
- Assumptions must include validation approaches
- Maximum 500 words, densely packed with data
- Include competitive differentiation points
```

### 2. Functional Specification Generation

#### Standard Functional Spec Prompt
```
CONTEXT: Based on the approved purpose in specs/purpose.md for [PROJECT_NAME], we need to define functional requirements. The purpose states [PURPOSE_SUMMARY]. Key user needs identified are [USER_NEEDS].
TASK: Generate a complete functional specification.
FORMAT: Markdown with sections: Feature Overview, User Journeys (minimum 3), Acceptance Criteria (testable with thresholds), Data Requirements, Integration Points.
CONSTRAINTS:
- Each user journey must include measurable success metrics
- Acceptance criteria must be testable and specific with numeric thresholds
- Include data flow diagrams using Mermaid syntax
- Reference the purpose specification directly
- Minimum 3 user journeys covering different personas
- Each acceptance criterion must be verifiable
EXAMPLE:
User Journey 1: New Customer Onboarding
- Success Metric: 90% of new customers complete onboarding in <5 minutes
- Steps: Account creation → Profile setup → First action → Success confirmation
```

#### API-Focused Functional Spec Prompt
```
CONTEXT: This project is primarily an API service for [API_PURPOSE]. The purpose specification defines [PURPOSE_SUMMARY]. We need to focus on API contracts and data flows.
TASK: Generate an API-focused functional specification.
FORMAT: Markdown with sections: API Overview, Endpoint Specifications, Data Models, Authentication & Authorization, Rate Limiting, Error Handling, Integration Examples.
CONSTRAINTS:
- Include OpenAPI/Swagger specification snippets
- Define exact request/response schemas
- Include authentication flow diagrams
- Specify rate limits and quotas
- Provide curl examples for each endpoint
- Error responses must follow consistent format
- Include versioning strategy
```

### 3. Technical Specification Generation

#### Standard Technical Spec Prompt
```
CONTEXT: Based on the functional specification in specs/functional_spec.md for [PROJECT_NAME], we need technical implementation details. The functional requirements include [FUNCTIONAL_SUMMARY].
TASK: Generate a comprehensive technical specification.
FORMAT: Markdown with sections: Architecture Overview (with Mermaid diagrams), Technology Stack (with versions), Component Design, Performance Requirements (with target/max thresholds), Security Considerations, Deployment Architecture.
CONSTRAINTS:
- Include system architecture diagram using Mermaid
- Specify exact versions for all technologies
- Include performance benchmarks with measurable targets and maximums
- Address security requirements with specific standards
- Define scaling strategy and capacity planning
- Include monitoring and observability requirements
- Specify data storage and backup strategies
EXAMPLE:
Performance Requirements:
| Operation | Target | Max Acceptable | Measurement Method |
|-----------|--------|----------------|-------------------|
| API response time | <100ms | <500ms | 95th percentile |
| Database query | <50ms | <200ms | Average response |
```

#### Microservices Technical Spec Prompt
```
CONTEXT: This project uses microservices architecture for [PROJECT_NAME]. The functional spec defines [FUNCTIONAL_SUMMARY]. We need detailed service specifications.
TASK: Generate microservices technical specification.
FORMAT: Markdown with sections: Service Architecture, Service Specifications (per service), Inter-Service Communication, Data Management, Service Discovery, Configuration Management, Monitoring & Logging.
CONSTRAINTS:
- Define service boundaries and responsibilities
- Include service interaction diagrams
- Specify communication protocols (REST, gRPC, messaging)
- Define data consistency patterns
- Include circuit breaker and retry patterns
- Specify service mesh requirements
- Include deployment strategies per service
```

### 4. Architecture Decision Records (ADRs)

#### Standard ADR Prompt
```
CONTEXT: We need to decide on [TECHNICAL_DECISION] for our project [PROJECT_NAME]. Current situation: [CURRENT_STATE]. Options being considered: [OPTION_A], [OPTION_B], [OPTION_C]. We have constraints: [CONSTRAINTS].
TASK: Create an Architecture Decision Record (ADR) following the SSOT template.
FORMAT: Markdown with sections: Context, Decision, Consequences (Positive/Negative/Neutral), Alternatives Considered, Related Decisions.
CONSTRAINTS:
- Include specific evidence for the decision
- List at least 2 alternatives with detailed rejection rationale
- Document measurable consequences where possible
- Reference relevant standards or best practices
- Include implementation considerations
- Consider long-term maintenance impact
EXAMPLE:
Decision: Use PostgreSQL as primary database
Evidence: Requires ACID compliance, team has PostgreSQL expertise, cloud provider offers managed PostgreSQL with 99.99% SLA
```

#### Technology Selection ADR Prompt
```
CONTEXT: We're selecting technology for [TECHNOLOGY_AREA] in [PROJECT_NAME]. Requirements include [REQUIREMENTS]. Team expertise includes [TEAM_SKILLS]. Budget constraints: [BUDGET]. Timeline: [TIMELINE].
TASK: Create a comprehensive technology selection ADR.
FORMAT: Markdown with sections: Context, Decision, Consequences, Alternatives Considered (with detailed comparison table), Implementation Plan, Risk Mitigation.
CONSTRAINTS:
- Include detailed comparison matrix of alternatives
- Consider total cost of ownership (TCO)
- Address team learning curve and hiring implications
- Include vendor lock-in considerations
- Specify migration path if needed
- Consider community support and long-term viability
- Include proof-of-concept results if available
```

---

## Diátaxis Framework Prompts

### 1. Tutorial Generation

#### Getting Started Tutorial Prompt
```
CONTEXT: We have implemented [FEATURE_NAME] in [PROJECT_NAME]. The target users are [BEGINNER_USERS] with no prior experience. The main user journey is [USER_JOURNEY_SUMMARY].
TASK: Generate a step-by-step tutorial for beginners.
FORMAT: Tutorial with sections: Prerequisites, Learning Objectives, Step-by-Step Guide (with numbered steps), Practice Exercises, Summary, Next Steps.
CONSTRAINTS:
- Each step must be actionable and verifiable
- Include screenshots or visual descriptions where helpful
- Provide expected outcomes for each step
- Include troubleshooting tips for common issues
- Estimated completion time: 30-45 minutes
- No prior knowledge assumed
- Include hands-on exercises for reinforcement
EXAMPLE:
Step 1: Install the Application
1. Download the installer from [URL]
2. Run the installer with default settings
3. Verify installation by opening [APPLICATION]
Expected: Application opens and shows welcome screen
```

#### Advanced Tutorial Prompt
```
CONTEXT: Users have completed the basic tutorial for [FEATURE_NAME] and need to learn advanced techniques. Complex scenarios include [ADVANCED_SCENARIOS].
TASK: Generate an advanced tutorial covering complex use cases.
FORMAT: Tutorial with sections: Prerequisites (basic knowledge assumed), Advanced Concepts, Complex Scenarios, Best Practices, Performance Tips, Real-World Examples.
CONSTRAINTS:
- Assume basic familiarity with the feature
- Include complex, real-world scenarios
- Cover edge cases and error handling
- Include performance optimization techniques
- Provide integration examples with other tools
- Estimated completion time: 60-90 minutes
- Include challenge problems for advanced users
```

### 2. How-To Guide Generation

#### Problem-Solution How-To Prompt
```
CONTEXT: Users frequently encounter the problem [PROBLEM_DESCRIPTION] when using [FEATURE_NAME]. Current solutions are [CURRENT_SOLUTIONS]. We need a clear step-by-step solution.
TASK: Generate a how-to guide solving this specific problem.
FORMAT: How-To Guide with sections: Problem Description, Prerequisites, Solution Steps, Verification, Common Issues, Related Solutions.
CONSTRAINTS:
- Focus on one specific problem and solution
- Steps must be ordered and actionable
- Include verification steps to confirm success
- Address common pitfalls and mistakes
- Provide alternative approaches if applicable
- Estimated completion time: 10-15 minutes
- Include "What you'll need" checklist
EXAMPLE:
Problem: API requests are timing out after 30 seconds
Solution: Configure timeout settings and implement retry logic
```

#### Integration How-To Prompt
```
CONTEXT: Users need to integrate [FEATURE_NAME] with [EXTERNAL_SYSTEM]. The integration requirements are [INTEGRATION_REQUIREMENTS]. Common challenges include [INTEGRATION_CHALLENGES].
TASK: Generate an integration how-to guide.
FORMAT: How-To Guide with sections: Integration Overview, Prerequisites, Configuration Steps, Testing the Integration, Troubleshooting, Advanced Configuration.
CONSTRAINTS:
- Include specific configuration examples
- Provide test cases to verify integration
- Address security and authentication
- Include error handling best practices
- Consider different deployment environments
- Estimated completion time: 45-60 minutes
- Include code snippets and configuration files
```

### 3. Reference Material Generation

#### API Reference Prompt
```
CONTEXT: We have an API for [API_PURPOSE] with endpoints [ENDPOINT_LIST]. The technical specification is in [TECH_SPEC_FILE]. We need comprehensive reference documentation.
TASK: Generate complete API reference documentation.
FORMAT: Reference documentation with sections: Authentication, Base URL, Endpoints (with request/response examples), Error Codes, Rate Limits, SDK Examples.
CONSTRAINTS:
- Include every endpoint with full details
- Provide request/response examples in JSON
- Document all error codes with solutions
- Include authentication examples
- Provide code samples in multiple languages
- Use consistent formatting throughout
- Include pagination and filtering documentation
EXAMPLE:
GET /api/users
Description: Retrieve a list of users
Parameters:
- page (integer): Page number (default: 1)
- limit (integer): Items per page (default: 20, max: 100)
Response: Array of user objects
```

#### Configuration Reference Prompt
```
CONTEXT: Our application [APPLICATION_NAME] has configuration options in [CONFIG_FILES]. The settings include [SETTING_CATEGORIES]. Users need to understand all available options.
TASK: Generate comprehensive configuration reference.
FORMAT: Reference documentation with sections: Configuration Files, Settings by Category, Environment Variables, Examples, Best Practices.
CONSTRAINTS:
- Document every configuration option
- Include default values and allowed ranges
- Provide examples for common scenarios
- Explain dependencies between settings
- Include security considerations
- Use tables for structured data
- Provide validation rules
EXAMPLE:
Database Configuration:
- db.host (string): Database server hostname (default: localhost)
- db.port (integer): Database port (default: 5432, range: 1-65535)
- db.ssl_mode (enum): SSL mode (disabled, require, verify-ca, verify-full)
```

### 4. Explanation Documentation

#### Concept Explanation Prompt
```
CONTEXT: Users need to understand [CONCEPT_NAME] to effectively use [FEATURE_NAME]. Common misconceptions include [MISCONCEPTIONS]. The underlying principles are [PRINCIPLES].
TASK: Generate an in-depth explanation of the concept.
FORMAT: Explanation with sections: What is [Concept], Why It Matters, How It Works, Common Misconceptions, Real-World Analogies, Related Concepts.
CONSTRAINTS:
- Use clear, non-technical language where possible
- Include analogies and real-world examples
- Address common misconceptions directly
- Provide historical context if relevant
- Include visual descriptions or diagrams
- Connect to practical usage
- Target audience: intelligent non-experts
EXAMPLE:
What is Caching?
Caching is like keeping frequently used items on your desk instead of walking to the filing cabinet every time...
```

#### Architecture Explanation Prompt
```
CONTEXT: Our system uses [ARCHITECTURE_PATTERN] to solve [PROBLEM]. The key components are [COMPONENTS]. Data flows through the system as [DATA_FLOW].
TASK: Generate an architectural explanation document.
FORMAT: Explanation with sections: Architecture Overview, Key Components, Data Flow, Design Decisions, Trade-offs, Evolution Path.
CONSTRAINTS:
- Include high-level architecture diagram
- Explain the "why" behind design decisions
- Discuss trade-offs and alternatives
- Include performance characteristics
- Address scalability and reliability
- Use consistent terminology
- Include historical context and evolution
EXAMPLE:
Microservices Architecture:
Our system uses microservices to enable independent scaling and deployment of different business capabilities...
```

---

## Validation and Quality Assurance Prompts

### 1. SSOT Compliance Validation

#### Documentation Compliance Check Prompt
```
CONTEXT: Review the current project documentation in the specs/ directory for [PROJECT_NAME]. The SSOT framework requires specific files and content standards.
TASK: Validate SSOT framework compliance and identify gaps.
FORMAT: Structured report with sections: Compliance Status, Missing Artifacts, Quality Issues, Specific Recommendations, Priority Actions.
CONSTRAINTS:
- Check all required files exist and are properly formatted
- Validate cross-references are correct and complete
- Ensure measurable metrics are present and specific
- Verify diagram standards (Mermaid syntax)
- Check document word counts and content density
- Validate ID schemes and numbering consistency
- Include specific file paths and line numbers for issues
EXAMPLE:
Missing Artifacts:
- specs/architecture/adr_003_database_selection.md (referenced but not found)
- evidence/performance/baseline_metrics.json (required for technical spec)
Quality Issues:
- specs/purpose.md line 15: Success metric "improve performance" is not measurable
```

#### Cross-Reference Validation Prompt
```
CONTEXT: The project documentation includes multiple interconnected files. We need to ensure all references are accurate and complete.
TASK: Validate all cross-references and internal links.
FORMAT: Validation report with sections: Reference Summary, Broken Links, Inconsistent References, Missing Targets, Correction Recommendations.
CONSTRAINTS:
- Check every internal link and reference
- Validate feature IDs and ADR numbers
- Ensure bidirectional references where appropriate
- Check for orphaned documents (no incoming references)
- Validate diagram references and labels
- Include specific corrections needed
- Prioritize fixes by impact
EXAMPLE:
Broken Links:
- specs/functional_spec.md line 45: References F-007 which doesn't exist
- docs/how-to/api-integration.md line 12: Links to deleted endpoint guide
```

### 2. Content Quality Assessment

#### Quality Review Prompt
```
CONTEXT: Review the documentation file [FILE_PATH] for quality, completeness, and adherence to SSOT standards. The document type is [DOCUMENT_TYPE].
TASK: Perform comprehensive quality review.
FORMAT: Detailed review with sections: Overall Assessment, Strengths, Critical Issues, Improvement Recommendations, Compliance Score.
CONSTRAINTS:
- Evaluate clarity, specificity, and completeness
- Check for measurable metrics and quantifiable criteria
- Validate technical accuracy and consistency
- Verify adherence to template structure
- Assess user perspective and usefulness
- Provide specific, actionable feedback
- Include numerical quality scores
EXAMPLE:
Critical Issues:
- Line 23: "Fast response time" needs specific metric (target <100ms)
- Section 4: Missing error handling scenarios
- Diagram: Missing legend for component symbols
Compliance Score: 75/100 (needs improvement in measurability)
```

#### Measurability Assessment Prompt
```
CONTEXT: Many requirements in our specifications lack specific, measurable criteria. This makes validation and testing difficult.
TASK: Assess and improve measurability of requirements.
FORMAT: Assessment report with sections: Measurability Score, Non-Measurable Requirements, Suggested Metrics, Implementation Impact.
CONSTRAINTS:
- Identify all requirements without specific metrics
- Propose measurable alternatives for vague requirements
- Consider testing and validation implications
- Include baseline and target values where possible
- Address both functional and non-functional requirements
- Prioritize by criticality and testability
EXAMPLE:
Non-Measurable Requirements:
- "Improve user satisfaction" → "Achieve user satisfaction score ≥4.2/5.0"
- "Reduce errors" → "Decrease error rate from 5% to <1% of transactions"
```

---

## Maintenance and Update Prompts

### 1. Documentation Update Prompts

#### Change Impact Documentation Prompt
```
CONTEXT: We have implemented [CHANGE_DESCRIPTION] in [PROJECT_NAME]. The affected files are [AFFECTED_FILES]. The change impacts [IMPACTED_AREAS].
TASK: Update documentation to reflect the implemented changes.
FORMAT: Updated documentation with change tracking and impact analysis.
CONSTRAINTS:
- Update all affected documentation files
- Include change rationale and impact assessment
- Update cross-references and dependencies
- Add new examples or remove outdated ones
- Update performance metrics if affected
- Include migration notes if breaking changes
- Maintain consistency across all documents
EXAMPLE:
Updated specs/technical_spec.md:
- Added new API endpoint /api/v2/analytics
- Updated performance benchmarks for new feature
- Modified architecture diagram to include analytics service
```

#### Periodic Review Prompt
```
CONTEXT: It's time for the quarterly documentation review for [PROJECT_NAME]. The documentation was last updated [LAST_UPDATE_DATE]. Changes since then include [RECENT_CHANGES].
TASK: Conduct comprehensive documentation review and update.
FORMAT: Review report with sections: Currency Assessment, Accuracy Check, Completeness Gap Analysis, Update Recommendations, Action Plan.
CONSTRAINTS:
- Assess accuracy against current implementation
- Identify outdated information and screenshots
- Check for missing features or capabilities
- Evaluate user feedback and support tickets
- Review performance benchmarks against current metrics
- Update templates and examples if needed
- Prioritize updates by user impact
EXAMPLE:
Currency Assessment:
- 85% of documentation is current
- API reference needs updates for 3 new endpoints
- Tutorial screenshots show outdated UI (version 2.1 vs 2.4)
```

### 2. Automation and Integration Prompts

#### Validation Script Generation Prompt
```
CONTEXT: We need to automate validation of our SSOT documentation for [PROJECT_NAME]. Current manual checks include [MANUAL_CHECKS]. We want to catch issues automatically.
TASK: Generate validation scripts for automated documentation checking.
FORMAT: Python scripts with clear functions and documentation.
CONSTRAINTS:
- Check file existence and structure compliance
- Validate cross-references and links
- Verify measurable metrics presence
- Check diagram syntax and standards
- Include configurable rules and thresholds
- Provide clear error messages and suggestions
- Support continuous integration
EXAMPLE:
def validate_purpose_document(filepath):
    """Validate purpose document meets SSOT standards"""
    issues = []
    content = read_file(filepath)
    
    if word_count(content) > 500:
        issues.append("Document exceeds 500 word limit")
    
    if count_measurable_metrics(content) < 3:
        issues.append("Requires at least 3 measurable success metrics")
    
    return issues
```

#### Documentation Generation Automation Prompt
```
CONTEXT: We want to automate generation of routine documentation for [PROJECT_NAME]. Source data includes [DATA_SOURCES]. Target formats are [OUTPUT_FORMATS].
TASK: Create automation scripts for documentation generation.
FORMAT: Automation scripts with templates and data processing.
CONSTRAINTS:
- Pull data from multiple sources (API, database, files)
- Apply consistent formatting and templates
- Generate multiple output formats
- Include validation and quality checks
- Support scheduled and triggered generation
- Handle errors and data validation gracefully
- Maintain version control integration
EXAMPLE:
def generate_api_reference():
    """Generate API reference from OpenAPI spec"""
    spec = load_openapi_spec("api/openapi.yaml")
    reference = apply_template(spec, "api-reference-template.md")
    validate_reference(reference)
    save_file("docs/reference/api.md", reference)
    commit_to_git("Updated API reference")
```

---

## Specialized Prompts

### 1. Performance and Security Documentation

#### Performance Benchmark Documentation Prompt
```
CONTEXT: We need to document performance benchmarks for [PROJECT_NAME]. Test results are in [TEST_RESULTS_FILE]. The performance requirements are in [REQUIREMENTS_FILE].
TASK: Generate comprehensive performance documentation.
FORMAT: Performance documentation with sections: Benchmark Overview, Test Environment, Results Analysis, Trends, Thresholds, Optimization Recommendations.
CONSTRAINTS:
- Include specific test configurations and hardware
- Present results with clear tables and charts
- Define target and maximum thresholds
- Include historical trend analysis
- Provide optimization guidance
- Address different load scenarios
- Include measurement methodologies
EXAMPLE:
API Response Time Benchmarks:
| Endpoint | Target | 95th Percentile | 99th Percentile | Max Acceptable |
|----------|--------|-----------------|-----------------|----------------|
| GET /users | <50ms | 45ms | 78ms | <200ms |
| POST /orders | <100ms | 89ms | 145ms | <500ms |
```

#### Security Documentation Prompt
```
CONTEXT: Our application [APPLICATION_NAME] handles [DATA_TYPE] data and must comply with [COMPLIANCE_STANDARDS]. Security measures include [SECURITY_MEASURES].
TASK: Generate comprehensive security documentation.
FORMAT: Security documentation with sections: Threat Model, Security Controls, Compliance, Best Practices, Incident Response.
CONSTRAINTS:
- Address all relevant security domains
- Include specific implementation details
- Reference compliance requirements
- Provide code examples where appropriate
- Include monitoring and alerting procedures
- Document incident response procedures
- Address different user roles and permissions
EXAMPLE:
Authentication Security:
- JWT tokens with 256-bit signing keys
- Token expiration: 15 minutes (access), 7 days (refresh)
- Rate limiting: 100 requests per minute per IP
- Failed login lockout: 5 attempts, 30 minute cooldown
```

### 2. Migration and Deployment Documentation

#### Migration Guide Prompt
```
CONTEXT: Users need to migrate from [OLD_VERSION] to [NEW_VERSION] of [PROJECT_NAME]. Migration challenges include [MIGRATION_CHALLENGES]. Data changes are [DATA_CHANGES].
TASK: Generate comprehensive migration guide.
FORMAT: Migration guide with sections: Migration Overview, Prerequisites, Step-by-Step Process, Data Migration, Verification, Rollback Procedure.
CONSTRAINTS:
- Include detailed pre-migration checklist
- Provide step-by-step instructions with verification
- Address data backup and restoration
- Include rollback procedures for each step
- Estimate downtime and resource requirements
- Address different deployment scenarios
- Include troubleshooting for common issues
EXAMPLE:
Migration Steps:
1. Backup current database (estimated: 15 minutes)
2. Deploy new version (estimated: 10 minutes)
3. Run database migrations (estimated: 5 minutes)
4. Verify data integrity (estimated: 10 minutes)
5. Update configuration files (estimated: 5 minutes)
Total estimated time: 45 minutes
```

#### Deployment Documentation Prompt
```
CONTEXT: We need to document deployment procedures for [PROJECT_NAME] in [ENVIRONMENT_TYPES]. Deployment tools include [DEPLOYMENT_TOOLS]. Infrastructure requirements are [INFRASTRUCTURE].
TASK: Generate comprehensive deployment documentation.
FORMAT: Deployment documentation with sections: Architecture Overview, Prerequisites, Deployment Process, Configuration, Monitoring, Troubleshooting.
CONSTRAINTS:
- Cover all deployment environments (dev, staging, prod)
- Include infrastructure requirements and setup
- Provide step-by-step deployment procedures
- Document configuration management
- Include health checks and monitoring setup
- Address scaling and high availability
- Include security considerations
EXAMPLE:
Production Deployment:
1. Infrastructure setup: 3 app servers, 2 database servers, load balancer
2. Prerequisites: Docker 20.10+, Kubernetes 1.24+, SSL certificates
3. Deployment time: Approximately 30 minutes
4. Rolling update strategy: Zero downtime deployment
```

---

## Prompt Optimization Tips

### 1. Context Optimization

#### Effective Context Providing
- Include relevant file contents directly in the prompt
- Reference specific sections and line numbers
- Provide current state and recent changes
- Include user feedback or issues encountered
- Mention constraints and limitations

#### Context Examples
```
GOOD CONTEXT:
"Based on specs/purpose.md which states 'Reduce order processing time from 45 minutes to <5 minutes for 90% of orders', and the current implementation in src/order_processor.py showing average time of 38 minutes..."

BAD CONTEXT:
"The project needs to be faster and better..."
```

### 2. Task Specification

#### Clear Task Definition
- Use action verbs (Generate, Create, Analyze, Validate)
- Specify exact output requirements
- Define scope and boundaries
- Include success criteria
- Specify target audience

#### Task Examples
```
GOOD TASK:
"Generate a functional specification with exactly 3 user journeys, each including success metrics with specific percentage targets and time measurements"

BAD TASK:
"Write about what the project should do"
```

### 3. Constraint Engineering

#### Effective Constraints
- Be specific about metrics and thresholds
- Include format requirements exactly
- Define quality standards clearly
- Set realistic limits and boundaries
- Include validation criteria

#### Constraint Examples
```
GOOD CONSTRAINTS:
"- Maximum 500 words total
- Minimum 3 success metrics with numeric targets (e.g., 'reduce from X to Y')
- At least 5 scope inclusions and 5 exclusions
- All technical terms defined in-line or in glossary"

BAD CONSTRAINTS:
"Make it good and comprehensive"
```

---

## Troubleshooting Prompt Issues

### Common Problems and Solutions

#### Issue: AI Doesn't Follow Template Structure
**Problem**: Output doesn't match expected format
**Solution**: 
- Provide explicit format examples
- Break complex requests into smaller prompts
- Use "FORMAT MUST BE:" emphasis
- Include template file content directly

#### Issue: Generated Content Too Vague
**Problem**: Lacks specific metrics and details
**Solution**:
- Add specific constraints requiring numbers
- Provide examples of good vs bad output
- Include "BE SPECIFIC" in constraints
- Request quantifiable data explicitly

#### Issue: Cross-References Become Inconsistent
**Problem**: References don't match actual document structure
**Solution**:
- Always provide current document structure
- Use validation prompts to check references
- Include "Verify all references exist" in constraints
- Run reference validation after generation

#### Issue: Quality Varies Between AI Agents
**Problem**: Different agents produce different quality levels
**Solution**:
- Use validation framework consistently
- Adapt prompt complexity to agent capabilities
- Provide more detailed examples for less capable agents
- Use quality assessment prompts to evaluate output

---

## Advanced Prompt Techniques

### 1. Chain of Thought Prompts

#### Structured Thinking Process
```
CONTEXT: [Provide context]
TASK: [Specify task]
THINKING PROCESS:
1. First, analyze the requirements and constraints
2. Then, identify the key components needed
3. Next, structure the output according to the format
4. Finally, validate against all constraints
FORMAT: [Specify format]
CONSTRAINTS: [List constraints]
```

### 2. Few-Shot Learning Prompts

#### Example-Based Learning
```
CONTEXT: [Context description]
TASK: [Task description]
EXAMPLE 1:
Input: [Example input 1]
Output: [Example output 1]

EXAMPLE 2:
Input: [Example input 2]
Output: [Example output 2]

NOW, GENERATE:
Input: [Actual input]
Output:
```

### 3. Self-Validation Prompts

#### Built-in Quality Checks
```
CONTEXT: [Context]
TASK: [Task]
FORMAT: [Format]
CONSTRAINTS: [Constraints]

VALIDATION CHECKLIST:
- [ ] All constraints satisfied
- [ ] Format requirements met
- [ ] Quality standards achieved
- [ ] Cross-references accurate

After generating, review against this checklist and fix any issues.
```

---

## Conclusion

These agent-agnostic command templates provide a comprehensive foundation for generating high-quality documentation using any AI agent. The key principles are:

1. **Structured Prompts**: Clear context, task, format, and constraints
2. **Specific Requirements**: Measurable metrics and exact formats
3. **Quality Focus**: Built-in validation and compliance checking
4. **Adaptability**: Works across different AI platforms
5. **Continuous Improvement**: Iterative refinement based on results

Use these templates as starting points and adapt them to your specific project needs, AI agent capabilities, and organizational requirements. The validation framework ensures consistent quality regardless of which AI agent you use.