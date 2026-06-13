# A/B slot OTA state machine

Bootloader + application contract for dual-slot firmware update. The pattern is
the one used (with naming differences) by MCUboot swap modes, Zephyr's
`mcumgr`/DFU flow, Android A/B, and most vendor OTA SDKs — the invariant is:
**at every instant, at least one slot is verified-bootable.**

## Slot metadata (per slot, in its own flash sector)

```c
typedef struct {
    uint32_t magic;          /* valid-metadata marker                   */
    uint32_t fw_version;     /* monotonic; checked against anti-rollback */
    uint8_t  image_hash[32]; /* SHA-256 of payload                      */
    uint8_t  state;          /* EMPTY | STAGED | TRIAL | CONFIRMED | BAD */
    uint8_t  boot_count;     /* attempts in TRIAL before auto-revert    */
} slot_meta_t;
```

Write metadata last, after the payload, and write the `state` field with an
erase-free update if the flash allows it (program 1→0 transitions only), so a
power cut leaves the slot `STAGED`-but-unverified rather than half-`TRIAL`.

## States and transitions

```
                       download complete,
   EMPTY ── download ──► STAGED ── sig+hash verify OK ──► TRIAL (boot_count = N)
                            │                                │
                            └─ verify fails ──► BAD          │ bootloader boots it
                                                             ▼
                              app health checks pass ──► CONFIRMED
                              (app calls ota_confirm())
                                                             │
                 boot_count exhausted / watchdog reset ──────┘
                              ▼
                  REVERT: other slot (CONFIRMED) booted; this slot ► BAD
```

### Bootloader rules (keep it dumb)

1. If a slot is `TRIAL` with `boot_count > 0`: decrement `boot_count`
   (persist!), boot it, start the watchdog.
2. If a slot is `TRIAL` with `boot_count == 0`: mark `BAD`, boot the
   `CONFIRMED` slot.
3. Otherwise boot the `CONFIRMED` slot. If no slot is `CONFIRMED`, enter
   recovery (serial/USB DFU) — this is the "both slots bad" story; it must
   exist even if it's just a recovery image in a third, write-protected slot.
4. The bootloader never clears boot counters and never marks `CONFIRMED`.
   Confirmation is the application's job, after it has proven itself.

### Application confirm flow

```c
void app_main(void) {
    init_hardware();
    if (!selftest_pass())            reboot();       /* burn a trial boot   */
    if (!comms_reach_backend(60_s))  reboot();       /* must phone home     */
    ota_confirm();    /* state := CONFIRMED; bump anti-rollback counter;
                         only NOW is the update "done" for rollout metrics */
    report_version_to_fleet();
}
```

Health checks should cover whatever the device exists to do — a thermostat that
boots but can't read its temp sensor must *not* confirm.

## Power-loss test matrix

Force power cuts at each point; the device must come back running a verified
image every time:

| Cut during | Expected outcome |
|---|---|
| Download (any offset) | resume from persisted offset; slot stays `STAGED` |
| Verification | re-verify on next attempt; no state change |
| Metadata write (`STAGED→TRIAL`) | slot treated as unverified; old slot boots |
| First trial boot | boot_count already decremented → finite retries |
| Between health-check pass and `ota_confirm()` | trial retry or revert — never a half-confirmed slot |
| Anti-rollback counter bump | counter ≤ confirmed version; old signed images still rejected per policy |

## Anti-rollback note

Bump the monotonic counter (eFuse / RPMB / protected flash) only at confirm.
Bumping at download or trial means a failed update can strand the device unable
to boot the only image it has. Decide explicitly whether the counter tracks
security version (recommended — allows benign downgrades within a security
epoch) or full firmware version.
