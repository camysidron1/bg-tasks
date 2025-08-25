#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

const chalk = require('chalk');

const homeDir = os.homedir();
const MARKER_START = '# >>> bg-task start >>>';
const MARKER_END = '# <<< bg-task end <<<'

console.log(chalk.yellow('🗑️  Uninstalling bg-task...'));

function getShellConfigs() {
  return [
    path.join(homeDir, '.zshrc'),
    path.join(homeDir, '.bashrc'),
    path.join(homeDir, '.config/fish/config.fish')
  ];
}

function backupFile(file) {
  if (!fs.existsSync(file)) return null;
  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const backup = `${file}.bg-task.bak.${ts}`;
  fs.copyFileSync(file, backup);
  return backup;
}

function removeSnippet(configPath) {
  if (!fs.existsSync(configPath)) return false;
  let content = fs.readFileSync(configPath, 'utf8');
  const startIdx = content.indexOf(MARKER_START);
  const endIdx = content.indexOf(MARKER_END);
  if (startIdx !== -1 && endIdx !== -1 && endIdx > startIdx) {
    const before = content.slice(0, startIdx);
    const after = content.slice(endIdx + MARKER_END.length);
    fs.writeFileSync(configPath, before + after);
    return true;
  }
  return false;
}

function validateZsh(configPath) {
  try {
    execSync(`zsh -n ${configPath}`, { stdio: 'pipe' });
    return true;
  } catch (e) {
    return false;
  }
}

function main() {
  const shellConfigs = getShellConfigs();
  let removedAny = false;

  for (const configPath of shellConfigs) {
    const backup = backupFile(configPath);
    const removed = removeSnippet(configPath);
    if (removed) {
      removedAny = true;
      if (!validateZsh(configPath)) {
        // rollback
        if (backup) fs.copyFileSync(backup, configPath);
        console.log(chalk.red(`❌ Validation failed; restored ${configPath}`));
      } else {
        console.log(chalk.green(`✅ Removed bg-task snippet from ${configPath}`));
      }
    }
  }

  // Remove function file
  const funcPath = path.join(homeDir, '.config', 'bg-task', 'bg-task.zsh');
  try { fs.unlinkSync(funcPath); } catch {}

  if (!removedAny) {
    console.log(chalk.yellow('ℹ️  No bg-task snippet found in shell configs'));
  }

  console.log(chalk.green('\n✨ bg-task uninstalled successfully!'));
  console.log(chalk.cyan('Restart your terminal or run: source ~/.zshrc (or your shell config)'));
}

main();
