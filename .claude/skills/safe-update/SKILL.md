---
name: safe-update
description: "Safely update NanoClaw with full rollback. Stops the service, backs up database and WhatsApp auth, runs the update, verifies build/tests/service, and rolls back if anything fails. Triggers on \"safe update\", \"safe-update\", \"update safely\", \"careful update\"."
---

# Safe Update

Wraps the `/update` skill with service lifecycle management and runtime data backup/rollback. The existing `/update` skill backs up source files; this additionally protects the SQLite database and WhatsApp auth credentials.

**Principle:** Automate everything. Only pause for user confirmation before applying changes or when rollback fails and needs manual intervention.

**UX Note:** Use `AskUserQuestion` for all user-facing questions.

## 1. Pre-flight

Check for uncommitted git changes:

```bash
git status --porcelain
```

**If uncommitted changes:** Warn the user and use AskUserQuestion with options: "Continue anyway", "Abort (I'll commit first)". If abort, stop here.

Check that the skills system is initialized:

```bash
test -d .nanoclaw && echo "INITIALIZED" || echo "NOT_INITIALIZED"
```

**If NOT_INITIALIZED:** Run:

```bash
npx tsx -e "import { initNanoclawDir } from './skills-engine/init.js'; initNanoclawDir();"
```

## 2. Stop the service

Run:

```bash
./.claude/skills/safe-update/scripts/stop-service.sh
```

Parse the status block between `<<< STATUS` and `STATUS >>>`. Record `SERVICE_MANAGER` and `SERVICE_WAS_RUNNING` for later restart.

**If SERVICE_STOPPED=false and SERVICE_WAS_RUNNING=true:** Warn the user: "Could not stop the service. Updating with the service running risks database corruption. Continue anyway?" Use AskUserQuestion. If they abort, stop here.

## 3. Back up runtime state

Run:

```bash
./.claude/skills/safe-update/scripts/backup-store.sh
```

Parse the status block. Record `BACKUP_DIR` for potential rollback.

Report to user: "Backed up database and auth to `{BACKUP_DIR}` ({BACKUP_SIZE_MB} MB)"

**If STATUS=error:** Stop. Restart the service (step 8) without updating.

## 4. Fetch upstream and preview

Run:

```bash
./.claude/skills/safe-update/scripts/fetch-upstream.sh
```

Parse the status block. Extract `TEMP_DIR`, `CURRENT_VERSION`, `NEW_VERSION`.

**If STATUS=error:** Show error, skip to step 8 (restart service).

**If CURRENT_VERSION equals NEW_VERSION:** Tell user they're up to date. Use AskUserQuestion: "Force update anyway?" / "Cancel". If cancel, skip to step 8.

Run the preview:

```bash
npx tsx scripts/update-core.ts --json --preview-only <TEMP_DIR>
```

Present changes to user:
- "Updating from **{currentVersion}** to **{newVersion}**"
- Number of files changed (list if <= 20, summarize otherwise)
- Conflict risks and custom patches at risk
- Files to be deleted

Use AskUserQuestion: "Apply this update?" with "Yes, apply update" / "No, cancel". If cancel, clean up temp dir and skip to step 8.

## 5. Apply update

Run:

```bash
npx tsx scripts/update-core.ts --json <TEMP_DIR>
```

Parse the JSON output.

**If success=true with no issues:** Continue to step 6.

**If backupPending=true (merge conflicts):** For each file in `mergeConflicts`:
1. Read the file (contains `<<<<<<<` / `=======` / `>>>>>>>` markers)
2. Check for intent files in applied skills (`.claude/skills/<skill>/modify/<path>.intent.md`)
3. Resolve using intent and codebase understanding
4. Write resolved file

After resolving: `npx tsx scripts/post-update.ts`

**If resolution fails:** Proceed to rollback (step 7).

**If customPatchFailures or skillReapplyResults failures:** Warn user but continue (these are non-fatal).

## 6. Build, test, and verify

Run migrations between versions:

```bash
npx tsx scripts/run-migrations.ts <CURRENT_VERSION> <NEW_VERSION> <TEMP_DIR>
```

**If any migration fails:** Proceed to rollback (step 7).

Install dependencies and build:

```bash
npm install && npm run build
```

**If build fails:** Try once more after `npm install`. If still fails, proceed to rollback (step 7).

Run tests:

```bash
npm test
```

**If tests fail:** Try to diagnose and fix. If cannot fix, proceed to rollback (step 7).

Restart the service if it was previously running:

```bash
./.claude/skills/safe-update/scripts/start-service.sh
```

Run health check:

```bash
./.claude/skills/safe-update/scripts/verify-health.sh
```

**If PROCESS_RUNNING=false or DB_INTEGRITY=error:** Proceed to rollback (step 7).

**If everything passes:** Skip to step 8 (success path).

## 7. Rollback (only if steps 5-6 failed)

This step runs ONLY if something failed after the backup was taken.

Stop the service if it was started during step 6:

```bash
./.claude/skills/safe-update/scripts/stop-service.sh
```

Restore runtime state from backup:

```bash
./.claude/skills/safe-update/scripts/restore-store.sh <BACKUP_DIR>
```

Restore source files using the skills-engine backup (created by update-core.ts):

```bash
npx tsx -e "import { restoreBackup, clearBackup } from './skills-engine/backup.js'; restoreBackup(); clearBackup();"
```

Rebuild from restored source:

```bash
npm run build
```

Restart the service:

```bash
./.claude/skills/safe-update/scripts/start-service.sh
```

Run health check:

```bash
./.claude/skills/safe-update/scripts/verify-health.sh
```

**If rollback health check fails:** Report the backup location and tell the user to manually restore: `cp <BACKUP_DIR>/messages.db store/messages.db`

Log the rollback (see step 9).

## 8. Restart service (if not already done)

If the service was running before the update (`SERVICE_WAS_RUNNING=true`) and hasn't been started yet:

```bash
./.claude/skills/safe-update/scripts/start-service.sh
```

## 9. Log and cleanup

Append to `.nanoclaw/safe-update.log`:

```
[ISO_TIMESTAMP] safe-update from <old> to <new>
  Backup: <backup_dir>
  Update applied: yes/no
  Build: pass/fail
  Tests: pass/fail
  Rollback: none/success/fail
  Result: SUCCESS | ROLLED_BACK | FAILED
```

Clean up the temp directory from fetch-upstream:

```bash
rm -rf <TEMP_DIR>
```

Clean up backups older than 30 days:

```bash
find .nanoclaw/safe-update-backup/ -maxdepth 1 -type d -name '20*' -mtime +30 -exec rm -rf {} +
```

Do NOT remove the current backup. Tell user it's at `<BACKUP_DIR>`.

Report final status:
- **Success:** "Updated from **X** to **Y**. Service is running. Backup at `<path>`."
- **Rolled back:** "Update failed at [step]. Rolled back to previous version. Service is running."
- **Failed:** "Update and rollback both failed. Backup preserved at `<path>` for manual recovery."

## Troubleshooting

**sqlite3 not installed:** The backup script falls back to `cp` when `sqlite3` CLI is unavailable. This is safe because the service is stopped first. However, `verify-health.sh` cannot run `PRAGMA integrity_check` without it.

**Backup directory missing:** If `.nanoclaw/safe-update-backup/latest` exists, it symlinks to the most recent backup. Use `ls -la .nanoclaw/safe-update-backup/` to find all backups.

**Rollback didn't fix the issue:** The backup only covers `store/messages.db` and `store/auth/`. If the problem is in source code, the skills-engine backup handles that separately. Check `.nanoclaw/backup/` for source file backups.

**Service won't start after rollback:** Check `logs/nanoclaw.error.log`. Common cause: the build artifacts (`dist/`) don't match the restored source. Run `npm run build` manually after rollback.
