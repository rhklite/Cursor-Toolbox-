---
name: SSH to isaacgem in Cursor
overview: Configure SSH so Cursor Remote can connect to the `isaacgem` container at `huh.desktop.us` as user `huh`, then verify connectivity and open the remote workspace from Cursor GUI.
todos:
  - id: add-ssh-alias
    content: Create/update ~/.ssh/config with an isaacgem host alias using HostName huh.desktop.us and User huh.
    status: completed
  - id: set-auth-options
    content: Configure IdentityFile, IdentitiesOnly, and optional Port for the container SSH endpoint.
    status: completed
  - id: verify-cli-ssh
    content: Test ssh isaacgem from terminal to confirm successful login.
    status: completed
  - id: connect-cursor-remote
    content: Use Cursor Remote SSH to connect via alias isaacgem and open the remote workspace.
    status: completed
isProject: false
---

# Set Up Cursor SSH Access to `isaacgem`

## Goal

Enable Cursor GUI to connect over SSH directly to the container endpoint for `isaacgem` using user `huh`.

## Files to configure

- SSH client config: `[/Users/HanHu/.ssh/config](/Users/HanHu/.ssh/config)`
- Optional key file (if needed): `[/Users/HanHu/.ssh/id_ed25519](/Users/HanHu/.ssh/id_ed25519)`

## Implementation plan

1. Add a dedicated SSH host alias in `[/Users/HanHu/.ssh/config](/Users/HanHu/.ssh/config)`, for example `Host isaacgem`, with:
  - `HostName huh.desktop.us`
  - `User huh`
  - `IdentityFile` pointing to your SSH key
  - `IdentitiesOnly yes`
  - `ServerAliveInterval` and `ServerAliveCountMax` for stability
2. If the container SSH endpoint uses a non-default port, include `Port <container_ssh_port>` in that alias.
3. Validate locally via terminal: `ssh isaacgem` to ensure the SSH handshake, auth, and shell entry work end-to-end.
4. In Cursor GUI, use **Remote SSH / Connect to Host** and select the alias `isaacgem`.
5. Open the desired remote folder once connected; confirm terminal and file operations work in the remote environment.

## Verification checklist

- `ssh isaacgem` succeeds without username prompts or auth errors.
- Cursor Remote SSH connects to `isaacgem` using the same alias.
- Remote terminal in Cursor reports container environment (not local machine).
- You can open/edit files in the remote container workspace.

## Notes

- If host key trust prompt appears on first connection, accept and persist known host.
- If auth fails, the likely fixes are key path/permissions (`chmod 600 ~/.ssh/config`, `chmod 600 ~/.ssh/id_`*) or wrong SSH port.

