---
name: Test Reverse SSH Connection
overview: SSH into huh.desktop.us, then from that machine SSH back to the local laptop via the H2H.Laptop.us alias, verifying the full round-trip works.
todos:
  - id: test-reverse-ssh
    content: Run nested SSH command to verify huh.desktop.us can SSH back to this laptop via H2H.Laptop.us
    status: completed
isProject: false
---

# Test Reverse SSH Connection

## Prerequisite

macOS Remote Login must be enabled on this laptop (System Settings > General > Sharing > Remote Login). If it is off, the reverse SSH will fail regardless of key/config correctness.

## Test Command

Run a nested SSH command from the local machine:

```bash
ssh huh.desktop.us 'ssh -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10 H2H.Laptop.us "hostname && whoami && echo SUCCESS"'
```

This will:
1. SSH into `huh.desktop.us` (10.160.64.142)
2. From there, SSH back to `H2H.Laptop.us` (10.160.67.54, user `HanHu`, key `~/.ssh/id_ed25519`)
3. Run `hostname && whoami && echo SUCCESS` on the local laptop

## Expected output

```
Hans-MacBook-Pro.local
HanHu
SUCCESS
```

## If it fails

- Check if Remote Login is enabled on this Mac
- Check firewall settings (`sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate`)
- Verify the desktop can reach 10.160.67.54 (`ssh huh.desktop.us 'ping -c1 10.160.67.54'`)
