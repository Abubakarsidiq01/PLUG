# Evidence

One folder per phase. A gate is not signed without the folder.

```
evidence/
  P0/
    ios/        one screenshot per required state, real device,
                default and largest Dynamic Type
    web/        Playwright captures at 360, 768 and 1280 px
    failures/   at least one deliberate failure, recovered, recorded
    a11y/       axe report (web) + VoiceOver walkthrough (iOS)
    security/   dependency scan, header check, forbidden-role test, abuse suite
    logs/       the correlation ID from the connected checkpoint,
                in both the client and the backend log
```

The state matrix in section 12 of the manual says which states are required for
which screen. The reviewer checks this folder against that table. Missing
screenshots block the gate.
