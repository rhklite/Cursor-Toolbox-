---
name: Test gpu_type default change
overview: Add test cases to verify the `gpu_type` default change from `shared` to `exclusive` across the deploy script, sweep dispatcher, and both skill docs, then run all tests end-to-end.
todos:
  - id: extend-deploy-tests
    content: Add tests 11-13 to test_fuyao_deploy_gpu_config.sh verifying exclusive default, plus sweep dispatcher and skill doc assertions
    status: completed
  - id: run-all-tests
    content: Run the test script locally, run import integrity tests, and dry-run on remote kernel to verify end-to-end
    status: completed
isProject: false
---

# Test gpu_type Default Change to Exclusive

## Scope

Four assets were changed to default `gpu_type` to `exclusive`:

1. [humanoid-gym/scripts/fuyao_deploy.sh](humanoid-gym/scripts/fuyao_deploy.sh) line 18: `gpu_type='exclusive'`
2. [~/.cursor/skills/deploy-fuyao/SKILL.md](~/.cursor/skills/deploy-fuyao/SKILL.md) line 30: `(default: exclusive; ...)`
3. [~/.cursor/skills/sweep-fuyao/SKILL.md](~/.cursor/skills/sweep-fuyao/SKILL.md) line 33: `(default: exclusive)`
4. [~/.cursor/scripts/deploy_fuyao_sweep_dispatcher.sh](~/.cursor/scripts/deploy_fuyao_sweep_dispatcher.sh) lines 21 and 207: `DEFAULT_GPU_TYPE="exclusive"`

## 1. Extend existing deploy GPU test script

File: [humanoid-gym/scripts/test_fuyao_deploy_gpu_config.sh](humanoid-gym/scripts/test_fuyao_deploy_gpu_config.sh)

Add three new tests at the end (before the results summary):

- **Test 11**: grep `fuyao_deploy.sh` for `gpu_type='exclusive'` to confirm the hardcoded default
- **Test 12**: `build_fuyao_cmd 1 false exclusive ""` -- single GPU with exclusive default should produce `--gpu-type=exclusive` and NO `--gpu-slice`
- **Test 13**: `build_fuyao_cmd 4 true exclusive ""` -- 4 GPU distributed with exclusive should produce `--gpu-type=exclusive` and NO `--gpu-slice` (already covered by Test 4 but now represents the default path)

## 2. Add sweep dispatcher default test

Add a new test section to the same script (or a sibling script) that:

- greps `deploy_fuyao_sweep_dispatcher.sh` for `DEFAULT_GPU_TYPE="exclusive"`
- greps `deploy_fuyao_sweep_dispatcher.sh` for `s("gpu_type", "exclusive")`

## 3. Add skill documentation default tests

Add tests that:

- grep `deploy-fuyao/SKILL.md` for `default: \`exclusive`
- grep `sweep-fuyao/SKILL.md` for `default: \`exclusive`

## 4. Run all tests

After writing the tests, execute them in order:

1. `bash humanoid-gym/scripts/test_fuyao_deploy_gpu_config.sh` -- deploy GPU config tests (existing + new)
2. `python3 -m pytest humanoid-gym/tests/test_import_integrity.py -v` -- import graph validation
3. Dry-run on remote kernel to confirm end-to-end:
  - Single GPU default: `fuyao_deploy.sh --task ... --dry-run --yes` -- verify output contains `--gpu-type=exclusive` and no `--gpu-slice`
  - Multi-GPU default: `fuyao_deploy.sh --distributed --nproc_per_node 4 --task ... --dry-run --yes` -- same check
