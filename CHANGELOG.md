# Changelog

All changes to the skills in this repo. The versions use [semantic versioning](https://semver.org/). See [Versions](README.md#versions) in the README.

## Unreleased

### Added

- Sync of outside skills from the repos in `sources.yml`. The sync runs every week and opens a pull request.
- 9 skills from [frappe/skills](https://github.com/frappe/skills) at commit `0bef982`: `code-style`, `deep-app-audit`, `draft-security-advisory`, `fix-issue`, `frappe-app-dev`, `frappe-code-review`, `resolve-backport-conflicts`, `technical-writing`, `ui-design`.
- Release workflow that makes one `.zip` file per skill for Claude and ChatGPT on the web.
- README with steps to install, update, release, and add skills.
