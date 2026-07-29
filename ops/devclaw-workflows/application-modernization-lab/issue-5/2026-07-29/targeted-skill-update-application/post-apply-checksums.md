# Post-Apply Checksums

## Required After-State Comparison

| File | Required SHA-256 | Actual SHA-256 | Result |
| --- | --- | --- | --- |
| `SKILL.md` | `d4631c7a987092f9247a615d4917cbd55fb453f543ca93273b506c35ffb6469f` | `d4631c7a987092f9247a615d4917cbd55fb453f543ca93273b506c35ffb6469f` | Match |
| `references/aspire-modeling.md` | `7efba9137e79800ce52544d0f4a2346dc2721384e3a30a7d916ebb95af57acda` | `7efba9137e79800ce52544d0f4a2346dc2721384e3a30a7d916ebb95af57acda` | Match |
| `references/compose-inventory.md` | `b06db062dfda05871f653df588ec142ad2f68df2a9c158d417c705d84861b6fc` | `b06db062dfda05871f653df588ec142ad2f68df2a9c158d417c705d84861b6fc` | Match |
| `references/failure-modes.md` | `0eca396d7834146c57c3651f6d433160ed2c15c8870753232f7adf18ad44ed77` | `0eca396d7834146c57c3651f6d433160ed2c15c8870753232f7adf18ad44ed77` | Match |
| `references/validation-checklist.md` | `d5c9696448e243acfaa941a5eb274af80f730d4ae3b6ecf6216babe90f85ddb7` | `d5c9696448e243acfaa941a5eb274af80f730d4ae3b6ecf6216babe90f85ddb7` | Match |

## Additional Checks

- Active inventory remained exactly five files.
- No new active skill or active reference file was created.
- Active skill remained readable.
- Directory ownership and permissions remained `devclaw-svc:devclaw-svc 700`.
- Active file ownership and permissions remained `devclaw-svc:devclaw-svc 600`.
- Actual changed files were limited to the three approved reference files.
