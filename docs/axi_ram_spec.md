# AXI RAM Slave Specification

## 1. Purpose

`axi_ram` is a synthesizable AXI4 memory-mapped slave that stores AXI write data in an internal word-addressed memory and returns stored data for AXI read bursts.

The implementation supports:

- AXI4 write address, write data, and write response channels
- AXI4 read address and read data channels
- Byte write strobes
- Configurable data width, address width, ID width, and optional read-output pipelining
- One active write burst and one active read burst at a time

The module does not expose a CPU register interface. The complete externally visible interface is the AXI4 slave port list described below.

## 2. Module

```verilog
axi_ram #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .STRB_WIDTH(DATA_WIDTH/8),
    .ID_WIDTH(ID_WIDTH),
    .PIPELINE_OUTPUT(PIPELINE_OUTPUT)
) instance_name (
    .clk(clk),
    .rst(rst),
    // AXI4 write channels
    ...
    // AXI4 read channels
    ...
);
```

Reset is synchronous and active high. All handshake and response outputs are registered.

## 3. Parameters

| Parameter | Default | Meaning |
|---|---:|---|
| `DATA_WIDTH` | `32` | AXI data width in bits. Must be divisible by 8. |
| `ADDR_WIDTH` | `16` | AXI address width in bits. |
| `STRB_WIDTH` | `DATA_WIDTH/8` | Number of byte lanes in `WDATA` and `WSTRB`. Normally derived from `DATA_WIDTH`. |
| `ID_WIDTH` | `8` | Width of AXI transaction IDs. |
| `PIPELINE_OUTPUT` | `0` | When `1`, inserts a registered pipeline stage on the read data outputs. |

The RTL checks that the data width is divisible by the strobe width and that the strobe width is a power of two.

The memory depth is:

```text
2 ** (ADDR_WIDTH - clog2(STRB_WIDTH)) words
```

For the default configuration (`DATA_WIDTH=32`, `ADDR_WIDTH=16`, `STRB_WIDTH=4`), the memory contains `16384` 32-bit words and covers `64 KiB` of byte address space.

## 4. AXI port groups

### 4.1 Clock and reset

| Port | Direction | Width | Description |
|---|---|---:|---|
| `clk` | input | 1 | Rising-edge clock. |
| `rst` | input | 1 | Synchronous active-high reset. During reset, the read and write FSMs return to idle and outstanding response valid signals are cleared. |

### 4.2 Write address channel

| Port | Direction | Width | Description |
|---|---|---:|---|
| `s_axi_awid` | input | `ID_WIDTH` | ID returned on `BID`. |
| `s_axi_awaddr` | input | `ADDR_WIDTH` | Start byte address. |
| `s_axi_awlen` | input | 8 | Burst length minus one. A value of `0` means one beat. |
| `s_axi_awsize` | input | 3 | Requested bytes-per-beat encoded as `2**AWSIZE`. |
| `s_axi_awburst` | input | 2 | Burst type: `00` FIXED, nonzero values increment the address in this implementation. |
| `s_axi_awvalid` | input | 1 | Address valid. Held by the master until `AWREADY`. |
| `s_axi_awready` | output | 1 | Address accepted when high together with `AWVALID`. |

The write address is accepted only while the write FSM is idle. After acceptance, the module deasserts `AWREADY` and accepts write data.

### 4.3 Write data channel

| Port | Direction | Width | Description |
|---|---|---:|---|
| `s_axi_wdata` | input | `DATA_WIDTH` | Write payload. |
| `s_axi_wstrb` | input | `STRB_WIDTH` | One write-enable bit per byte lane. A zero bit leaves that byte unchanged. |
| `s_axi_wlast` | input | 1 | AXI last-beat indication. The current RTL does not validate this signal against `AWLEN`. |
| `s_axi_wvalid` | input | 1 | Data valid. Held by the master until `WREADY`. |
| `s_axi_wready` | output | 1 | Data accepted when high together with `WVALID`. |

For each accepted beat, enabled byte lanes are written to the memory word selected by the current address. The internal beat counter, initialized from `AWLEN`, determines when the write burst completes.

### 4.4 Write response channel

| Port | Direction | Width | Description |
|---|---|---:|---|
| `s_axi_bid` | output | `ID_WIDTH` | ID captured from the accepted write address. |
| `s_axi_bresp` | output | 2 | Always `2'b00` (`OKAY`) in the current RTL. |
| `s_axi_bvalid` | output | 1 | Write response valid. Held until `BREADY`. |
| `s_axi_bready` | input | 1 | Response accepted when high together with `BVALID`. |

A response is generated after the beat count reaches the final beat. The implementation does not generate write errors and does not check `WLAST`.

### 4.5 Read address channel

| Port | Direction | Width | Description |
|---|---|---:|---|
| `s_axi_arid` | input | `ID_WIDTH` | ID copied to every beat of the read response. |
| `s_axi_araddr` | input | `ADDR_WIDTH` | Start byte address. |
| `s_axi_arlen` | input | 8 | Burst length minus one. A value of `0` means one beat. |
| `s_axi_arsize` | input | 3 | Requested bytes-per-beat encoded as `2**ARSIZE`. |
| `s_axi_arburst` | input | 2 | Burst type: `00` FIXED, nonzero values increment the address in this implementation. |
| `s_axi_arvalid` | input | 1 | Address valid. Held by the master until `ARREADY`. |
| `s_axi_arready` | output | 1 | Address accepted when high together with `ARVALID`. |

The read address is accepted only while the read FSM is idle. The module then generates one response beat at a time, applying backpressure through `RVALID` and `RREADY`.

### 4.6 Read data channel

| Port | Direction | Width | Description |
|---|---|---:|---|
| `s_axi_rid` | output | `ID_WIDTH` | Captured `ARID`. |
| `s_axi_rdata` | output | `DATA_WIDTH` | Memory word selected by the current read address. |
| `s_axi_rresp` | output | 2 | Always `2'b00` (`OKAY`) in the current RTL. |
| `s_axi_rlast` | output | 1 | Asserted on the final beat determined by `ARLEN`. |
| `s_axi_rvalid` | output | 1 | Read data valid. Held until `RREADY`. |
| `s_axi_rready` | input | 1 | Read data accepted when high together with `RVALID`. |

The memory read is initiated only when the current response register can accept a new beat. The output data and sideband signals remain stable while a response is stalled.

## 5. Addressing and byte lanes

The memory is indexed by the AXI byte address with the low byte-lane address bits removed:

```text
memory_word_index = byte_address >> clog2(STRB_WIDTH)
```

For the default 32-bit configuration:

```text
address 0x0000 -> memory word 0
address 0x0004 -> memory word 1
address 0x0008 -> memory word 2
```

`WSTRB[0]` controls the least-significant byte of `WDATA`, `WSTRB[1]` the next byte, and so on.

Addresses that are not aligned to the configured data-word size are accepted by the current RTL but still select a complete memory word. Narrow-transfer lane placement is not implemented.

## 6. Burst behavior implemented by the RTL

- `AWLEN` and `ARLEN` are interpreted as beat count minus one.
- FIXED bursts (`AxBURST=2'b00`) keep the same memory address for every beat.
- Any non-FIXED burst increments the address by `2**AxSIZE` bytes per accepted beat.
- The implementation does not calculate AXI WRAP boundaries.
- `AxSIZE` is clamped to the native memory word size when it is larger than the supported size or narrower than the configured word size.
- There is no explicit 4-KB boundary check.
- Only one write burst and one read burst can be active in each channel at a time.
- Read and write channels have independent FSMs and may operate concurrently, subject to the implementation target's RAM inference behavior.

## 7. Reset behavior

`rst` is sampled on the rising edge of `clk`.

When reset is asserted:

- The read FSM returns to `READ_STATE_IDLE`.
- The write FSM returns to `WRITE_STATE_IDLE`.
- `ARREADY`, `AWREADY`, `RVALID`, `BVALID`, and related registered state are cleared.
- The memory contents are not reset by `rst`.

The memory is initialized to zero by an `initial` block. Whether this initialization is synthesizable and maps to FPGA block RAM depends on the target tool and device.

## 8. Important limitations and integration requirements

The current RTL should be treated as a constrained AXI RAM model rather than a complete AXI4-compliant slave.

1. `BRESP` and `RRESP` are always `OKAY`.
2. `WLAST` is not checked against the programmed burst length.
3. WRAP bursts are not implemented correctly.
4. Narrow transfers and transfers larger than the native data width are not correctly supported; `AxSIZE` is clamped.
5. There is no explicit address or burst legality checking.
6. The design does not support multiple outstanding transactions per channel.
7. Read and write accesses to the same memory word in the same clock cycle have target-dependent behavior when inferred as a true dual-port RAM.
8. Reset does not clear memory contents.
9. The implementation does not expose ECC, byte-address error reporting, protection attributes, or timeout handling.

An integrating system should issue aligned, native-width, INCR or FIXED bursts only, keep each burst within the intended address range, and use `AxLEN` as the authoritative beat count.

## 9. Recommended conformance work before release

Before using this module as standalone production IP, add:

- Explicit support or rejection for each AXI burst type.
- Validation of `AxSIZE`, alignment, `WLAST`, and burst boundaries.
- Proper `SLVERR`/`DECERR` generation for invalid accesses.
- Assertions for `VALID` stability, response stability, and final-beat timing.
- Directed tests for backpressure, one-beat bursts, maximum bursts, partial strobes, reset, and simultaneous read/write access.
- A synthesis check for each intended FPGA or ASIC target.
