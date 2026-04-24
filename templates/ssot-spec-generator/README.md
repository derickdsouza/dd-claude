# Spec Generator

Generate documentation and TypeScript types from YAML specifications.

## Installation

```bash
cd tools/spec-generator
npm install
```

## Usage

```bash
# Validate all specs
npm run dev -- --validate

# Generate documentation only
npm run dev -- --docs

# Generate TypeScript types only
npm run dev -- --typescript

# Generate everything
npm run dev

# With verbose output
npm run dev -- -v
```

## Directory Structure

The generator expects this structure in your project:

```
project-root/
├── spec/                    # YAML specifications (SSOT)
│   ├── schemas/             # JSON Schema for validation
│   │   ├── entity.schema.json
│   │   └── config.schema.json
│   ├── domain/              # Entity definitions
│   │   └── *.yaml
│   ├── config/              # Configuration schemas
│   │   └── *.yaml
│   ├── services/            # Service definitions
│   │   └── *.yaml
│   └── workflows/           # State machines
│       └── *.yaml
├── docs/
│   └── reference/           # Generated docs go here
│       ├── entities/
│       ├── config/
│       ├── services/
│       └── workflows/
└── frontend/src/generated/  # Generated TypeScript goes here
    └── types/
```

## Command Line Options

```
-s, --spec-dir <path>      Specification directory (default: spec)
-o, --docs-output <path>   Documentation output (default: docs/reference)
-t, --ts-output <path>     TypeScript output (default: frontend/src/generated)
--docs                     Generate documentation only
--typescript               Generate TypeScript only
--validate                 Validate specs only (no generation)
-v, --verbose              Verbose output
```

## Output

### Documentation
- `docs/reference/entities/*.md` - Entity documentation
- `docs/reference/config/*.md` - Configuration documentation
- `docs/reference/services/*.md` - Service documentation
- `docs/reference/workflows/*.md` - Workflow documentation with Mermaid diagrams
- `docs/reference/entities.md` - Entity index
- `docs/reference/configuration.md` - Configuration index
- `docs/reference/services.md` - Service index

### TypeScript
- `frontend/src/generated/types/entities.ts` - Entity interfaces and enums
- `frontend/src/generated/types/config.ts` - Configuration interfaces
- `frontend/src/generated/types/index.ts` - Re-exports
