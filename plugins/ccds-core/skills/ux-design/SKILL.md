---
name: ux-design
description: UX and frontend design critic. Auto-invoked when implementing UI components, forms, layouts, navigation flows, or any user-facing interactions.
---

# UX Design

UI that passes QA can still fail users — unclear states, broken keyboard paths, and
inconsistent patterns erode trust one interaction at a time, and nobody files a bug
for "this felt confusing".

## When to reach for this

- Implementing or reviewing UI components, forms, layouts, or navigation flows
- Adding loading, error, empty, and success states to a user-facing surface
- Checking a new screen against the product's existing design-system conventions
- Diagnosing friction or confusion reports in an existing flow

## Principles

1. **Usability first.** The interface must be clear, learnable, and forgiving of
   errors — destructive actions confirm or undo, never silently commit.
2. **Every state is designed.** Loading, success, error, and empty states are part of
   the component, not afterthoughts; an unhandled state is a blank screen in prod.
3. **Consistency beats novelty.** Match the visual and interaction language of the
   rest of the product; a one-off pattern is a usability bug even if it's "better".
4. **Accessibility is the baseline, not a layer.** Keyboard reachability, screen-reader
   compatibility, and focus management are checked during implementation (pull
   `common-a11y` for criterion-level audits).
5. **Responsive means unbroken, not just resized.** Verify the layout at small,
   medium, and large viewports — including text-zoom at 200%.
6. **Copy is part of the interface.** UI text must be clear, actionable, and free of
   jargon; error messages say what happened and what to do next.
7. **Perceived performance is UX.** Flag layout shift, flash of unstyled content, and
   blocking renders — users experience these as broken, not slow.

## Accessibility baseline (non-negotiable)

- [ ] All interactive elements reachable and operable via keyboard
- [ ] ARIA roles and labels present where native semantics are insufficient
- [ ] Color is never the sole means of conveying information
- [ ] Minimum contrast ratio: 4.5:1 for normal text, 3:1 for large text
- [ ] Focus indicators visible — no `outline: none` without an equivalent replacement

## Review pass

When critiquing a surface, walk these dimensions and label findings `[BLOCKER]`,
`[CONCERN]`, or `[NIT]`, citing the specific WCAG criterion for accessibility issues:

| Dimension | The question |
|---|---|
| Usability | Clear, learnable, forgiving of errors? |
| Accessibility | Keyboard, screen reader, contrast, focus management? |
| Consistency | Matches the product's visual and interaction language? |
| Feedback | Loading / success / error / empty states communicated? |
| Responsiveness | Works across viewport sizes without breaking? |
| Copy | Clear, actionable, jargon-free? |

End a critique with 2–3 concrete improvements the developer can act on immediately.

## Pitfalls

- Forms that lose user input on validation failure
- Disabled buttons with no explanation of *why* they are disabled
- Spinners with no timeout or failure path — eternal loading on a dropped request
- Modal dialogs that trap scroll, lose focus, or can't be closed by keyboard
- Empty states that show a blank region instead of guiding the first action
- "Mobile works" claims tested only by narrowing a desktop browser

---
*Related: `common-a11y` (criterion-level audit), `common-i18n` (RTL and text
expansion), `common-notifications` (preferences UI) · pulled by any domain agent ·
output/ADR format: `playbook-conventions`*
