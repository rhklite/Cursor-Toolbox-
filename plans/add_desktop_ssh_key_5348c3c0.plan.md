---
name: Add Desktop SSH Key
overview: Fetch huh.desktop.us's public key(s) and add them to the local laptop's ~/.ssh/authorized_keys so the desktop can SSH back to the laptop.
todos:
  - id: list-remote-keys
    content: List ~/.ssh/*.pub on huh.desktop.us to identify available public keys
    status: completed
  - id: append-to-authorized-keys
    content: Append remote public key(s) to local ~/.ssh/authorized_keys (no duplicates)
    status: completed
  - id: set-permissions
    content: Ensure ~/.ssh is 700 and authorized_keys is 600, verify with ls -la
    status: completed
isProject: false
---

# Add Desktop SSH Key to Local authorized_keys

Fetch the public key(s) from `huh.desktop.us` and append them to `~/.ssh/authorized_keys` on the local machine (`HanHu@Hans-MacBook-Pro.local`, IP `10.160.67.54`).

## Steps

1. **List remote public keys** — `ssh huh.desktop.us 'ls ~/.ssh/*.pub'` to confirm which keys exist
2. **Read remote key(s)** — `ssh huh.desktop.us 'cat ~/.ssh/*.pub'` to get the key content
3. **Guard local authorized_keys** — `touch ~/.ssh/authorized_keys` to ensure file exists
4. **Append missing keys** — for each remote public key, check if it's already in `~/.ssh/authorized_keys` (via `grep`); append only if absent
5. **Set correct permissions** — `chmod 700 ~/.ssh && chmod 600 ~/.ssh/authorized_keys`
6. **Verify** — `grep` for the remote key fingerprint in the local `authorized_keys` and `ls -la ~/.ssh/authorized_keys`

## Key files

- Remote source: `huh.desktop.us:~/.ssh/*.pub`
- Local target: `~/.ssh/authorized_keys` (`/Users/HanHu/.ssh/authorized_keys`)
