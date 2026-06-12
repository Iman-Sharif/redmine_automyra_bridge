# Submodule / Push Discipline & Anti-Loss Checklist

This plugin's history includes one catastrophic data loss event:
migrations were silently `.gitignore`d under a blanket `db/` rule, work was
committed against an orphaned ref, and the parent's tracked pointer drifted
from the working tree. The result was that a "green" submodule sitting on top
of a stale parent pointer effectively threw the migrations away.

This doc is the push discipline that prevents that from happening again.
Every command and path here is grounded in the actual layout of this repo as
of HEAD `28625ac`. If something here stops matching reality, fix this doc
first, then push.

---

## 1. Repo reality (verify, don't assume)

Plugin working tree (host bind-mount, also live inside the container):

- Host: `/opt/redmica/plugins/redmine_automyra_bridge/`
- Container: `/usr/src/redmica/plugins/redmine_automyra_bridge/`

Plugin remote:

```
origin  https://github.com/Iman-Sharif/automyra-redmica.git (fetch)
origin  https://github.com/Iman-Sharif/automyra-redmica.git (push)
```

Branch: `main`. There is no protected production branch in front of it,
so a push is the deploy.

Parent layout (`/opt/redmica`):

- `/opt/redmica` is itself a git working tree (separate clone, same URL).
- It tracks `plugins/redmine_automyra_bridge` as a **gitlink** (mode `160000`):
  ```
  $ git -C /opt/redmica ls-tree HEAD plugins/redmine_automyra_bridge
  160000 commit <sha>	plugins/redmine_automyra_bridge
  ```
- There is **no `.gitmodules` file** in the parent. The plugin is a gitlink
  (a tree pointer to a commit SHA) but is not registered as a configured
  submodule. Consequence: `git submodule update` does not pull or sync this
  path. The pointer can only move via an explicit `git add <path>` in the
  parent.
- The plugin's `.git` is a real directory (full standalone clone), not a
  `gitdir:` pointer file. So the plugin can be committed and pushed on its
  own without the parent participating.

Verify both ends any time:

```
git -C /opt/redmica/plugins/redmine_automyra_bridge remote -v
git -C /opt/redmica/plugins/redmine_automyra_bridge rev-parse HEAD
git -C /opt/redmica/plugins/redmine_automyra_bridge rev-parse --show-superproject-working-tree
git -C /opt/redmica ls-tree HEAD plugins/redmine_automyra_bridge
ls /opt/redmica/.gitmodules 2>/dev/null
```

If `.gitmodules` is empty/missing and the parent prints a `160000` line, you
are in the gitlink-only hybrid this doc is written for.

---

## 2. Standalone-clone workflow (current default)

This is the workflow you use today, because the parent's `.gitmodules` is not
populated. Treat the plugin as a normal repo.

```
cd /opt/redmica/plugins/redmine_automyra_bridge
git status                 # confirm clean / expected diff
git add <intended files>   # avoid `git add .` when sibling tasks are in flight
git commit -m '...'
git push origin main
```

Bind-mount caveat that's bitten this repo before: every host edit is
**immediately live inside the container** (the entrypoint reruns
`db:migrate` + `redmine:plugins:migrate`). Live does not mean saved.
Until you commit and push, a `docker compose down && up`, image rebuild,
or host reset can wipe the change. "It works in prod" is not a substitute
for `git push`.

---

## 3. Submodule workflow (when the parent is updated to a real submodule)

If `/opt/redmica` is later promoted to track this plugin via `.gitmodules`
(or any time the parent's gitlink pointer needs to move), the discipline is:

```
# 1. Commit + push inside the plugin first.
cd /opt/redmica/plugins/redmine_automyra_bridge
git add <intended files>
git commit -m '...'
git push origin main          # plugin SHA must be reachable on origin

# 2. Move the parent pointer to the new SHA.
cd /opt/redmica
git add plugins/redmine_automyra_bridge
git commit -m 'bump automyra plugin pointer to <short-sha>'
git push origin <parent-branch>
```

Even with no `.gitmodules`, **step 2 is what's missing today** — the parent
is sitting on `ca752137`, the plugin is on `28625ac`, that's a 17-commit
drift. The parent pointer is what gets cloned/checked-out by anyone bringing
up a fresh environment from `/opt/redmica`. A green submodule with a stale
parent pointer is split-brain: fresh deploys roll back to the parent's
pointer and silently lose every plugin commit since.

Rules of thumb:

- Push the plugin **first**, then the parent. Never the other way around —
  a parent pointing at an unpushed SHA is a broken clone for everyone else.
- The parent commit message should name the plugin short SHA so the bump
  is greppable.
- If you `git checkout` a different parent branch / commit, the plugin
  pointer it carries may be older than your working tree. Check with
  `git -C /opt/redmica ls-tree HEAD plugins/redmine_automyra_bridge`
  before you assume the working tree matches "what's deployed".

---

## 4. Anti-loss checklist (run before every push)

Run from `/opt/redmica/plugins/redmine_automyra_bridge`:

- [ ] **No untracked migrations.** This is the original-catastrophe guard.
      Every `db/migrate/*.rb` must be tracked, never `.gitignore`d.
      ```
      for f in db/migrate/*.rb; do
        git check-ignore -q "$f" && echo "LOST: $f"
      done
      # must print nothing
      ```

- [ ] **`.gitignore` does not blanket-ignore `db/`.** Task 2 fixed this; verify
      the targeted shape is intact:
      ```
      grep -nE '^(db/|!db/migrate|!db/schema\.rb|db/\*\.sqlite3)' .gitignore
      # expected lines: db/*.sqlite3, db/*.sqlite3-*, !db/migrate/, !db/migrate/**, !db/schema.rb
      # must NOT contain a bare `db/` or `db/**` ignore
      ```

- [ ] **No orphaned work.** `git status` shows nothing unexpected; nothing
      committed against a detached HEAD.
      ```
      git status
      git symbolic-ref HEAD       # must print refs/heads/main, not error
      ```

- [ ] **Schema and migrations in sync.** New migration files have a matching
      bump in `db/schema.rb`, and the version count matches what's in prod.
      ```
      ls db/migrate/*.rb | wc -l                 # repo count
      grep -c 'redmine_automyra_bridge' \
        <(docker exec redmica-app psql ... \
          -c "select version from schema_migrations where version like '%-redmine_automyra_bridge'")
      # must match (28-and-rising as of HEAD 28625ac)
      ```

- [ ] **Plugin pushed.** `git push origin main` exits 0 and the remote
      tip matches local HEAD:
      ```
      git rev-parse HEAD
      git rev-parse origin/main
      # must be equal
      ```

- [ ] **Parent pointer pushed (submodule case only).** If the parent is
      tracking the plugin via gitlink and you intended this commit to land
      in the parent's deploy:
      ```
      cd /opt/redmica
      git ls-tree HEAD plugins/redmine_automyra_bridge | awk '{print $3}'
      # must equal the plugin HEAD you just pushed
      ```
      If it doesn't, the pointer bump in section 3 step 2 was skipped.

- [ ] **Bind-mount sanity.** The host `git rev-parse HEAD` and the
      container's `git -C /usr/src/redmica/plugins/redmine_automyra_bridge
      rev-parse HEAD` agree (they're the same files via bind-mount, so they
      should). Disagreement means the container is on a different image
      layer or the bind-mount is broken.

A push is "done" only when every item above is checked. Half a push (plugin
pushed, parent pointer not bumped, or migration silently ignored) is what
caused the original loss.

---

## 5. Reference: the original loss

For the historical context this doc exists to prevent, see the plugin
notepad's `learnings.md`:

- Task 3: confirms this is a "full git clone (not submodule)" with
  `origin → https://github.com/Iman-Sharif/automyra-redmica.git`, deployed
  via RW bind-mount.
- Task 1: 28-migration parity baseline against prod `schema_migrations`.
- Task 2: replaced the blanket `db/` `.gitignore` rule with the targeted
  pattern in section 4 above (`db/*.sqlite3` only; `!db/migrate/`,
  `!db/schema.rb` explicitly un-ignored).

The catastrophe vector was not "bad git". It was a `.gitignore` rule that
made migrations invisible to `git add`, plus a parent pointer that was never
updated. The checklist above is the literal reverse of those two failures.
