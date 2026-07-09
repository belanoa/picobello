// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Author: Tim Fischer <fischeti@iis.ee.ethz.ch>

`include "axi/assign.svh"
`include "axi/typedef.svh"
`include "tcdm_interface/typedef.svh"

module cluster_tile
  import floo_pkg::*;
  import floo_picobello_noc_pkg::*;
  import snitch_cluster_pkg::*;
  import picobello_pkg::*;
(
  input  logic                                    clk_i,
  input  logic                                    rst_ni,
  input  logic                                    test_enable_i,
  input  logic                                    tile_clk_en_i,
  input  logic                                    tile_rst_ni,
  input  logic                                    clk_rst_bypass_i,
  // Cluster ports
  input  logic                      [NrCores-1:0] debug_req_i,
  input  logic                      [NrCores-1:0] meip_i,
  input  logic                      [NrCores-1:0] mtip_i,
  input  logic                      [NrCores-1:0] msip_i,
  input  logic                      [        9:0] hart_base_id_i,
  input  snitch_cluster_pkg::addr_t               cluster_base_addr_i,
  // Chimney ports
  input  id_t                                     id_i,
  // Router ports
  output floo_req_t                 [ West:North] floo_req_o,
  input  floo_rsp_t                 [ West:North] floo_rsp_i,
  output floo_wide_t                [ West:North] floo_wide_o,
  input  floo_req_t                 [ West:North] floo_req_i,
  output floo_rsp_t                 [ West:North] floo_rsp_o,
  input  floo_wide_t                [ West:North] floo_wide_i,
  // FractalSync ports
  output fsync_req_t                              fsync_req_ht_o,
  input  fsync_rsp_t                              fsync_rsp_ht_i,
  output fsync_req_t                              fsync_req_hn_o,
  input  fsync_rsp_t                              fsync_rsp_hn_i,
  output fsync_req_t                              fsync_req_vt_o,
  input  fsync_rsp_t                              fsync_rsp_vt_i,
  output fsync_req_t                              fsync_req_vn_o,
  input  fsync_rsp_t                              fsync_rsp_vn_i
);

  // Tile-specific reset and clock signals
  logic                                 tile_clk;
  logic                                 tile_rst_n;

  ////////////////////
  // Snitch Cluster //
  ////////////////////

  snitch_cluster_pkg::narrow_in_req_t   cluster_narrow_in_req;
  snitch_cluster_pkg::narrow_in_resp_t  cluster_narrow_in_rsp;
  snitch_cluster_pkg::narrow_out_req_t  cluster_narrow_out_req;
  snitch_cluster_pkg::narrow_out_resp_t cluster_narrow_out_rsp;
  snitch_cluster_pkg::wide_out_req_t    cluster_wide_out_req;
  snitch_cluster_pkg::wide_out_resp_t   cluster_wide_out_rsp;
  snitch_cluster_pkg::wide_in_req_t     cluster_wide_in_req;
  snitch_cluster_pkg::wide_in_resp_t    cluster_wide_in_rsp;

  snitch_cluster_pkg::tcdm_ext_req_t    [3:0] cluster_tcdm_wide_ext_req;
  snitch_cluster_pkg::tcdm_ext_rsp_t    [3:0] cluster_tcdm_wide_ext_rsp;
  snitch_cluster_pkg::tcdm_req_t        [3:0] cluster_tcdm_narrow_ext_req;
  snitch_cluster_pkg::tcdm_rsp_t        [3:0] cluster_tcdm_narrow_ext_rsp;

  logic                          [3:0] barrier;
  snitch_cluster_pkg::hive_req_t [3:0] hive_req;
  snitch_cluster_pkg::hive_rsp_t [3:0] hive_rsp;
  snitch_pkg::core_events_t      [3:0] core_events;
  logic out_barrier;
  logic [3:0] cl_interrupt;

  logic mxip;

  snitch_cluster_pkg::x_issue_req_t  x_issue_req;
  snitch_cluster_pkg::x_issue_resp_t x_issue_resp;
  snitch_cluster_pkg::x_register_t   x_register;
  snitch_cluster_pkg::x_commit_t     x_commit;
  snitch_cluster_pkg::x_result_t     x_result;

  logic x_issue_valid;
  logic x_issue_ready;
  logic x_register_valid;
  logic x_register_ready;
  logic x_commit_valid;
  logic x_result_valid;
  logic x_result_ready;

  logic [3:0] redmule_sync_req;
  logic       redmule_sync_rsp;

  localparam snitch_ssr_pkg::ssr_cfg_t [2:0] SsrCfg = '{'{1, 0, 0, 1, 1, 1, 4, 18, 18, 3, 4, 3, 8, 4, 3},
    '{1, 1, 1, 0, 1, 1, 4, 18, 18, 3, 4, 3, 8, 4, 3},
    '{1, 1, 0, 0, 1, 1, 4, 18, 18, 3, 4, 3, 8, 4, 3}};


  snitch_cluster_pkg::pace_param_t pace_param;

  snitch_cluster_wrapper i_cluster (
    .clk_i                  (tile_clk),
    .rst_ni                 (tile_rst_n),
    .debug_req_i,
    .meip_i,
    .mtip_i,
    .msip_i,
    .mxip_i                 (mxip),
    .hart_base_id_i,
    .cluster_base_addr_i,
    .clk_d2_bypass_i        ('0),
    .sram_cfgs_i            ('0),
    .narrow_in_req_i        (cluster_narrow_in_req),
    .narrow_in_resp_o       (cluster_narrow_in_rsp),
    .narrow_out_req_o       (cluster_narrow_out_req),
    .narrow_out_resp_i      (cluster_narrow_out_rsp),
    .wide_out_req_o         (cluster_wide_out_req),
    .wide_out_resp_i        (cluster_wide_out_rsp),
    .wide_in_req_i          (cluster_wide_in_req),
    .wide_in_resp_o         (cluster_wide_in_rsp),
    .x_issue_req_o          (x_issue_req),
    .x_issue_resp_i         (x_issue_resp),
    .x_issue_valid_o        (x_issue_valid),
    .x_issue_ready_i        (x_issue_ready),
    .x_register_o           (x_register),
    .x_register_valid_o     (x_register_valid),
    .x_register_ready_i     (x_register_ready),
    .x_commit_o             (x_commit),
    .x_commit_valid_o       (x_commit_valid),
    .x_result_i             (x_result),
    .x_result_valid_i       (x_result_valid),
    .x_result_ready_o       (x_result_ready),
    .tcdm_wide_ext_req_i    (cluster_tcdm_wide_ext_req),
    .tcdm_wide_ext_resp_o   (cluster_tcdm_wide_ext_rsp),
    .tcdm_narrow_ext_req_i  (cluster_tcdm_narrow_ext_req),
    .tcdm_narrow_ext_resp_o (cluster_tcdm_narrow_ext_rsp),
    .barrier_i              (barrier),
    .hive_req_i             (hive_req),
    .core_events_i          (core_events),
    .barrier_o              (out_barrier),
    .hive_rsp_o             (hive_rsp),
    .cl_interrupt_o         (cl_interrupt),
    .pace_param_o           (pace_param),
    .dca_req_i ('0),
    .dca_rsp_o (),
    .cluster_base_offset_i (snitch_cluster_pkg::CfgClusterBaseOffset),
    .narrow_ext_resp_i ('0),
    .narrow_ext_req_o()
  );

  snitch_cluster_pkg::x_issue_req_t x_issue_req_nohartid;
  snitch_cluster_pkg::x_register_t x_register_nohartid;
  snitch_cluster_pkg::x_commit_t x_commit_nohartid;

  assign x_issue_req_nohartid = '{
    instr: x_issue_req.instr,
    hartid: '0,
    id: x_issue_req.id
  };

  assign x_register_nohartid = '{
    hartid: '0,
    id: x_register.id,
    rs: x_register.rs,
    rs_valid: x_register.rs_valid
  };

  assign x_commit_nohartid = '{
    hartid: '0,
    id: x_commit.id,
    commit_kill: x_commit.commit_kill
  };

  snitch_fsync_stub #(
    .FsSyncOpCode          (7'b0001011),
    .FsSyncIOpCode         (7'b0001011),
    .FsClrOpCode           (7'b0001011),
    .FsSyncFunct3          (3'b100),
    .FsSyncIFunct3         (3'b100),
    .FsClrFunct3           (3'b101),
    .FsSyncFunct2          (2'b00),
    .FsSyncIFunct2         (2'b01),
    .FsClrFunct2           (2'b00),
    .InstFifoDepth         (2),
    .XifIdWidth            (snitch_cluster_pkg::XifIdWidth),
    .XifNumHarts           (1),
    .XifIssueRegisterSplit (0),
    .NrFsyncLvls           (picobello_pkg::NrFsyncLvls),
    .x_issue_req_t         (snitch_cluster_pkg::x_issue_req_t),
    .x_issue_resp_t        (snitch_cluster_pkg::x_issue_resp_t),
    .x_register_t          (snitch_cluster_pkg::x_register_t),
    .x_commit_t            (snitch_cluster_pkg::x_commit_t),
    .x_result_t            (snitch_cluster_pkg::x_result_t),
    .fsync_req_t           (picobello_pkg::fsync_req_t),
    .fsync_rsp_t           (picobello_pkg::fsync_rsp_t)
  ) i_fsync_stub (
    .clk_i              (tile_clk),
    .rst_ni             (tile_rst_n),
    .clear_i            ('0),
    .x_issue_req_i      (x_issue_req_nohartid),
    .x_issue_resp_o     (x_issue_resp),
    .x_issue_valid_i    (x_issue_valid),
    .x_issue_ready_o    (x_issue_ready),
    .x_register_i       (x_register_nohartid),
    .x_register_valid_i (x_register_valid),
    .x_register_ready_o (x_register_ready),
    .x_commit_i         (x_commit_nohartid),
    .x_commit_valid_i   (x_commit_valid),
    .x_result_o         (x_result),
    .x_result_valid_o   (x_result_valid),
    .x_result_ready_i   (x_result_ready),
    .fsync_req_ht_o,
    .fsync_rsp_ht_i,
    .fsync_req_hn_o,
    .fsync_rsp_hn_i,
    .fsync_req_vt_o,
    .fsync_rsp_vt_i,
    .fsync_req_vn_o,
    .fsync_rsp_vn_i,
    .irq_o              (mxip)
  );

  localparam int unsigned NrRedH = 2;
  localparam int unsigned NrRedW = 2;

  assign redmule_sync_rsp = &redmule_sync_req;

  hwpe_stream_intf_stream #( .DATA_WIDTH ( ExtDataWidth ) ) w_streams [0:(NrRedH)*(NrRedW+1)-1] ( .clk( clk_i ) );
  hwpe_stream_intf_stream #( .DATA_WIDTH ( ExtDataWidth ) ) x_streams [0:(NrRedH+1)*(NrRedW)-1] ( .clk( clk_i ) );

  for (genvar i = 0; i < NrRedH; i++) begin : assign_w_streams
    assign w_streams[i*(NrRedW+1)].valid = '0;
    assign w_streams[i*(NrRedW+1)].data  = '0;
    assign w_streams[i*(NrRedW+1)].strb  = '0;
    assign w_streams[i*(NrRedW+1)+NrRedW].ready = '1;
  end

  for (genvar j = 0; j < NrRedW; j++) begin : assign_x_streams
    assign x_streams[j].valid = '0;
    assign x_streams[j].data  = '0;
    assign x_streams[j].strb  = '0;
    assign x_streams[NrRedH*NrRedW+j].ready = '1;
  end


localparam fpnew_pkg::fpu_implementation_t MicroFPUImplementation [1] = '{
  '{
      PipeRegs: // FMA Block
                '{
                  '{  3, // FP32
                      3, // FP64
                      3, // FP16
                      3, // FP8
                      3, // FP16alt
                      3,  // FP8alt
                      0, // FP6
                      0, // FP6alt
                      0  // FP4
                    },
                  '{1, 1, 1, 1, 1, 1, 0, 0, 0},   // DIVSQRT
                  '{1,
                    1,
                    1,
                    1,
                    1,
                    1,
                    0, 0, 0},   // NONCOMP
                  '{2,
                    2,
                    2,
                    2,
                    2,
                    2,
                    0, 0, 0},   // CONV
                  '{3,
                    3,
                    3,
                    3,
                    3,
                    3,
                    0, 0, 0},    // DOTP
                  '{4,
                    4,
                    4,
                    4,
                    4,
                    4,
                    4,
                    4,
                    4}    // MXDOTP
                  },
      UnitTypes: '{'{fpnew_pkg::MERGED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::MERGED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED},  // FMA
                  '{fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED}, // DIVSQRT
                  '{fpnew_pkg::PARALLEL,
                      fpnew_pkg::PARALLEL,
                      fpnew_pkg::PARALLEL,
                      fpnew_pkg::PARALLEL,
                      fpnew_pkg::PARALLEL,
                      fpnew_pkg::PARALLEL,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED}, // NONCOMP
                  '{fpnew_pkg::MERGED,
                      fpnew_pkg::MERGED,
                      fpnew_pkg::MERGED,
                      fpnew_pkg::MERGED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED},   // CONV
                  '{fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED}, // DOTP
                  '{fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED,
                      fpnew_pkg::DISABLED}},  // MXDOTP
      PipeConfig: fpnew_pkg::INSIDE
    }
  };


  for (genvar i = 0; i < NrRedH; i++) begin : gen_ccc_h
    for (genvar j = 0; j < NrRedW; j++) begin : gen_ccc_w
      micro_cluster #(
        .AddrWidth              (snitch_cluster_pkg::AddrWidth),
        .NarrowDataWidth        (snitch_cluster_pkg::NarrowDataWidth),
        .WideDataWidth          (snitch_cluster_pkg::ExtDataWidth),
        .TCDMAddrWidth          (snitch_cluster_pkg::TcdmAddrWidth),
        .NrBanksL0              (8),
        .TCDMDepthL0            (512),
        .BootAddr               (32'h30020000),
        .RVE                    (0),
        .RVM                    (1),
        .RVF                    (1),
        .RVD                    (0),
        .XDivSqrt               (1),
        .XF16                   (1),
        .XF8                    (1),
        .XF8ALT                 (1),
        .XFVEC                  (1),
        .XFDOTP                 (0),
        .Xfrep                  (1),
        .Xssr                   (1),
        .Xcopift                (1),
        .PaceCfg                (snitch_cluster_pkg::PaceCfg),
        .NumIntOutstandingLoads (4),
        .NumIntOutstandingMem   (4),
        .NumFPOutstandingLoads  (4),
        .NumFPOutstandingMem    (4),
        .FPUImplementation      (MicroFPUImplementation[0]),
        .NumDTLBEntries         (1),
        .NumITLBEntries         (1),
        .NumSequencerInstr      (16),
        .NumSequencerLoops      (1),
        .NumSsrs                (3),
        .SsrMuxRespDepth        (4),
        .SsrCfgs                (SsrCfg),
        .SsrRegs                ('{2,1,0}),
        .RegisterOffloadReq     (1),
        .RegisterOffloadRsp     (1),
        .RegisterCoreReq        (1),
        .RegisterCoreRsp        (1),
        .RegisterTCDMCuts       (0),
        .RegisterFPUReq         (1),
        .RegisterSequencer      (0),
        .RegisterFPUIn          (0),
        .RegisterFPUOut         (0),
        .CaqDepth               (8),
        .CaqTagWidth            (16),
        .MemoryMacroLatency     (1),
        .wide_tcdm_req_t        (snitch_cluster_pkg::tcdm_ext_req_t),
        .wide_tcdm_rsp_t        (snitch_cluster_pkg::tcdm_ext_rsp_t),
        .narrow_tcdm_req_t      (snitch_cluster_pkg::tcdm_req_t),
        .narrow_tcdm_rsp_t      (snitch_cluster_pkg::tcdm_rsp_t),
        .hive_req_t             (snitch_cluster_pkg::hive_req_t),
        .hive_rsp_t             (snitch_cluster_pkg::hive_rsp_t),
        .pace_param_t           (snitch_cluster_pkg::pace_param_t),
        .pace_cfg_t             (snitch_cluster_pkg::pace_cfg_t)
      ) i_ccc (
        .clk_i (tile_clk),
        .rst_ni (tile_rst_n),
        .hart_id_i (hart_base_id_i + i*NrRedW + j + 1),
        .tcdm_addr_base_i (cluster_base_addr_i),
        .wide_tcdm_req_o (cluster_tcdm_wide_ext_req[i*NrRedW + j]),
        .wide_tcdm_rsp_i (cluster_tcdm_wide_ext_rsp[i*NrRedW + j]),
        .narrow_tcdm_req_o (cluster_tcdm_narrow_ext_req[i*NrRedW + j]),
        .narrow_tcdm_rsp_i (cluster_tcdm_narrow_ext_rsp[i*NrRedW + j]),
        .mcip_i (cl_interrupt[i*NrRedW + j]),
        .hive_req_o (hive_req[i*NrRedW + j]),
        .hive_rsp_i (hive_rsp[i*NrRedW + j]),
        .barrier_o (barrier[i*NrRedW + j]),
        .barrier_i (out_barrier),
        .sync_o (redmule_sync_req[i*NrRedW + j]),
        .sync_i (redmule_sync_rsp),
        .w_stream_i (w_streams[i*(NrRedW+1)+j]),
        .x_stream_i (x_streams[i*NrRedW+j]),
        .w_stream_o (w_streams[i*(NrRedW+1)+j+1]),
        .x_stream_o (x_streams[(i+1)*NrRedW+j]),
        .pace_param_i (pace_param)
      );
    end
  end

  ////////////
  // Router //
  ////////////

  floo_req_t [Eject:North] router_floo_req_out, router_floo_req_in;
  floo_rsp_t [Eject:North] router_floo_rsp_out, router_floo_rsp_in;
  floo_wide_t [Eject:North] router_floo_wide_out, router_floo_wide_in;

  floo_nw_router #(
    .AxiCfgN     (AxiCfgN),
    .AxiCfgW     (AxiCfgW),
    .EnMultiCast (RouteCfg.EnMultiCast),
    .RouteAlgo   (RouteCfg.RouteAlgo),
    .NumRoutes   (5),
    .InFifoDepth (2),
    .OutFifoDepth(2),
    .id_t        (id_t),
    .hdr_t       (hdr_t),
    .floo_req_t  (floo_req_t),
    .floo_rsp_t  (floo_rsp_t),
    .floo_wide_t (floo_wide_t)
  ) i_router (
    .clk_i,
    .rst_ni,
    .test_enable_i,
    .id_i,
    .id_route_map_i('0),
    .floo_req_i    (router_floo_req_in),
    .floo_rsp_o    (router_floo_rsp_out),
    .floo_req_o    (router_floo_req_out),
    .floo_rsp_i    (router_floo_rsp_in),
    .floo_wide_i   (router_floo_wide_in),
    .floo_wide_o   (router_floo_wide_out)
  );

  assign floo_req_o                      = router_floo_req_out[West:North];
  assign router_floo_req_in[West:North]  = floo_req_i;
  assign floo_rsp_o                      = router_floo_rsp_out[West:North];
  assign router_floo_rsp_in[West:North]  = floo_rsp_i;
  assign floo_wide_o                     = router_floo_wide_out[West:North];
  assign router_floo_wide_in[West:North] = floo_wide_i;

  /////////////
  // Chimney //
  /////////////

  floo_nw_chimney #(
    .AxiCfgN             (floo_picobello_noc_pkg::AxiCfgN),
    .AxiCfgW             (floo_picobello_noc_pkg::AxiCfgW),
    .ChimneyCfgN         (floo_pkg::ChimneyDefaultCfg),
    .ChimneyCfgW         (floo_pkg::ChimneyDefaultCfg),
    .RouteCfg            (floo_picobello_noc_pkg::RouteCfg),
    .AtopSupport         (1'b1),
    .MaxAtomicTxns       (1),
    .Sam                 (picobello_pkg::SamMcast),
    .id_t                (floo_picobello_noc_pkg::id_t),
    .rob_idx_t           (floo_picobello_noc_pkg::rob_idx_t),
    .hdr_t               (floo_picobello_noc_pkg::hdr_t),
    .sam_rule_t          (picobello_pkg::sam_multicast_rule_t),
    .sam_idx_t           (picobello_pkg::sam_idx_t),
    .mask_sel_t          (picobello_pkg::mask_sel_t),
    .axi_narrow_in_req_t (snitch_cluster_pkg::narrow_out_req_t),
    .axi_narrow_in_rsp_t (snitch_cluster_pkg::narrow_out_resp_t),
    .axi_narrow_out_req_t(snitch_cluster_pkg::narrow_in_req_t),
    .axi_narrow_out_rsp_t(snitch_cluster_pkg::narrow_in_resp_t),
    .axi_wide_in_req_t   (snitch_cluster_pkg::wide_out_req_t),
    .axi_wide_in_rsp_t   (snitch_cluster_pkg::wide_out_resp_t),
    .axi_wide_out_req_t  (snitch_cluster_pkg::wide_in_req_t),
    .axi_wide_out_rsp_t  (snitch_cluster_pkg::wide_in_resp_t),
    .floo_req_t          (floo_picobello_noc_pkg::floo_req_t),
    .floo_rsp_t          (floo_picobello_noc_pkg::floo_rsp_t),
    .floo_wide_t         (floo_picobello_noc_pkg::floo_wide_t),
    .sram_cfg_t          (snitch_cluster_pkg::sram_cfg_t),
    .user_struct_t       (picobello_pkg::mcast_user_t)
  ) i_chimney (
    .clk_i               (tile_clk),
    .rst_ni              (tile_rst_n),
    .test_enable_i,
    .id_i,
    .route_table_i       ('0),
    .sram_cfg_i          ('0),
    .axi_narrow_in_req_i (cluster_narrow_out_req),
    .axi_narrow_in_rsp_o (cluster_narrow_out_rsp),
    .axi_narrow_out_req_o(cluster_narrow_in_req),
    .axi_narrow_out_rsp_i(cluster_narrow_in_rsp),
    .axi_wide_in_req_i   (cluster_wide_out_req),
    .axi_wide_in_rsp_o   (cluster_wide_out_rsp),
    .axi_wide_out_req_o  (cluster_wide_in_req),
    .axi_wide_out_rsp_i  (cluster_wide_in_rsp),
    .floo_req_o          (router_floo_req_in[Eject]),
    .floo_rsp_o          (router_floo_rsp_in[Eject]),
    .floo_wide_o         (router_floo_wide_in[Eject]),
    .floo_req_i          (router_floo_req_out[Eject]),
    .floo_rsp_i          (router_floo_rsp_out[Eject]),
    .floo_wide_i         (router_floo_wide_out[Eject])
  );

  //////////////////////////
  // Clock Gating & Reset //
  //////////////////////////

  tc_clk_gating i_tc_clk_gating_cluster (
    .clk_i,
    .en_i     (tile_clk_en_i),
    .test_en_i(clk_rst_bypass_i),
    .clk_o    (tile_clk)
  );

`ifdef TARGET_XILINX
  // Using clk cells makes Vivado flag the reset as a clock tree
  assign tile_rst_n = (clk_rst_bypass_i) ? rst_ni : tile_rst_ni;
`else
  tc_clk_mux2 i_tc_reset_mux (
    .clk0_i   (tile_rst_ni),
    .clk1_i   (rst_ni),
    .clk_sel_i(clk_rst_bypass_i),
    .clk_o    (tile_rst_n)
  );
`endif



endmodule
