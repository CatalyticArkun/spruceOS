# `archiveUnpacker` first-boot completion gap

## Summary
First boot starts background unpacking and reboots before full unpack completion; completion spills to next boot.

## Expected behavior
First-boot unpack workflow should either complete before reboot boundary or leave explicit resumable state markers.

## Actual behavior
Unpacker logs continue through first boot; no `Finished running` appears before reboot.

## Evidence (timestamps)
- `spruce4.log` first boot:
  - `04:49:59` `Unpacker started silently in background due to first_boot flag`
  - multiple `Unpacked and removed` lines through `04:51:59`
  - reboot path begins around `04:52:08`
  - no `Unpacker: Finished running` in this session
- `spruce3.log` follow-up:
  - `04:52:38` `Unpacker: Finished running`

## Impact
Boot-to-boot state drift and startup overlap complexity increase; update/network/UI startup run concurrently with incomplete unpack work.

## Likely owning subsystem
- first boot orchestration in runtime + unpacker launcher

## Suggested next debugging step
Persist explicit unpack progress marker and gate reboot-sensitive steps when unpack queue is still active.

## Labels (suggested)
`firstboot` `archives` `startup-ordering`
