# Security Policy

## Reporting a Vulnerability

If you find a security issue in the SideQuest plugin or native app, please **do not open a public GitHub issue**.

Use [GitHub's private vulnerability reporting](https://github.com/trySideQuest-ai/sidequest/security/advisories/new) (the **Security** tab → **Report a vulnerability**).

Include:

- A description of the issue and its impact.
- The affected version(s) (`plugin/VERSION` and the macOS app `CFBundleShortVersionString`).
- Steps to reproduce.
- A proof-of-concept if one exists.
- Whether you would like credit in the disclosure (and how to attribute).

## Response

This project is maintained by a small team. We will respond to reports as quickly as we can but do not commit to a fixed SLA. If we cannot fix an issue, we will explain why.

## Scope

Security reports are accepted for code in this repository:

- The Claude Code plugin under `plugin/` (Bash + Python hooks, skills).
- The native macOS app under `macOS/` (Swift sources, Xcode project, scripts).
- Build + release scripts under `scripts/` and `.github/workflows/`.

Out of scope (please report to the relevant project instead):

- Vulnerabilities in third-party dependencies — please report to the upstream maintainer; a heads-up here is welcome so we can pin a fix.
- Issues in the SideQuest API or landing pages — those live in a private repository and have their own disclosure path.

## Bug Bounty

There is no bug bounty program. We may credit responsible disclosures in release notes if you want.
