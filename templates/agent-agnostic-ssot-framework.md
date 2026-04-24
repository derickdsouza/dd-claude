# Agent-Agnostic SSOT Documentation Framework

**Version**: 1.0.0  
**Date**: 2025-01-24  
**Compatible With**: Any AI Agent (ChatGPT, Claude, Gemini, Custom Agents)

---

## Overview

The Agent-Agnostic Single Source of Truth (SSOT) Documentation Framework is a universal methodology for creating, managing, and maintaining project documentation using any AI assistant. This framework combines the SSOT approach with the Diátaxis documentation methodology to create clear, maintainable, and comprehensive project documentation.

### Core Philosophy

1. **Single Source of Truth**: All project knowledge lives in one structured location
2. **Diátaxis Framework**: Four documentation types - Tutorials, How-to Guides, Reference, Explanation
3. **Agent Agnostic**: Works with any AI system through standardized prompts
4. **Evidence-Based**: All decisions backed by documented evidence and validation
5. **Continuous Generation**: Documentation evolves with the project

### Key Benefits

- **Universal Compatibility**: Works with ChatGPT, Claude, Gemini, or any AI agent
- **Structured Approach**: Clear organization and predictable file locations
- **Quality Assurance**: Built-in validation and verification processes
- **Version Control Ready**: All documentation in text format, perfect for Git
- **Scalable**: Works for solo developers to large teams

---

## Framework Architecture

### Directory Structure

```
project-root/
├── docs/                          # Diátaxis documentation
│   ├── tutorials/                 # Learning-oriented (T1)
│   ├── how-to-guides/            # Problem-oriented (T2)
│   ├── reference/                # Information-oriented (T3)
│   └── explanation/              # Understanding-oriented (T4)
├── specs/                        # SSOT specifications
│   ├── architecture/             # Architecture Decision Records
│   ├── features/                 # Feature specifications
│   ├── research/                 # Research findings
│   └── standards/                # Project standards
├── evidence/                     # Proof and validation artifacts
│   ├── visual-baselines/         # UI/UX reference points
│   ├── performance/              # Performance benchmarks
│   └── testing/                  # Test evidence and results
├── templates/                    # Documentation templates
│   ├── ssot-templates/          # SSOT framework templates
│   └── diataxis-templates/      # Diátaxis framework templates
└── scripts/                      # Automation scripts
    ├── generate-docs.py          # Documentation generation
    ├── validate-ssot.py          # SSOT validation
    └── sync-standards.py         # Standards synchronization
```

### Three-Layer Context System

1. **Layer 1: Universal Standards** - Cross-project patterns and best practices
2. **Layer 2: Project Context** - Project-specific documentation and decisions
3. **Layer 3: Feature Context** - Feature-level specifications and details

---

## Diátaxis Framework Integration

### Documentation Types

#### T1: Tutorials (Learning-Oriented)
- **Purpose**: Step-by-step learning for beginners
- **Location**: `docs/tutorials/`
- **Format**: Lesson-based with practical exercises
- **Validation**: Completion rate, user success metrics

#### T2: How-To Guides (Problem-Oriented)
- **Purpose**: Solve specific problems
- **Location**: `docs/how-to-guides/`
- **Format**: Goal-oriented, specific steps
- **Validation**: Problem resolution rate

#### T3: Reference Material (Information-Oriented)
- **Purpose**: Factual information lookup
- **Location**: `docs/reference/`
- **Format**: Structured, searchable, comprehensive
- **Validation**: Information accuracy, completeness

#### T4: Explanation (Understanding-Oriented)
- **Purpose**: Deep understanding of concepts
- **Location**: `docs/explanation/`
- **Format**: Context-rich, background information
- **Validation**: Concept clarity, knowledge transfer

### Content Allocation Rules

| Content Type | Diátaxis Category | Location | Example |
|--------------|-------------------|----------|---------|
| Getting Started | Tutorial | `docs/tutorials/` | "First Project Setup" |
| API Usage | How-To | `docs/how-to-guides/` | "Authenticate with API" |
| Function Reference | Reference | `docs/reference/` | "Function Parameters" |
| Architecture Decisions | Explanation | `docs/explanation/` | "Why We Chose Microservices" |

---

## SSOT Specification System

### Core Specification Files

#### 1. Purpose Specification (`specs/purpose.md`)
```markdown
# Project Purpose

## Problem Statement
[What problem exists, quantified with metrics]

## Target Users
[Who benefits, with specific user counts]

## Scope
**Included**: [Specific features and boundaries]
**Excluded**: [Explicit out-of-scope items]

## Success Criteria
[Minimum 3 measurable metrics with targets]

## Key Assumptions
[Assumptions with validation methods]

## Context & Constraints
[Business, technical, and resource constraints]
```

#### 2. Functional Specification (`specs/functional_spec.md`)
```markdown
# Functional Specification

## Feature Overview
[High-level feature description]

## User Journeys
[Detailed user workflows with success metrics]

## Acceptance Criteria
[Testable criteria with measurable thresholds]

## Data Requirements
[Data structures and flows]

## Integration Points
[External system dependencies]
```

#### 3. Technical Specification (`specs/technical_spec.md`)
```markdown
# Technical Specification

## Architecture Overview
[System architecture with diagrams]

## Technology Stack
[Technologies with version requirements]

## Component Design
[Detailed component specifications]

## Performance Requirements
[Specific performance benchmarks]

## Security Considerations
[Security requirements and measures]
```

### Architecture Decision Records (ADRs)

#### ADR Template (`specs/architecture/adr_XXX_title.md`)
```markdown
# ADR-XXX: [Decision Title]

**Status**: [Accepted/Rejected/Deprecated]
**Date**: YYYY-MM-DD
**Deciders**: [Roles/Teams]

## Context
[Problem statement with evidence]

## Decision
[What was decided and why]

## Consequences
**Positive**: [Benefits]
**Negative**: [Trade-offs]
**Neutral**: [Other implications]

## Alternatives Considered
[Other options and rejection rationale]

## Related Decisions
- [Links to related ADRs]
```

---

## Agent-Agnostic Command Templates

### Universal Prompt Structure

All prompts follow this structure:
```
CONTEXT: [Relevant background information]
TASK: [Specific action required]
FORMAT: [Expected output format]
CONSTRAINTS: [Limitations and requirements]
EXAMPLE: [Sample output if helpful]
```

### Core Documentation Prompts

#### 1. Generate Purpose Specification
```
CONTEXT: I'm starting a new project called [PROJECT_NAME]. The initial idea is [BRIEF_DESCRIPTION].
TASK: Generate a complete purpose specification following the SSOT framework.
FORMAT: Markdown file with sections: Problem Statement, Target Users, Scope (Included/Excluded), Success Criteria (3+ measurable metrics), Key Assumptions, Context & Constraints.
CONSTRAINTS: 
- Maximum 500 words total
- Minimum 3 quantifiable success metrics
- At least 5 scope inclusions and 5 exclusions
- All technical terms defined
EXAMPLE: [Provide brief example if needed]
```

#### 2. Create Architecture Decision Record
```
CONTEXT: We need to decide on [TECHNICAL_DECISION] for our project. Current options are [OPTION_A], [OPTION_B], [OPTION_C].
TASK: Create an Architecture Decision Record (ADR) following the SSOT template.
FORMAT: Markdown with sections: Context, Decision, Consequences (Positive/Negative/Neutral), Alternatives Considered, Related Decisions.
CONSTRAINTS:
- Include specific evidence for the decision
- List at least 2 alternatives with rejection rationale
- Document measurable consequences
EXAMPLE: [Show brief ADR example]
```

#### 3. Generate Functional Specification
```
CONTEXT: Based on the approved purpose in specs/purpose.md, we need to define the functional requirements for [PROJECT_NAME].
TASK: Generate a complete functional specification.
FORMAT: Markdown with sections: Feature Overview, User Journeys (3+ with success metrics), Acceptance Criteria (testable with thresholds), Data Requirements, Integration Points.
CONSTRAINTS:
- Each user journey must include measurable success metrics
- Acceptance criteria must be testable and specific
- Include data flow diagrams using Mermaid
- Reference the purpose specification
```

#### 4. Create Technical Specification
```
CONTEXT: Based on the functional specification in specs/functional_spec.md, we need technical details for implementation.
TASK: Generate a comprehensive technical specification.
FORMAT: Markdown with sections: Architecture Overview (with Mermaid diagrams), Technology Stack (with versions), Component Design, Performance Requirements (with target/max thresholds), Security Considerations.
CONSTRAINTS:
- Include system architecture diagram
- Specify exact versions for all technologies
- Include performance benchmarks with measurable thresholds
- Address security requirements
```

#### 5. Generate User Documentation (Diátaxis)
```
CONTEXT: We have implemented [FEATURE_NAME] and need to create user documentation.
TASK: Generate documentation following the Diátaxis framework.
FORMAT: Create 4 files:
1. Tutorial: Step-by-step learning guide
2. How-To Guide: Problem-solving steps
3. Reference: Technical details and parameters
4. Explanation: Background and context
CONSTRAINTS:
- Each document targets different user needs
- Tutorial includes practical exercises
- How-To guide solves specific problems
- Reference is comprehensive and accurate
- Explanation provides deep understanding
```

### Validation and Quality Assurance Prompts

#### 1. Validate SSOT Compliance
```
CONTEXT: Review the current project documentation in the specs/ directory.
TASK: Validate SSOT framework compliance and identify gaps.
FORMAT: Structured report with sections: Compliance Status, Missing Artifacts, Quality Issues, Recommendations.
CONSTRAINTS:
- Check all required files exist
- Validate cross-references are correct
- Ensure measurable metrics are present
- Verify diagram standards (Mermaid)
```

#### 2. Quality Review
```
CONTEXT: Review the documentation file [FILE_PATH] for quality and completeness.
TASK: Perform comprehensive quality review.
FORMAT: Detailed review with sections: Strengths, Issues, Improvements Needed, Compliance Score.
CONSTRAINTS:
- Check clarity and specificity
- Validate measurable metrics
- Ensure technical accuracy
- Verify consistency with other documents
```

---

## Implementation Guide

### Phase 1: Setup and Initialization

#### 1.1 Create Directory Structure
```bash
# Create main directories
mkdir -p docs/{tutorials,how-to-guides,reference,explanation}
mkdir -p specs/{architecture,features,research,standards}
mkdir -p evidence/{visual-baselines,performance,testing}
mkdir -p templates/{ssot-templates,diataxis-templates}
mkdir -p scripts

# Create initial files
touch specs/purpose.md
touch specs/functional_spec.md
touch specs/technical_spec.md
touch README.md
```

#### 1.2 Initialize Templates
Create template files in `templates/ssot-templates/`:
- `purpose-template.md`
- `functional-spec-template.md`
- `technical-spec-template.md`
- `adr-template.md`

Create template files in `templates/diataxis-templates/`:
- `tutorial-template.md`
- `how-to-template.md`
- `reference-template.md`
- `explanation-template.md`

### Phase 2: Content Generation

#### 2.1 Generate Core Specifications
Use the appropriate prompt templates with your AI agent:
1. Generate Purpose Specification
2. Create Functional Specification
3. Develop Technical Specification
4. Document Architecture Decisions

#### 2.2 Create User Documentation
Apply Diátaxis framework prompts:
1. Generate Tutorial content
2. Create How-To Guides
3. Develop Reference material
4. Write Explanations

### Phase 3: Validation and Maintenance

#### 3.1 Validate Documentation
```
CONTEXT: Complete project documentation generated
TASK: Validate all documentation against SSOT and Diátaxis standards
FORMAT: Comprehensive validation report
CONSTRAINTS: Check all files, cross-references, and quality metrics
```

#### 3.2 Setup Maintenance Process
- Regular documentation reviews
- Update triggers (feature changes, decisions)
- Version control integration
- Quality metrics tracking

---

## Validation Framework

### Automated Validation Rules

#### 1. File Structure Validation
```yaml
required_files:
  - specs/purpose.md
  - specs/functional_spec.md
  - specs/technical_spec.md
  - README.md

required_directories:
  - docs/tutorials/
  - docs/how-to-guides/
  - docs/reference/
  - docs/explanation/
  - specs/architecture/
  - specs/features/
  - evidence/
```

#### 2. Content Quality Rules
```yaml
purpose_requirements:
  max_words: 500
  min_success_metrics: 3
  min_scope_inclusions: 5
  min_scope_exclusions: 5
  requires_measurable_metrics: true

functional_spec_requirements:
  min_user_journeys: 3
  requires_success_metrics: true
  requires_testable_criteria: true

technical_spec_requirements:
  requires_architecture_diagram: true
  requires_performance_benchmarks: true
  requires_security_section: true
```

#### 3. Cross-Reference Validation
```yaml
cross_reference_rules:
  - functional_spec must reference purpose
  - technical_spec must reference functional_spec
  - ADRs must be numbered sequentially
  - All feature IDs must be documented
```

### Quality Metrics

#### Documentation Completeness Score
```python
def calculate_completeness_score(project_docs):
    """
    Calculates documentation completeness percentage
    """
    required_files = get_required_files()
    existing_files = get_existing_files(project_docs)
    
    file_score = len(existing_files) / len(required_files) * 100
    
    content_score = calculate_content_quality(existing_files)
    
    return (file_score + content_score) / 2
```

#### Measurability Index
```python
def calculate_measurability_index(spec_file):
    """
    Measures how many requirements have quantifiable metrics
    """
    requirements = extract_requirements(spec_file)
    measurable = count_measurable_requirements(requirements)
    
    return (measurable / len(requirements)) * 100
```

### Validation Checklist

#### Pre-Gate Validation
- [ ] All required files exist
- [ ] Purpose document meets word count and metric requirements
- [ ] Functional spec includes user journeys with success metrics
- [ ] Technical spec includes architecture diagrams and performance benchmarks
- [ ] All cross-references are valid
- [ ] ADRs are properly formatted and numbered
- [ ] Documentation follows Diátaxis framework

#### Quality Gates
- [ ] Completeness Score ≥ 90%
- [ ] Measurability Index ≥ 80%
- [ ] Cross-Reference Accuracy = 100%
- [ ] Diagram Standards Compliance = 100%
- [ ] User Documentation Coverage ≥ 75%

---

## Integration with AI Agents

### ChatGPT Integration
```markdown
**System Prompt Setup:**
"You are an expert technical documentation specialist using the SSOT + Diátaxis framework. Always follow the provided templates and validation rules. Generate clear, measurable, and comprehensive documentation."

**Usage:**
1. Copy the appropriate prompt template
2. Replace bracketed placeholders with project-specific information
3. Submit to ChatGPT
4. Review output against validation rules
5. Iterate if needed
```

### Claude Integration
```markdown
**System Prompt Setup:**
"Follow the Agent-Agnostic SSOT Documentation Framework. Use the provided prompt templates and ensure all generated content meets the validation criteria in the framework."

**Usage:**
1. Use the universal prompt structure
2. Include context and constraints
3. Request specific format adherence
4. Validate output using framework rules
```

### Gemini Integration
```markdown
**System Prompt Setup:**
"You are implementing the Agent-Agnostic SSOT Documentation Framework. Follow the Diátaxis methodology for user documentation and SSOT principles for technical specifications."

**Usage:**
1. Provide context using the template structure
2. Specify exact output format requirements
3. Include validation constraints
4. Review against framework standards
```

### Custom Agent Integration
```python
# Example integration script
def generate_documentation(agent_type, prompt_template, context):
    """
    Generic documentation generation for any AI agent
    """
    prompt = format_prompt(prompt_template, context)
    
    if agent_type == "openai":
        response = openai_generate(prompt)
    elif agent_type == "claude":
        response = claude_generate(prompt)
    elif agent_type == "gemini":
        response = gemini_generate(prompt)
    else:
        response = custom_agent_generate(prompt)
    
    # Validate against framework rules
    validation_result = validate_documentation(response)
    
    return response, validation_result
```

---

## Best Practices

### Documentation Principles

1. **Always Be Specific**: Avoid vague language, use quantifiable metrics
2. **Single Source of Truth**: One canonical location for each piece of information
3. **Version Control Everything**: All documentation in Git, track changes
4. **Validate Continuously**: Regular quality checks and compliance validation
5. **Update Incrementally**: Keep documentation current with project changes

### Content Guidelines

#### Writing Style
- Use active voice
- Be concise but complete
- Include measurable metrics
- Define all technical terms
- Use consistent terminology

#### Diagram Standards
- Use Mermaid for all diagrams
- Keep diagrams simple (max 50 nodes)
- Include legends and labels
- Ensure text-based version control

#### Cross-Reference Rules
- Always link related documents
- Use consistent ID schemes
- Validate all links
- Maintain traceability matrices

### Maintenance Practices

#### Regular Reviews
- Weekly documentation updates
- Monthly quality assessments
- Quarterly compliance audits
- Annual framework reviews

#### Update Triggers
- Feature implementation complete
- Architecture decision made
- Performance benchmark established
- User feedback received

#### Version Control
- Commit documentation with code
- Use descriptive commit messages
- Tag documentation releases
- Maintain change logs

---

## Troubleshooting

### Common Issues

#### Issue: Generated documentation is too vague
**Solution**: Add specific constraints to prompts requiring measurable metrics and quantifiable criteria.

#### Issue: AI agent doesn't follow template structure
**Solution**: Provide explicit format examples and break down complex requests into smaller, specific prompts.

#### Issue: Cross-references become broken
**Solution**: Implement automated validation scripts and regular link checking.

#### Issue: Documentation becomes outdated
**Solution**: Set up automated triggers that update documentation when code changes.

#### Issue: Quality varies between AI agents
**Solution**: Use the validation framework to ensure consistent quality regardless of AI agent used.

### Validation Failures

#### Completeness Score < 90%
- Check for missing required files
- Verify all sections are populated
- Ensure minimum requirements are met

#### Measurability Index < 80%
- Add specific metrics to requirements
- Include quantifiable success criteria
- Define measurable acceptance criteria

#### Cross-Reference Errors
- Update all links when files move
- Validate ID schemes are consistent
- Check for broken internal links

---

## Examples and Templates

### Complete Project Example

See `examples/complete-project/` for a full implementation of the framework with:
- Complete specification documents
- User documentation in all Diátaxis categories
- Validation scripts and results
- Maintenance automation

### Quick Start Templates

Use `templates/quick-start/` for:
- Simple project initialization
- Basic documentation generation
- Minimal validation setup

### Advanced Templates

Use `templates/advanced/` for:
- Complex project structures
- Multi-team coordination
- Advanced automation

---

## Conclusion

The Agent-Agnostic SSOT Documentation Framework provides a universal approach to creating high-quality, maintainable project documentation using any AI agent. By combining the SSOT methodology with the Diátaxis framework, it ensures comprehensive coverage of both technical and user documentation needs.

The framework's strength lies in its:
- **Universal Compatibility**: Works with any AI system
- **Structured Approach**: Clear organization and standards
- **Quality Assurance**: Built-in validation and verification
- **Scalability**: Adapts to project complexity and team size

Start with the basic templates, gradually adopt advanced features, and maintain quality through continuous validation. The result is comprehensive, accurate, and useful documentation that serves both technical and user needs.

---

## Appendix

### A. Validation Script Examples
### B. Template Library Reference
### C. Integration Code Samples
### D. Quality Metrics Formulas
### E. Troubleshooting Guide

---

*This framework is continuously evolving. Contributions and feedback are welcome through the project repository.*