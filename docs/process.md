# Development Process

We follow **spec-driven development**: every meaningful change starts with a
written spec.

## Lifecycle
1. **Idea** — captured as a one-line problem statement.
2. **Spec** — write a spec using [TEMPLATE.md](specs/TEMPLATE.md). Discuss and
   align before coding.
3. **Build** — implement against the spec. Update the spec if reality forces
   changes.
4. **Verify** — confirm the spec's acceptance criteria are met.
5. **Ship** — release. The spec becomes the historical record of the change.

## When to write a spec
- New feature
- Significant refactor
- Architectural change
- Anything that affects users or other teams

Skip the spec for: trivial fixes, typos, dependency bumps.

## Code review
Reviewers check:
- Does the change match the linked spec?
- Are the acceptance criteria met?
- Are deviations from the spec called out in the PR?
