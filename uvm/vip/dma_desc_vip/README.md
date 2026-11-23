# DMA Descriptor Verification IP (`dma_desc_vip`)

## 1. VIP Architectural Overview

The `dma_desc_vip` package provides a transaction-level verification component that models the host processor software driver interface for the **AMBA AXI4 Direct Memory Access (DMA) Subsystem**.

It manages the command and control plane of the DMA by injecting transfer descriptors and collecting asynchronous completion status pulses:
1. **MM2S Read Descriptor Agent (`dma_rd_desc_agent`):** Manages read descriptor command injection (`s_axis_read_desc_*`), controls global `read_enable`, and captures read completion status tokens (`m_axis_read_desc_status_*`).
2. **S2MM Write Descriptor Agent (`dma_wr_desc_agent`):** Manages write descriptor command injection (`s_axis_write_desc_*`), controls global `write_enable`, controls `write_abort`, and captures write completion status tokens (`m_axis_write_desc_status_*`).

Both sub-agents operate in **Active Master** mode, acting as host command masters driving the DMA's slave descriptor interfaces.

## 2. The Transaction Class (`dma_desc_seq_item`)

The sequence item (`dma_desc_seq_item.sv`) represents a single DMA transfer job. It encapsulates both the outbound command attributes (driven to the DUT) and the inbound completion status attributes (sampled from the DUT upon transfer completion).

### 2.1 Randomized Command Fields (`rand`)

The following fields define the parameters of an issued descriptor:

| Field Name | Type | Width / Range | Protocol Role & Microarchitectural Purpose |
| :--- | :--- | :---: | :--- |
| `trans_type` | `rand dma_desc_type_e` | 1 bit (`DESC_READ`, `DESC_WRITE`) | Directs the transaction to the MM2S read engine or S2MM write engine. |
| `addr` | `rand bit [ADDR_WIDTH-1:0]` | Parameterized (Default 16 bits) | Source memory address (Read DMA) or destination buffer base address (Write DMA). |
| `len` | `rand bit [LEN_WIDTH-1:0]` | Parameterized (Default 20 bits) | Requested transfer length in bytes (supports transfers up to 1 MB). |
| `tag` | `rand bit [TAG_WIDTH-1:0]` | Parameterized (Default 8 bits) | Unique transaction tag (0–255) for out-of-order tracking and status correlation. |
| `id` | `rand bit [ID_WIDTH-1:0]` | Parameterized (Default 8 bits) | Stream source identifier (`TID`) attached to egress stream packets. |
| `dest` | `rand bit [DEST_WIDTH-1:0]` | Parameterized (Default 8 bits) | Stream routing tag (`TDEST`) attached to egress stream packets. |
| `user` | `rand bit [USER_WIDTH-1:0]` | Parameterized (Default 1 bit) | User sideband attribute (`TUSER`) attached to egress stream packets. |
| `valid_delay` | `rand int unsigned` | Integer ($\ge 0$) | Number of idle clock cycles to insert before asserting descriptor `valid`. |

### 2.2 Sequence Item Constraints

To model diverse operational profiles while guaranteeing address validity, `dma_desc_seq_item` implements six formal constraint blocks:

#### 1. Strictly Positive Length (`c_len_positive`)
A transfer length of zero is illegal under DMA hardware semantics:
```systemverilog
constraint c_len_positive {
    len > 0;
}
```

#### 2. Transfer Length Distribution (`c_default_len`)
Biases stimulus toward typical operational packet lengths while reserving budget for multi-burst stress:
```systemverilog
constraint c_default_len {
    soft len dist {
        [1    : 64]   :/ 50,  // Short transfers (1 to 2 AXI bursts) - 50%
        [65   : 512]  :/ 35,  // Medium multi-burst transfers         - 35%
        [513  : 4096] :/ 15   // Large stress transfers (up to 4KB)   - 15%
    };
}
```

#### 3. Address Space Bounds (`c_default_addr`)
Ensures that the entire transfer length fits within the physical memory address space without wrapping around 16-bit address boundaries (`0xFFFF`):
```systemverilog
constraint c_default_addr {
    soft addr <= (1 << ADDR_WIDTH) - 1 - len;
}
```

#### 4. Default 4-Byte Word Alignment (`c_default_alignment`)
Defaults to word-aligned base addresses, which can be overridden by unaligned test cases:
```systemverilog
constraint c_default_alignment {
    soft addr[1:0] == 2'b00;
}
```

#### 5. Sideband Metadata Tie-Off (`c_default_sideband`)
Defaults sideband attributes to zero unless explicitly constrained:
```systemverilog
constraint c_default_sideband {
    soft id   == '0;
    soft dest == '0;
    soft user == '0;
}
```

#### 6. Command Throttle Delay (`c_default_delay`)
Softly constrains inter-descriptor delays between 0 and 3 cycles to model realistic host driver command injection:
```systemverilog
constraint c_default_delay {
    soft valid_delay inside {[0 : 3]};
}
```

### 2.3 Monitor-Sampled Status Fields (Non-Randomized)

Upon transfer completion, the DMA hardware emits a 1-cycle status pulse. The monitor samples this pulse and populates the status fields within the matching descriptor item:

| Field Name | Type | Width / Range | Captured Information |
| :--- | :--- | :---: | :--- |
| `status_tag` | `bit [TAG_WIDTH-1:0]` | 8 bits | Tag of the completed descriptor, matching `tag` from command issuance. |
| `status_error` | `dma_error_e` | 4-bit enum | Completion error code (`DMA_ERR_NONE`, `TIMEOUT`, `PARITY`, `AXI_RD_SLVERR`, `AXI_WR_SLVERR`, etc.). |
| `status_len` | `bit [LEN_WIDTH-1:0]` | 20 bits | Actual number of bytes committed to memory (Write DMA path). |
| `status_id` | `bit [ID_WIDTH-1:0]` | 8 bits | Ingress stream `TID` captured at packet boundary (Write DMA path). |
| `status_dest` | `bit [DEST_WIDTH-1:0]` | 8 bits | Ingress stream `TDEST` captured at packet boundary (Write DMA path). |
| `status_user` | `bit [USER_WIDTH-1:0]` | 1 bit | Ingress stream `TUSER` captured at packet boundary (Write DMA path). |

## 3. Driver Implementation (`dma_rd_desc_driver` & `dma_wr_desc_driver`)

The drivers convert sequence items into cycle-accurate descriptor command handshakes.

### 3.1 Read Descriptor Driver (`dma_rd_desc_driver.sv`)

#### Run Phase Architecture
Manages the hardware reset sequence, enables the DMA core, and enters the command driving loop:
```systemverilog
virtual task run_phase(uvm_phase phase);
    vif.rd_desc_drv_cb.read_enable <= 1'b0;
    reset_signals();

    // Wait for reset release
    wait(!vif.rst);
    @(vif.rd_desc_drv_cb);

    // Assert read_enable to activate DMA read engine
    vif.rd_desc_drv_cb.read_enable <= 1'b1;

    forever begin
        seq_item_port.get_next_item(req);
        drive_descriptor(req);
        seq_item_port.item_done();
    end
endtask : run_phase
```

#### Descriptor Driving Task (`drive_descriptor`)
Executes the command handshake on physical pins:
1. **Inter-Descriptor Delay:** If `req.valid_delay > 0`, clears descriptor pins and holds `read_desc_valid = 0` for $N$ cycles.
2. **Drive Command Parameters:** Assigns `read_desc_addr`, `read_desc_len`, `read_desc_tag`, `read_desc_id`, `read_desc_dest`, `read_desc_user`, and asserts `read_desc_valid = 1`.
3. **Synchronous Handshake Wait:** Holds signals stable until an accepted handshake occurs (`read_desc_valid && read_desc_ready` sampled high at a clock edge after drive time):
   ```systemverilog
   drive_time = $time;
   @(vif.rd_desc_drv_cb);
   while (!vif.rd_desc_drv_cb.read_desc_ready || $time == drive_time) begin
       @(vif.rd_desc_drv_cb);
   end
   ```
4. **Clean Interface Deassertion:** Clears valid and zeroes data lines immediately upon handshake completion.

### 3.2 Write Descriptor Driver (`dma_wr_desc_driver.sv`)

Operates symmetrically on the write channel (`s_axis_write_desc_*`), asserting global `write_enable = 1` and holding `write_abort = 0` during normal operation.

## 4. Monitor Implementation (`dma_rd_desc_monitor` & `dma_wr_desc_monitor`)

The descriptor monitors passively inspect command issuance and status retirement strictly through clocking block `rd_desc_mon_cb` and `wr_desc_mon_cb`.

### 4.1 Read Descriptor Monitor (`dma_rd_desc_monitor.sv`)

#### Dual Analysis Ports
The monitor instantiates two independent TLM analysis ports:
* `cmd_ap`: Broadcasts newly accepted command descriptors to `dma_scoreboard` and `dma_coverage`.
* `status_ap`: Broadcasts completed descriptors stamped with status codes.

#### Associative Command Tracking Table
Maintains an internal table indexing in-flight commands by their unique tag:
```systemverilog
item_type pending_cmds[bit [TAG_WIDTH-1:0]];
```

#### Priority-Ordered Run Phase
On every clock edge, the monitor evaluates completion status **before** command acceptance. This ensures that completed tags are retired cleanly prior to immediate tag reuse by a new command on the exact same cycle:
```systemverilog
virtual task run_phase(uvm_phase phase);
    forever begin
        wait(!vif.rst);
        while (!vif.rst) begin
            @(vif.rd_desc_mon_cb);
            if (!vif.rst) begin
                // Priority: Process status before command on the same cycle
                if (vif.rd_desc_mon_cb.read_desc_status_valid) begin
                    process_status();
                end
                // Sample command only on accepted handshake (valid && ready)
                if (vif.rd_desc_mon_cb.read_desc_valid &&
                    vif.rd_desc_mon_cb.read_desc_ready) begin
                    process_cmd();
                end
            end
        end
        pending_cmds.delete(); // Flush table if reset occurs
    end
endtask : run_phase
```

#### Command Processing (`process_cmd`)
1. Samples `read_desc_addr`, `read_desc_len`, `read_desc_tag`, `read_desc_id`, `read_desc_dest`, `read_desc_user`.
2. **Tag Collision Detection:** Checks if `pending_cmds.exists(item.tag)`. If a command with the same tag is already outstanding, flags an immediate `uvm_error`.
3. Stores a clone in `pending_cmds[item.tag] = item`.
4. Broadcasts the command snapshot via `cmd_ap.write(cmd_snapshot)`.

#### Status Processing (`process_status`)
1. Samples `read_desc_status_tag` and `read_desc_status_error`.
2. Retrieves the matching in-flight command from `pending_cmds[status_tag]`.
3. Deletes the retired tag from `pending_cmds`.
4. Stamps `status_error` into the sequence item and broadcasts the completed transaction via `status_ap.write(retire_item)`.

### 4.2 Write Descriptor Monitor (`dma_wr_desc_monitor.sv`)

Operates identically to the read monitor, with the addition of capturing:
* `status_len`: Actual number of bytes committed to memory (used by the scoreboard to detect early stream termination or buffer clamp).
* `status_id`, `status_dest`, `status_user`: Sideband attributes captured at the final packet boundary.
