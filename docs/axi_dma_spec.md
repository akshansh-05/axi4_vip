# Functional Specification: AXI4 DMA Engine (`axi_dma`)

**Document Version:** 1.0  
**Target RTL Modules:**  
- `axi_dma.v` (Top-level DMA Controller)
- `axi_dma_rd.v` (Memory-Mapped to Stream Read Engine - MM2S)
- `axi_dma_wr.v` (Stream to Memory-Mapped Write Engine - S2MM)

> **Note & Provenance:**  
> The base RTL design modules in this project have been sourced and adapted from **Alex Forencich's** widely used open-source **[alexforencich/verilog-axi](https://github.com/alexforencich/verilog-axi)** library.

---

## 1. System Overview & Architecture

The `axi_dma` module is a high-performance, full-duplex Direct Memory Access (DMA) engine designed to bridge **AXI4 Memory-Mapped (MM)** interconnects and **AXI4-Stream (AXIS)** endpoints.

It contains two independent, concurrently operating processing engines:
1. **MM2S Read Engine (`axi_dma_rd`):** Fetches data from AXI4 memory via Read Address (`AR`) and Read Data (`R`) channels and transmits it as an AXI-Stream (`m_axis_read_data_*`).
2. **S2MM Write Engine (`axi_dma_wr`):** Receives incoming data from an AXI-Stream (`s_axis_write_data_*`) and writes it into AXI4 memory via Write Address (`AW`), Write Data (`W`), and Write Response (`B`) channels.

### Block Diagram

```
                 ┌────────────────────────────────────────────────────────┐
                 │                        axi_dma                         │
                 │                                                        │
[Read Desc] ───> │ ┌──────────────┐                  ┌──────────────────┐ │
                 │ │ axi_dma_rd   │ ── AR Channel ─> │                  │ │
[Read Stream]<── │ │ (MM2S Engine)│ <── R Channel ── │                  │ │
                 │ │              │                  │                  │ │
[Read Status]<── │ └──────────────┘                  │     AXI4 Bus     │ │ ====> [ AXI4 Slave / RAM ]
                 │                                   │   Interconnect   │ │ <====
[Write Desc]───> │ ┌──────────────┐                  │                  │ │
                 │ │ axi_dma_wr   │ ── AW Channel ─> │                  │ │
[Write Stream]─> │ │ (S2MM Engine)│ ── W Channel ──> │                  │ │
                 │ │              │ <── B Channel ── └──────────────────┘ │
[Write Status]<─ │ └──────────────┘                                       │
                 └────────────────────────────────────────────────────────┘
```

---

## 2. Parameter Definitions & Configuration

| Parameter | Default | Valid Range | Description |
| :--- | :---: | :---: | :--- |
| `AXI_DATA_WIDTH` | `32` | `32, 64, 128, 256, 512, 1024` | Width of the AXI4 data bus in bits. Must be an even power of 2. |
| `AXI_ADDR_WIDTH` | `16` | `12` to `64` | Width of the AXI4 address bus in bits. |
| `AXI_STRB_WIDTH` | `AXI_DATA_WIDTH/8`| Computed | Number of byte strobe lanes (1 bit per byte). |
| `AXI_ID_WIDTH` | `8` | `1` to `32` | Width of AXI transaction ID signals (`AWID`, `BID`, `ARID`, `RID`). |
| `AXI_MAX_BURST_LEN` | `16` | `1` to `256` | Maximum burst length (in beats) generated per AXI transfer. |
| `AXIS_DATA_WIDTH` | `AXI_DATA_WIDTH` | Equal to `AXI_DATA_WIDTH` | Width of AXI-Stream data payload. |
| `AXIS_KEEP_ENABLE`| `(DATA_WIDTH>8)`| `0, 1` | Enables byte qualification (`TKEEP`) on stream interfaces. |
| `AXIS_KEEP_WIDTH` | `DATA_WIDTH/8`| Computed | Width of `TKEEP` signal in bits. |
| `AXIS_LAST_ENABLE`| `1` | `0, 1` | Enables frame boundary (`TLAST`) generation on stream interfaces. |
| `AXIS_ID_ENABLE` | `0` | `0, 1` | Enables propagation of stream `TID`. |
| `AXIS_ID_WIDTH` | `8` | `1` to `32` | Width of stream `TID`. |
| `AXIS_DEST_ENABLE`| `0` | `0, 1` | Enables propagation of stream routing `TDEST`. |
| `AXIS_DEST_WIDTH`| `8` | `1` to `32` | Width of stream `TDEST`. |
| `AXIS_USER_ENABLE`| `1` | `0, 1` | Enables propagation of user sideband `TUSER`. |
| `AXIS_USER_WIDTH`| `1` | `1` to `32` | Width of stream `TUSER`. |
| `LEN_WIDTH` | `20` | `8` to `32` | Width of descriptor byte length field (Transfers up to $2^{\text{LEN\_WIDTH}}-1$ bytes). |
| `TAG_WIDTH` | `8` | `1` to `16` | Width of descriptor transaction tracking tag. |
| `ENABLE_SG` | `0` | `0, 1` | **Scatter-Gather:** Allows multiple descriptors per AXI stream frame (suppresses intermediate `TLAST`). |
| `ENABLE_UNALIGNED`| `0` | `0, 1` | **Unaligned Transfers:** Enables non-word-aligned byte addressing and byte realignments. |

---

## 3. Port List & Signal Descriptions

### 3.1 Global Clock and Reset
| Signal Name | Dir | Width | Description |
| :--- | :---: | :---: | :--- |
| `clk` | Input | 1 | System clock. All interfaces operate synchronously on the rising edge. |
| `rst` | Input | 1 | Synchronous active-high reset. Clears all handshakes, pointers, and returns FSMs to `IDLE`. |

---

### 3.2 Read Descriptor Interface (Host $\to$ DMA)
| Signal Name | Dir | Width | Description |
| :--- | :---: | :---: | :--- |
| `s_axis_read_desc_addr` | Input | `AXI_ADDR_WIDTH` | Source byte address in AXI memory space. |
| `s_axis_read_desc_len` | Input | `LEN_WIDTH` | Total number of bytes to transfer. |
| `s_axis_read_desc_tag` | Input | `TAG_WIDTH` | Identifier tag returned in status output upon completion. |
| `s_axis_read_desc_id` | Input | `AXIS_ID_WIDTH` | `TID` value to attach to outgoing stream packets. |
| `s_axis_read_desc_dest` | Input | `AXIS_DEST_WIDTH`| `TDEST` value to attach to outgoing stream packets. |
| `s_axis_read_desc_user` | Input | `AXIS_USER_WIDTH`| `TUSER` value to attach to outgoing stream packets. |
| `s_axis_read_desc_valid`| Input | 1 | Indicates a valid read descriptor is presented. |
| `s_axis_read_desc_ready`| Output| 1 | Indicates the DMA read engine is ready to accept the descriptor. |

---

### 3.3 Read Descriptor Status Interface (DMA $\to$ Host)
| Signal Name | Dir | Width | Description |
| :--- | :---: | :---: | :--- |
| `m_axis_read_desc_status_tag` | Output | `TAG_WIDTH` | Tag matching the completed read descriptor. |
| `m_axis_read_desc_status_error`| Output | 4 | Status/error code (`0=OKAY`, `4=SLVERR`, `5=DECERR`). |
| `m_axis_read_desc_status_valid`| Output | 1 | Pulsed high for 1 cycle when status is valid. |

---

### 3.4 AXI-Stream Read Data Interface (DMA $\to$ Sink)
| Signal Name | Dir | Width | Description |
| :--- | :---: | :---: | :--- |
| `m_axis_read_data_tdata` | Output | `AXIS_DATA_WIDTH` | Transmitted data payload. |
| `m_axis_read_data_tkeep` | Output | `AXIS_KEEP_WIDTH` | Byte qualifiers indicating valid byte lanes. |
| `m_axis_read_data_tvalid`| Output | 1 | Indicates valid stream data is presented. |
| `m_axis_read_data_tready`| Input | 1 | Downstream sink ready to consume data. |
| `m_axis_read_data_tlast` | Output | 1 | Asserted on the last beat of a packet frame. |
| `m_axis_read_data_tid` | Output | `AXIS_ID_WIDTH` | Stream ID copied from descriptor. |
| `m_axis_read_data_tdest` | Output | `AXIS_DEST_WIDTH`| Stream Destination copied from descriptor. |
| `m_axis_read_data_tuser` | Output | `AXIS_USER_WIDTH`| Stream User sideband copied from descriptor. |

---

### 3.5 Write Descriptor Interface (Host $\to$ DMA)
| Signal Name | Dir | Width | Description |
| :--- | :---: | :---: | :--- |
| `s_axis_write_desc_addr` | Input | `AXI_ADDR_WIDTH` | Destination byte address in AXI memory space. |
| `s_axis_write_desc_len` | Input | `LEN_WIDTH` | Maximum expected transfer length in bytes. |
| `s_axis_write_desc_tag` | Input | `TAG_WIDTH` | Identifier tag returned in status output upon completion. |
| `s_axis_write_desc_valid`| Input | 1 | Indicates a valid write descriptor is presented. |
| `s_axis_write_desc_ready`| Output| 1 | Indicates DMA write engine is ready to accept the descriptor. |

---

### 3.6 Write Descriptor Status Interface (DMA $\to$ Host)
| Signal Name | Dir | Width | Description |
| :--- | :---: | :---: | :--- |
| `m_axis_write_desc_status_len` | Output | `LEN_WIDTH` | Actual number of bytes written to memory. |
| `m_axis_write_desc_status_tag` | Output | `TAG_WIDTH` | Tag matching the completed write descriptor. |
| `m_axis_write_desc_status_id` | Output | `AXIS_ID_WIDTH` | `TID` captured from incoming stream packet. |
| `m_axis_write_desc_status_dest`| Output | `AXIS_DEST_WIDTH`| `TDEST` captured from incoming stream packet. |
| `m_axis_write_desc_status_user`| Output | `AXIS_USER_WIDTH`| `TUSER` captured from incoming stream packet. |
| `m_axis_write_desc_status_error`| Output| 4 | Status/error code (`0=OKAY`, `6=SLVERR`, `7=DECERR`). |
| `m_axis_write_desc_status_valid`| Output| 1 | Pulsed high for 1 cycle when status is valid. |

---

### 3.7 AXI-Stream Write Data Interface (Source $\to$ DMA)
| Signal Name | Dir | Width | Description |
| :--- | :---: | :---: | :--- |
| `s_axis_write_data_tdata` | Input | `AXIS_DATA_WIDTH` | Incoming data payload. |
| `s_axis_write_data_tkeep` | Input | `AXIS_KEEP_WIDTH` | Incoming byte valid qualifiers. |
| `s_axis_write_data_tvalid`| Input | 1 | Stream data valid. |
| `s_axis_write_data_tready`| Output| 1 | DMA ready to accept stream data. |
| `s_axis_write_data_tlast` | Input | 1 | Asserted by source on the final beat of a frame. |
| `s_axis_write_data_tid` | Input | `AXIS_ID_WIDTH` | Incoming Stream ID. |
| `s_axis_write_data_tdest` | Input | `AXIS_DEST_WIDTH`| Incoming Stream Destination. |
| `s_axis_write_data_tuser` | Input | `AXIS_USER_WIDTH`| Incoming Stream User sideband. |

---

### 3.8 AXI4 Master Interface (`m_axi_*`)

#### Write Address Channel (AW)
| Port | Dir | Width | Description |
| :--- | :---: | :---: | :--- |
| `m_axi_awid` | Output | `AXI_ID_WIDTH` | Write transaction ID tag. |
| `m_axi_awaddr` | Output | `AXI_ADDR_WIDTH` | Write start address. |
| `m_axi_awlen` | Output | 8 | Burst length (number of beats - 1). |
| `m_axi_awsize` | Output | 3 | Burst size ($\log_2(\text{AXI\_DATA\_WIDTH}/8)$ bytes per beat). |
| `m_axi_awburst`| Output | 2 | Burst type (`2'b01` `INCR`). |
| `m_axi_awvalid`| Output | 1 | Write address valid. |
| `m_axi_awready`| Input | 1 | Slave ready to accept write address. |

#### Write Data Channel (W)
| Port | Dir | Width | Description |
| :--- | :---: | :---: | :--- |
| `m_axi_wdata` | Output | `AXI_DATA_WIDTH` | Write data bus. |
| `m_axi_wstrb` | Output | `AXI_STRB_WIDTH` | Write byte strobes (1 bit per byte). |
| `m_axi_wlast` | Output | 1 | Asserted on final beat of write burst. |
| `m_axi_wvalid`| Output | 1 | Write data valid. |
| `m_axi_wready`| Input | 1 | Slave ready to accept write data. |

#### Write Response Channel (B)
| Port | Dir | Width | Description |
| :--- | :---: | :---: | :--- |
| `m_axi_bid` | Input | `AXI_ID_WIDTH` | Response transaction ID. |
| `m_axi_bresp` | Input | 2 | Response status (`00` OKAY, `10` SLVERR, `11` DECERR). |
| `m_axi_bvalid`| Input | 1 | Write response valid. |
| `m_axi_bready`| Output | 1 | Master ready to accept write response. |

#### Read Address Channel (AR)
| Port | Dir | Width | Description |
| :--- | :---: | :---: | :--- |
| `m_axi_arid` | Output | `AXI_ID_WIDTH` | Read transaction ID tag. |
| `m_axi_araddr` | Output | `AXI_ADDR_WIDTH` | Read start address. |
| `m_axi_arlen` | Output | 8 | Burst length (number of beats - 1). |
| `m_axi_arsize` | Output | 3 | Burst size ($\log_2(\text{AXI\_DATA\_WIDTH}/8)$ bytes per beat). |
| `m_axi_arburst`| Output | 2 | Burst type (`2'b01` `INCR`). |
| `m_axi_arvalid`| Output | 1 | Read address valid. |
| `m_axi_arready`| Input | 1 | Slave ready to accept read address. |

#### Read Data Channel (R)
| Port | Dir | Width | Description |
| :--- | :---: | :---: | :--- |
| `m_axi_rid` | Input | `AXI_ID_WIDTH` | Read response ID tag. |
| `m_axi_rdata` | Input | `AXI_DATA_WIDTH` | Read data bus. |
| `m_axi_rresp` | Input | 2 | Read response status (`00` OKAY, `10` SLVERR, `11` DECERR). |
| `m_axi_rlast` | Input | 1 | Asserted on final beat of read burst. |
| `m_axi_rvalid`| Input | 1 | Read data valid. |
| `m_axi_rready`| Output | 1 | Master ready to accept read data. |

---

### 3.9 Control & Configuration Ports
| Signal Name | Dir | Width | Description |
| :--- | :---: | :---: | :--- |
| `read_enable` | Input | 1 | Master enable for Read DMA engine. When `0`, descriptor processing halts. |
| `write_enable`| Input | 1 | Master enable for Write DMA engine. When `0`, descriptor processing halts. |
| `write_abort` | Input | 1 | Immediately aborts the current write operation and drains incoming stream data. |

---

## 4. Theory of Operation & Protocols

### 4.1 Read DMA Engine (MM2S: Memory-to-Stream)
1. **Descriptor Queueing:** Descriptors are accepted when `read_enable = 1` and pushed into an internal command FIFO.
2. **Burst Segmentation & 4KB Splitting:**
   * Transfers larger than `AXI_MAX_BURST_LEN` beats are split into multiple sequential `INCR` bursts.
   * **4KB Boundary Check:** Bursts approaching page boundary `0xX000` are split so that no burst crosses `0xFFF`.
3. **Data Repacking & Stream Generation:**
   * Read beats from `m_axi_rdata` are buffered in an asynchronous/synchronous FIFO.
   * Unaligned offsets (`ENABLE_UNALIGNED=1`) are shifted to align with stream word boundaries.
   * `m_axis_read_data_tlast` is generated on the exact byte count specified by `s_axis_read_desc_len`.
4. **Status Reporting:** Upon receiving the final read beat, `m_axis_read_desc_status_*` pulses valid with the matching tag and error code.

### 4.2 Write DMA Engine (S2MM: Stream-to-Memory)
1. **Descriptor Queueing:** Accepts target start address `s_axis_write_desc_addr` and maximum buffer `s_axis_write_desc_len`.
2. **Stream Buffering & Write Burst Generation:**
   * Stream data is accepted on `s_axis_write_data_*`.
   * DMA issues `m_axi_awvalid` with calculated burst length.
   * Drives `m_axi_wdata` with appropriate byte strobes (`m_axi_wstrb`).
   * Sets `m_axi_wlast = 1` on the final beat of each burst.
3. **Packet Completion Scenarios:**
   * **Normal Packet End:** `s_axis_write_data_tlast` received $\to$ terminates write burst and reports actual transferred byte count.
   * **Buffer Exhaustion:** If data exceeds descriptor `len`, DMA commits `len` bytes, then enters `STATE_DROP_DATA` to discard remaining packet beats until `tlast`.
   * **Abort:** If `write_abort = 1`, current burst is aborted, and stream is drained.
4. **Response Synchronization:** Emits status valid only after receiving `BVALID` for all generated write bursts.

---

## 5. Protocol Error Code Matrix

| Error Code (`3:0`) | Symbolic Name | Meaning |
| :---: | :--- | :--- |
| `4'd0` | `DMA_ERROR_NONE` | Transfer completed successfully with `OKAY` response. |
| `4'd1` | `DMA_ERROR_TIMEOUT` | Timeout occurred waiting for channel handshake. |
| `4'd2` | `DMA_ERROR_PARITY` | Parity error detected on data payload. |
| `4'd4` | `DMA_ERROR_AXI_RD_SLVERR`| AXI Slave returned `SLVERR` (`2'b10`) on Read data (`RRESP`). |
| `4'd5` | `DMA_ERROR_AXI_RD_DECERR`| AXI Interconnect returned `DECERR` (`2'b11`) on Read data (`RRESP`). |
| `4'd6` | `DMA_ERROR_AXI_WR_SLVERR`| AXI Slave returned `SLVERR` (`2'b10`) on Write response (`BRESP`). |
| `4'd7` | `DMA_ERROR_AXI_WR_DECERR`| AXI Interconnect returned `DECERR` (`2'b11`) on Write response (`BRESP`). |
| `4'd8` | `DMA_ERROR_PCIE_FLR` | PCIe Function Level Reset triggered. |

---

## 6. Critical Boundary & Verification Constraints

1. **4KB Address Boundary:** `(AxADDR[11:0] + (AxLEN + 1) * (1 << AxSIZE)) <= 4096`.
2. **Ready/Valid Handshake Stability:** Once `VALID` is asserted, payload signals must remain stable until `READY` is high.
3. **Write Response Tracking:** Status output must not be asserted until all outstanding write bursts receive `BVALID`.
