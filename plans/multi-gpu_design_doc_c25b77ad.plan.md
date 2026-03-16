---
name: Multi-GPU design doc
overview: Write a standalone design document at `docs/multi-gpu-distributed-training.md` introducing the multi-GPU branch, the distributed training architecture (iron_turbo + Accelerate), deploy/sweep Cursor commands, test infrastructure, and known constraints.
todos:
  - id: write-doc
    content: Write docs/multi-gpu-distributed-training.md with all sections
    status: completed
isProject: false
---

# Write Multi-GPU Design Documentation

Create `docs/multi-gpu-distributed-training.md` in the motion_rl repo with the following sections:

## Document structure

1. **Overview** -- what the branch adds, why multi-GPU, key benefits
2. **Architecture** -- mermaid diagram showing iron_turbo + Accelerate + fuyao_train.sh + fuyao_deploy.sh flow
3. **How to deploy** -- Cursor commands (`deploy-fuyao`, `sweep-fuyao`) with concrete single-GPU and multi-GPU examples
4. **Distributed training internals** -- iron_turbo primitives, what they do, where they're used
5. **Deploy script flags** -- `--distributed`, `--nproc_per_node`, `--seeds`, `--model`, `--dry-run`
6. **Test infrastructure** -- what tests exist, how to run them (import integrity, GPU config, E2E)
7. **Known constraints** -- no `--gpu-type` flag, queue compatibility, single-node only for now
8. **Troubleshooting** -- common failures and how to diagnose (pre-flight import check, fuyao log commands)
