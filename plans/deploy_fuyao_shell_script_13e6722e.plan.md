---
name: Deploy Fuyao Shell Script
overview: Create a short, deterministic `deploy_fuyao` shell script in your Cursor toolbox and wire the existing Cursor command to invoke it, preserving current behavior while removing command inconsistency.
todos:
  - id: create-wrapper
    content: Create canonical `~/.cursor/scripts/deploy_fuyao.sh` wrapper script with strict mode, prechecks, repo-root resolution, and arg passthrough.
    status: pending
  - id: wire-command
    content: Update `~/.cursor/commands/deploy-fuyao.md` to invoke the wrapper script as the single execution path.
    status: pending
  - id: validate-wrapper
    content: Run help/argument-forwarding checks and confirm behavior mirrors existing `humanoid-gym/scripts/fuyao_deploy.sh`.
    status: pending
  - id: sync-toolbox-local
    content: Apply local toolbox sync workflow after command/script edits and report sync outcome.
    status: pending
isProject: false
---

# Implement Short `deploy_fuyao` Script in Cursor Toolbox

## So this is the workflow that I want:

1. First SSH into the remote kernel.So this is the workflow that I want:
2. First, SSH into the remote kernel.
