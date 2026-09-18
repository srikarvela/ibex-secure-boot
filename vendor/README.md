# Vendored core

D2 protects a real RISC-V core rather than a student design. Add lowRISC Ibex
as a submodule (kept untouched — not forked into your own work):

```bash
git submodule add https://github.com/lowRISC/ibex vendor/ibex
git -C vendor/ibex checkout <pinned-sha>   # pin a known-good commit
```

Ibex is the core inside OpenTitan, the flagship open-source silicon root of
trust. PicoRV32 is the lighter fallback if the Ibex build proves awkward.

`vendor/ibex/` is git-ignored as tracked content because it is a submodule.
Until it is added, `rot_top` builds only its RoT peripheral blocks; the CPU
instance is guarded by `\`ifdef IBEX_PRESENT`.
