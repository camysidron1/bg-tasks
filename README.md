# 🚀 bg-task

Smart terminal-based task management with AI-powered task generation.

## ✨ Features

- **🎯 Quick Task Creation**: `bg taskname` creates timestamped task files instantly
- **🤖 AI-Powered Tasks**: `bg -ai taskname` uses Claude 4 to analyze your terminal history and create intelligent task templates
- **📝 Editor Agnostic**: Works with any text editor - vim, VS Code, nano, emacs, etc.
- **🧹 Easy Cleanup**: `bg clear` safely removes all task files with confirmation
- **⚙️ Smart Setup**: `bg --setup` automatically configures directories, gitignore, and environment

## 🔠️ Installation

```bash
npm install -g bg-task
```

The package will automatically:
1. **Detect your shell** (zsh/bash/fish)  
2. **Navigate to select your project directory** (interactive folder tree)
3. **Install the `bg` function** to your shell config

## 🎮 Usage

### Basic Commands
```bash
bg taskname          # Create a new task file
bg -ai taskname      # Create AI-powered task (requires API key)
bg clear             # Delete all task files (with confirmation)
bg --setup           # Setup/re-setup environment
```

### Examples
```bash
# Create a simple task
bg fix-login-bug

# Create an AI-powered task that analyzes your terminal history
bg -ai implement-authentication

# Clean up completed tasks
bg clear
```

## 🤖 AI Features Setup

To enable AI-powered task generation:

1. Get your API key from [Anthropic Console](https://console.anthropic.com/)
2. Add to your project's `.env` file:
   ```
   ANTHROPIC_API_KEY=your-key-here
   ```
3. Or export it globally:
   ```bash
   export ANTHROPIC_API_KEY='your-key-here'
   ```

The AI will analyze your recent terminal commands, git status, and current directory to create contextual, actionable task templates.

## 📁 File Structure

Tasks are created in a `To-Dos/` directory in your project root:
```
your-project/
├── To-Dos/                    # Auto-created, gitignored
│   ├── 2025-08-25_14-30-22_fix-bug.md
│   └── 2025-08-25_15-45-10_add-feature.md
├── .gitignore                 # Auto-updated
└── .env                       # For API keys
```


## 📋 Task Template

Each task file includes:
```markdown
# Task: your-task-name
Created: Thu Aug 25 14:30:22 PDT 2025

## Description
[AI generates context-aware description or blank for manual entry]

## Progress
- [ ] [AI generates actionable steps based on terminal history]
- [ ] 
- [ ] 

## Notes
[AI includes relevant file paths, errors, or technical context]
```

## 🔧 Customization

After installation, you can edit the `bg` function in your shell config to customize the project directory or other settings.

## 🗑️ Uninstalling

```bash
npm uninstall -g bg-task
```

Then manually remove the `bg` function from your shell config file (`~/.zshrc`, `~/.bashrc`, etc.).

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License.

## ❓ FAQ

**Q: Can I use this without AI features?**  
A: Yes! All basic functionality works without an API key.

**Q: What shells are supported?**  
A: Currently zsh, bash, and fish.

**Q: Can I use a different AI provider?**  
A: Currently supports Anthropic's Claude. OpenAI support planned.

**Q: How do I change the project directory after installation?**  
A: Edit the `bg` function in your shell config file and update the `project_root` variable.

---

Made with ❤️ for developers who love efficient task management.
