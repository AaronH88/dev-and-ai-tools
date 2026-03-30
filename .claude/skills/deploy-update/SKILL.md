# Skill: Deploy Update

## Purpose
Safely update a deployed application — backup first, pull latest code,
deploy, verify. Never skip the backup step.

## When to Use This Skill
When deploying changes to a running production instance that has live data.

## Assumptions
- The app is deployed on a Linux server (LXC, VM, or bare metal)
- The repo is cloned on the server at a known path
- A `deploy/update.sh` script exists in the repo
- A `deploy/backup.sh` script exists in the repo
- The service is managed by systemd

## Process

---

### Step 1 — Locate the Deployment

Find where the repo lives on this server:

```bash
find /root /home /opt -name "deploy" -type d 2>/dev/null | head -5
```

Also check what service is running:

```bash
systemctl list-units --type=service --state=running | grep -v systemd
```

Confirm the repo path and service name before proceeding.

---

### Step 2 — Backup First (mandatory, never skip)

Run the backup script:

```bash
{repo_path}/deploy/backup.sh
```

Verify the backup was created:

```bash
ls -lht /var/lib/*/backups/ 2>/dev/null | head -5
```

A timestamped backup file must exist before proceeding.
If the backup fails, stop and report the error — do not continue.

---

### Step 3 — Check Current State

Record the current state before making changes:

```bash
# Current git status
cd {repo_path} && git log --oneline -3
git status

# Service health
systemctl status {service_name} | head -10

# Quick API check (adjust path as needed)
curl -s http://localhost:{port}/api/v1/settings | head -c 100
```

---

### Step 4 — Pull Latest Code

```bash
cd {repo_path}
git pull
```

Review what changed:

```bash
git log --oneline -5
git diff HEAD~1 --name-only
```

If there are database migration files or schema changes, note them —
they may require additional steps after deployment.

---

### Step 5 — Run Update Script

```bash
cd {repo_path}
sudo deploy/update.sh
```

Watch for errors. The update script should:
- Stop the service
- Sync code files
- Update dependencies
- Rebuild frontend (if applicable)
- Start the service

If the update script fails partway through, the service may be stopped.
Restart it manually if needed:

```bash
systemctl start {service_name}
```

---

### Step 6 — Verify Deployment

Check the service came back up:

```bash
sleep 3
systemctl status {service_name}
```

Check the API responds:

```bash
curl -s http://localhost:{port}/api/v1/settings
```

Check logs for errors:

```bash
journalctl -u {service_name} -n 30 --no-pager
```

If any of these checks fail, report the error with the full log output.

---

### Step 7 — Verify Data Integrity

Confirm the database is intact and data is accessible:

```bash
sqlite3 /var/lib/*/db.sqlite "SELECT COUNT(*) FROM sqlite_master WHERE type='table';"
```

The table count should match what was there before the update.

---

## Rollback Procedure

If the update broke something and you need to roll back:

```bash
# Stop the service
systemctl stop {service_name}

# Restore the database from backup
LATEST_BACKUP=$(ls -t /var/lib/*/backups/*.sqlite | head -1)
echo "Restoring from: $LATEST_BACKUP"
cp "$LATEST_BACKUP" /var/lib/*/db.sqlite

# Roll back code
cd {repo_path}
git log --oneline -5   # find the previous commit hash
git checkout {previous_hash}
sudo deploy/update.sh

# Verify
systemctl status {service_name}
```

## Output Summary Format

```
=== Deploy Update Complete ===

Backup:   {backup_file_path}
Deployed: {git_commit_hash} — {commit_message}
Service:  {service_name} running (PID {pid})
API:      responding at {url}

Previous version: {old_commit_hash}
Rollback command: git checkout {old_commit_hash} && sudo deploy/update.sh
```

## Quality Rules

- Never proceed past Step 2 if the backup failed
- Always verify the service is running after deployment
- Always check logs for errors even if the service appears healthy
- Always record the previous commit hash in case rollback is needed
