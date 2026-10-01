---
name: github-cli
description: Use the GitHub CLI (gh) for all GitHub work. Use this skill when the user asks to do anything on GitHub - read or open an issue, fork or clone a repo, push a branch, open, review or merge a pull request, check Actions runs, make a release, or read files from a GitHub repo. Also use it when the user gives a github.com link, says "make a PR", "open an issue", "fork it", or "check the workflow", even if they do not say "gh".
---

# GitHub CLI

Use `gh` for every GitHub task. Do not use a web fetch, curl, or the browser to read or change GitHub. `gh` uses the user's login, works with private repos, and gives exact data.

## 1. Check the setup first

Before the first GitHub command in a session, run:

```bash
gh auth status
```

- If `gh` is not installed, tell the user how to install it. On Ubuntu, use the official apt repo from https://cli.github.com, not the old Ubuntu package. Stop until it is installed.
- If the user is not logged in, tell them to run `gh auth login`. Do not ask for a token in the chat.

Then check what the user can do in the repo:

```bash
gh api repos/OWNER/REPO --jq '.permissions'
```

If `push` is `false`, use the fork flow (section 4).

## 2. Read GitHub data

| Task | Command |
| --- | --- |
| Repo summary and README | `gh repo view OWNER/REPO` |
| List files | `gh api repos/OWNER/REPO/contents/PATH --jq '.[].path'` |
| Read one file | `gh api repos/OWNER/REPO/contents/PATH --jq .content \| base64 -d` |
| List issues | `gh issue list -R OWNER/REPO` |
| Read an issue and its comments | `gh issue view N -R OWNER/REPO --comments` |
| List pull requests | `gh pr list -R OWNER/REPO --state all` |
| Read a PR, its diff, its checks | `gh pr view N -R OWNER/REPO`, `gh pr diff N -R OWNER/REPO`, `gh pr checks N -R OWNER/REPO` |
| Workflow runs | `gh run list -R OWNER/REPO`, `gh run view RUN_ID -R OWNER/REPO --log-failed` |
| Releases | `gh release list -R OWNER/REPO` |
| Anything else | `gh api ...` with `--jq` to keep the output short |

When the user gives a github.com link, take OWNER, REPO and the number from the link. Then use the matching command above.

To read many files, clone the repo into a temporary folder: `git clone --depth 1 https://github.com/OWNER/REPO`.

## 3. Commits and pull request titles

Use Conventional Commits for every commit message and every PR title:

```
<type>(<optional scope>): <short summary in the imperative>
```

| Type | Use for |
| --- | --- |
| `feat` | A new feature or a new skill |
| `fix` | A bug fix |
| `docs` | Documentation only |
| `chore` | Maintenance: changelog, config, dependencies |
| `refactor` | A code change that does not change behavior |
| `test` | Tests only |
| `ci` | Workflow and CI changes |

Rules:

- Keep the summary under 72 characters, in lower case, with no period at the end.
- Put one type of change in one commit. Split unrelated changes into separate commits.
- Use the body to say what changed and why.
- Before you commit, read the message again and make sure that it starts with a type.

## 4. Make a pull request

### If the user has write access

```bash
git checkout main && git pull
git checkout -b feat-short-name
# make the changes
git add PATHS && git commit -m "feat: short summary"
git push -u origin feat-short-name
gh pr create --base main --title "feat: short summary" --body-file BODY.md
```

### If the user has no write access (fork flow)

```bash
gh repo fork OWNER/REPO --clone     # origin = the fork, upstream = OWNER/REPO
cd REPO
git checkout -b feat-short-name
# make the changes and commit
git push -u origin feat-short-name
gh pr create --repo OWNER/REPO --base main --head FORK_OWNER:feat-short-name \
  --title "feat: short summary" --body-file BODY.md
```

If the fork already exists, update it before you make a branch:

```bash
git fetch upstream
git checkout main && git merge --ff-only upstream/main
```

GitHub cannot fork an empty repo. If the repo has no branches, tell the user that an owner must add a first commit, for example a README.

### The PR body

Write these sections:

1. **Summary**: one or two sentences about the purpose.
2. **What changed**: a list of the changed files or parts.
3. **Testing**: what you ran and the result. If you did not test something, say so.
4. **After merge**: settings or steps that a maintainer must do, if there are any.

## 5. Ask before an action that other people see

These actions change GitHub for other people. Ask the user before you do them, unless the user told you to do that action in this task:

- open, close, or merge a pull request
- open, close, or comment on an issue
- push to a shared branch, or force-push
- delete a branch, a release, or a repo
- make a release or push a tag
- change repo settings

Do not push to `main` of a shared repo. Use a branch and a pull request.

Do not force-push or rewrite history on a branch that is already merged.

If the user asks you to redo a pull request, close the old one with `gh pr close N --comment "REASON"`. Then open a new one, and write "Replaces #N" in the body.

## 6. Report the result

After each GitHub action, give the user:

- the link that `gh` printed, for example the PR URL
- what was done, and what was not done
- any step that only an owner or admin can do, for example merge, or turn on a repo setting

If a command fails, show the error message and explain it. For example, `HTTP 403` means that the user does not have permission. Do not try the same command again without a change.
