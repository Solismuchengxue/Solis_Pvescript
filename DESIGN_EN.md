# Design Boundaries

[中文](DESIGN.md)

Status: migration to the formal path is complete, and the independent public/private repository topology is active.

## Project Topology

The project uses an outer container with two independent Git repositories:

```text
Solis_Pvescript/
├── public/   # public repository: Solismuchengxue/Solis_Pvescript
└── private/  # private repository: Solismuchengxue/Solis_Pvescript-private
```

The outer `Solis_Pvescript/` directory only contains the repositories. It is not a third repository and must not hold a project-level Git history or Agent state.

## Repository Responsibilities

- `public/`: compliant user-facing scripts, public documentation, and driver acquisition entry points without credentials.
- `private/`: the complete personal deployment edition, private extensions, and driver archives retained within their authorized scope.
- Each repository has its own Git history, branch, remote, and working-tree state. They are not branches or worktrees of one repository.

## Maintenance Invariants

- Maintenance ended on 2026-11-01. This design is retained as historical architecture; no new development or deployment work is planned.

- The formal project path is `F:\60_Infrastructure_and_Operations\Solis_Pvescript`.
- Preserve the outer container and its `public/` and `private/` repositories.
- Do not merge the repositories, initialize Git in the outer directory, rewrite history, or silently change a remote.
- Delivery, maintenance, and migration checks must verify each repository's HEAD, branch, remote, status, and worktree independently.
- Public accepts only content suitable for disclosure. Private assets, drivers, credentials, and site configuration must not enter public through documentation synchronization.

## Infrastructure Safety Boundary

- Documentation, migration, or repository-governance work must not operate PVE, FnOS, drivers, VMs, containers, deployments, or hardware.
- The public repository must not receive private driver binaries, credentials, certificates, tokens, or private configuration.
- Deletion, movement, remote changes, history changes, or runtime configuration require separate explicit authorization.

See [`README_EN.md`](README_EN.md) for the technical architecture, module responsibilities, end-to-end workflows, and current limitations.
