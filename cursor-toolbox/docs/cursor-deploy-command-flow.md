# Cursor Deploy Command Flow

## Command Relationships

```mermaid
flowchart TD
    subgraph cursorSkills [Cursor Skills]
        deploySkill["deploy-fuyao(SKILL.md)"]
        sweepSkill["sweep-fuyao(SKILL.md)"]
    end

    subgraph cursorScripts ["~/.cursor/scripts/"]
        sweepDispatcher["deploy_fuyao_sweep_dispatcher.sh"]
        deployFuyaoSh["deploy_fuyao.sh(per-combo deployer)"]
        verifyJobs["verify_fuyao_jobs.sh"]
    end

    subgraph workspaceRepo [Workspace Repo]
        deployScript["humanoid-gym/scripts/fuyao_deploy.sh"]
        trainScript["humanoid-gym/scripts/fuyao_train.sh"]
    end

    subgraph remoteEnv [Remote Kernel Plus Cluster]
        remoteKernel["CLUSTER_SSH_ALIAS /root/project_repo"]
        fuyaoCluster["Fuyao Cluster"]
    end

    deploySkill -->|"SSH"| deployScript
    sweepSkill --> sweepDispatcher
    sweepDispatcher -->|"per combo"| deployFuyaoSh
    deployFuyaoSh -->|"SSH"| deployScript
    sweepSkill --> verifyJobs
    deployScript -->|"submit"| fuyaoCluster
    fuyaoCluster -->|"runs"| trainScript
```

## deploy-fuyao Step Sequence

```mermaid
sequenceDiagram
    actor User
    participant Cursor as CursorAgent
    participant Git as GitOrOrigin
    participant Kernel as RemoteKernel
    participant Deploy as fuyao_deploy.sh
    participant Fuyao as FuyaoCluster

    User->>Cursor: Deploy task with selected resources
    Cursor->>Cursor: Resolve branch task label
    Cursor->>Git: Validate task registration
    Cursor->>Git: Check clean branch and push
    Cursor->>Kernel: SSH fetch checkout reset
    Cursor-->>User: Confirmation prompt
    User->>Cursor: Confirm
    Cursor->>Kernel: SSH run fuyao_deploy.sh
    Kernel->>Deploy: Prepare and submit
    Deploy->>Fuyao: Submit job
    Fuyao-->>Cursor: Return job name
    Cursor-->>User: Post-submit report
```

## sweep-fuyao Step Sequence

```mermaid
sequenceDiagram
    actor User
    participant Cursor as CursorAgent
    participant Git as GitOrOrigin
    participant Dispatcher as deploy_fuyao_sweep_dispatcher.sh
    participant Kernel as RemoteKernel
    participant DeployScript as deploy_fuyao.sh
    participant Fuyao as FuyaoCluster
    participant Verify as verify_fuyao_jobs.sh

    User->>Cursor: Sweep multiple hyperparameters
    Cursor->>Cursor: Resolve branch task hp_specs
    Cursor->>Git: Validate task registration
    Cursor->>Cursor: Build payload and show preview
    Cursor-->>User: Confirmation prompt
    User->>Cursor: Confirm
    Cursor->>Dispatcher: Dispatch payload

    loop Each combo
        Dispatcher->>Kernel: Create combo workspace
        Dispatcher->>Kernel: Patch config values
        Dispatcher->>DeployScript: Deploy combo
        DeployScript->>Fuyao: Submit job
    end

    Dispatcher-->>Cursor: Return run_root
    Cursor->>Verify: Verify statuses
    Verify-->>Cursor: Return verification result
    Cursor-->>User: Post-submit report
```

## Key Differences

- deploy-fuyao runs one job per invocation.
- sweep-fuyao dispatches a parameter grid.
- sweep-fuyao patches config values per combo.
- sweep-fuyao includes mandatory post-dispatch verification.
