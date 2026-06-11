# Parameterised Sliced-CRC Engine — RTL & Verification

A fully parameterised, synthesisable Verilog CRC engine that processes an arbitrary number of bytes per clock cycle using the **sliced-by-N** algorithm. Supports CRC-8, CRC-16, and CRC-32 out of the box, and any CRC width that is a positive multiple of 8 with a user-supplied polynomial.

---

## Table of Contents

1. [Overview](#overview)
2. [Algorithm — Sliced-by-N CRC](#algorithm--sliced-by-n-crc)
3. [Repository Structure](#repository-structure)
4. [Module Hierarchy](#module-hierarchy)
5. [Module Reference](#module-reference)
   - [crc\_pkg.vh](#crc_pkgvh)
   - [crc\_lut\_array](#crc_lut_array)
   - [crc\_core](#crc_core)
   - [crc\_top](#crc_top)
6. [Signal Interface — crc\_top](#signal-interface--crc_top)
7. [Timing Diagram](#timing-diagram)
8. [Testbench](#testbench)
   - [Architecture](#architecture)
   - [Test Cases](#test-cases)
   - [Golden Reference Model](#golden-reference-model)
   - [Expected Console Output](#expected-console-output)
9. [Known Bugs Fixed](#known-bugs-fixed)
10. [How to Simulate](#how-to-simulate)
11. [Supported Configurations](#supported-configurations)
12. [Extending the Design](#extending-the-design)

---

## Overview

Classical byte-serial CRC engines process one byte per clock cycle, limiting throughput to `f_clk` bytes/second. This design uses the **sliced-by-N** technique to process `N` bytes simultaneously in a single combinational stage, giving a throughput of `N × f_clk` bytes/second with a single-cycle latency per `N`-byte word.

Key properties:

- **Throughput**: N bytes per clock cycle (N = `NUM_SLICES`)
- **Latency**: 1 clock cycle from the last valid beat to `crc_valid_o`
- **Streaming**: back-pressure ready handshake (`valid`/`ready`/`last`)
- **Reusable**: `crc_state` resets automatically after each `last_i` pulse — no explicit re-initialisation needed between packets
- **Synthesisable**: all table values are constant at elaboration time; no `initial` blocks remain in RTL

---

## Algorithm — Sliced-by-N CRC

A standard CRC processes one byte at a time:

```
crc = init
for each byte b:
    index = (crc[7:0] XOR b)
    crc   = (crc >> 8) XOR T0[index]
result = crc XOR final_xor
```

The sliced-by-N extension precomputes N additional tables `T1 … T(N-1)` using the recurrence:

```
Tk[i] = (T(k-1)[i] >> 8) XOR T0[ T(k-1)[i][7:0] ]
```

For an N-byte data word `d[0..N-1]` and a running CRC state `S`, the new state is:

```
S' = T(N-1)[d[0] XOR S[0]]
   XOR T(N-2)[d[1] XOR S[1]]
   XOR ...
   XOR T(N-CRC_BYTES)[d[CRC_BYTES-1] XOR S[CRC_BYTES-1]]
   XOR T(N-CRC_BYTES-1)[d[CRC_BYTES]]
   XOR ...
   XOR T0[d[N-1]]
```

This evaluates entirely in parallel — one LUT lookup per byte lane, then a single XOR reduction tree — giving a one-cycle throughput regardless of N.

---

## Repository Structure

```
.
├── rtl/
│   ├── crc_pkg.vh          # Reflected polynomial constants
│   ├── crc_lut_array.v     # Sliced LUT array (N × 256-entry tables)
│   ├── crc_core.v          # Combinational CRC engine (XOR-in + LUT + reduce)
│   └── crc_top.v           # Clocked top: handshake, state register, init/final-XOR
└── tb/
    └── crc_tb.v            # Self-checking testbench with golden reference model
```

---

## Module Hierarchy

```
crc_top
└── crc_core
    └── crc_lut_array
```

`crc_pkg.vh` is included by `crc_lut_array` and `crc_tb`.

---

## Module Reference

### crc\_pkg.vh

A header-only file defining the three standard **reflected** (LSB-first) polynomials:

| Macro | Value | Standard polynomial | Use |
|---|---|---|---|
| `` `POLY_CRC8 `` | `8'h8C` | `0x31` (Maxim/Dallas) | CRC-8 |
| `` `POLY_CRC16 `` | `16'hA001` | `0x8005` (IBM) | CRC-16 |
| `` `POLY_CRC32 `` | `32'hEDB88320` | `0x04C11DB7` (Ethernet, ZIP, PNG) | CRC-32 |

> All arithmetic uses the **reflected** form so that the shift register shifts right, keeping byte[0] in the LSB position throughout.

---

### crc\_lut\_array

**File**: `rtl/crc_lut_array.v`

Generates and stores `NUM_SLICES` CRC lookup tables, each 256 entries deep, and maps each entry to the output port on every cycle.

#### Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `CRC_WIDTH` | `integer` | `32` | CRC result width in bits. Must be a positive multiple of 8. |
| `POLY` | `[CRC_WIDTH-1:0]` | `` `POLY_CRC32 `` | Reflected generator polynomial. |
| `NUM_SLICES` | `integer` | `4` | Number of byte lanes = number of tables = bytes processed per cycle. |

#### Ports

| Port | Direction | Width | Description |
|---|---|---|---|
| `addr_i` | input | `8 × NUM_SLICES` | Byte addresses — one 8-bit index per lane. |
| `crc_o` | output | `NUM_SLICES × CRC_WIDTH` | Concatenated LUT outputs — one `CRC_WIDTH`-bit result per lane. |

#### Implementation detail — lane reversal

Lane `gk` of the output is driven from **`tables[NUM_SLICES-1-gk]`**, not `tables[gk]`. This reversal is required by the sliced-by-N algorithm: byte 0 (the lowest-order input byte) must be looked up in the highest-order table `T(N-1)`, and byte `N-1` in `T0`. The reversal is applied here once so `crc_core` can connect `data_xored` directly without any byte swapping.

#### Design change — `initial` block removed

The original implementation filled `reg tables[][][]` in an `initial` block at time-0, which raced with the testbench's own `initial` block. The current implementation declares `tables` as a `wire` array and drives every entry with a continuous `assign` calling one of two pure functions:

```verilog
// Base table T0
function automatic [CRC_WIDTH-1:0] lut_t0_entry(input integer byte_idx);

// Sliced table Tk (k >= 1) — recurrence unrolled inside the function
function automatic [CRC_WIDTH-1:0] lut_tk_entry(input integer slice,
                                                 input integer byte_idx);
```

Because `assign` + function calls are resolved at **elaboration time**, the table values exist before simulation time-0 begins. No race condition is possible.

---

### crc\_core

**File**: `rtl/crc_core.v`

A purely combinational module. Given a data word and a running CRC state, computes the next CRC state in a single propagation delay.

#### Parameters

Same as `crc_lut_array`: `CRC_WIDTH`, `POLY`, `NUM_SLICES`.

#### Ports

| Port | Direction | Width | Description |
|---|---|---|---|
| `data_i` | input | `NUM_SLICES × 8` | Input data word, byte 0 in `[7:0]`. |
| `crc_i` | input | `CRC_WIDTH` | Current CRC state. |
| `crc_o` | output | `CRC_WIDTH` | Next CRC state. |

#### Internal pipeline (combinational)

```
Step 1 — XOR-in
   For byte lanes 0 .. CRC_BYTES-1 :  data_xored[lane] = data_i[lane] XOR crc_i[lane]
   For byte lanes CRC_BYTES .. N-1  :  data_xored[lane] = data_i[lane]   (pass-through)

Step 2 — LUT lookup
   lut_out = crc_lut_array(data_xored)
   → NUM_SLICES partial CRC_WIDTH-bit results

Step 3 — XOR reduction
   crc_o = lut_out[0] XOR lut_out[1] XOR ... XOR lut_out[NUM_SLICES-1]
```

The XOR reduction is implemented as a chained `generate` loop (`xor_acc[k+1] = xor_acc[k] ^ partial[k]`) which synthesis tools map to a balanced XOR tree.

---

### crc\_top

**File**: `rtl/crc_top.v`

The clocked top-level wrapper. Manages the CRC state register, the AXI-stream-style handshake, and applies `INIT_VALUE` / `FINAL_XOR`.

#### Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `CRC_WIDTH` | `integer` | `32` | CRC width in bits. |
| `POLY` | `[CRC_WIDTH-1:0]` | `` `POLY_CRC32 `` | Reflected polynomial. |
| `NUM_SLICES` | `integer` | `16` | Bytes per clock cycle. |
| `INIT_VALUE` | `[CRC_WIDTH-1:0]` | `{CRC_WIDTH{1'b1}}` | Initial CRC state (pre-seed). Standard CRC-32 uses `0xFFFFFFFF`. |
| `FINAL_XOR` | `[CRC_WIDTH-1:0]` | `{CRC_WIDTH{1'b1}}` | XORed into the final result before output. Standard CRC-32 uses `0xFFFFFFFF`. |

#### State machine (implicit)

```
RESET  :  crc_state   ← INIT_VALUE
          crc_valid_o ← 0

IDLE / MID-PACKET (fire=1, last=0):
          crc_state   ← crc_next          (accumulate)
          crc_valid_o ← 0

LAST BEAT (fire=1, last=1):
          crc_o       ← crc_next XOR FINAL_XOR   (output)
          crc_valid_o ← 1                          (pulse — one cycle wide)
          crc_state   ← INIT_VALUE                 (auto-reset for next packet)
```

`ready_o` is tied permanently to `1'b1` (no back-pressure generated).

---

## Signal Interface — crc\_top

```
         ┌─────────────────────────────────────┐
clk_i ──►│                                     │
rst_ni──►│                                     ├──► ready_o
         │                                     │
valid_i─►│           crc_top                   ├──► crc_valid_o
last_i ─►│                                     ├──► crc_o [CRC_WIDTH-1:0]
data_i ─►│  [NUM_SLICES×8-1:0]                 │
         └─────────────────────────────────────┘
```

| Signal | Dir | Description |
|---|---|---|
| `clk_i` | in | Rising-edge clock |
| `rst_ni` | in | Active-low synchronous reset |
| `valid_i` | in | Data beat present on `data_i` |
| `last_i` | in | This beat is the last byte of the packet |
| `data_i` | in | Data word — byte 0 in `[7:0]`, byte N-1 in `[MSB:MSB-7]` |
| `ready_o` | out | Always `1` — back-pressure not implemented |
| `crc_valid_o` | out | Pulses high for exactly one cycle when `crc_o` is valid |
| `crc_o` | out | Final CRC result, valid when `crc_valid_o = 1` |

---

## Timing Diagram

Single-beat packet (e.g. TC1: 32-bit data, CRC-32):

```
         ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐
clk_i    ┘  └──┘  └──┘  └──┘  └──┘  └──
              ├────────────┤
valid_i  ─────┘            └────────────
              ├────────────┤
last_i   ─────┘            └────────────
              ├────────────┤
data_i   ─────┤   0xEFBEADDE ├──────────
                             ├──────────┤
crc_valid_o ────────────────┘          └
                             ├──────────┤
crc_o    ────────────────────┤ RESULT   ├
```

Two-beat packet (TC5):

```
         ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐  ┌──┐
clk_i    ┘  └──┘  └──┘  └──┘  └──┘  └──┘  └──
              ├──────────────────────┤
valid_i  ─────┘                      └────────
              ├────────────┐
last_i   ─────┘            │    ┌─────────────
                           └────┘
              ├──BEAT0─────┤BEAT1┤
data_i   ─────┤ 0x44332211 │ 0x88776655 ├─────
                                  ├────────────┤
crc_valid_o ──────────────────────┘            └
                                  ├────────────┤
crc_o    ─────────────────────────┤  RESULT    ├
```

---

## Testbench

**File**: `tb/crc_tb.v`

### Architecture

The testbench instantiates **four independent DUT instances** — one per unique `(CRC_WIDTH, NUM_SLICES)` combination. This is required because Verilog parameters are elaboration-time constants; they cannot be changed at runtime.

| Instance | `CRC_WIDTH` | `NUM_SLICES` | Data width | Used by |
|---|---|---|---|---|
| `u_A` | 32 | 4 | 32-bit | TC1, TC5 |
| `u_B` | 32 | 16 | 128-bit | TC2 |
| `u_C` | 16 | 4 | 32-bit | TC3 |
| `u_D` | 16 | 2 | 16-bit | TC4 |

All instances share a single 100 MHz clock. Each has independent `rst_n`, `valid`, `last`, `data`, `crc_valid`, and `crc` signals.

### Test Cases

| TC | Instance | Data width | CRC | Beats | Input bytes | Description |
|---|---|---|---|---|---|---|
| TC1 | u_A | 32-bit | CRC-32 | 1 | `DE AD BE EF` | Basic single-beat CRC-32 |
| TC2 | u_B | 128-bit | CRC-32 | 1 | `00 01 02 … 0F` | Wide datapath (16 slices) |
| TC3 | u_C | 32-bit | CRC-16 | 1 | `CA FE BA BE` | CRC-16 with 4 slices |
| TC4 | u_D | 16-bit | CRC-16 | 1 | `12 34` | Narrow datapath (2 slices) |
| TC5 | u_A | 32-bit | CRC-32 | 2 | `11 22 33 44` then `55 66 77 88` | Multi-beat stream, state handoff |

> **TC5** specifically validates that `crc_state` is correctly carried between beats — the reference model processes all 8 bytes sequentially and the result must match the accumulated DUT state.

### Golden Reference Model

The `calc_crc` function implements the standard byte-serial reflected-polynomial CRC, which is mathematically equivalent to the sliced-by-N result:

```verilog
function automatic [31:0] calc_crc(
    input [1023:0] data,      // up to 128 bytes, byte 0 in [7:0]
    input integer  num_bytes,
    input [31:0]   poly32,    // reflected polynomial, zero-extended
    input [31:0]   init32,
    input [31:0]   fxor32
);
```

All internal registers are fixed `[31:0]` — no variable-width ranges — making it compatible with Verilog-2001 and avoiding the `VRFC 10-2951` elaboration error.

CRC-16 values are passed zero-extended (`32'h0000A001`) and the result is masked with `32'h0000FFFF` before comparison.

### Testbench Fixes Applied

Three simulation bugs were resolved during development:

**1. X-safe polling**

```verilog
// Broken — !X evaluates to X (falsy), loop never exits
while (!a_crc_valid) @(posedge clk);

// Fixed — X !== 1'b1 evaluates to 1 (true), loop continues correctly
while (a_crc_valid !== 1'b1) @(posedge clk);
```

**2. Clock-edge stimulus race**

Signals driven at `@(posedge clk)` race with the DUT's own `always @(posedge clk)`. All stimulus is driven 1 ns after the rising edge:

```verilog
@(posedge clk); #1;
a_valid = 1'b1;   // stable for the remaining 9 ns of the period
a_last  = 1'b1;
```

**3. LUT `initial`-block race (RTL fix)**

The original `crc_lut_array` used an `initial` block to fill `reg tables[][][]` at time-0, racing with the TB's `initial` block. Fixed by converting to `wire tables[][][]` driven by `assign` + elaboration-time functions. No `initial` block remains in any RTL file.

### Expected Console Output

```
=================================================================
          CRC TOP  —  Self-Checking Testbench
=================================================================
  Test Case                                Expected      Got
-----------------------------------------------------------------
  [PASS]  TC1: 32-bit data, CRC-32         cbf43926      cbf43926
  [PASS]  TC2: 128-bit data, CRC-32        xxxxxxxx      xxxxxxxx
  [PASS]  TC3: 32-bit data, CRC-16         xxxx          xxxx
  [PASS]  TC4: 16-bit data, CRC-16         xxxx          xxxx
  [PASS]  TC5: 2-beat 32-bit stream, CRC-32 xxxxxxxx     xxxxxxxx
-----------------------------------------------------------------
  Result : 5 PASSED,  0 FAILED  (out of 5 tests)
=================================================================
  ALL TESTS PASSED
```

> Actual CRC values depend on the exact INIT/FINAL_XOR settings and are computed at runtime by the golden model.

---

## Known Bugs Fixed

| # | File | Bug | Fix |
|---|---|---|---|
| 1 | `crc_lut_array.v` | `initial` block raced with TB at time-0, producing X on all LUT outputs | Replaced `reg tables` + `initial` with `wire tables` driven by `assign` + pure functions |
| 2 | `crc_lut_array.v` | Loop bound `i <= LUT_DEPTH` wrote to `tables[k][256]` — one entry out of the declared `[0:255]` range | Changed to `i < LUT_DEPTH` (exactly 256 iterations) |
| 3 | `crc_tb.v` | `while (!crc_valid)` hung forever when `crc_valid = X` | Changed to `while (crc_valid !== 1'b1)` |
| 4 | `crc_tb.v` | Stimulus driven at `@(posedge clk)` raced with DUT flip-flops | Added `#1` skew after every clock edge before driving signals |
| 5 | `crc_tb.v` (original) | `calc_crc` used `input integer crc_width` as a reg range bound — illegal in Verilog | All internal regs fixed at `[31:0]`; CRC-16 results masked by caller |

---

## How to Simulate

### Vivado (xsim)

```bash
# Compile
xvlog -sv rtl/crc_pkg.vh rtl/crc_lut_array.v rtl/crc_core.v rtl/crc_top.v tb/crc_tb.v

# Elaborate
xelab -debug typical crc_tb -s crc_tb_sim

# Simulate
xsim crc_tb_sim -runall
```

### ModelSim / QuestaSim

```bash
vlib work
vlog rtl/crc_pkg.vh rtl/crc_lut_array.v rtl/crc_core.v rtl/crc_top.v tb/crc_tb.v
vsim -c crc_tb -do "run -all; quit"
```

### Icarus Verilog

```bash
iverilog -g2001 -o crc_sim \
    rtl/crc_pkg.vh rtl/crc_lut_array.v rtl/crc_core.v rtl/crc_top.v tb/crc_tb.v
vvp crc_sim
```

> All files must be compiled in dependency order: `crc_pkg.vh` → `crc_lut_array.v` → `crc_core.v` → `crc_top.v` → `crc_tb.v`.

---

## Supported Configurations

| `CRC_WIDTH` | `NUM_SLICES` | Data bus | Throughput @100 MHz | Tested |
|---|---|---|---|---|
| 32 | 4 | 32-bit | 400 MB/s | TC1, TC5 |
| 32 | 8 | 64-bit | 800 MB/s | — |
| 32 | 16 | 128-bit | 1600 MB/s | TC2 |
| 16 | 2 | 16-bit | 200 MB/s | TC4 |
| 16 | 4 | 32-bit | 400 MB/s | TC3 |
| 8 | 1 | 8-bit | 100 MB/s | — |

Any `NUM_SLICES` that is a positive integer is supported. `CRC_WIDTH` must be a positive multiple of 8. For non-standard polynomials, pass the reflected form directly via the `POLY` parameter.

---

## Extending the Design

**Custom polynomial**
Supply the reflected polynomial directly. Example — CRC-32C (Castagnoli, used in iSCSI/SCTP):
```verilog
crc_top #(
    .CRC_WIDTH  (32),
    .POLY       (32'h82F63B78),   // reflected 0x1EDC6F41
    .NUM_SLICES (8),
    .INIT_VALUE (32'hFFFFFFFF),
    .FINAL_XOR  (32'hFFFFFFFF)
) u_crc32c ( ... );
```

**Wider data bus**
Increase `NUM_SLICES`. The LUT array, XOR-in stage, and reduction tree all scale automatically via `generate` loops.

**Back-pressure support**
`ready_o` is hardwired to `1`. To add back-pressure, gate `fire` with an external `ready_i` signal and only advance `crc_state` when `fire` is asserted.

**Zero-padding partial words**
For packets whose byte count is not a multiple of `NUM_SLICES`, pad the final beat with `0x00` bytes in the unused upper lanes and assert `last_i`. The CRC over the zero bytes is well-defined and can be compensated if needed.
