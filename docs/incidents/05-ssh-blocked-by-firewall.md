# Incident 05: SSH blocked by the firewall

| | |
|---|---|
| Date | TODO: YYYY-MM-DD |
| Severity | High |
| Detected by | Connection attempts timing out |
| Time to resolve | TODO minutes |

## Symptom
New SSH connections from the Windows host hung until they timed out.
`Test-NetConnection <vm-ip> -Port 22` reported `TcpTestSucceeded : False`.

## Timeline
- TODO hh:mm The firewall was enabled with a default "deny incoming" policy and no SSH rule
- TODO hh:mm New SSH connections began to time out
- TODO hh:mm From the VM console: SSH service active and listening, so the firewall was suspected
- TODO hh:mm `ufw allow ssh` added the missing rule
- TODO hh:mm SSH worked again from the host

## Investigation
Checked each layer in order, from the VM console:
```bash
systemctl is-active ssh
sudo ss -tlnp | grep :22
sudo ufw status verbose
```
- The SSH service was `active` and listening on port 22, so the service itself was fine.
- `ufw status verbose` showed `Default: deny (incoming)` and no rule allowing port 22.

## Root cause
The firewall was enabled with a default-deny policy and no rule for port 22, so new
connections were dropped even though the SSH service was healthy.

## Fix
`sudo ufw allow ssh`, then confirmed `Test-NetConnection` returned `True` and SSH
logins worked. Afterwards the firewall was disabled again to restore the lab setup.

## Prevention
- Run `ufw allow ssh` **before** `ufw enable`.
- Keep a second session or the VM console open when changing remote-access rules.
- When a connection fails, work through the layers: network path, firewall, service.

## What I learned
An existing SSH session survives a new firewall rule, which hides the problem until
the next login. A listening service plus a timeout points at a firewall or network
filter, not at the service.
