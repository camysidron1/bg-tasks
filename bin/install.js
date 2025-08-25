#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

const chalk = require('chalk');

const homeDir = os.homedir();
const packageDir = path.dirname(__dirname);

const MARKER_START = '# >>> bgt-task start >>>';
const MARKER_END = '# <<< bgt-task end <<<'
const SNIPPET = `${MARKER_START}\n# bgt-task: source function\nif [ -f "$HOME/.config/bgt-task/bgt.zsh" ]; then\n  source "$HOME/.config/bgt-task/bgt.zsh"\nfi\n${MARKER_END}\n`;

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
  // Find matching function end by searching for the closing brace of function with alias line that follows
  let endIndex = -1;
  for (let i = startIndex + 1; i < lines.length; i++) {
    if (lines[i].startsWith('alias begin=')) { endIndex = i; break; }
  }
  if (startIndex !== -1 && endIndex !== -1) {
    lines.splice(startIndex, (endIndex - startIndex) + 1);
    fs.writeFileSync(configPath, lines.join('\n'));
  }
}

// Remove an old bg-task snippet block if present
function removeOldSnippet(configPath) {
  if (!fs.existsSync(configPath)) return;
  const OLD_START = '# >>> bg-task start >>>';
  const OLD_END = '# <<< bg-task end <<<'
  let content = fs.readFileSync(configPath, 'utf8');
  const startIdx = content.indexOf(OLD_START);
  const endIdx = content.indexOf(OLD_END);
  if (startIdx !== -1 && endIdx !== -1 && endIdx > startIdx) {
    const before = content.slice(0, startIdx);
    const after = content.slice(endIdx + OLD_END.length);
    fs.writeFileSync(configPath, before + after);
  }
}

function main() {
  try {
    const configDir = path.join(homeDir, '.config', 'bgt-task');
    const funcPath = path.join(configDir, 'bgt.zsh');
    const configPath = getShellConfigPath();

    // Ensure config directory and write function file
    ensureDir(configDir);
    fs.writeFileSync(funcPath, getBgFunctionTemplate());

    // Backup shell config before editing
    ensureDir(path.dirname(configPath));
    if (!fs.existsSync(configPath)) fs.writeFileSync(configPath, '');
    const backup = backupFile(configPath);

    // Remove legacy embedded function and old bg-task snippet if present, then insert idempotent new snippet
    stripLegacyEmbeddedFunction(configPath);
    removeOldSnippet(configPath);
    applySnippetToConfig(configPath);

    // Validate and rollback if necessary
    if (!validateZsh(configPath)) {
      fs.copyFileSync(backup, configPath);
      console.log(chalk.red('❌ Validation failed. Restored your original shell config.'));
      process.exit(1);
    }

    console.log(chalk.green('✅ bgt-task installed: added source snippet to your shell config.'));
    console.log(chalk.gray(`Function file: ${funcPath}`));

    console.log(chalk.green.bold('\n🎉 bgt-task ready!'));
    console.log(chalk.cyan('\nNext steps:'));
    console.log(chalk.white('  1. Restart your terminal or run: source ' + configPath));
    console.log(chalk.white('  2. Run: bgt --setup'));
    console.log(chalk.white('  3. Try: bgt --help'));
  } catch (error) {
    console.error(chalk.red('❌ Installation failed:'), error.message);
    process.exit(1);
  }
}

main();
