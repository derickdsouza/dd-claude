#!/usr/bin/env node

import { program } from 'commander';
import { existsSync, mkdirSync } from 'fs';
import { resolve, dirname } from 'path';
import { fileURLToPath } from 'url';
import chalk from 'chalk';
import { parseAllSpecs } from './parser.js';
import { generateDocs } from './generators/docs-generator.js';
import { generateTypeScript } from './generators/typescript-generator.js';

// Get the directory of this script
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Project root is two levels up from tools/spec-generator/src
const PROJECT_ROOT = resolve(__dirname, '../../..');

const DEFAULT_SPEC_DIR = resolve(PROJECT_ROOT, 'spec');
const DEFAULT_DOCS_OUTPUT = resolve(PROJECT_ROOT, 'docs/reference');
const DEFAULT_TS_OUTPUT = resolve(PROJECT_ROOT, 'frontend/src/generated');

program
  .name('spec-generator')
  .description('Generate documentation and types from PTMS YAML specifications')
  .version('1.0.0')
  .option('-s, --spec-dir <path>', 'Specification directory', 'spec')
  .option('-o, --docs-output <path>', 'Documentation output directory', 'docs/reference')
  .option('-t, --ts-output <path>', 'TypeScript output directory', 'frontend/src/generated')
  .option('--docs', 'Generate documentation only')
  .option('--typescript', 'Generate TypeScript types only')
  .option('--validate', 'Validate specifications only (no generation)')
  .option('-v, --verbose', 'Verbose output');

program.parse();

const options = program.opts();

async function main(): Promise<void> {
  // Use provided paths or defaults (defaults are already absolute)
  const specDir = options.specDir.startsWith('/') ? options.specDir : resolve(PROJECT_ROOT, options.specDir);
  const docsOutput = options.docsOutput.startsWith('/') ? options.docsOutput : resolve(PROJECT_ROOT, options.docsOutput);
  const tsOutput = options.tsOutput.startsWith('/') ? options.tsOutput : resolve(PROJECT_ROOT, options.tsOutput);

  console.log(chalk.blue('PTMS Specification Generator'));
  console.log(chalk.gray('═'.repeat(50)));

  // Validate spec directory exists
  if (!existsSync(specDir)) {
    console.error(chalk.red(`Error: Specification directory not found: ${specDir}`));
    process.exit(1);
  }

  console.log(chalk.gray(`Spec directory: ${specDir}`));

  // Parse all specifications
  console.log(chalk.yellow('\n📖 Parsing specifications...'));

  let specs;
  try {
    specs = await parseAllSpecs(specDir);
    console.log(chalk.green(`   Found ${specs.length} specifications:`));

    const counts = {
      entity: specs.filter(s => s.type === 'entity').length,
      config: specs.filter(s => s.type === 'config').length,
      service: specs.filter(s => s.type === 'service').length,
      workflow: specs.filter(s => s.type === 'workflow').length,
    };

    console.log(chalk.gray(`   - ${counts.entity} entities`));
    console.log(chalk.gray(`   - ${counts.config} config schemas`));
    console.log(chalk.gray(`   - ${counts.service} services`));
    console.log(chalk.gray(`   - ${counts.workflow} workflows`));

    if (options.verbose) {
      for (const spec of specs) {
        console.log(chalk.gray(`     • ${spec.type}/${spec.fileName}`));
      }
    }
  } catch (error) {
    console.error(chalk.red(`Error parsing specifications: ${error}`));
    process.exit(1);
  }

  // Validate only mode
  if (options.validate) {
    console.log(chalk.green('\n✓ All specifications parsed successfully'));
    return;
  }

  // Determine what to generate
  const generateDocsFlag = options.docs || (!options.docs && !options.typescript);
  const generateTsFlag = options.typescript || (!options.docs && !options.typescript);

  // Generate documentation
  if (generateDocsFlag) {
    console.log(chalk.yellow('\n📝 Generating documentation...'));
    console.log(chalk.gray(`   Output: ${docsOutput}`));

    if (!existsSync(docsOutput)) {
      mkdirSync(docsOutput, { recursive: true });
    }

    try {
      generateDocs(specs, docsOutput);
      console.log(chalk.green('   ✓ Documentation generated successfully'));
    } catch (error) {
      console.error(chalk.red(`   Error generating docs: ${error}`));
      process.exit(1);
    }
  }

  // Generate TypeScript types
  if (generateTsFlag) {
    console.log(chalk.yellow('\n🔷 Generating TypeScript types...'));
    console.log(chalk.gray(`   Output: ${tsOutput}`));

    if (!existsSync(tsOutput)) {
      mkdirSync(tsOutput, { recursive: true });
    }

    try {
      generateTypeScript(specs, tsOutput);
      console.log(chalk.green('   ✓ TypeScript types generated successfully'));
    } catch (error) {
      console.error(chalk.red(`   Error generating TypeScript: ${error}`));
      process.exit(1);
    }
  }

  console.log(chalk.blue('\n═'.repeat(50)));
  console.log(chalk.green('✓ Generation complete!'));
}

main().catch((error) => {
  console.error(chalk.red(`Unexpected error: ${error}`));
  process.exit(1);
});
