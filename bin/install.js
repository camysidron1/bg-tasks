#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

const chalk = require('chalk');

const homeDir = os.homedir();
const packageDir = path.dirname(__dirname);

const MARKER_START = '# >>> bg-task start >>>';
const MARKER_END = '# <<< bg-task end <<<'
const SNIPPET = `${MARKER_START}\n# bg-task: source function\nif [ -f "$HOME/.config/bg-task/bg-task.zsh" ]; then\n  source "$HOME/.config/bg-task/bg-task.zsh"\nfi\n${MARKER_END}\n`;

console.log(chalk.cyan('🚀 Installing bg-task...'));

function getShellConfigPath() {
  const shell = process.env.SHELL || '';
  if (shell.includes('zsh')) return path.join(homeDir, '.zshrc');
  if (shell.includes('bash')) return path.join(homeDir, '.bashrc');
  if (shell.includes('fish')) return path.join(homeDir, '.config/fish/config.fish');
  // Default to zsh if unknown
  return path.join(homeDir, '.zshrc');
}

function ensureDir(p) {
  if (!fs.existsSync(p)) fs.mkdirSync(p, { recursive: true });
}

function getBgFunctionTemplate() {
  return fs.readFileSync(path.join(packageDir, 'templates/bg-function.sh'), 'utf8');
}

function backupFile(file) {
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const backup = `${file}.bg-task.bak.${ts}`;
  fs.copyFileSync(file, backup);
  return backup;
}

function applySnippetToConfig(configPath) {
  let content = fs.existsSync(configPath) ? fs.readFileSync(configPath, 'utf8') : '';
  const startIdx = content.indexOf(MARKER_START);
  const endIdx = content.indexOf(MARKER_END);
  if (startIdx !== -1 && endIdx !== -1 && endIdx > startIdx) {
    // Replace existing block
    const before = content.slice(0, startIdx);
    const after = content.slice(endIdx + MARKER_END.length);
    content = `${before}${SNIPPET}${after}`;
  } else {
    // Append with separation
    if (content.length && !content.endsWith('\n')) content += '\n';
    content += `\n${SNIPPET}`;
  }
  fs.writeFileSync(configPath, content);
}

function validateZsh(configPath) {
  try {
    execSync(`zsh -n ${configPath}`, { stdio: 'pipe' });
    return true;
  } catch (e) {
    return false;
  }
}

function stripLegacyEmbeddedFunction(configPath) {
  if (!fs.existsSync(configPath)) return;
  let content = fs.readFileSync(configPath, 'utf8');
  if (!content.includes('# Enhanced bg function')) return;
  const lines = content.split('\n');
  const startIndex = lines.findIndex(l => l.includes('# Enhanced bg function'));
  // Find matching function end by searching for the closing brace of bg() with alias line that follows
  let endIndex = -1;
  for (let i = startIndex + 1; i < lines.length; i++) {
    if (lines[i].startsWith('alias begin=')) { endIndex = i; break; }
  }
  if (startIndex !== -1 && endIndex !== -1) {
    lines.splice(startIndex, (endIndex - startIndex) + 1);
    fs.writeFileSync(configPath, lines.join('\n'));
  }
}

function main() {
  try {
    const configDir = path.join(homeDir, '.config', 'bg-task');
    const funcPath = path.join(configDir, 'bg-task.zsh');
    const configPath = getShellConfigPath();

    // Ensure config directory and write function file
    ensureDir(configDir);
    fs.writeFileSync(funcPath, getBgFunctionTemplate());

    // Backup shell config before editing
    ensureDir(path.dirname(configPath));
    if (!fs.existsSync(configPath)) fs.writeFileSync(configPath, '');
    const backup = backupFile(configPath);

    // Remove legacy embedded function if present and insert idempotent snippet
    stripLegacyEmbeddedFunction(configPath);
    applySnippetToConfig(configPath);

    // Validate and rollback if necessary
    if (!validateZsh(configPath)) {
      fs.copyFileSync(backup, configPath);
      console.log(chalk.red('❌ Validation failed. Restored your original shell config.'));
      process.exit(1);
    }

    console.log(chalk.green('✅ bg-task installed: added source snippet to your shell config.'));
    console.log(chalk.gray(`Function file: ${funcPath}`));

    console.log(chalk.green.bold('\n🎉 bg-task ready!'));
    console.log(chalk.cyan('\nNext steps:'));
    console.log(chalk.white('  1. Restart your terminal or run: source ' + configPath));
    console.log(chalk.white('  2. Run: bg --setup'));
    console.log(chalk.white('  3. Try: bg --help'));
  } catch (error) {
    console.error(chalk.red('❌ Installation failed:'), error.message);
    process.exit(1);
  }
}

main();
