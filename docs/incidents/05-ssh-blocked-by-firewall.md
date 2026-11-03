# Incident 05: SSH blocked by the firewall

| | |
|---|---|
| Date | 2026-11-03 |
| Severity | High |
| Detected by | Firewall rule listing: no rule allowing port 22 |
| Time to resolve | About 4 minutes (detected 08:06:01, fixed by 08:10:02) |

## Symptom
With the firewall's default policy set to deny incoming traffic and the rules allowing SSH
removed, new connections to port 22 were no longer permitted. Before the change,
`Test-NetConnection 192.168.211.128 -Port 22` from the Windows host (192.168.211.1, VMware
VMnet8 adapter) had returned `TcpTestSucceeded : True`.

## Timeline
- 08:02:10 Baseline: firewall active, `Default: deny (incoming)`, and two rules allowing 22/tcp (IPv4 and IPv6)
- 08:03:10 Both SSH rules were deleted with `ufw delete`
- 08:06:01 Investigation from the VM console began
- 08:10:02 `ufw allow ssh` restored the rules; fix recorded

## Investigation
Checked each layer in order, from the VM console (not over SSH):
```bash
systemctl is-active ssh
sudo ss -tlnp | grep :22
sudo ufw status verbose
```
- `systemctl is-active ssh` printed `active`.
- `ss` showed `sshd` (PID 1574) listening on `0.0.0.0:22` and `[::]:22`, so the service was
  healthy and reachable inside the VM.
- `ufw status verbose` showed `Status: active`, `Default: deny (incoming), allow (outgoing)`
  and an empty rule table: nothing allowed port 22.

## Root cause
The firewall's default policy denies incoming traffic, and the only rules allowing port 22
had been removed. The SSH service was healthy, but packets from the network were dropped
before reaching it.

## Fix
`sudo ufw allow ssh` re-created the allow rules for IPv4 and IPv6. The firewall was left
active, as it was at the start.

## Prevention
- Run `ufw allow ssh` **before** enabling the firewall or changing its rules.
- Keep a second session or the VM console open when changing remote-access rules.
- When a connection fails, work through the layers: network path, firewall, service.
- Existing SSH sessions survive a rule change, which hides the problem until the next login.

## What I learned
A listening service plus a firewall with no matching allow rule means traffic is being
dropped before the service sees it. Checking each layer separately (service, listening
socket, firewall rules) isolates the cause quickly, and working from the VM console avoids
locking myself out while testing.

## Port test results
From the Windows host to the VM (`Test-NetConnection 192.168.211.128 -Port 22`):

| Moment | Result |
|---|---|
| Firewall active with the SSH allow rules (baseline) | `TcpTestSucceeded : True` |
| After the SSH rules were removed | `TcpTestSucceeded : False` |
| After `sudo ufw allow ssh` | `TcpTestSucceeded : True` |

## Firewall log evidence
The kernel log recorded the dropped connection attempt (first matching entry):

```
Nov 03 08:03:59 sivaprakash-VMware-Virtual-Platform kernel: [UFW BLOCK] IN=ens33 OUT= MAC=(hidden) SRC=192.168.211.1 DST=192.168.211.128 LEN=52 TOS=0x00 PREC=0x00 TTL=128 ID=4627 DF PROTO=TCP SPT=51110 DPT=22 WINDOW=65535 RES=0x00 SYN URGP=0 
```
