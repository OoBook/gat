# GAT - GitHub Actions Tester

A universal testing tool for GitHub Actions workflows. Test your workflows locally before pushing to GitHub.

## Features

✅ **Auto-discovers workflows** - Finds all workflows in your repository  
✅ **Scenario-based testing** - Define multiple test cases per workflow  
✅ **Local execution** - Test with Act (Docker-based GitHub Actions runner)  
✅ **Dry-run simulation** - Preview workflow behavior without execution  
✅ **Multi-project support** - Test workflows across different repositories  
✅ **Flexible configuration** - Customize paths, Act flags, and test scenarios  

## Installation

### Quick Install (Recommended)

```bash
# Clone or download
git clone https://github.com/oobook/gat.git
cd gat

# Make executable
chmod +x main.sh

# Create system-wide command
sudo ln -s "$(pwd)/main.sh" /usr/local/bin/gat
```

### Manual Install

```bash
# Download the script
curl -o main.sh https://raw.githubusercontent.com/oobook/gat/main/main.sh

# Make executable
chmod +x main.sh

# Move to PATH
sudo mv main.sh /usr/local/bin/gat
```

1. Install latest version:

```bash
curl -sSL https://raw.githubusercontent.com/oobook/gat/main/install.sh | bash
```

2. Install specific version:

```bash
curl -sSL https://raw.githubusercontent.com/oobook/gat/main/install.sh | bash -s v1.0.0
```

## Dependencies

**Required:**
- `jq` - JSON processor

**Optional:**
- `yq` - Better YAML parsing
- `act` - Local GitHub Actions runner
- `docker` - Required for Act

### Install Dependencies

```bash
# macOS
brew install jq yq act

# Linux (Ubuntu/Debian)
sudo apt-get install jq
# For yq and act, see their official installation guides

# Start Docker Desktop (macOS)
open -a Docker
```

## Quick Start

### 1. List Available Workflows

```bash
# In your repository
gat list

# Or specify project directory
gat -p path/to/repo list
```

### 2. Initialize Test Scenarios

```bash
# Initialize by workflow number
gat init 1

# Or by workflow name
gat init create-issue-branch
```

This creates a test scenarios file at `.github/workflow-tests/<workflow-name>-scenarios.json`

### 3. View Test Scenarios

```bash
gat list-scenarios create-issue-branch
```

### 4. Run Tests

```bash
# Dry run (simulation only)
gat test create-issue-branch 1

# Run with Act (full execution)
gat test create-issue-branch 1 --act

# Run all scenarios
gat test-all create-issue-branch --act
```

## Usage

```bash
gat [flags] <command> [options]
```

### Flags

| Flag | Description | Default |
|------|-------------|---------|
| `-p, --project-dir <path>` | Git project directory | Auto-detect |
| `-w, --workflows-dir <path>` | Workflows directory | `.github/workflows` |
| `-c, --config-dir <path>` | Config directory | `.github/workflow-tests` |
| `-a, --act-flags <flags>` | Additional Act flags | None |
| `-h, --help` | Show help message | - |

### Commands

| Command | Description |
|---------|-------------|
| `list, ls` | List all workflows |
| `init <workflow>` | Initialize test scenarios |
| `list-scenarios <workflow>` | List test scenarios |
| `test <workflow> <num>` | Test a specific scenario |
| `test <workflow> <num> --act` | Test with Act |
| `test-all <workflow>` | Test all scenarios |
| `help` | Show help message |

## Examples

### Basic Usage

```bash
# List workflows in current repo
gat list

# Initialize tests for first workflow
gat init 1

# Test first scenario (dry run)
gat test my-workflow 1

# Test with Act
gat test my-workflow 1 --act
```

### Multi-Project Testing

```bash
# Test workflow in another project
gat -p ~/projects/myapp list
gat -p ~/projects/myapp test workflow 1 --act

# Test with custom paths
gat -p myproject -w .github/workflows -c tests/workflows init 1
```

### Advanced Act Configuration

```bash
# Run with custom Act flags
gat -a '--container-architecture linux/amd64' test workflow 1 --act

# Multiple Act flags
gat -a '--verbose --container-daemon-socket unix:///var/run/docker.sock' test workflow 1 --act

# Dry run with Act
gat -a '--dryrun' test workflow 1 --act
```

### Real-World Workflow

```bash
# 1. Navigate to your project
cd myproject

# 2. List workflows
gat list

# 3. Initialize tests for "Create Issue Branch" workflow
gat init create-issue-branch

# 4. Edit test scenarios
vim .github/workflow-tests/create-issue-branch-scenarios.json

# 5. View scenarios
gat list-scenarios create-issue-branch

# 6. Test first scenario (simulation)
gat test create-issue-branch 1

# 7. Test with Act
gat test create-issue-branch 1 --act

# 8. Test all scenarios
gat test-all create-issue-branch --act
```

## Test Scenarios Format

Scenarios are defined in JSON format at `.github/workflow-tests/<workflow-name>-scenarios.json`:

```json
{
  "workflow": ".github/workflows/create-issue-branch.yml",
  "trigger": "issues",
  "scenarios": [
    {
      "name": "Feature from version branch",
      "description": "Test feature branch creation from 1.x",
      "event": {
        "action": "labeled",
        "issue": {
          "number": 101,
          "title": "[Enhancement]: Add user authentication",
          "labels": [
            {"name": "enhancement"},
            {"name": "planned"},
            {"name": "1.x"}
          ]
        }
      }
    },
    {
      "name": "Critical hotfix",
      "description": "Test critical bug creates hotfix from default branch",
      "event": {
        "action": "labeled",
        "issue": {
          "number": 102,
          "title": "[Bug]: Security vulnerability",
          "labels": [
            {"name": "bug"},
            {"name": "planned"}
          ]
        },
        "severity": "Critical"
      }
    }
  ]
}
```

### Supported Triggers

GAT automatically generates templates for:
- `issues` - Issue events
- `pull_request` - Pull request events
- `push` - Push events
- `workflow_dispatch` - Manual triggers
- Custom triggers (with basic template)

## Common Act Flags

| Flag | Description |
|------|-------------|
| `--container-architecture linux/amd64` | Set container architecture |
| `--container-daemon-socket <socket>` | Specify Docker socket |
| `--verbose` or `-v` | Verbose output |
| `--dryrun` | Show what would run without executing |
| `-P ubuntu-latest=<image>` | Specify runner image |
| `--secret-file <file>` | Load secrets from file |

## Troubleshooting

### "jq: command not found"

```bash
# Install jq
brew install jq  # macOS
sudo apt-get install jq  # Linux
```

### "Docker is not running"

```bash
# Start Docker Desktop
open -a Docker  # macOS

# Or start Docker daemon
sudo systemctl start docker  # Linux
```

### "Not inside a git repository"

```bash
# Use -p flag to specify project directory
gat -p path/to/your/repo test workflow 1 --act
```

### Act fails with architecture error

```bash
# Specify architecture explicitly
gat -a '--container-architecture linux/amd64' test workflow 1 --act
```

## Project Structure

```
your-repo/
├── .github/
│   ├── workflows/
│   │   ├── ci.yml
│   │   └── create-issue-branch.yml
│   └── workflow-tests/
│       ├── ci-scenarios.json
│       ├── create-issue-branch-scenarios.json
│       └── event.json (generated)
└── ...
```

## Tips

1. **Start with simulation**: Use `gat test workflow 1` (without `--act`) to preview event data before running with Act

2. **Edit scenarios incrementally**: Start with the generated template and add your specific test cases

3. **Use version-specific tests**: For workflows that handle version branches (e.g., 1.x, 2.x), create scenarios for each version

4. **Store secrets safely**: Never commit secrets to test scenarios. Use Act's `--secret-file` option instead

5. **Debug with verbose**: Add `-a '--verbose'` to see detailed Act execution logs

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see LICENSE file for details

## Author

Created by [Your Name]

## Support

- Issues: https://github.com/yourusername/gat/issues
- Discussions: https://github.com/yourusername/gat/discussions

---

**Made with ❤️ for the GitHub Actions community**