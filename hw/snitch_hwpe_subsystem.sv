// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

`include "hci_helpers.svh"

module snitch_hwpe_subsystem
  import hci_package::*;
  import hwpe_ctrl_package::*;
  import reqrsp_pkg::amo_op_e;
#(
  parameter type         tcdm_req_t    = logic,
  parameter type         tcdm_rsp_t    = logic,
  parameter type         periph_req_t  = logic,
  parameter type         periph_rsp_t  = logic,
  parameter int unsigned HwpeDataWidth = 256,
  parameter int unsigned IdWidth       = 8,
  parameter int unsigned NrCores       = 8,
  parameter int unsigned NrPorts       = NrCores,
  parameter int unsigned TCDMDataWidth = 64,
  parameter int unsigned XifNumHarts           = 1,
  parameter int unsigned XifIdWidth            = 1,
  parameter int unsigned XifIssueRegisterSplit = 0,
  parameter int unsigned NrRedW = 1,
  parameter int unsigned NrRedH = 1,
  // XIF types
  parameter type         x_issue_req_t          = logic,
  parameter type         x_issue_resp_t         = logic,
  parameter type         x_register_t           = logic,
  parameter type         x_commit_t             = logic,
  parameter type         x_result_t             = logic
) (
  input logic clk_i,
  input logic rst_ni,
  input logic test_mode_i,

  // TCDM interface (Master)
  output tcdm_req_t     [NrPorts-1:0] tcdm_req_o,
  input  tcdm_rsp_t     [NrPorts-1:0] tcdm_rsp_i,

  input  x_issue_req_t  [NrCores-1:0] x_issue_req_i      ,
  output x_issue_resp_t [NrCores-1:0] x_issue_resp_o     ,
  input  logic          [NrCores-1:0] x_issue_valid_i    ,
  output logic          [NrCores-1:0] x_issue_ready_o    ,
  input  x_register_t   [NrCores-1:0] x_register_i       ,
  input  logic          [NrCores-1:0] x_register_valid_i ,
  output logic          [NrCores-1:0] x_register_ready_o ,
  input  x_commit_t     [NrCores-1:0] x_commit_i         ,
  input  logic          [NrCores-1:0] x_commit_valid_i   ,
  output x_result_t     [NrCores-1:0] x_result_o         ,
  output logic          [NrCores-1:0] x_result_valid_o   ,
  input  logic          [NrCores-1:0] x_result_ready_i   ,

  output logic [NrCores-1:0] hwpe_evt_o,

  // Inter-CCC network
  hwpe_stream_intf_stream.sink    w_stream_i ,
  hwpe_stream_intf_stream.sink    x_stream_i ,
  hwpe_stream_intf_stream.source  w_stream_o ,
  hwpe_stream_intf_stream.source  x_stream_o
);

  localparam int unsigned NrTCDMPorts = (HwpeDataWidth / TCDMDataWidth);

  // verilog_format: off
  localparam hci_size_parameter_t HCISizeTcdm = '{
    DW:  HwpeDataWidth,
    AW:  DEFAULT_AW,
    BW:  DEFAULT_BW,
    UW:  DEFAULT_UW,
    IW:  DEFAULT_IW,
    EW:  0,
    EHW: 0
  };
  // verilog_format: on

  logic [1:0]                   hwpe_clk;
  logic [1:0]                   clk_en;
  logic                         mux_sel;

  // Currently unused
  logic [1:0][NrCores-1:0][1:0] evt;
  logic                         busy;

  // Machine HWPE Interrupt
  logic [NrCores-1:0] hwpe_evt_d, hwpe_evt_q;

  hci_core_intf #(
`ifndef SYNTHESIS
    .WAIVE_RSP3_ASSERT(1'b1),
    .WAIVE_RSP5_ASSERT(1'b1),
`endif
    .DW               (HwpeDataWidth),
    .EW               (0),
    .EHW              (0)
  ) tcdm[0:NrPorts-1] (
    .clk(clk_i)
  );

  // No Datamover
  //assign hwpe_evt_o[NrCores-1] = '0;
  //assign hwpe_evt_o[NrCores-2:NrPorts] = '0;

  //assign x_issue_resp_o [NrCores-2:NrRedH*NrRedW] = '0;
  //assign x_issue_ready_o [NrCores-2:NrRedH*NrRedW] = '0;
  //assign x_register_ready_o [NrCores-2:NrRedH*NrRedW] = '0;
  //assign x_result_o [NrCores-2:NrRedH*NrRedW] = '0;
  //assign x_result_valid_o [NrCores-2:NrRedH*NrRedW] = '0;

  // No Datamover for now
  //assign x_issue_resp_o [NrCores-1] = '0;
  //assign x_issue_ready_o [NrCores-1] = '0;
  //assign x_register_ready_o [NrCores-1] = '0;
  //assign x_result_o [NrCores-1] = '0;
  //assign x_result_valid_o [NrCores-1] = '0;

  for (genvar i = 0; i < NrRedH; i++) begin
    for (genvar j = 0; j < NrRedW; j++) begin
      x_issue_req_t x_issue_req_local;
      x_register_t  x_register_local;
      x_commit_t    x_commit_local;

      always_comb begin
        x_issue_req_local        = x_issue_req_i[i*NrRedW+j];
        x_issue_req_local.hartid = '0;
        x_register_local         = x_register_i[i*NrRedW+j];
        x_register_local.hartid  = '0;
        x_commit_local           = x_commit_i[i*NrRedW+j];
        x_commit_local.hartid    = '0;
      end

      // request channel
      assign tcdm_req_o[i*NrRedW+j].q_valid = tcdm[i*NrRedW+j].req;
      assign tcdm_req_o[i*NrRedW+j].q.addr  = tcdm[i*NrRedW+j].add;
      assign tcdm_req_o[i*NrRedW+j].q.write = ~tcdm[i*NrRedW+j].wen;
      assign tcdm_req_o[i*NrRedW+j].q.strb  = tcdm[i*NrRedW+j].be;
      assign tcdm_req_o[i*NrRedW+j].q.data  = tcdm[i*NrRedW+j].data;
      assign tcdm_req_o[i*NrRedW+j].q.amo   = reqrsp_pkg::AMONone;
      assign tcdm_req_o[i*NrRedW+j].q.user  = '0;
      // response channel
      assign tcdm[i*NrRedW+j].gnt           = tcdm_rsp_i[i*NrRedW+j].q_ready;
      assign tcdm[i*NrRedW+j].r_valid       = tcdm_rsp_i[i*NrRedW+j].p_valid;
      assign tcdm[i*NrRedW+j].r_data        = tcdm_rsp_i[i*NrRedW+j].p.data;
      assign tcdm[i*NrRedW+j].r_opc         = '0;
      assign tcdm[i*NrRedW+j].r_user        = '0;

      redmule_top #(
        .DataW (HwpeDataWidth),
        //.FpFormat (),
        .Height (HwpeDataWidth/32),
        .Width (HwpeDataWidth/32),
        .NumPipeRegs (1),
        .McnfigOpCode (7'b0001011),
        .MarithOpCode (7'b0001011),
        .MopcntOpCode (7'b0001011),
        .XifNumHarts (XifNumHarts),
        .XifIdWidth (XifIdWidth),
        .XifIssueRegisterSplit (XifIssueRegisterSplit),
        .x_issue_req_t (x_issue_req_t),
        .x_issue_resp_t (x_issue_resp_t),
        .x_register_t (x_register_t),
        .x_commit_t (x_commit_t),
        .x_result_t (x_result_t),
        .HCI_SIZE_tcdm(HCISizeTcdm)
      ) i_redmule_top (
        .clk_i      (clk_i),
        .rst_ni     (rst_ni),
        .test_mode_i(test_mode_i),
        .evt_o      (hwpe_evt_o[i*NrRedW+j]),
        .busy_o     (),
        .w_stream_i (w_stream_i),
        .w_stream_o (w_stream_o),
        .x_stream_i (x_stream_i),
        .x_stream_o (x_stream_o),
        .x_issue_req_i (x_issue_req_local),
        .x_issue_resp_o (x_issue_resp_o[i*NrRedW+j]),
        .x_issue_valid_i (x_issue_valid_i[i*NrRedW+j]),
        .x_issue_ready_o (x_issue_ready_o[i*NrRedW+j]),
        .x_register_i (x_register_local),
        .x_register_valid_i (x_register_valid_i[i*NrRedW+j]),
        .x_register_ready_o (x_register_ready_o[i*NrRedW+j]),
        .x_commit_i (x_commit_local),
        .x_commit_valid_i (x_commit_valid_i[i*NrRedW+j]),
        .x_result_o (x_result_o[i*NrRedW+j]),
        .x_result_valid_o (x_result_valid_o[i*NrRedW+j]),
        .x_result_ready_i (x_result_ready_i[i*NrRedW+j]),
        .tcdm       (tcdm[i*NrRedW+j])
      );
    end
  end

endmodule : snitch_hwpe_subsystem
