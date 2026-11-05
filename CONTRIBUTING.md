# Contributing to iChat

## Pull requests & reviews

All changes to **`main`** should land via pull request and be reviewed before merge.

| Role | GitHub account |
| --- | --- |
| Owner / required code owner | [@OldCodmasters](https://github.com/OldCodmasters) (Amin Dehghani) |

Ownership is declared in [`.github/CODEOWNERS`](.github/CODEOWNERS). That file auto-requests reviewers; **required** approval is enforced only after the repository ruleset below is enabled in GitHub Settings (bots cannot flip that switch with current token permissions).

### Add more required reviewers later

1. Give the person **Write** access: Settings → Collaborators → Add people.
2. Edit `.github/CODEOWNERS` and append their `@username` on the default `*` line (or add a path-specific line).
3. Open a PR; after merge, new PRs that touch those paths will request them.
4. With **Require review from Code Owners** enabled on the ruleset, any listed code owner’s approval satisfies the ownership check (see GitHub docs). Keep Amin on the line unless you intentionally transfer ownership.

### What the agent / automation cannot finish

Creating or editing **repository rulesets / branch protection** returned HTTP 403 for this environment’s GitHub token. Amin (repo admin) must apply the Settings steps once.

---

## Branch protection — Settings steps for Amin

Do this on **https://github.com/OldCodmasters/iChat** while signed in as `@OldCodmasters`:

1. Open **Settings → Rules → Rulesets → New ruleset → New branch ruleset**  
   (classic UI: **Settings → Branches → Add branch protection rule** — rulesets are preferred).
2. **Ruleset name:** `Protect main — required reviews`
3. **Enforcement status:** Active
4. **Target branches:** Include `main` (or `refs/heads/main`)
5. Enable rules:
   - **Restrict deletions**
   - **Block force pushes**
   - **Require a pull request before merging**
     - Required approvals: **1**
     - **Require review from Code Owners** ← required so `@OldCodmasters` (and anyone you add to CODEOWNERS) must approve
     - **Dismiss stale pull request approvals when new commits are pushed** (recommended)
   - Optionally: **Require status checks to pass** once CI exists
6. **Bypass list:** leave empty if you want no unreviewed merges.  
   If you keep yourself as bypass for emergencies, know that bypasses can merge without review — avoid for “every merge must be reviewed.”
7. Save the ruleset.

**Solo-owner note:** GitHub will not count your own approval on your own PR as satisfying “required reviews” in the usual case. With no bypass, a second code owner (or temporary bypass) is needed for Amin-authored PRs. Collaborator PRs must get Amin’s (or another CODEOWNERS) approval.

Verify: open a test PR from a branch; the UI should request `@OldCodmasters` and block merge until approved (and ruleset active).

---

## Architecture reminder (Stage 1)

Realtime path is **chatlog `fs.watch` + companion overlay + WebSocket relay** — not SavedVariables poll / `/ichat sync`. See root [README.md](README.md).
