# Backup and restore

`scripts/backup.sh` creates compressed, timestamped archives of the folders listed
in `BACKUP_SOURCES` (see `config/toolkit.conf`).

## Commands

| Command | What it does |
|---|---|
| `backup.sh run` | Create a backup, write a SHA-256 checksum, delete backups older than `BACKUP_RETENTION_DAYS` |
| `backup.sh list` | List existing backups |
| `backup.sh verify [FILE]` | Check the checksum and archive integrity (default: newest backup) |
| `backup.sh restore-test [FILE]` | Extract to a temp folder and compare with the sources |

## Safety features

- A lock file prevents two backups from running at once.
- Every backup gets a `.sha256` file, so silent corruption is detected.
- Failures write to `logs/backup.log` and raise an alert through `alert.sh`.
- Old backups are removed automatically (default 7 days).

## Restore by hand

```bash
mkdir -p /tmp/restore
tar -xzf ~/toolkit-backups/backup-YYYYMMDD-HHMMSS.tar.gz -C /tmp/restore
# files appear under /tmp/restore/<original absolute path>
cp -r /tmp/restore/home/USER/demo-data/reports ~/demo-data/
```

A backup you have never restored is not a backup, so run `restore-test` regularly.
