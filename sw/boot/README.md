# Boot ROM code (D2)

The ROM image the hardware `boot_rom` loads. Responsibilities, in order:

1. Initialize the SHA-256 accelerator, hash the application image block by block.
2. Ed25519-verify the image signature against the public key in `key_store`
   (signature math in software; the hash came from hardware — the honest
   hardware/software partition).
3. Extend `measure_chain` with each stage measurement (measured boot).
4. On success, jump to the application. On failure, raise the tamper flag and
   halt — no fallback, no degraded mode.

## Status

**Not yet written.** `boot.hex` is a placeholder so `boot_rom` elaborates. The
Ed25519 verify routine and the Ibex build (linker script, startup, `boot.hex`
generation) are the remaining D2 software work. Until then `rot_top` reports
`boot_ok = 0` honestly.
