# Installing TaskPlex for Codex

Enable TaskPlex skills in Codex via native skill discovery. Just clone and symlink.

## Prerequisites

- Git

## Installation

1. **Clone the TaskPlex repository:**
   ```bash
   git clone https://github.com/flight505/taskplex.git ~/.codex/taskplex
   ```

2. **Create the skills symlink:**
   ```bash
   mkdir -p ~/.agents/skills
   ln -s ~/.codex/taskplex/skills ~/.agents/skills/taskplex
   ```

   **Windows (PowerShell):**
   ```powershell
   New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\.agents\skills"
   cmd /c mklink /J "$env:USERPROFILE\.agents\skills\taskplex" "$env:USERPROFILE\.codex\taskplex\skills"
   ```

3. **Restart Codex** (quit and relaunch the CLI) to discover the skills.

## Verify

```bash
ls -la ~/.agents/skills/taskplex
```

You should see a symlink (or junction on Windows) pointing to your TaskPlex skills directory.

## Updating

```bash
cd ~/.codex/taskplex && git pull
```

Skills update instantly through the symlink.

## Uninstalling

```bash
rm ~/.agents/skills/taskplex
```

Optionally delete the clone: `rm -rf ~/.codex/taskplex`.
