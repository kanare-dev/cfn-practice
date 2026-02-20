<!--
Sync Impact Report
==================
Version change: [TEMPLATE] → 1.0.0
Modified principles: N/A (initial ratification — all four principles are new)
Added sections:
  - Core Principles: I. Code Quality, II. Testing Standards,
    III. UX Consistency, IV. Performance Requirements
  - Development Workflow
  - Quality Gates & Review Process
  - Governance
Removed sections: N/A (template placeholders cleared)
Templates requiring updates:
  - .specify/templates/plan-template.md ✅ — Constitution Check section aligns with
    I–IV; Performance Goals/Constraints fields directly support Principle IV
  - .specify/templates/spec-template.md ✅ — Acceptance Scenarios support Principle II;
    Measurable Outcomes support Principles III and IV
  - .specify/templates/tasks-template.md ✅ — Test tasks, Polish phase, and quality
    gates align with Principles I–IV; no structural changes required
  - .specify/templates/agent-file-template.md ⚠ pending — Code Style section should
    reflect Principle I constraints once the active technology stack is defined
Follow-up TODOs: None — all placeholders resolved
-->

# CFN Practice Constitution

## Core Principles

### I. Code Quality

All production code MUST pass automated static analysis (linting and formatting) before
merge. Cyclomatic complexity per function MUST NOT exceed 10; any exception MUST be
documented in the Complexity Tracking table of the relevant `plan.md`.

- Code MUST be reviewed by at least one peer before merging to the main branch.
- Functions and modules MUST have a single, clearly stated responsibility (SRP).
- Dead code, commented-out blocks, and unused imports MUST be removed before merge.
- Inline comments are REQUIRED only where business logic is non-obvious; trivially
  readable code MUST NOT be over-commented.
- All public interfaces MUST be named clearly enough to communicate intent without
  requiring a docstring to understand.

**Rationale**: Consistent quality standards reduce defect rates, lower onboarding
friction, and make code reviews faster and more effective.

### II. Testing Standards

Testing MUST follow a Test-First discipline: tests are written and confirmed to FAIL
before implementation begins. The Red-Green-Refactor cycle MUST be enforced on every
task.

- Unit tests MUST cover all public interfaces and non-trivial internal logic.
- Integration tests MUST be written for every cross-component boundary and every
  external service interaction.
- Contract tests MUST be written whenever an API endpoint or shared schema is introduced
  or changed.
- Minimum branch coverage target: 80%. Falling below this threshold MUST block merge.
- Tests MUST be deterministic: random data, sleep calls, or environment-dependent
  assertions are PROHIBITED without explicit documented justification.
- Skipping tests or reducing coverage MUST be recorded in the Complexity Tracking table
  and approved by a second reviewer.

**Rationale**: Test-first development prevents defect accumulation, documents expected
behavior as executable specifications, and enables safe refactoring.

### III. User Experience Consistency

All user-facing interfaces MUST conform to the established interaction patterns and
visual language defined in the feature spec. Any deliberate divergence MUST be explicitly
approved and documented before implementation.

- Error messages MUST be human-readable, identify the root cause, and suggest a
  corrective action. Silent failures visible to end users are PROHIBITED.
- Navigation and interaction flows MUST be consistent across equivalent screens or
  commands — no surprising context switches.
- Loading, error, and empty states MUST be handled explicitly in every user-facing
  component.
- Accessibility requirements (keyboard navigation, screen-reader labels, sufficient
  color contrast) MUST be addressed for any visual component.

**Rationale**: Inconsistent UX erodes user trust and increases support burden. Explicit
handling of all states eliminates a leading source of user-facing defects.

### IV. Performance Requirements

Performance targets MUST be defined per feature in the `plan.md` Technical Context
section before implementation begins. Targets are non-negotiable quality gates, not
aspirational goals.

- API response time: p95 MUST be ≤ 200 ms under expected load unless a higher budget
  is explicitly justified in `plan.md`.
- Page/screen load time: Time-to-interactive MUST be ≤ 2 s on a mid-tier
  device/network profile.
- Memory footprint: No feature MUST cause a measurable regression (> 5%) in baseline
  memory usage without explicit approval.
- Performance regression tests MUST be part of the CI/CD pipeline; a failing regression
  test MUST block merge.

**Rationale**: Performance is a feature. Regressions not caught at merge time compound
into systemic degradation that is expensive to remediate later.

## Development Workflow

All feature work MUST follow the speckit lifecycle in order:

1. **Specify** (`/speckit.specify`): Define user stories and acceptance scenarios.
2. **Clarify** (`/speckit.clarify`): Resolve ambiguities before design begins.
3. **Plan** (`/speckit.plan`): Produce architecture, data model, and contracts.
4. **Constitution Check**: Verify `plan.md` satisfies Principles I–IV before proceeding.
5. **Tasks** (`/speckit.tasks`): Generate ordered, dependency-aware task list.
6. **Implement** (`/speckit.implement`): Execute tasks; tests MUST fail before code
   is written.
7. **Analyze** (`/speckit.analyze`): Run cross-artifact consistency check before PR.

Skipping steps or reordering MUST be documented with explicit justification in the
relevant `plan.md`.

## Quality Gates & Review Process

The following gates MUST pass before any code is merged to the main branch:

| Gate | Enforced By | Failure Action |
| ---- | ----------- | -------------- |
| Lint & formatting | CI (automated) | Block merge |
| Test coverage ≥ 80% | CI (automated) | Block merge |
| No failing tests | CI (automated) | Block merge |
| Performance regression | CI (automated) | Block merge |
| Peer code review | Pull request approval | Block merge |
| Constitution Check | Plan review checklist | Block plan approval |

Use of `--no-verify`, coverage exclusions, or skip pragmas MUST be recorded in the
Complexity Tracking table and approved by a second reviewer. Violations MUST be resolved,
not suppressed.

## Governance

This constitution supersedes all other written or informal development practices. In the
event of a conflict, the constitution takes precedence.

**Amendment procedure**:

1. Propose the change in writing (PR or document), citing the principle affected and the
   rationale for the change.
2. Obtain approval from at least two project stakeholders.
3. Update `constitution.md`, increment the version per the versioning policy below, and
   propagate changes to all dependent templates (record in Sync Impact Report).
4. Record the amendment in the Sync Impact Report comment block at the top of this file.

**Versioning policy**:

- MAJOR: Removal or redefinition of a principle that changes compliance requirements.
- MINOR: Addition of a new principle or materially expanded guidance.
- PATCH: Clarifications, wording fixes, non-semantic refinements.

**Compliance review**: Every PR description MUST include a Constitution Check confirming
changes satisfy Principles I–IV. Non-compliance MUST be justified in the `plan.md`
Complexity Tracking table or the PR description, and approved before merge.

**Version**: 1.0.0 | **Ratified**: 2026-02-21 | **Last Amended**: 2026-02-21
