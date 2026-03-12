# Fuyao Remote Deploy (User Command)

Use this command to run the verified deployment flow through the wrapper script:
`humanoid-gym/scripts/fuyao_deploy.sh`.
Invoke as `/deploy-fuyao`.

## Required Inputs

Collect these values before execution:

- `branch` (git branch to sync to remote kernel repo before deploy)
- `task` (must be a registered task name)
- `label` (always collect via selectable prompt; include generated suggested label)
- `experiment` for Fuyao experiment name (default: `huh8/r01`; do not prompt unless user explicitly asks to override)

Optional:

- `project` (default: `rc-wbc`)
- `queue` (default: `rc-wbc-4090`; always use fully-qualified queue name, never bare aliases like `4090`)

## Argument Prompt Contract (Selectable Questions)

Collect inputs with selectable questions before any git/deploy command runs.
For required inputs, ask if missing. For `label`, always ask a selectable question even when a label was already provided.

Precedence order:

1. explicit values provided by user in invocation/message
2. answers from selectable questions
3. documented defaults/derivation

Prompt order when multiple required inputs are missing:

1. `branch`
2. `task`
3. `label`

### `branch` prompt contract

- Source branch candidates from:
  - `git branch --format='%(refname:short)'`
- If more than 12 branches are available:
  - show current branch first (if present), then alphabetical, trimmed to 12
- Present a single-select question with:
  - candidate branches
  - `Enter custom branch`
- If user selects custom, ask one follow-up free-form question for the branch name.

### `task` prompt contract

- Follow matching/validation workflow from **Task Validation (Mandatory + Fuzzy Match)**.
- If exact/case-insensitive matching does not resolve one concrete task:
  - present single-select choices of best task candidates
  - include `Enter custom task`
  - require explicit user selection before deploy

### `label` prompt contract (always ask)

- Show this prompt only after `branch` is resolved.
- Generate suggested label from selected branch:
  - if branch starts with `huh8/`, strip one leading `huh8/` prefix (`huh8/foo` -> `foo`)
  - otherwise use the branch string unchanged
- Present a single-select question with:
  - `Use suggested label: <generated_label>`
  - `Use provided label: <user_label>` (only when user provided `label`)
  - `Enter custom label`
- If user selects custom, ask one follow-up free-form question for label.
- If custom label is empty, re-prompt until label is non-empty.
- Do not execute deploy until one label option is explicitly selected.

### Optional input prompt behavior

- `project`, `site`, and `queue` do not block execution when omitted.
- If omitted, use defaults from **Defaults**.
- Only if user explicitly asks to configure optional values, present single-select questions:
  - `project`: `rc-wbc` or `Enter custom project`
  - `queue`: `rc-wbc-4090` or `Enter custom queue` (must be fully-qualified name like `rc-wbc-4090`, never bare `4090`)

## Baseline Command Pattern

Always execute deploy via SSH into remote kernel and wrapper script from repo root:

```bash
BRANCH="<branch>"
PROJECT="<project>"
LABEL="<label>"
TASK="<task>"
EXPERIMENT="<experiment>"
QUEUE="<queue>"

git checkout "${BRANCH}" \
    && if [[ -n "$(git status --porcelain)" ]]; then
    git add -A
    git commit -m "chore: commit before deploy"
fi
git push -u origin "${BRANCH}"

SSH_ALIAS="Huh8.remote_kernel.fuyao"
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${SSH_ALIAS}" "echo ok >/dev/null" >/dev/null 2>&1; then
  SSH_ALIAS="remote.kernel.fuyo"
fi
ssh "${SSH_ALIAS}" "cd /root/motion_rl && \
  git fetch origin && \
  if git show-ref --verify --quiet refs/heads/\"${BRANCH}\"; then \
    git checkout \"${BRANCH}\"; \
  else \
    git checkout -b \"${BRANCH}\" \"origin/${BRANCH}\"; \
  fi && \
  git reset --hard \"origin/${BRANCH}\" && \
  bash ./humanoid-gym/scripts/fuyao_deploy.sh --project \"${PROJECT}\" --label \"${LABEL}\" --task \"${TASK}\" --experiment \"${EXPERIMENT}\" --queue \"${QUEUE}\" --yes"
```

Do not use direct `fuyao deploy --remote-kernel ...` as the default path for this command.

## Task Validation (Mandatory + Fuzzy Match)

`task` is mandatory and must be validated against registered tasks.

- Preferred source: `humanoid-gym/humanoid/envs/__init__.py`
- Parse names from `task_registry.register("...")`
- Matching workflow:
  1. exact match
  2. case-insensitive exact match
  3. substring / close matches
  4. if ambiguous, present choices and require explicit user selection
- Do not deploy until task is resolved to one concrete registered value.

## Branch Sync Safeguard

Before deploy, ensure remote kernel branch matches local selected branch.

1. Local:
   - checkout target branch
   - if working tree is dirty, commit changes first
   - set upstream to `origin/<branch>` if needed
   - push branch to origin
2. Remote kernel (`/root/motion_rl`):
   - fetch origin
   - switch to same branch (or create it from `origin/<branch>` if missing)
   - force remote workspace branch to exactly match `origin/<branch>` via `git reset --hard origin/<branch>`
3. If remote kernel lacks GitLab SSH auth:
   - use forwarded agent (`ForwardAgent yes`)
   - ensure local `ssh-agent` has key loaded (`ssh-add -l` not empty)

## Defaults

Use these defaults unless user explicitly overrides:

- `project=rc-wbc`
- `queue=rc-wbc-4090` (fully-qualified; site is resolved by the deploy script from the queue name)
- `experiment=huh8/r01`
- `--yes` enabled

## Execution Workflow

1. Resolve `branch` and `task` via **Argument Prompt Contract (Selectable Questions)**; apply `experiment=huh8/r01` by default unless user explicitly overrides.
2. Resolve `label` via **label prompt contract** (always asked after `branch`/`task`); include suggested label derived from branch (`huh8/foo` -> `foo`).
3. Validate `task` from humanoid registry.
4. Commit local branch changes (if any), then sync branch local -> origin -> remote kernel.
5. Execute wrapper-based SSH command from `/root/motion_rl`.
6. If failure includes auth error:
   - check local `ssh-add -l`
   - verify remote forwarded identity (`ssh "${SSH_ALIAS}" 'ssh-add -l'`)
   - verify GitLab auth (`ssh "${SSH_ALIAS}" 'ssh -T git@gitlab-adc.xiaopeng.link'`)
   - retry deploy.

## Post-Submit Output

Report:

- execution path: `ssh->(resolved deploy alias)` where `Huh8.remote_kernel.fuyao` is preferred and `remote.kernel.fuyo` is fallback
- workdir used: `/root/motion_rl`
- branch used
- submission status (success/failure)
- job name/id
- site, queue, project, label
- next checks:
  - `fuyao info --job-name <job_name>`
  - `fuyao log --job-name <job_name>`
