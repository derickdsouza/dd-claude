import { readFileSync, existsSync } from 'fs';
import { parse as parseYaml } from 'yaml';
import { glob } from 'glob';
import { join, basename } from 'path';
import type { EntitySpec, ConfigSpec, ServiceSpec, WorkflowSpec, SpecType } from './types.js';

export interface ParsedSpec {
  type: SpecType;
  filePath: string;
  fileName: string;
  spec: EntitySpec | ConfigSpec | ServiceSpec | WorkflowSpec;
}

export async function parseAllSpecs(specDir: string): Promise<ParsedSpec[]> {
  const specs: ParsedSpec[] = [];

  // Parse domain entities
  const entityFiles = await glob(join(specDir, 'domain', '*.yaml'));
  for (const file of entityFiles) {
    const spec = parseYamlFile<EntitySpec>(file);
    specs.push({ type: 'entity', filePath: file, fileName: basename(file, '.yaml'), spec });
  }

  // Parse config specs
  const configFiles = await glob(join(specDir, 'config', '*.yaml'));
  for (const file of configFiles) {
    const spec = parseYamlFile<ConfigSpec>(file);
    specs.push({ type: 'config', filePath: file, fileName: basename(file, '.yaml'), spec });
  }

  // Parse service specs
  const serviceFiles = await glob(join(specDir, 'services', '*.yaml'));
  for (const file of serviceFiles) {
    const spec = parseYamlFile<ServiceSpec>(file);
    specs.push({ type: 'service', filePath: file, fileName: basename(file, '.yaml'), spec });
  }

  // Parse workflow specs
  const workflowFiles = await glob(join(specDir, 'workflows', '*.yaml'));
  for (const file of workflowFiles) {
    const spec = parseYamlFile<WorkflowSpec>(file);
    specs.push({ type: 'workflow', filePath: file, fileName: basename(file, '.yaml'), spec });
  }

  return specs;
}

function parseYamlFile<T>(filePath: string): T {
  if (!existsSync(filePath)) {
    throw new Error(`File not found: ${filePath}`);
  }

  const content = readFileSync(filePath, 'utf-8');
  return parseYaml(content) as T;
}

export function getSpecsByType(specs: ParsedSpec[], type: SpecType): ParsedSpec[] {
  return specs.filter(s => s.type === type);
}
