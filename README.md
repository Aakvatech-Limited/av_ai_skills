# Aakvatech AI Skills

Skills for AI agents that the Aakvatech team uses. A skill is a folder with a `SKILL.md` file. The file tells an AI agent how to do one type of task, for example how to build a Frappe app or how to review code.

This repo has two types of skills:

- **Our own skills.** The team writes these.
- **Outside skills.** A workflow copies these from other repos, for example [frappe/skills](https://github.com/frappe/skills). The list of outside repos is in [`sources.yml`](sources.yml).

All skills are in [`skills/`](skills/).

## Contents

- [Install](#install)
  - [Terminal and editor agents](#terminal-and-editor-agents)
  - [Claude on the web and the desktop app](#claude-on-the-web-and-the-desktop-app)
  - [ChatGPT on the web](#chatgpt-on-the-web)
  - [Claude Code on the web](#claude-code-on-the-web)
- [Update](#update)
- [Versions](#versions)
- [Add a skill](#add-a-skill)
- [Add an outside repo](#add-an-outside-repo)
- [How the sync works](#how-the-sync-works)

## Install

### Terminal and editor agents

Use this method for Claude Code, Codex, Cursor, and other agents that run on your computer. You need [Node.js](https://nodejs.org/).

1. Run this command from your home folder:

   ```bash
   npx skills add Aakvatech-Limited/av_ai_skills -g
   ```

2. At **Select skills to install**, select **Select All**.
3. At the list of agents, select the agents that you use, for example **Claude Code**.
4. At **Installation method**, select **Symlink**.
5. Start a new agent session. In Claude Code, type `/` to see the skills.

The `-g` flag installs the skills for all your projects. If you do not use `-g`, the command installs the skills into the current folder. Then git shows the skill files as changes in that project.

To install only some skills, use `--skill`:

```bash
npx skills add Aakvatech-Limited/av_ai_skills -g --skill frappe-app-dev --skill code-style
```

### Claude on the web and the desktop app

1. Go to the [latest release](https://github.com/Aakvatech-Limited/av_ai_skills/releases/latest).
2. Download the `.zip` file for each skill that you want.
3. In Claude, go to **Settings > Capabilities > Skills**.
4. Upload each `.zip` file.

On a Claude Team or Enterprise plan, an admin can upload the skills one time for the full organization.

### ChatGPT on the web

ChatGPT on the web does not install skill folders. Use a ChatGPT Project instead:

1. Download the `.zip` files from the [latest release](https://github.com/Aakvatech-Limited/av_ai_skills/releases/latest).
2. Extract the files.
3. Make a ChatGPT Project.
4. Add the `SKILL.md` files to the project files.

### Claude Code on the web

Claude Code on the web does not see the skills on your computer. It only reads skills in the repo that it works on, in `.claude/skills/`. To use a skill there, copy the skill folder into that repo.

## Update

The method to update depends on how you installed the skills.

| Install method | How to update |
| --- | --- |
| Terminal and editor agents | Run `npx skills update -g`. |
| Claude on the web | Download the new `.zip` files from the latest release. Then upload them again. |
| ChatGPT Project | Download the new files from the latest release. Then replace the files in the project. |

To get an email when there is a new release, go to the repo page. Then select **Watch > Custom > Releases**.

## Versions

Each release has a version tag, for example `v1.2.0`. The tag uses [semantic versioning](https://semver.org/):

- **Major** (`v2.0.0`): a skill was removed or renamed.
- **Minor** (`v1.3.0`): a skill was added, or an outside sync brought new skills.
- **Patch** (`v1.2.1`): a skill was changed or fixed.

[`CHANGELOG.md`](CHANGELOG.md) lists the changes in each version.

[`skills/.sources.lock`](skills/.sources.lock) shows the commit of each outside repo that the outside skills came from.

### Make a release

A maintainer does these steps:

1. Make sure that `main` has all the changes for the release.
2. In `CHANGELOG.md`, move the items under **Unreleased** to a new version heading.
3. Merge that change into `main`.
4. Tag the merge commit and push the tag:

   ```bash
   git checkout main
   git pull
   git tag v1.0.0
   git push origin v1.0.0
   ```

The [release workflow](.github/workflows/release.yml) then makes a GitHub release with one `.zip` file per skill.

## Add a skill

1. Fork this repo. If you have write access, make a branch instead.
2. Make a folder in `skills/`. Use a short name in lowercase with hyphens, for example `skills/frappe-server-script/`.
3. In the folder, add a `SKILL.md` file. Start the file with this frontmatter:

   ```markdown
   ---
   name: frappe-server-script
   description: What the skill does, and when the agent must use it.
   ---

   The instructions for the agent.
   ```

   The `name` must be the same as the folder name. The agent reads the `description` to decide when to use the skill. Write it with care.

4. Optional: add more files to the folder, for example reference files or scripts. Refer to them from `SKILL.md`.
5. Add a line under **Unreleased** in `CHANGELOG.md`.
6. Open a pull request.

Do not use the name of an outside skill. The sync stops with an error if two skills have the same name.

Do not edit the outside skills in `skills/`. The next sync replaces your changes. To change an outside skill, send the change to its source repo.

## Add an outside repo

The outside repo must keep its skills in folders that have a `SKILL.md` file, for example `skills/<name>/SKILL.md`.

1. Add an entry to [`sources.yml`](sources.yml):

   ```yaml
   - name: example
     repo: owner/repo
     ref: main
     path: skills
     include: all
     exclude: []
   ```

   To take only some skills, set `include` to a list of skill names.

2. Open a pull request.
3. After the merge, run the sync. Go to **Actions > Sync upstream skills > Run workflow**.

## How the sync works

The [sync workflow](.github/workflows/sync-upstream.yml) runs every Monday at 03:00 UTC. You can also start it from the **Actions** tab.

The workflow runs [`scripts/sync.sh`](scripts/sync.sh). For each repo in `sources.yml`, the script:

1. Clones the repo.
2. Deletes the skills that it copied from that repo the last time.
3. Copies the selected skills into `skills/`.
4. Writes the commit of the repo to `skills/.sources.lock`.

If the files changed, the workflow opens a pull request. A team member reads the changes and merges the pull request. Read each change with care. An AI agent follows the instructions in a skill.

To run the sync on your computer, install [yq](https://github.com/mikefarah/yq). Then run:

```bash
scripts/sync.sh
```

The workflow can only open pull requests if this setting is on: **Settings > Actions > General > Allow GitHub Actions to create and approve pull requests**.
