// Type definitions for PTMS specifications

export interface EntitySpec {
  name: string;
  description: string;
  version: string;
  tableName?: string;
  fields: EntityField[];
  relationships?: Relationship[];
  indexes?: Index[];
  validation?: ValidationRule[];
  audit?: AuditSettings;
}

export interface EntityField {
  name: string;
  type: 'string' | 'integer' | 'decimal' | 'boolean' | 'date' | 'datetime' | 'enum' | 'json' | 'text';
  description?: string;
  primary?: boolean;
  required?: boolean;
  unique?: boolean;
  maxLength?: number;
  minLength?: number;
  precision?: number;
  scale?: number;
  default?: unknown;
  values?: string[];
  references?: string;
  nullable?: boolean;
  encrypted?: boolean;
  sensitive?: boolean;
}

export interface Relationship {
  name: string;
  type: 'one-to-one' | 'one-to-many' | 'many-to-one' | 'many-to-many';
  target: string;
  foreignKey?: string;
  through?: string;
}

export interface Index {
  name?: string;
  fields: string[];
  unique?: boolean;
}

export interface ValidationRule {
  rule: string;
  message: string;
}

export interface AuditSettings {
  enabled?: boolean;
  trackCreated?: boolean;
  trackUpdated?: boolean;
  trackBy?: boolean;
}

export interface ConfigSpec {
  name: string;
  description: string;
  version: string;
  section: string;
  properties: ConfigProperty[];
  environmentVariables?: EnvVar[];
}

export interface ConfigProperty {
  name: string;
  type: 'string' | 'integer' | 'decimal' | 'boolean' | 'duration' | 'array' | 'object';
  description: string;
  default?: unknown;
  required?: boolean;
  sensitive?: boolean;
  minimum?: number;
  maximum?: number;
  pattern?: string;
  enum?: string[];
  items?: object;
  properties?: ConfigProperty[];
  examples?: unknown[];
}

export interface EnvVar {
  name: string;
  property: string;
  description?: string;
}

export interface ServiceSpec {
  name: string;
  description: string;
  version: string;
  namespace?: string;
  className?: string;
  dependencies?: Dependency[];
  configuration?: ServiceConfig;
  operations?: Operation[];
  events?: ServiceEvents;
  metrics?: Metric[];
  gracefulDegradation?: GracefulDegradation;
}

export interface Dependency {
  name: string;
  description?: string;
}

export interface ServiceConfig {
  section: string;
  properties?: ConfigProperty[];
}

export interface Operation {
  name: string;
  description: string;
  parameters?: Parameter[];
  returns?: string;
  behavior?: string;
}

export interface Parameter {
  name: string;
  type: string;
  description?: string;
}

export interface ServiceEvents {
  published?: EventDef[];
  consumed?: EventDef[];
}

export interface EventDef {
  name: string;
  description: string;
  payload?: string[];
  source?: string;
}

export interface Metric {
  name: string;
  type: 'counter' | 'gauge' | 'histogram';
  labels?: string[];
  description: string;
}

export interface GracefulDegradation {
  enabled: boolean;
  description?: string;
  configuration?: ServiceConfig;
}

export interface WorkflowSpec {
  name: string;
  description: string;
  version: string;
  initialState: string;
  states: WorkflowState[];
  transitions: Transition[];
  hooks?: WorkflowHooks;
}

export interface WorkflowState {
  name: string;
  description: string;
  terminal: boolean;
  allowedActions: string[];
}

export interface Transition {
  from: string;
  to: string;
  action: string;
  description?: string;
  requiredRole?: string[];
  condition?: string;
  sideEffects?: string[];
}

export interface WorkflowHooks {
  onEnter?: Hook[];
  onExit?: Hook[];
  onTransition?: Hook[];
}

export interface Hook {
  state?: string;
  action: string;
  description?: string;
  applies?: string;
}

export type SpecType = 'entity' | 'config' | 'service' | 'workflow';

export interface GeneratorOptions {
  specDir: string;
  outputDir: string;
  generateDocs: boolean;
  generateTs: boolean;
  validateOnly: boolean;
}
