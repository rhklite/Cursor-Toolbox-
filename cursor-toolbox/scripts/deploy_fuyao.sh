#!/usr/bin/env bash
set -euo pipefail

# Non-interactive Fuyao deploy script.
# Argument prompting/selection is handled by Cursor command docs.

# -----------------------------------------------------------------------------
# Defaults
# -----------------------------------------------------------------------------
SSH_ALIAS_DEFAULT="CLUSTER_SSH_ALIAS"
REMOTE_ROOT_DEFAULT="/root/project_repo"

DOCKER_IMAGE_DEFAULT="infra-registry-vpc.cn-wulanchabu.cr.aliyuncs.com/data-infra/fuyao:isaacgym-250516-0347"
NODES_DEFAULT="1"
GPUS_PER_NODE_DEFAULT="1"
GPU_TYPE_DEFAULT="shared"
SITE_DEFAULT="fuyao_sh_n2"
QUEUE_DEFAULT="rc-wbc-4090-share"
PROJECT_DEFAULT="rc-wbc"
EXPERIMENT_DEFAULT="default/experiment"
PRIORITY_DEFAULT="normal"
RL_DEVICE_DEFAULT="cuda:0"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
usage() {
    cat <<'EOF'
Usage:
  deploy_fuyao.sh --task <task> [options]

Required:
  --task <name>            Training task name

Optional (with defaults):
  --branch <name>          Git branch to push and sync (default: current local branch)
  --ssh-alias <alias>      SSH alias for remote kernel (default: CLUSTER_SSH_ALIAS)
  --remote-root <path>     Remote repo root (default: /root/project_repo)
  --local-root <path>      Local repo root (default: detected from workspace)
  --label <label>          Deploy label (default: derived from branch)
  --remote-kernel <bool>   Enable remote kernel (default: true)
  --docker-image <image>   Docker image (default: isaacgym-250516-0347)
  --nodes <n>              Number of nodes (default: 1)
  --gpus-per-node <n>      GPUs per node (default: 1)
  --gpu-type <type>        GPU type (default: shared)
  --gpu-slice <slice>      GPU slice (default: computed from gpus-per-node)
  --site <site>            Fuyao site (default: fuyao_sh_n2)
  --queue <queue>          Fuyao queue (default: rc-wbc-4090-share)
  --project <project>      Fuyao project (default: rc-wbc)
  --experiment <exp>       Fuyao experiment (default: default/experiment)
  --priority <pri>         Job priority (default: normal)
  --auto-yes <bool>        Skip fuyao confirmation (default: true)
  --rl-device <device>     RL device (default: cuda:0)
  --resume <bool>          Resume training (default: false)
  --checkpoint-path <path> Checkpoint path (required when resume=true)
  --auto-commit-msg <msg>  Commit message if local tree is dirty (omit to fail on dirty tree)
  --skip-git-sync <bool>   Skip local/remote git sync and push (default: false)
  --dry-run                Print composed command without executing
  -h, --help               Show this help message
EOF
}

require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: missing command '$cmd'" >&2
        exit 1
    fi
}

# Resolve local repo root from workspace hints first, then git fallback.
detect_local_root_from_workspace() {
    local candidate=""

    for candidate in "${CURSOR_WORKSPACE_PATH:-}" "${WORKSPACE_PATH:-}" "${PWD:-}"; do
        if [ -n "$candidate" ] && [ -d "$candidate/.git" ]; then
            echo "$candidate"
            return 0
        fi
    done

    if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git rev-parse --show-toplevel
        return 0
    fi

    echo "Error: unable to detect local workspace git root." >&2
    echo "Run from a Cursor workspace repo or pass --local-root <path>." >&2
    exit 1
}

# Shared queue mapping used by existing deploy workflow.
# 1->1of4, 2->2of4, 3->3of4, 4->4of4
default_gpu_slice_for_gpus_per_node() {
    local gpus_per_node="$1"
    case "$gpus_per_node" in
    1) echo "1of4" ;;
    2) echo "2of4" ;;
    3) echo "3of4" ;;
    4) echo "4of4" ;;
    *)
        echo "Error: unsupported gpus-per-node value: ${gpus_per_node}. Supported: 1, 2, 3, 4." >&2
        exit 1
        ;;
    esac
}

# Fallback label when the agent does not supply a custom one.
derive_label_from_branch() {
    local branch="$1"
    echo "${branch##*/}"
}

# -----------------------------------------------------------------------------
# Runtime values (CLI-overridable)
# -----------------------------------------------------------------------------
SSH_ALIAS="$SSH_ALIAS_DEFAULT"
REMOTE_ROOT="$REMOTE_ROOT_DEFAULT"   # default: /root/project_repo
LOCAL_ROOT=""                        # default: auto-detected from workspace
BRANCH=""                            # default: current local branch
TASK=""                              # required
LABEL=""                             # default: derived from branch
REMOTE_KERNEL="true"                 # default: true
DOCKER_IMAGE="$DOCKER_IMAGE_DEFAULT" # default: isaacgym-250516-0347
NODES="$NODES_DEFAULT"               # default: 1
GPUS_PER_NODE="$GPUS_PER_NODE_DEFAULT" # default: 1
GPU_TYPE="$GPU_TYPE_DEFAULT"         # default: shared
GPU_SLICE=""                         # default: computed from gpus-per-node
SITE="$SITE_DEFAULT"                 # default: fuyao_sh_n2
QUEUE="$QUEUE_DEFAULT"               # default: rc-wbc-4090-share
PROJECT="$PROJECT_DEFAULT"           # default: rc-wbc
EXPERIMENT="$EXPERIMENT_DEFAULT"     # default: default/experiment
PRIORITY="$PRIORITY_DEFAULT"         # default: normal
AUTO_YES="true"                      # default: true
RL_DEVICE="$RL_DEVICE_DEFAULT"       # default: cuda:0
RESUME="false"                       # default: false
CHECKPOINT_PATH=""                   # required if resume=true
AUTO_COMMIT_MSG=""                   # optional; needed only to auto-commit dirty tree
SKIP_GIT_SYNC="false"                # default: false
DRY_RUN=false                        # default: false

# -----------------------------------------------------------------------------
# Parse CLI args
# -----------------------------------------------------------------------------
while [ $# -gt 0 ]; do
    case "$1" in
        --ssh-alias) SSH_ALIAS="$2"; shift 2 ;;
        --remote-root) REMOTE_ROOT="$2"; shift 2 ;;
        --local-root) LOCAL_ROOT="$2"; shift 2 ;;
        --branch) BRANCH="$2"; shift 2 ;;
        --task) TASK="$2"; shift 2 ;;
        --label) LABEL="$2"; shift 2 ;;
        --remote-kernel) REMOTE_KERNEL="$2"; shift 2 ;;
        --docker-image) DOCKER_IMAGE="$2"; shift 2 ;;
        --nodes) NODES="$2"; shift 2 ;;
        --gpus-per-node) GPUS_PER_NODE="$2"; shift 2 ;;
        --gpu-type) GPU_TYPE="$2"; shift 2 ;;
        --gpu-slice) GPU_SLICE="$2"; shift 2 ;;
        --site) SITE="$2"; shift 2 ;;
        --queue) QUEUE="$2"; shift 2 ;;
        --project) PROJECT="$2"; shift 2 ;;
        --experiment) EXPERIMENT="$2"; shift 2 ;;
        --priority) PRIORITY="$2"; shift 2 ;;
        --auto-yes) AUTO_YES="$2"; shift 2 ;;
        --rl-device) RL_DEVICE="$2"; shift 2 ;;
        --resume) RESUME="$2"; shift 2 ;;
        --checkpoint-path) CHECKPOINT_PATH="$2"; shift 2 ;;
        --auto-commit-msg) AUTO_COMMIT_MSG="$2"; shift 2 ;;
        --skip-git-sync) SKIP_GIT_SYNC="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -h|--help)
            usage
            exit 0
            ;;
    *)
        echo "Unknown option: $1" >&2
        usage
        exit 1
        ;;
    esac
done

# -----------------------------------------------------------------------------
# Resolve computed defaults
# -----------------------------------------------------------------------------
if [ "$SKIP_GIT_SYNC" != "true" ] && [ -z "$LOCAL_ROOT" ]; then
    LOCAL_ROOT="$(detect_local_root_from_workspace)"
fi

if [ "$GPU_TYPE" = "shared" ] || [ "$GPU_TYPE" = "mig" ]; then
    if [ -z "$GPU_SLICE" ]; then
        GPU_SLICE="$(default_gpu_slice_for_gpus_per_node "$GPUS_PER_NODE")"
    fi
else
    GPU_SLICE=""
fi

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------
require_cmd ssh
if [ "$SKIP_GIT_SYNC" != "true" ]; then
    require_cmd git
fi

if [ "$SKIP_GIT_SYNC" != "true" ]; then
    if [ ! -d "$LOCAL_ROOT/.git" ]; then
        echo "Error: local root is not a git repo: $LOCAL_ROOT" >&2
        echo "Fix: run this script from a git repository, or pass --local-root <path> to a valid repo." >&2
        exit 1
    fi

    if [ -z "$BRANCH" ]; then
        BRANCH="$(git -C "$LOCAL_ROOT" rev-parse --abbrev-ref HEAD)"
        echo "No --branch specified; using current local branch: ${BRANCH}"
    fi
fi

if [ -z "$LABEL" ]; then
    if [ -n "$BRANCH" ]; then
        LABEL="$(derive_label_from_branch "$BRANCH")"
    else
        LABEL="${TASK}-$(date +%Y%m%d-%H%M%S)"
    fi
fi

if [ -z "$TASK" ]; then
    echo "Error: --task is required." >&2
    exit 1
fi

if [ "$RESUME" = "true" ] && [ -z "$CHECKPOINT_PATH" ]; then
    echo "Error: --checkpoint-path is required when --resume true." >&2
    exit 1
fi

if [ "$RESUME" = "true" ] && [ -n "$CHECKPOINT_PATH" ]; then
    CKPT_BASENAME="$(basename "$CHECKPOINT_PATH")"
    if [ "$CHECKPOINT_PATH" != "$CKPT_BASENAME" ]; then
        echo "Warning: --checkpoint-path contains a directory component: $CHECKPOINT_PATH" >&2
        echo "  fuyao_train.sh runs from humanoid-gym/, so relative paths resolve from there." >&2
        echo "  Stripping to basename: $CKPT_BASENAME" >&2
        CHECKPOINT_PATH="$CKPT_BASENAME"
    fi
fi

# -----------------------------------------------------------------------------
# Step 1/3: SSH connectivity
# -----------------------------------------------------------------------------
if [ "$DRY_RUN" = true ]; then
    echo "Step 1/3: Skipping SSH connectivity check (dry run)"
else
    echo "Step 1/3: Checking SSH connectivity to ${SSH_ALIAS} ..."
    ssh "$SSH_ALIAS" "echo ok >/dev/null"
    echo "SSH connectivity check passed."
fi

if [ "$SKIP_GIT_SYNC" != "true" ]; then
    # -----------------------------------------------------------------------------
    # Step 2/3: Git sync
    # -----------------------------------------------------------------------------
    echo
    echo "Step 2a/3: Local git sync and push for branch ${BRANCH}"

    if [ -n "$(git -C "$LOCAL_ROOT" status --porcelain)" ]; then
        if [ -n "$AUTO_COMMIT_MSG" ]; then
            echo "Committing local changes: ${AUTO_COMMIT_MSG}"
            git -C "$LOCAL_ROOT" add -A
            git -C "$LOCAL_ROOT" commit -m "$AUTO_COMMIT_MSG"
        else
            echo "Error: local tree is dirty and no --auto-commit-msg provided." >&2
            echo "Uncommitted files:" >&2
            git -C "$LOCAL_ROOT" status --porcelain >&2
            exit 1
        fi
    fi

    git -C "$LOCAL_ROOT" fetch origin
    git -C "$LOCAL_ROOT" checkout "$BRANCH"

    if [ -n "$(git -C "$LOCAL_ROOT" status --porcelain)" ]; then
        if [ -n "$AUTO_COMMIT_MSG" ]; then
            echo "Committing post-checkout changes: ${AUTO_COMMIT_MSG}"
            git -C "$LOCAL_ROOT" add -A
            git -C "$LOCAL_ROOT" commit -m "$AUTO_COMMIT_MSG"
        else
            echo "Error: branch ${BRANCH} has uncommitted changes after checkout and no --auto-commit-msg provided." >&2
            git -C "$LOCAL_ROOT" status --porcelain >&2
            exit 1
        fi
    fi

    git -C "$LOCAL_ROOT" push -u origin "$BRANCH"

    echo
    echo "Step 2b/3: Remote strict reset to origin/${BRANCH}"

    REMOTE_SHA="$(
        ssh "$SSH_ALIAS" "bash -s" -- "$REMOTE_ROOT" "$BRANCH" <<'REMOTE_SYNC'
set -euo pipefail
export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=no"
REMOTE_ROOT="$1"
BRANCH="$2"
cd "$REMOTE_ROOT"
git fetch origin
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    git checkout "${BRANCH}"
else
    git checkout -b "${BRANCH}" "origin/${BRANCH}"
fi
git reset --hard "origin/${BRANCH}"
git rev-parse HEAD
REMOTE_SYNC
)"
    echo "Remote SHA after strict reset: ${REMOTE_SHA}"
else
    echo
    echo "Step 2/3: Skipping git sync (--skip-git-sync true)"
fi

# -----------------------------------------------------------------------------
# Step 3/3: Compose and run Fuyao deploy on remote kernel
# -----------------------------------------------------------------------------
echo
echo "Step 3/3: Compose and run remote Fuyao deploy"

declare -a DEPLOY_CMD
DEPLOY_CMD=(fuyao deploy)

if [ "$REMOTE_KERNEL" = "true" ]; then
    DEPLOY_CMD+=(--remote-kernel)
fi

DEPLOY_CMD+=(
    "--docker-image=${DOCKER_IMAGE}"
    "--nodes=${NODES}"
    "--gpus-per-node=${GPUS_PER_NODE}"
)
DEPLOY_CMD+=(
    "--site=${SITE}"
    "--queue=${QUEUE}"
    "--project=${PROJECT}"
    "--experiment=${EXPERIMENT}"
    "--label=${LABEL}"
    "--priority=${PRIORITY}"
)

if [ "$AUTO_YES" = "true" ]; then
    DEPLOY_CMD+=(--yes --ignore-artifact-size)
fi

DEPLOY_CMD+=(
    /bin/bash humanoid-gym/scripts/fuyao_train.sh
    --label "$LABEL"
    --task "$TASK"
    --rl_device "$RL_DEVICE"
)

if [ "$RESUME" = "true" ]; then
    DEPLOY_CMD+=(--resume --checkpoint_path "$CHECKPOINT_PATH")
fi

# Render fuyao command separately for piping and logging.
FUYAO_CMD_STR="$(printf '%q ' "${DEPLOY_CMD[@]}")"
DEPLOY_CMD_STR="cd ${REMOTE_ROOT} && ${FUYAO_CMD_STR}"

echo "Final deploy command (runs on remote kernel via SSH):"
echo "  ${DEPLOY_CMD_STR}"

if [ "$DRY_RUN" = true ]; then
    echo "Dry run: command not executed."
    exit 0
fi

# Pipe 'N' to auto-decline fuyao upgrade prompt.
ssh "$SSH_ALIAS" "cd ${REMOTE_ROOT} && echo N | ${FUYAO_CMD_STR}"

echo "Deploy command submitted."
