import { mkdirSync, writeFileSync, existsSync } from 'fs';
import { join } from 'path';
import type { ParsedSpec } from '../parser.js';
import type { EntitySpec, EntityField, ConfigSpec, ConfigProperty } from '../types.js';

export function generateTypeScript(specs: ParsedSpec[], outputDir: string): void {
  const typesDir = join(outputDir, 'types');
  if (!existsSync(typesDir)) {
    mkdirSync(typesDir, { recursive: true });
  }

  // Generate entity types
  const entitySpecs = specs.filter(s => s.type === 'entity');
  generateEntityTypes(entitySpecs, typesDir);

  // Generate config types
  const configSpecs = specs.filter(s => s.type === 'config');
  generateConfigTypes(configSpecs, typesDir);

  // Generate index file
  generateIndexFile(entitySpecs, configSpecs, typesDir);
}

function generateEntityTypes(specs: ParsedSpec[], outputDir: string): void {
  const lines: string[] = [];

  lines.push('// Auto-generated from spec/domain/*.yaml');
  lines.push('// DO NOT EDIT - changes will be overwritten');
  lines.push('');

  for (const parsed of specs) {
    const spec = parsed.spec as EntitySpec;

    // Generate enums first
    for (const field of spec.fields) {
      if (field.type === 'enum' && field.values) {
        const enumName = `${spec.name}${field.name}`;
        lines.push(`export type ${enumName} = ${field.values.map(v => `'${v}'`).join(' | ')};`);
        lines.push('');
        lines.push(`export const ${enumName}Values = [${field.values.map(v => `'${v}'`).join(', ')}] as const;`);
        lines.push('');
      }
    }

    // Generate interface
    lines.push(`/**`);
    lines.push(` * ${spec.description.split('\n')[0].trim()}`);
    lines.push(` * @version ${spec.version}`);
    lines.push(` */`);
    lines.push(`export interface ${spec.name} {`);

    for (const field of spec.fields) {
      const tsType = fieldToTypeScript(field, spec.name);
      const optional = !field.required && !field.primary ? '?' : '';
      const comment = field.description ? ` // ${field.description.split('\n')[0].trim()}` : '';
      lines.push(`  ${camelCase(field.name)}${optional}: ${tsType};${comment}`);
    }

    lines.push('}');
    lines.push('');
  }

  writeFileSync(join(outputDir, 'entities.ts'), lines.join('\n'));
}

function generateConfigTypes(specs: ParsedSpec[], outputDir: string): void {
  const lines: string[] = [];

  lines.push('// Auto-generated from spec/config/*.yaml');
  lines.push('// DO NOT EDIT - changes will be overwritten');
  lines.push('');

  for (const parsed of specs) {
    const spec = parsed.spec as ConfigSpec;
    const interfaceName = pascalCase(spec.section.replace(/\./g, '')) + 'Config';

    lines.push(`/**`);
    lines.push(` * ${spec.name}`);
    lines.push(` * Configuration section: ${spec.section}`);
    lines.push(` * @version ${spec.version}`);
    lines.push(` */`);
    lines.push(`export interface ${interfaceName} {`);

    generateConfigInterface(spec.properties, lines, 1);

    lines.push('}');
    lines.push('');
  }

  // Generate root config interface
  lines.push('/**');
  lines.push(' * Root configuration interface combining all config sections');
  lines.push(' */');
  lines.push('export interface PTMSConfig {');
  for (const parsed of specs) {
    const spec = parsed.spec as ConfigSpec;
    const interfaceName = pascalCase(spec.section.replace(/\./g, '')) + 'Config';
    const propName = camelCase(spec.section.replace(/\./g, '_'));
    lines.push(`  ${propName}?: ${interfaceName};`);
  }
  lines.push('}');
  lines.push('');

  writeFileSync(join(outputDir, 'config.ts'), lines.join('\n'));
}

function generateConfigInterface(properties: ConfigProperty[], lines: string[], depth: number): void {
  const indent = '  '.repeat(depth);

  for (const prop of properties) {
    const tsType = configPropertyToTypeScript(prop);
    const optional = !prop.required ? '?' : '';
    const comment = prop.description ? ` // ${prop.description.split('\n')[0].trim()}` : '';

    if (prop.type === 'object' && prop.properties) {
      lines.push(`${indent}${camelCase(prop.name)}${optional}: {${comment}`);
      generateConfigInterface(prop.properties, lines, depth + 1);
      lines.push(`${indent}};`);
    } else {
      lines.push(`${indent}${camelCase(prop.name)}${optional}: ${tsType};${comment}`);
    }
  }
}

function generateIndexFile(entitySpecs: ParsedSpec[], configSpecs: ParsedSpec[], outputDir: string): void {
  const lines: string[] = [];

  lines.push('// Auto-generated index file');
  lines.push('// DO NOT EDIT - changes will be overwritten');
  lines.push('');
  lines.push("export * from './entities.js';");
  lines.push("export * from './config.js';");
  lines.push('');

  writeFileSync(join(outputDir, 'index.ts'), lines.join('\n'));
}

function fieldToTypeScript(field: EntityField, entityName: string): string {
  switch (field.type) {
    case 'string':
    case 'text':
      return 'string';
    case 'integer':
      return 'number';
    case 'decimal':
      return 'number';
    case 'boolean':
      return 'boolean';
    case 'date':
    case 'datetime':
      return 'Date';
    case 'enum':
      return `${entityName}${field.name}`;
    case 'json':
      return 'Record<string, unknown>';
    default:
      return 'unknown';
  }
}

function configPropertyToTypeScript(prop: ConfigProperty): string {
  switch (prop.type) {
    case 'string':
    case 'duration':
      return 'string';
    case 'integer':
    case 'decimal':
      return 'number';
    case 'boolean':
      return 'boolean';
    case 'array':
      return 'unknown[]';
    case 'object':
      return 'Record<string, unknown>';
    default:
      return 'unknown';
  }
}

function camelCase(str: string): string {
  return str.charAt(0).toLowerCase() + str.slice(1);
}

function pascalCase(str: string): string {
  return str
    .split(/[-_]/)
    .map(part => part.charAt(0).toUpperCase() + part.slice(1).toLowerCase())
    .join('');
}
