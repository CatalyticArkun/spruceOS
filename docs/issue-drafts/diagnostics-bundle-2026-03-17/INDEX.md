# Diagnostics Bundle Issue Draft Index (2026-03-17)

Source bundle: `H:\Saves\spruce.zip` (original bundle).

| Draft | Confidence | Relationship | File now? |
| --- | --- | --- | --- |
| Audio emit lifecycle coverage gap | confirmed | parent (includes sleep/wake-only symptom) | yes |
| Brightness emit lifecycle coverage gap | confirmed | parent (includes zero-brightness-emits symptom) | yes |
| `system.json` non-atomic/invalid read-write parse storm | confirmed | parent (includes repeated parse storm symptom) | yes |
| Update checker network establishment failure | confirmed | parent; possible startup-collision follow-up | yes |
| `archiveUnpacker` first-boot completion gap | confirmed | standalone; linked to startup overlap | yes |
| PyUI state-file missing intermittency | likely | standalone or child of startup stability | yes |
| Startup overlap/race-window hardening (investigation) | unconfirmed/likely mix | umbrella follow-up for overlap, listener churn, update collision | hold/follow-up |
| Power-button cooldown duplicate-event behavior (investigation) | likely | standalone follow-up | hold/follow-up |

