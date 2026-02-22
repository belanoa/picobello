// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Andrea Belano <andrea.belano2@unibo.it>

`include "mem_interface/typedef.svh"
`include "tcdm_interface/typedef.svh"

`include "axi/typedef.svh"
`include "reqrsp_interface/typedef.svh"

module micro_cluster
  import snitch_pkg::*;
  import snitch_cluster_pkg::*;
#(
  parameter int unsigned                    AddrWidth              = 32,
  parameter int unsigned                    NarrowDataWidth        = 64,
  parameter int unsigned                    WideDataWidth          = 128,
  parameter int unsigned                    TCDMAddrWidth          = 32,
  parameter int unsigned                    NrBanksL0              = 1,
  /// Data/TCDM memory depth per cut (in words).
  parameter int unsigned                    TCDMDepthL0            = 0,
  parameter int unsigned                    BootAddr               = 0,
  parameter bit                             RVE                    = 0,
  parameter bit                             RVM                    = 0,
  parameter bit                             RVF                    = 0,
  parameter bit                             RVD                    = 0,
  parameter bit                             XDivSqrt               = 0,
  parameter bit                             XF16                   = 0,
  parameter bit                             XF16ALT                = 0,
  parameter bit                             XF8                    = 0,
  parameter bit                             XF8ALT                 = 0,
  parameter bit                             XFVEC                  = 0,
  parameter bit                             XFDOTP                 = 0,
  parameter bit                             Xfrep                  = 0,
  parameter bit                             Xssr                   = 0,
  parameter bit                             Xcopift                = 0,
  parameter int unsigned                    NumIntOutstandingLoads = 0,
  parameter int unsigned                    NumIntOutstandingMem   = 0,
  parameter int unsigned                    NumFPOutstandingLoads  = 0,
  parameter int unsigned                    NumFPOutstandingMem    = 0,
  parameter fpnew_pkg::fpu_implementation_t FPUImplementation      = '{default: fpnew_pkg::fpu_implementation_t'(0)},
  parameter int unsigned                    NumDTLBEntries         = 0,
  parameter int unsigned                    NumITLBEntries         = 0,
  parameter int unsigned                    NumSequencerInstr      = 0,
  parameter int unsigned                    NumSequencerLoops      = 0,
  parameter int unsigned                    NumSsrs                = 0,
  parameter int unsigned                    SsrMuxRespDepth        = 0,
  parameter snitch_ssr_pkg::ssr_cfg_t [2:0] SsrCfgs                = '{default: '0},
  parameter logic [2:0][4:0]                SsrRegs                = '{default: '0},
  parameter bit                             RegisterOffloadReq     = 0,
  parameter bit                             RegisterOffloadRsp     = 0,
  parameter bit                             RegisterCoreReq        = 0,
  parameter bit                             RegisterCoreRsp        = 0,
  parameter bit                             RegisterTCDMCuts       = 0,
  parameter bit                             RegisterFPUReq         = 0,
  parameter bit                             RegisterSequencer      = 0,
  parameter bit                             RegisterFPUIn          = 0,
  parameter bit                             RegisterFPUOut         = 0,
  parameter int unsigned                    CaqDepth               = 0,
  parameter int unsigned                    CaqTagWidth            = 0,
  parameter int unsigned                    MemoryMacroLatency     = 1 + RegisterTCDMCuts,
  parameter type                            wide_tcdm_req_t        = logic,
  parameter type                            wide_tcdm_rsp_t        = logic,
  parameter type                            narrow_tcdm_req_t      = logic,
  parameter type                            narrow_tcdm_rsp_t      = logic,
  parameter type                            hive_req_t             = logic,
  parameter type                            hive_rsp_t             = logic
) (
  input logic                 clk_i,
  input logic                 rst_ni,

  input logic [31:0]          hart_id_i,
  input logic [AddrWidth-1:0] tcdm_addr_base_i,

  output wide_tcdm_req_t      wide_tcdm_req_o,
  input  wide_tcdm_rsp_t      wide_tcdm_rsp_i,

  output narrow_tcdm_req_t    narrow_tcdm_req_o,
  input  narrow_tcdm_rsp_t    narrow_tcdm_rsp_i,

  input  logic                mcip_i,

  output hive_req_t           hive_req_o,
  input  hive_rsp_t           hive_rsp_i,

  output logic                barrier_o,
  input  logic                barrier_i,

  output logic                sync_o,
  input  logic                sync_i,

  hwpe_stream_intf_stream.sink    w_stream_i,
  hwpe_stream_intf_stream.sink    x_stream_i,
  hwpe_stream_intf_stream.source  w_stream_o,
  hwpe_stream_intf_stream.source  x_stream_o
);

  localparam int unsigned TCDMMemAddrWidthL0 = $clog2(TCDMDepthL0);
  localparam int unsigned BanksPerSuperBankL0 = WideDataWidth / NarrowDataWidth;
  localparam int unsigned NrSuperBanksL0 = NrBanksL0 / BanksPerSuperBankL0;
  localparam int unsigned TCDMSizeL0 = NrBanksL0 * TCDMDepthL0 * (NarrowDataWidth/8);
  localparam int unsigned SuperBankSizeL0 = TCDMSizeL0 / NrSuperBanksL0;

  localparam int unsigned XifIdWidth = 4;
  localparam int unsigned NrTCDMPortsCore = NumSsrs > 1 ? NumSsrs : 1;

  typedef logic [NarrowDataWidth-1:0] narrow_data_t;
  typedef logic [NarrowDataWidth/8-1:0] narrow_strb_t;

  typedef logic [WideDataWidth-1:0] wide_data_t;
  typedef logic [WideDataWidth/8-1:0] wide_strb_t;

  typedef logic [TCDMAddrWidth-1:0] tcdm_addr_t;
  typedef logic [TCDMAddrWidth:0] tcdm_addr_wa_t;
  typedef logic [AddrWidth-1:0] addr_t;

  typedef logic [TCDMMemAddrWidthL0-1:0]  tcdm_mem_addr_t;

  `TCDM_TYPEDEF_ALL(tcdm_wa, tcdm_addr_wa_t, wide_data_t, wide_strb_t, logic)

  `TCDM_TYPEDEF_ALL(core_tcdm_wa, tcdm_addr_wa_t, narrow_data_t, narrow_strb_t, logic)

  `MEM_TYPEDEF_ALL(mem_narrow, tcdm_mem_addr_t, narrow_data_t, narrow_strb_t, logic)
  `MEM_TYPEDEF_ALL(mem_wide, tcdm_mem_addr_t, wide_data_t, wide_strb_t, logic)

  `REQRSP_TYPEDEF_ALL(reqrsp, addr_t, narrow_data_t, narrow_strb_t)

  typedef struct packed {
    logic [2:0] ema;
    logic [1:0] emaw;
    logic [0:0] emas;
  } sram_cfg_t;

  typedef struct packed {
    logic [31:0]           instr;
    logic [31:0]           hartid;
    logic [XifIdWidth-1:0] id;
  } x_issue_req_t;

  typedef struct packed {
    logic       accept;
    logic       writeback;
    logic [2:0] register_read;
  } x_issue_resp_t;

  typedef struct packed {
    logic [31:0]           hartid;
    logic [XifIdWidth-1:0] id;
    logic [2:0][31:0]      rs;
    logic [2:0]            rs_valid;
  } x_register_t;

  typedef struct packed {
    logic [31:0]           hartid;
    logic [XifIdWidth-1:0] id;
    logic                  commit_kill;
  } x_commit_t;

  typedef struct packed {
    logic [31:0]           hartid;
    logic [XifIdWidth-1:0] id;
    logic [31:0]           data;
    logic [4:0]            rd;
    logic                  we;
  } x_result_t;

  logic mxip;

  logic fence;

  x_issue_req_t  x_issue_req;
  x_issue_resp_t x_issue_resp;
  logic          x_issue_valid;
  logic          x_issue_ready;
  x_register_t   x_register;
  logic          x_register_valid;
  logic          x_register_ready;
  x_commit_t     x_commit;
  logic          x_commit_valid;
  x_result_t     x_result;
  logic          x_result_valid;
  logic          x_result_ready;

  core_tcdm_wa_req_t [NrTCDMPortsCore-1:0] core_tcdm_req;
  core_tcdm_wa_rsp_t [NrTCDMPortsCore-1:0] core_tcdm_rsp;

  narrow_tcdm_req_t [NrTCDMPortsCore-1:0] core_tcdm_req_l0, core_tcdm_req_l1;
  narrow_tcdm_rsp_t [NrTCDMPortsCore-1:0] core_tcdm_rsp_l0, core_tcdm_rsp_l1;

  tcdm_wa_req_t hwpe_tcdm_req;
  tcdm_wa_rsp_t hwpe_tcdm_rsp;

  wide_tcdm_req_t hwpe_tcdm_req_l0, hwpe_tcdm_req_l1;
  wide_tcdm_rsp_t hwpe_tcdm_rsp_l0, hwpe_tcdm_rsp_l1;

  mem_narrow_req_t [NrSuperBanksL0-1:0][BanksPerSuperBankL0-1:0] ic_req;
  mem_narrow_rsp_t [NrSuperBanksL0-1:0][BanksPerSuperBankL0-1:0] ic_rsp;
  mem_wide_req_t   [NrSuperBanksL0-1:0]                          sb_hwpe_req;
  mem_wide_rsp_t   [NrSuperBanksL0-1:0]                          sb_hwpe_rsp;

  interrupts_t irq;

  assign irq.debug = '0;
  assign irq.meip = '0;
  assign irq.mtip = '0;
  assign irq.msip = '0;
  assign irq.mcip = mcip_i;
  assign irq.mxip = mxip;

  // Dummy types
  `AXI_TYPEDEF_ALL(axi_dummy, logic, logic, logic, logic, logic)

  snitch_cc #(
    .AddrWidth (AddrWidth),
    .DataWidth (NarrowDataWidth),
    //.DMADataWidth (WideDataWidth),
    //.DMAIdWidth (WideIdWidthIn),
    //.DMAUserWidth (WideUserWidth),
    .SnitchPMACfg (SnitchPMACfg),
    //.DMANumAxInFlight (DMANumAxInFlight),
    //.DMAReqFifoDepth (DMAReqFifoDepth),
    //.DMANumChannels (DMANumChannels),
    .dreq_t (reqrsp_req_t),
    .drsp_t (reqrsp_rsp_t),
    .tcdm_req_t (core_tcdm_wa_req_t),
    .tcdm_rsp_t (core_tcdm_wa_rsp_t),
    .tcdm_user_t (logic),
    .axi_ar_chan_t (axi_dummy_ar_chan_t),
    .axi_aw_chan_t (axi_dummy_aw_chan_t),
    .axi_req_t (axi_dummy_req_t),
    .axi_rsp_t (axi_dummy_resp_t),
    .hive_req_t (hive_req_t),
    .hive_rsp_t (hive_rsp_t),
    .acc_req_t (acc_req_t),
    .acc_resp_t (acc_resp_t),
    //.dma_events_t (dma_events_t),
    .XifIdWidth (XifIdWidth),
    .x_issue_req_t (x_issue_req_t),
    .x_issue_resp_t (x_issue_resp_t),
    .x_register_t (x_register_t),
    .x_commit_t (x_commit_t),
    .x_result_t (x_result_t),
    .BootAddr (BootAddr),
    .RVE (RVE),
    .RVM (RVM),
    .RVF (RVF),
    .RVD (RVD),
    .XDivSqrt (XDivSqrt),
    .XF16 (XF16),
    .XF16ALT (XF16ALT),
    .XF8 (XF8),
    .XF8ALT (XF8ALT),
    .XFVEC (XFVEC),
    .XFDOTP (XFDOTP),
    .Xdma ('0),
    .IsoCrossing ('0),
    .Xfrep (Xfrep),
    .Xssr (Xssr),
    .Xcopift (Xcopift),
    .Xipu (1'b0),
    .VMSupport ('0),
    .NumIntOutstandingLoads (NumIntOutstandingLoads),
    .NumIntOutstandingMem (NumIntOutstandingMem),
    .NumFPOutstandingLoads (NumFPOutstandingLoads),
    .NumFPOutstandingMem (NumFPOutstandingMem),
    .FPUImplementation (FPUImplementation),
    .NumDTLBEntries (NumDTLBEntries),
    .NumITLBEntries (NumITLBEntries),
    .NumSequencerInstr (NumSequencerInstr),
    .NumSequencerLoops (NumSequencerLoops),
    .NumSsrs (NumSsrs),
    .SsrMuxRespDepth (SsrMuxRespDepth),
    .SsrCfgs (SsrCfgs),
    .SsrRegs (SsrRegs),
    .RegisterOffloadReq (RegisterOffloadReq),
    .RegisterOffloadRsp (RegisterOffloadRsp),
    .RegisterCoreReq (RegisterCoreReq),
    .RegisterCoreRsp (RegisterCoreRsp),
    .RegisterFPUReq (RegisterFPUReq),
    .RegisterSequencer (RegisterSequencer),
    .RegisterFPUIn (RegisterFPUIn),
    .RegisterFPUOut (RegisterFPUOut),
    .TCDMAddrWidth (TCDMAddrWidth+1),
    .CaqDepth (CaqDepth),
    .CaqTagWidth (CaqTagWidth),
    .DebugSupport (0),
    .TCDMAliasEnable (0),
    .TCDMAliasStart (0)
  ) i_snitch_cc (
    .clk_i,
    .clk_d2_i (clk_i),
    .rst_ni,
    .rst_int_ss_ni (1'b1),
    .rst_fp_ss_ni (1'b1),
    .hart_id_i (hart_id_i),
    .hive_req_o (hive_req_o),
    .hive_rsp_i (hive_rsp_i),
    .irq_i (irq),
    .data_req_o (),
    .data_rsp_i ('0),
    .tcdm_req_o (core_tcdm_req),
    .tcdm_rsp_i (core_tcdm_rsp),
    .x_issue_req_o (x_issue_req),
    .x_issue_resp_i (x_issue_resp),
    .x_issue_valid_o (x_issue_valid),
    .x_issue_ready_i (x_issue_ready),
    .x_register_o (x_register),
    .x_register_valid_o (x_register_valid),
    .x_register_ready_i (x_register_ready),
    .x_commit_o (x_commit),
    .x_commit_valid_o (x_commit_valid),
    .x_result_i (x_result),
    .x_result_valid_i (x_result_valid),
    .x_result_ready_o (x_result_ready),
    .axi_dma_req_o (),
    .axi_dma_res_i ('0),
    .axi_dma_busy_o (),
    .axi_dma_events_o (),
    .core_events_o (),
    .tcdm_addr_base_i (tcdm_addr_base_i),
    .barrier_o (barrier_o),
    .barrier_i (barrier_i),
    .fence_o (fence)
  );

  snitch_hwpe_subsystem #(
    .tcdm_req_t (tcdm_wa_req_t),
    .tcdm_rsp_t (tcdm_wa_rsp_t),
    .HwpeDataWidth(WideDataWidth),
    .IdWidth (),
    .NrCores (1),
    .XifNumHarts (1),
    .XifIdWidth (XifIdWidth),
    .XifIssueRegisterSplit (0),
    .x_issue_req_t (x_issue_req_t),
    .x_issue_resp_t (x_issue_resp_t),
    .x_register_t (x_register_t),
    .x_commit_t (x_commit_t),
    .x_result_t (x_result_t),
    .NrPorts (1),
    .NrRedW (1),
    .NrRedH (1),
    .TCDMDataWidth (NarrowDataWidth)
  ) i_snitch_hwpe_subsystem (
    .clk_i              (clk_i),
    .rst_ni             (rst_ni),
    .test_mode_i        (1'b0),
    .tcdm_req_o         (hwpe_tcdm_req),
    .tcdm_rsp_i         (hwpe_tcdm_rsp),
    .x_issue_req_i      (x_issue_req),
    .x_issue_resp_o     (x_issue_resp),
    .x_issue_valid_i    (x_issue_valid),
    .x_issue_ready_o    (x_issue_ready),
    .x_register_i       (x_register),
    .x_register_valid_i (x_register_valid),
    .x_register_ready_o (x_register_ready),
    .x_commit_i         (x_commit),
    .x_commit_valid_i   (x_commit_valid),
    .x_result_o         (x_result),
    .x_result_valid_o   (x_result_valid),
    .x_result_ready_i   (x_result_ready),
    .hwpe_evt_o         (mxip),
    .sync_o,
    .sync_i,
    .w_stream_i         (w_stream_i),
    .x_stream_i         (x_stream_i),
    .w_stream_o         (w_stream_o),
    .x_stream_o         (x_stream_o)
  );

  // MUXES and MEMORY //

  // Use the most significant address bit to select L1 or L0
  assign hwpe_tcdm_req_l0.q_valid = hwpe_tcdm_req.q_valid && hwpe_tcdm_req.q.addr[TCDMAddrWidth];
  assign hwpe_tcdm_req_l0.q.addr  = hwpe_tcdm_req.q.addr[TCDMAddrWidth-1:0];
  assign hwpe_tcdm_req_l0.q.write = hwpe_tcdm_req.q.write;
  assign hwpe_tcdm_req_l0.q.amo   = hwpe_tcdm_req.q.amo;
  assign hwpe_tcdm_req_l0.q.data  = hwpe_tcdm_req.q.data;
  assign hwpe_tcdm_req_l0.q.strb  = hwpe_tcdm_req.q.strb;
  assign hwpe_tcdm_req_l0.q.user  = hwpe_tcdm_req.q.user;

  assign hwpe_tcdm_req_l1.q_valid = hwpe_tcdm_req.q_valid && ~hwpe_tcdm_req.q.addr[TCDMAddrWidth];
  assign hwpe_tcdm_req_l1.q.addr  = hwpe_tcdm_req.q.addr[TCDMAddrWidth-1:0];
  assign hwpe_tcdm_req_l1.q.write = hwpe_tcdm_req.q.write;
  assign hwpe_tcdm_req_l1.q.amo   = hwpe_tcdm_req.q.amo;
  assign hwpe_tcdm_req_l1.q.data  = hwpe_tcdm_req.q.data;
  assign hwpe_tcdm_req_l1.q.strb  = hwpe_tcdm_req.q.strb;
  assign hwpe_tcdm_req_l1.q.user  = hwpe_tcdm_req.q.user;

  for (genvar i = 0; i < NrTCDMPortsCore; i++) begin : gen_core_reqs
    assign core_tcdm_req_l0[i].q_valid = core_tcdm_req[i].q_valid && core_tcdm_req[i].q.addr[TCDMAddrWidth];
    assign core_tcdm_req_l0[i].q.addr  = core_tcdm_req[i].q.addr[TCDMAddrWidth-1:0];
    assign core_tcdm_req_l0[i].q.write = core_tcdm_req[i].q.write;
    assign core_tcdm_req_l0[i].q.amo   = core_tcdm_req[i].q.amo;
    assign core_tcdm_req_l0[i].q.data  = core_tcdm_req[i].q.data;
    assign core_tcdm_req_l0[i].q.strb  = core_tcdm_req[i].q.strb;
    assign core_tcdm_req_l0[i].q.user  = core_tcdm_req[i].q.user;

    assign core_tcdm_req_l1[i].q_valid = core_tcdm_req[i].q_valid && ~core_tcdm_req[i].q.addr[TCDMAddrWidth];
    assign core_tcdm_req_l1[i].q.addr  = core_tcdm_req[i].q.addr[TCDMAddrWidth-1:0];
    assign core_tcdm_req_l1[i].q.write = core_tcdm_req[i].q.write;
    assign core_tcdm_req_l1[i].q.amo   = core_tcdm_req[i].q.amo;
    assign core_tcdm_req_l1[i].q.data  = core_tcdm_req[i].q.data;
    assign core_tcdm_req_l1[i].q.strb  = core_tcdm_req[i].q.strb;
    assign core_tcdm_req_l1[i].q.user  = core_tcdm_req[i].q.user;
  end

  assign hwpe_tcdm_rsp.p_valid    = hwpe_tcdm_rsp_l0.p_valid || hwpe_tcdm_rsp_l1.p_valid;
  assign hwpe_tcdm_rsp.p.data     = hwpe_tcdm_rsp_l0.p_valid ? hwpe_tcdm_rsp_l0.p.data : hwpe_tcdm_rsp_l1.p.data;
  assign hwpe_tcdm_rsp.q_ready    = hwpe_tcdm_req.q.addr[TCDMAddrWidth] ? hwpe_tcdm_rsp_l0.q_ready : hwpe_tcdm_rsp_l1.q_ready;

  for (genvar i = 0; i < NrTCDMPortsCore; i++) begin : gen_core_rsps
    assign core_tcdm_rsp[i].p_valid    = core_tcdm_rsp_l0[i].p_valid || core_tcdm_rsp_l1[i].p_valid;
    assign core_tcdm_rsp[i].p.data     = core_tcdm_rsp_l0[i].p_valid ? core_tcdm_rsp_l0[i].p.data : core_tcdm_rsp_l1[i].p.data;
    assign core_tcdm_rsp[i].q_ready    = core_tcdm_req[i].q.addr[TCDMAddrWidth] ? core_tcdm_rsp_l0[i].q_ready : core_tcdm_rsp_l1[i].q_ready;
  end

  tcdm_mux #(
    .NrPorts (3),
    .AddrWidth (TcdmAddrWidth),
    .DataWidth (NarrowDataWidth),
    .user_t (logic [1:0]),
    .RespDepth (4),
    .tcdm_req_t (narrow_tcdm_req_t),
    .tcdm_rsp_t (narrow_tcdm_rsp_t)
  ) i_core_mux (
    .clk_i,
    .rst_ni,
    .slv_req_i (core_tcdm_req_l1),
    .slv_rsp_o (core_tcdm_rsp_l1),
    .mst_req_o (narrow_tcdm_req_o),
    .mst_rsp_i (narrow_tcdm_rsp_i)
  );

  // The hwpe ss uses the wide port exclusively
  assign wide_tcdm_req_o.q_valid = hwpe_tcdm_req_l1.q_valid;

  assign wide_tcdm_req_o.q = '{
    addr:  hwpe_tcdm_req_l1.q.addr,
    write: hwpe_tcdm_req_l1.q.write,
    amo:   hwpe_tcdm_req_l1.q.amo,
    data:  hwpe_tcdm_req_l1.q.data,
    strb:  hwpe_tcdm_req_l1.q.strb,
    user:  '0
  };

  assign hwpe_tcdm_rsp_l1.q_ready = wide_tcdm_rsp_i.q_ready;
  assign hwpe_tcdm_rsp_l1.p_valid = wide_tcdm_rsp_i.p_valid;

  assign hwpe_tcdm_rsp_l1.p = '{
    data: wide_tcdm_rsp_i.p.data
  };

  // L0 interconnects

  snitch_tcdm_interconnect #(
    .NumInp (1),
    .NumOut (NrSuperBanksL0),
    .NumHyperBanks (1),
    .tcdm_req_t (wide_tcdm_req_t),
    .tcdm_rsp_t (wide_tcdm_rsp_t),
    .mem_req_t (mem_wide_req_t),
    .mem_rsp_t (mem_wide_rsp_t),
    .user_t (logic),
    .TcdmAddrWidth (TCDMAddrWidth),
    .MemAddrWidth (TCDMMemAddrWidthL0),
    .DataWidth (WideDataWidth),
    .SuperBankDataWidth (WideDataWidth),
    .MemoryResponseLatency (MemoryMacroLatency),
    .SuperBankSize (SuperBankSizeL0)
  ) i_hwpe_interconnect (
    .clk_i,
    .rst_ni,
    .req_i (hwpe_tcdm_req_l0),
    .rsp_o (hwpe_tcdm_rsp_l0),
    .mem_req_o (sb_hwpe_req),
    .mem_rsp_i (sb_hwpe_rsp)
  );

  snitch_tcdm_interconnect #(
    .NumInp (NrTCDMPortsCore),
    .NumOut (NrBanksL0),
    .NumHyperBanks (1),
    .tcdm_req_t (narrow_tcdm_req_t),
    .tcdm_rsp_t (narrow_tcdm_rsp_t),
    .mem_req_t (mem_narrow_req_t),
    .mem_rsp_t (mem_narrow_rsp_t),
    .TcdmAddrWidth (TCDMAddrWidth),
    .MemAddrWidth (TCDMMemAddrWidthL0),
    .DataWidth (NarrowDataWidth),
    .SuperBankDataWidth (WideDataWidth),
    .user_t (logic),
    .MemoryResponseLatency (MemoryMacroLatency),
    .Radix (2),
    .Topology (LogarithmicInterconnect),
    .NumSwitchNets (4),
    .SwitchLfsrArbiter (0),
    .SuperBankSize (SuperBankSizeL0)
  ) i_core_interconnect (
    .clk_i,
    .rst_ni,
    .req_i (core_tcdm_req_l0),
    .rsp_o (core_tcdm_rsp_l0),
    .mem_req_o (ic_req),
    .mem_rsp_i (ic_rsp)
  );

  for (genvar i = 0; i < NrSuperBanksL0; i++) begin : gen_tcdm_super_bank

    mem_narrow_req_t [BanksPerSuperBankL0-1:0] amo_req;
    mem_narrow_rsp_t [BanksPerSuperBankL0-1:0] amo_rsp;

    mem_wide_narrow_mux #(
      .NarrowDataWidth (NarrowDataWidth),
      .WideDataWidth (WideDataWidth),
      .ExtDataWidth (WideDataWidth),
      .mem_narrow_req_t (mem_narrow_req_t),
      .mem_narrow_rsp_t (mem_narrow_rsp_t),
      .mem_wide_req_t (mem_wide_req_t),
      .mem_wide_rsp_t (mem_wide_rsp_t),
      .mem_ext_req_t (mem_wide_req_t),
      .mem_ext_rsp_t (mem_wide_rsp_t)
    ) i_tcdm_mux (
      .clk_i,
      .rst_ni,
      .in_narrow_req_i (ic_req [i]),
      .in_narrow_rsp_o (ic_rsp [i]),
      .in_wide_req_i (sb_hwpe_req [i]),
      .in_wide_rsp_o (sb_hwpe_rsp [i]),
      .in_ext_req_i ('0),
      .in_ext_rsp_o (),
      .out_req_o (amo_req),
      .out_rsp_i (amo_rsp)
    );

    // generate banks of the superbank
    for (genvar j = 0; j < BanksPerSuperBankL0; j++) begin : gen_tcdm_bank

      logic mem_cs, mem_wen;
      tcdm_mem_addr_t mem_add;
      narrow_strb_t mem_be;
      narrow_data_t mem_rdata, mem_wdata;

      tc_sram_impl #(
        .NumWords (TCDMDepthL0),
        .DataWidth (NarrowDataWidth),
        .ByteWidth (8),
        .NumPorts (1),
        .Latency (1),
        .impl_in_t (sram_cfg_t)
      ) i_data_mem (
        .clk_i,
        .rst_ni,
        .impl_i ('0),
        .impl_o (  ),
        .req_i (mem_cs),
        .we_i (mem_wen),
        .addr_i (mem_add),
        .wdata_i (mem_wdata),
        .be_i (mem_be),
        .rdata_o (mem_rdata)
      );

      data_t amo_rdata_local;

      snitch_amo_shim #(
        .AddrMemWidth ( TCDMMemAddrWidthL0 ),
        .DataWidth ( NarrowDataWidth ),
        .CoreIDWidth ( 1 )
      ) i_amo_shim (
        .clk_i,
        .rst_ni ( rst_ni ),
        .valid_i ( amo_req[j].q_valid ),
        .ready_o ( amo_rsp[j].q_ready ),
        .addr_i ( amo_req[j].q.addr ),
        .write_i ( amo_req[j].q.write ),
        .wdata_i ( amo_req[j].q.data ),
        .wstrb_i ( amo_req[j].q.strb ),
        .core_id_i ( '0 ),
        .is_core_i ( '0 ),
        .rdata_o ( amo_rdata_local ),
        .amo_i ( amo_req[j].q.amo ),
        .mem_req_o ( mem_cs ),
        .mem_add_o ( mem_add ),
        .mem_wen_o ( mem_wen ),
        .mem_wdata_o ( mem_wdata ),
        .mem_be_o ( mem_be ),
        .mem_rdata_i ( mem_rdata ),
        .dma_access_i ( sb_hwpe_req[i].q_valid ),  // Requests from the acelerator have priority
        .amo_conflict_o (  )
      );

      // Insert a pipeline register at the output of each SRAM.
      shift_reg #( .dtype (data_t), .Depth (RegisterTCDMCuts)) i_sram_pipe (
        .clk_i, .rst_ni,
        .d_i (amo_rdata_local), .d_o (amo_rsp[j].p.data)
      );
    end
  end

endmodule