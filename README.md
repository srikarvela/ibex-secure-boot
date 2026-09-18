# Hardware Root of Trust — Secure Boot (D2)

A secure-boot / hardware root of trust in SystemVerilog, built around a RISC-V
core (lowRISC **Ibex**, the core inside OpenTitan): an immutable boot ROM at the
reset vector, a hardware **SHA-256** accelerator, a CPU-invisible **key store**,
a hardware-enforced one-way **lifecycle** FSM, and a PCR-style **measured-boot**
chain. The design partitions crypto the way real roots of trust do — hash
acceleration in silicon, signature math in ROM software — and its failure path
**refuses to boot** rather than falling back.

This is the "build the root of trust" half of a two-repo track; the sibling
[fault-injection-campaign](../fault-injection-campaign) red-teams it with
instruction-skip faults.

---

## ⚠️ What IS NOT implemented (read this first)

Leading with the limitations is deliberate — it is how this portfolio is kept
honest.

- **Not run on hardware.** No board, bitstream, pin constraints or AXI wrapper.
  "Deployment" would mean a bitstream loaded and producing output; that has not
  happened.
- **No synthesis numbers yet.** No Vivado run has been committed, so **no LUT,
  FF, Fmax, setup or hold figure is claimed anywhere in this repo.** `reports/`
  is empty. The OOC flow (`tcl/rot_synth.tcl`, `make vm-synth`) is written and
  mirrors the proven cordic-engine flow, but until it runs and the `.rpt` files
  are committed, there are no area or timing results — and setup will be
  distinguished from hold when there are.
- **Ibex not yet integrated.** `rot_top` instantiates and wires the four
  verified RoT blocks, but the CPU instance and its OBI/data-bus adaptation are
  a skeleton behind `\`ifdef IBEX_PRESENT`. See [vendor/README.md](vendor/README.md).
  Because the CPU-driven verify result is not yet real, `rot_top` reports
  `boot_ok = 0` honestly.
- **Ed25519 verify (software) not written.** The hardware/software split is
  designed — hash in the accelerator, signature check in ROM code — but the ROM
  routine and the Ibex build (`sw/boot/`) are TODO. `boot.hex` is a placeholder.
- **`sha256_accel` bus is a direct decode, not AXI/OBI.** The adaptation to
  Ibex's data port is TODO.
- **SHA-256 is characterized by known-answer vectors, not exhaustively proven.**
  17 golden vectors (both FIPS constants + padding-boundary + pseudo-random);
  drop a CAVP `.rsp` in `vectors/nist_sha256/` to widen coverage.

## What IS implemented and verified (Icarus Verilog 12)

| Block | File | Verified by | Result |
|---|---|---|---|
| SHA-256 compression core | [rtl/sha256_core.sv](rtl/sha256_core.sv) | [tb/tb_sha256.sv](tb/tb_sha256.sv) vs golden vectors | **17 / 17 bit-exact**, incl. both FIPS 180-2 published constants |
| One-way lifecycle FSM | [rtl/lifecycle_fsm.sv](rtl/lifecycle_fsm.sv) | [tb/tb_lifecycle.sv](tb/tb_lifecycle.sv), exhaustive 4×4 | **18 / 18**: every legal move taken, every illegal one rejected, state unchanged |
| CPU-invisible key store | [rtl/key_store.sv](rtl/key_store.sv) | [tb/tb_key_store.sv](tb/tb_key_store.sv) | **12 / 12**: CPU reads return 0 while crypto port holds the key; write-once; one-way lock |
| Measured-boot chain | [rtl/measure_chain.sv](rtl/measure_chain.sv) | [tb/tb_measure.sv](tb/tb_measure.sv) vs software reference | **3 / 3** PCR extends bit-exact |
| SHA-256 bus accelerator | [rtl/sha256_accel.sv](rtl/sha256_accel.sv) | elaborates; wraps the verified core | register-file wrapper |
| Boot ROM | [rtl/boot_rom.sv](rtl/boot_rom.sv) | elaborates; loads placeholder image | immutable, no write port |

Run it:

```bash
make sim          # all four self-checking block testbenches (Icarus)
make vectors      # regenerate golden vectors (python3, no MATLAB needed)
make waves T=sha  # re-run one tb dumping build/tb_sha.vcd
```

---

## Why each block is the point

| Block | Why it matters |
|---|---|
| **Boot ROM** | Immutability is the root. If it can be changed, nothing below it means anything. |
| **SHA-256 accelerator** | NIST publishes official vectors — instant bit-exact golden verification, no model to write. |
| **Key store** | A key the CPU can read is a variable, not a stored secret. The CPU-read-returns-zero assertion is the single most important one in the project. |
| **Lifecycle FSM** | Irreversibility in silicon, not firmware policy. Illegal transitions are structurally impossible — there is no code path that writes a lower state. |
| **Measurement chain** | `measure[n+1] = H(measure[n] ‖ stage)` is TPM/DICE attestation in miniature. |
| **Failure path** | Most student secure-boot projects verify and then boot anyway. The refusal is the feature. |

### The honest crypto partition

A full asymmetric verify in RTL is a large build on its own. SHA-256 is in
hardware; Ed25519 verification runs in software on Ibex against the hardware
hash. That is how real designs are partitioned — hash acceleration in silicon,
signature math in ROM code — so it is the correct answer, not a shortcut.

---

## Synthesis (planned, not yet run)

Out-of-context on `xc7z020clg400-1` (PYNQ-Z2), post-route, one block per run,
via the Parallels Windows VM (Apple Silicon can't run Vivado natively):

```bash
make vm-synth                      # default block list -> reports/<block>/*.rpt
make vm-synth BLOCKS="sha256_core key_store"
python3 scripts/ppa_table.py       # builds reports/ppa.csv from the .rpt files
```

`scripts/ppa_table.py` refuses to invent rows: with no committed `.rpt` files it
writes nothing and says so. When a run exists, area comes from
`report_utilization` ("Slice LUTs"), and setup (WNS) and hold (WHS) are reported
separately with their failing-endpoint counts — "setup met, hold not met" is not
"timing closed."

---

## Repository layout

```
rtl/          SystemVerilog RoT blocks (one module per file)
sw/boot/      ROM code (hash, Ed25519 verify, measure, jump) — TODO
tb/           self-checking Icarus testbenches (print TEST PASSED)
vectors/nist_sha256/  golden SHA-256 + measured-boot vectors + generator
tcl/ constraints/     OOC Vivado flow, mirroring cordic-engine
scripts/      Parallels-VM Vivado runner, PPA table generator
reports/      committed Vivado reports (empty until a real run)
vendor/       lowRISC Ibex submodule (see vendor/README.md)
```

## License

MIT — see [LICENSE](LICENSE).
