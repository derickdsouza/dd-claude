import { mkdirSync, writeFileSync, existsSync } from 'fs';
import { join, dirname } from 'path';
import type { ParsedSpec } from '../parser.js';
import type { EntitySpec, ConfigSpec, ServiceSpec, WorkflowSpec, EntityField, ConfigProperty } from '../types.js';

export function generateDocs(specs: ParsedSpec[], outputDir: string): void {
  // Create output directories
  const dirs = ['entities', 'config', 'services', 'workflows'];
  for (const dir of dirs) {
    const path = join(outputDir, dir);
    if (!existsSync(path)) {
      mkdirSync(path, { recursive: true });
    }
  }

  // Generate docs for each spec type
  for (const parsed of specs) {
    switch (parsed.type) {
      case 'entity':
        generateEntityDoc(parsed.spec as EntitySpec, parsed.fileName, outputDir);
        break;
      case 'config':
        generateConfigDoc(parsed.spec as ConfigSpec, parsed.fileName, outputDir);
        break;
      case 'service':
        generateServiceDoc(parsed.spec as ServiceSpec, parsed.fileName, outputDir);
        break;
      case 'workflow':
        generateWorkflowDoc(parsed.spec as WorkflowSpec, parsed.fileName, outputDir);
        break;
    }
  }

  // Generate index files
  generateEntityIndex(specs.filter(s => s.type === 'entity'), outputDir);
  generateConfigIndex(specs.filter(s => s.type === 'config'), outputDir);
  generateServiceIndex(specs.filter(s => s.type === 'service'), outputDir);
}

function generateEntityDoc(spec: EntitySpec, fileName: string, outputDir: string): void {
  const lines: string[] = [];

  // Header
  lines.push(`# ${spec.name}`);
  lines.push('');
  lines.push(`> Generated from \`spec/domain/${fileName}.yaml\` v${spec.version}`);
  lines.push('');
  lines.push(spec.description.trim());
  lines.push('');

  // Table info
  if (spec.tableName) {
    lines.push(`**Database Table:** \`${spec.tableName}\``);
    lines.push('');
  }

  // Fields table
  lines.push('## Fields');
  lines.push('');
  lines.push('| Field | Type | Required | Description |');
  lines.push('|-------|------|----------|-------------|');

  for (const field of spec.fields) {
    const typeStr = formatFieldType(field);
    const required = field.primary ? 'PK' : (field.required ? 'Yes' : 'No');
    const desc = formatDescription(field);
    lines.push(`| \`${field.name}\` | ${typeStr} | ${required} | ${desc} |`);
  }
  lines.push('');

  // Relationships
  if (spec.relationships && spec.relationships.length > 0) {
    lines.push('## Relationships');
    lines.push('');
    lines.push('| Name | Type | Target | Foreign Key |');
    lines.push('|------|------|--------|-------------|');
    for (const rel of spec.relationships) {
      lines.push(`| ${rel.name} | ${rel.type} | ${rel.target} | ${rel.foreignKey || '-'} |`);
    }
    lines.push('');
  }

  // Indexes
  if (spec.indexes && spec.indexes.length > 0) {
    lines.push('## Indexes');
    lines.push('');
    lines.push('| Name | Fields | Unique |');
    lines.push('|------|--------|--------|');
    for (const idx of spec.indexes) {
      const name = idx.name || `IX_${spec.name}_${idx.fields.join('_')}`;
      lines.push(`| \`${name}\` | ${idx.fields.join(', ')} | ${idx.unique ? 'Yes' : 'No'} |`);
    }
    lines.push('');
  }

  // Validation rules
  if (spec.validation && spec.validation.length > 0) {
    lines.push('## Validation Rules');
    lines.push('');
    for (const rule of spec.validation) {
      lines.push(`- **Rule:** \`${rule.rule}\``);
      lines.push(`  - *Message:* ${rule.message}`);
    }
    lines.push('');
  }

  // Audit settings
  if (spec.audit) {
    lines.push('## Audit Trail');
    lines.push('');
    lines.push(`- **Enabled:** ${spec.audit.enabled !== false ? 'Yes' : 'No'}`);
    lines.push(`- **Track Created:** ${spec.audit.trackCreated !== false ? 'Yes' : 'No'}`);
    lines.push(`- **Track Updated:** ${spec.audit.trackUpdated !== false ? 'Yes' : 'No'}`);
    lines.push(`- **Track By (User):** ${spec.audit.trackBy !== false ? 'Yes' : 'No'}`);
    lines.push('');
  }

  const outputPath = join(outputDir, 'entities', `${fileName}.md`);
  writeFileSync(outputPath, lines.join('\n'));
}

function generateConfigDoc(spec: ConfigSpec, fileName: string, outputDir: string): void {
  const lines: string[] = [];

  // Header
  lines.push(`# ${spec.name}`);
  lines.push('');
  lines.push(`> Generated from \`spec/config/${fileName}.yaml\` v${spec.version}`);
  lines.push('');
  lines.push(spec.description.trim());
  lines.push('');
  lines.push(`**Configuration Section:** \`${spec.section}\``);
  lines.push('');

  // Properties
  lines.push('## Properties');
  lines.push('');
  generateConfigProperties(spec.properties, lines, 0);

  // Environment variables
  if (spec.environmentVariables && spec.environmentVariables.length > 0) {
    lines.push('## Environment Variables');
    lines.push('');
    lines.push('| Variable | Property | Description |');
    lines.push('|----------|----------|-------------|');
    for (const env of spec.environmentVariables) {
      lines.push(`| \`${env.name}\` | ${env.property} | ${env.description || '-'} |`);
    }
    lines.push('');
  }

  // Example configuration
  lines.push('## Example Configuration');
  lines.push('');
  lines.push('```json');
  lines.push(`"${spec.section}": {`);
  generateExampleJson(spec.properties, lines, 1);
  lines.push('}');
  lines.push('```');
  lines.push('');

  const outputPath = join(outputDir, 'config', `${fileName}.md`);
  writeFileSync(outputPath, lines.join('\n'));
}

function generateConfigProperties(properties: ConfigProperty[], lines: string[], depth: number): void {
  const indent = '  '.repeat(depth);

  for (const prop of properties) {
    lines.push(`${indent}### ${prop.name}`);
    lines.push('');
    lines.push(`${indent}${prop.description}`);
    lines.push('');
    lines.push(`${indent}- **Type:** \`${prop.type}\``);
    if (prop.default !== undefined) {
      lines.push(`${indent}- **Default:** \`${JSON.stringify(prop.default)}\``);
    }
    if (prop.required) {
      lines.push(`${indent}- **Required:** Yes`);
    }
    if (prop.sensitive) {
      lines.push(`${indent}- **Sensitive:** Yes (do not log)`);
    }
    if (prop.minimum !== undefined) {
      lines.push(`${indent}- **Minimum:** ${prop.minimum}`);
    }
    if (prop.maximum !== undefined) {
      lines.push(`${indent}- **Maximum:** ${prop.maximum}`);
    }
    if (prop.enum) {
      lines.push(`${indent}- **Allowed Values:** ${prop.enum.map(v => `\`${v}\``).join(', ')}`);
    }
    if (prop.examples) {
      lines.push(`${indent}- **Examples:** ${prop.examples.map(v => `\`${JSON.stringify(v)}\``).join(', ')}`);
    }
    lines.push('');

    // Nested properties
    if (prop.properties && prop.properties.length > 0) {
      generateConfigProperties(prop.properties, lines, depth + 1);
    }
  }
}

function generateExampleJson(properties: ConfigProperty[], lines: string[], depth: number): void {
  const indent = '  '.repeat(depth);
  const propCount = properties.length;

  properties.forEach((prop, idx) => {
    const comma = idx < propCount - 1 ? ',' : '';
    const value = prop.default !== undefined ? JSON.stringify(prop.default) : getDefaultForType(prop.type);

    if (prop.type === 'object' && prop.properties) {
      lines.push(`${indent}"${prop.name}": {`);
      generateExampleJson(prop.properties, lines, depth + 1);
      lines.push(`${indent}}${comma}`);
    } else {
      lines.push(`${indent}"${prop.name}": ${value}${comma}`);
    }
  });
}

function getDefaultForType(type: string): string {
  switch (type) {
    case 'string': return '""';
    case 'integer': return '0';
    case 'decimal': return '0.0';
    case 'boolean': return 'false';
    case 'duration': return '"00:01:00"';
    case 'array': return '[]';
    case 'object': return '{}';
    default: return 'null';
  }
}

function generateServiceDoc(spec: ServiceSpec, fileName: string, outputDir: string): void {
  const lines: string[] = [];

  // Header
  lines.push(`# ${spec.name}`);
  lines.push('');
  lines.push(`> Generated from \`spec/services/${fileName}.yaml\` v${spec.version}`);
  lines.push('');
  lines.push(spec.description.trim());
  lines.push('');

  if (spec.namespace && spec.className) {
    lines.push(`**Full Name:** \`${spec.namespace}.${spec.className}\``);
    lines.push('');
  }

  // Dependencies
  if (spec.dependencies && spec.dependencies.length > 0) {
    lines.push('## Dependencies');
    lines.push('');
    for (const dep of spec.dependencies) {
      lines.push(`- \`${dep.name}\` - ${dep.description || ''}`);
    }
    lines.push('');
  }

  // Configuration
  if (spec.configuration) {
    lines.push('## Configuration');
    lines.push('');
    lines.push(`**Section:** \`${spec.configuration.section}\``);
    lines.push('');
    if (spec.configuration.properties) {
      lines.push('| Property | Type | Default | Description |');
      lines.push('|----------|------|---------|-------------|');
      for (const prop of spec.configuration.properties) {
        const def = prop.default !== undefined ? `\`${JSON.stringify(prop.default)}\`` : '-';
        lines.push(`| ${prop.name} | ${prop.type} | ${def} | ${prop.description} |`);
      }
      lines.push('');
    }
  }

  // Operations
  if (spec.operations && spec.operations.length > 0) {
    lines.push('## Operations');
    lines.push('');
    for (const op of spec.operations) {
      lines.push(`### ${op.name}`);
      lines.push('');
      lines.push(op.description);
      lines.push('');
      if (op.parameters && op.parameters.length > 0) {
        lines.push('**Parameters:**');
        for (const param of op.parameters) {
          lines.push(`- \`${param.name}\`: \`${param.type}\` ${param.description || ''}`);
        }
        lines.push('');
      }
      if (op.returns) {
        lines.push(`**Returns:** \`${op.returns}\``);
        lines.push('');
      }
      if (op.behavior) {
        lines.push('**Behavior:**');
        lines.push('');
        lines.push(op.behavior.trim());
        lines.push('');
      }
    }
  }

  // Events
  if (spec.events) {
    if (spec.events.published && spec.events.published.length > 0) {
      lines.push('## Published Events');
      lines.push('');
      for (const event of spec.events.published) {
        lines.push(`### ${event.name}`);
        lines.push('');
        lines.push(event.description);
        if (event.payload) {
          lines.push('');
          lines.push('**Payload:** ' + event.payload.map(p => `\`${p}\``).join(', '));
        }
        lines.push('');
      }
    }
    if (spec.events.consumed && spec.events.consumed.length > 0) {
      lines.push('## Consumed Events');
      lines.push('');
      for (const event of spec.events.consumed) {
        lines.push(`- **${event.name}** from ${event.source || 'unknown'}: ${event.description}`);
      }
      lines.push('');
    }
  }

  // Metrics
  if (spec.metrics && spec.metrics.length > 0) {
    lines.push('## Metrics');
    lines.push('');
    lines.push('| Metric | Type | Labels | Description |');
    lines.push('|--------|------|--------|-------------|');
    for (const metric of spec.metrics) {
      const labels = metric.labels ? metric.labels.join(', ') : '-';
      lines.push(`| \`${metric.name}\` | ${metric.type} | ${labels} | ${metric.description} |`);
    }
    lines.push('');
  }

  const outputPath = join(outputDir, 'services', `${fileName}.md`);
  writeFileSync(outputPath, lines.join('\n'));
}

function generateWorkflowDoc(spec: WorkflowSpec, fileName: string, outputDir: string): void {
  const lines: string[] = [];

  // Header
  lines.push(`# ${spec.name}`);
  lines.push('');
  lines.push(`> Generated from \`spec/workflows/${fileName}.yaml\` v${spec.version}`);
  lines.push('');
  lines.push(spec.description.trim());
  lines.push('');
  lines.push(`**Initial State:** \`${spec.initialState}\``);
  lines.push('');

  // State diagram (Mermaid)
  lines.push('## State Diagram');
  lines.push('');
  lines.push('```mermaid');
  lines.push('stateDiagram-v2');
  lines.push(`    [*] --> ${spec.initialState}`);
  for (const trans of spec.transitions) {
    if (trans.from === '*') {
      // Skip wildcard transitions in diagram for clarity
      continue;
    }
    lines.push(`    ${trans.from} --> ${trans.to}: ${trans.action}`);
  }
  for (const state of spec.states.filter(s => s.terminal)) {
    lines.push(`    ${state.name} --> [*]`);
  }
  lines.push('```');
  lines.push('');

  // States
  lines.push('## States');
  lines.push('');
  lines.push('| State | Description | Terminal | Allowed Actions |');
  lines.push('|-------|-------------|----------|-----------------|');
  for (const state of spec.states) {
    const actions = state.allowedActions.length > 0 ? state.allowedActions.join(', ') : '-';
    lines.push(`| \`${state.name}\` | ${state.description} | ${state.terminal ? 'Yes' : 'No'} | ${actions} |`);
  }
  lines.push('');

  // Transitions
  lines.push('## Transitions');
  lines.push('');
  for (const trans of spec.transitions) {
    lines.push(`### ${trans.action}`);
    lines.push('');
    lines.push(`**From:** \`${trans.from}\` **To:** \`${trans.to}\``);
    lines.push('');
    if (trans.description) {
      lines.push(trans.description);
      lines.push('');
    }
    if (trans.requiredRole && trans.requiredRole.length > 0) {
      lines.push(`**Required Roles:** ${trans.requiredRole.join(', ')}`);
      lines.push('');
    }
    if (trans.condition) {
      lines.push(`**Condition:** \`${trans.condition}\``);
      lines.push('');
    }
    if (trans.sideEffects && trans.sideEffects.length > 0) {
      lines.push('**Side Effects:**');
      for (const effect of trans.sideEffects) {
        lines.push(`- ${effect}`);
      }
      lines.push('');
    }
  }

  const outputPath = join(outputDir, 'workflows', `${fileName}.md`);
  writeFileSync(outputPath, lines.join('\n'));
}

function generateEntityIndex(specs: ParsedSpec[], outputDir: string): void {
  const lines: string[] = [];
  lines.push('# Entity Reference');
  lines.push('');
  lines.push('> Auto-generated from `spec/domain/*.yaml`');
  lines.push('');
  lines.push('This section contains reference documentation for all domain entities in the PTMS system.');
  lines.push('');
  lines.push('## Entities');
  lines.push('');

  for (const parsed of specs) {
    const spec = parsed.spec as EntitySpec;
    lines.push(`- [${spec.name}](./entities/${parsed.fileName}.md) - ${spec.description.split('\n')[0].trim()}`);
  }
  lines.push('');

  writeFileSync(join(outputDir, 'entities.md'), lines.join('\n'));
}

function generateConfigIndex(specs: ParsedSpec[], outputDir: string): void {
  const lines: string[] = [];
  lines.push('# Configuration Reference');
  lines.push('');
  lines.push('> Auto-generated from `spec/config/*.yaml`');
  lines.push('');
  lines.push('This section contains reference documentation for all configuration options.');
  lines.push('');
  lines.push('## Configuration Sections');
  lines.push('');

  for (const parsed of specs) {
    const spec = parsed.spec as ConfigSpec;
    lines.push(`- [${spec.name}](./config/${parsed.fileName}.md) - \`${spec.section}\``);
  }
  lines.push('');

  writeFileSync(join(outputDir, 'configuration.md'), lines.join('\n'));
}

function generateServiceIndex(specs: ParsedSpec[], outputDir: string): void {
  const lines: string[] = [];
  lines.push('# Service Reference');
  lines.push('');
  lines.push('> Auto-generated from `spec/services/*.yaml`');
  lines.push('');
  lines.push('This section contains reference documentation for backend services.');
  lines.push('');
  lines.push('## Services');
  lines.push('');

  for (const parsed of specs) {
    const spec = parsed.spec as ServiceSpec;
    lines.push(`- [${spec.name}](./services/${parsed.fileName}.md) - ${spec.description.split('\n')[0].trim()}`);
  }
  lines.push('');

  writeFileSync(join(outputDir, 'services.md'), lines.join('\n'));
}

function formatFieldType(field: EntityField): string {
  let type = field.type;
  if (field.type === 'enum' && field.values) {
    type = `enum(${field.values.slice(0, 3).join('|')}${field.values.length > 3 ? '|...' : ''})`;
  }
  if (field.type === 'string' && field.maxLength) {
    type = `string(${field.maxLength})`;
  }
  if (field.type === 'decimal' && field.precision) {
    type = `decimal(${field.precision},${field.scale || 0})`;
  }
  if (field.references) {
    type += ` FK->${field.references}`;
  }
  return type;
}

function formatDescription(field: EntityField): string {
  let desc = field.description || '';
  const badges: string[] = [];
  if (field.unique) badges.push('unique');
  if (field.encrypted) badges.push('encrypted');
  if (field.sensitive) badges.push('sensitive');
  if (badges.length > 0) {
    desc = `[${badges.join(', ')}] ${desc}`;
  }
  return desc.replace(/\|/g, '\\|').replace(/\n/g, ' ');
}
