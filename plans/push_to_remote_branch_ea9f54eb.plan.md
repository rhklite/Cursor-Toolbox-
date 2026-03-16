---
name: Push to remote branch
overview: Rebase over the single divergent remote commit on the tracking branch, then push.
todos:
  - id: rebase
    content: git pull --rebase origin <branch> to integrate the 1 remote commit
    status: completed
  - id: push
    content: git push to remote branch
    status: completed
isProject: false
---

# Push to Remote Branch

Current state: branch `huh/dev_r01_v12_sa_wholestate_female-balance-multi-GPU` is **ahead 1, behind 1** relative to its remote.

- Local-only commit: `17c3604ee` (our new commit)
- Remote-only commit: `a26bb9355` (touches `r01_plotjuggler_full.xml` and `play_interactive.py`)

## Steps

1. Run `git pull --rebase origin huh/dev_r01_v12_sa_wholestate_female-balance-multi-GPU` to rebase the local commit on top of the single remote commit.
2. Resolve any minor conflicts if they arise (likely in `r01_plotjuggler_full.xml` since both sides modified it).
3. Run `git push origin huh/dev_r01_v12_sa_wholestate_female-balance-multi-GPU` to push.
4. Verify with `git status` that local and remote are in sync.
