// Copyright 2025 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51
//
// Andrea Belano <andrea.belano2@unibo.it>
//

module snitch_fsync_stub
#(
  parameter logic [6:0]   FsSyncOpCode          = 7'b0001011,
  parameter logic [6:0]   FsSyncIOpCode         = 7'b0001011,
  parameter logic [6:0]   FsClrOpCode           = 7'b0001011,
  parameter logic [2:0]   FsSyncFunct3          = 3'b100,
  parameter logic [2:0]   FsSyncIFunct3         = 3'b100,
  parameter logic [2:0]   FsClrFunct3           = 3'b101,
  parameter logic [1:0]   FsSyncFunct2          = 2'b00,
  parameter logic [1:0]   FsSyncIFunct2         = 2'b01,
  parameter logic [1:0]   FsClrFunct2           = 2'b00,
  parameter  int unsigned InstFifoDepth         = 4,
  parameter  int unsigned XifIdWidth            = 4,
  parameter  int unsigned XifNumHarts           = 1,
  parameter  int unsigned XifIssueRegisterSplit = 0,
  parameter  int unsigned NrFsyncLvls           = 1,
  parameter type          x_issue_req_t         = logic,
  parameter type          x_issue_resp_t        = logic,
  parameter type          x_register_t          = logic,
  parameter type          x_commit_t            = logic,
  parameter type          x_result_t            = logic,
  parameter type          fsync_req_t           = logic,
  parameter type          fsync_rsp_t           = logic
)(
  input  logic                   clk_i,
  input  logic                   rst_ni,
  input  logic                   clear_i,
  input  x_issue_req_t           x_issue_req_i,
  output x_issue_resp_t          x_issue_resp_o,
  input  logic                   x_issue_valid_i,
  output logic                   x_issue_ready_o,
  input  x_register_t            x_register_i,
  input  logic                   x_register_valid_i,
  output logic                   x_register_ready_o,
  input  x_commit_t              x_commit_i,
  input  logic                   x_commit_valid_i,
  output x_result_t              x_result_o,
  output logic                   x_result_valid_o,
  input  logic                   x_result_ready_i,
  output fsync_req_t             fsync_req_ht_o,
  input  fsync_rsp_t             fsync_rsp_ht_i,
  output fsync_req_t             fsync_req_hn_o,
  input  fsync_rsp_t             fsync_rsp_hn_i,
  output fsync_req_t             fsync_req_vt_o,
  input  fsync_rsp_t             fsync_rsp_vt_i,
  output fsync_req_t             fsync_req_vn_o,
  input  fsync_rsp_t             fsync_rsp_vn_i,
  output logic [XifNumHarts-1:0] irq_o
);

  localparam int unsigned AggrWidthRs = NrFsyncLvls;
  localparam int unsigned IdWidthRs   = NrFsyncLvls - 3;

  localparam int unsigned HartIdWidth = XifNumHarts > 1 ? $clog2(XifNumHarts) : 1;

  localparam logic [11:0] FSSYNC  = {FsSyncFunct2,FsSyncFunct3,FsSyncOpCode};
  localparam logic [11:0] FSSYNCI = {FsSyncIFunct2,FsSyncIFunct3,FsSyncIOpCode};
  localparam logic [11:0] FSCLR   = {FsClrFunct2,FsClrFunct3,FsClrOpCode};

  logic [XifNumHarts-1:0] issue_fifo_full,  register_fifo_full,
                          issue_fifo_empty, register_fifo_empty;

  x_issue_req_t [XifNumHarts-1:0] cur_issue;
  x_register_t  [XifNumHarts-1:0] cur_register;

  logic [HartIdWidth-1:0]                  rr_counter_d, rr_counter_q;
  logic [XifNumHarts-1:0][HartIdWidth-1:0] rr_priority;
  logic [HartIdWidth-1:0]                  winner;

  logic legal_inst;

  logic pop_enable;

  logic [XifNumHarts-1:0] irq_q;
  logic                   irq_en;
  logic [XifNumHarts-1:0] irq_clr;

  logic [XifNumHarts-1:0][1:0] sync_num_ht, sync_num_vt;
  logic [XifNumHarts-1:0]      sync_num_hn, sync_num_vn;
  logic [XifNumHarts-1:0]      sync_num_valid;

  fsync_req_t [XifNumHarts-1:0] fsync_req_ht;
  fsync_req_t [XifNumHarts-1:0] fsync_req_hn;
  fsync_req_t [XifNumHarts-1:0] fsync_req_vt;
  fsync_req_t [XifNumHarts-1:0] fsync_req_vn;

  always_comb begin : legal_inst_assignment
    legal_inst = 1'b0;

    if ({x_issue_req_i.instr[26:25],x_issue_req_i.instr[14:12],x_issue_req_i.instr[6:0]} inside {FSSYNC,FSSYNCI,FSCLR})
      legal_inst = 1'b1;
  end

  always_comb begin : x_issue_resp_assignment
    x_issue_resp_o.accept = legal_inst;

    unique case ({x_issue_req_i.instr[26:25],x_issue_req_i.instr[14:12],x_issue_req_i.instr[6:0]})
      FSSYNC: begin
        x_issue_resp_o.writeback     = 'b0;
        x_issue_resp_o.register_read = 'b111;
      end
      FSSYNCI: begin
        x_issue_resp_o.writeback     = 'b0;
        x_issue_resp_o.register_read = 'b000;
      end
      FSCLR: begin
        x_issue_resp_o.writeback     = 'b0;
        x_issue_resp_o.register_read = 'b000;
      end
      default: begin
        x_issue_resp_o.writeback     = 'b0;
        x_issue_resp_o.register_read = 'b0;
      end
    endcase
  end


  always_comb begin : x_result_assignment
    x_result_valid_o  = ~issue_fifo_empty[winner] && ~register_fifo_empty[winner];
    x_result_o.hartid = cur_issue[winner].hartid;
    x_result_o.id     = cur_issue[winner].id;
    x_result_o.rd     = cur_issue[winner].instr[11:7];

    unique case ({cur_issue[winner].instr[26:25],cur_issue[winner].instr[14:12],cur_issue[winner].instr[6:0]})
      FSSYNC: begin
        x_result_o.we   = 'b0;
        x_result_o.data = 'b0;
      end
      FSSYNCI: begin
        x_result_o.we   = 'b0;
        x_result_o.data = 'b0;
      end
      FSCLR: begin
        x_result_o.we   = 'b0;
        x_result_o.data = 'b0;
      end
      default: begin
        x_result_o.we   = 'b0;
        x_result_o.data = 'b0;
      end
    endcase
  end

  always_comb begin : x_issue_ready_assignment
    x_issue_ready_o = 1'b0;

    for (int unsigned i = 0; i < XifNumHarts; i++) begin
      if (x_issue_req_i.hartid == i) begin
        x_issue_ready_o = ~issue_fifo_full[i];
      end
    end
  end

  always_comb begin : x_register_ready_assignment
    x_register_ready_o = 1'b0;

    for (int unsigned i = 0; i < XifNumHarts; i++) begin
      if (x_register_i.hartid == i) begin
        x_register_ready_o = ~register_fifo_full[i];
      end
    end
  end

  always_ff @(posedge clk_i, negedge rst_ni) begin : round_robin_counter
    if(~rst_ni) begin
      rr_counter_q <= '0;
    end else begin
      if (clear_i) begin
        rr_counter_q <= '0;
      end else if (irq_o[winner] && irq_clr[winner]) begin
        rr_counter_q <= rr_counter_d;
      end
    end
  end

  assign rr_counter_d = rr_counter_q == XifNumHarts-1 ? 0 : rr_counter_q + 1;

  always_comb begin : round_robin_priority
    for(int i = 0; i < XifNumHarts; i++) begin
      rr_priority[i] = (rr_counter_q + i < XifNumHarts) ? rr_counter_q + i : rr_counter_q + i - XifNumHarts;
    end
  end

  always_comb begin : winner_assignment
    winner = rr_counter_q;

    for(int i = 0; i < XifNumHarts; i++) begin
      if (~issue_fifo_empty[rr_priority[i]] && ~register_fifo_empty[rr_priority[i]]) begin
        winner = rr_priority[i];
      end
    end
  end

  // Pop the fifos the first as soon as we detect an FSSYNC(I) instruction or all the requested synchronizations are done
  always_comb begin
    pop_enable = 1'b1;

    if ({cur_issue[winner].instr[26:25],cur_issue[winner].instr[14:12],cur_issue[winner].instr[6:0]} inside {FSSYNC,FSSYNCI})
      pop_enable = irq_en;
  end

  for (genvar i = 0; i < XifNumHarts; i++) begin : gen_instruction_fifos
    logic [XifIdWidth-1:0] commit_id_d, commit_id_q,
                           kill_id_d, kill_id_q;

    logic commit_id_valid_d, commit_id_valid_q,
          kill_id_valid_d, kill_id_valid_q;

    logic commit_id_valid_flush,
          kill_id_valid_flush;

    logic fifo_flush;

    logic issue_push, register_push,
          issue_pop,  register_pop;

    logic [$clog2(InstFifoDepth)-1:0] issue_util;

    always_ff @(posedge clk_i or negedge rst_ni) begin : commit_id_register
      if (~rst_ni) begin
        commit_id_q <= '0;
      end else begin
        if (clear_i) begin
          commit_id_q <= '0;
        end else begin
          commit_id_q <= commit_id_d;
        end
      end
    end

    assign commit_id_d = (x_commit_valid_i && ~x_commit_i.commit_kill && x_commit_i.hartid == i) ? x_commit_i.id : commit_id_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin : commid_id_valid_register
      if (~rst_ni) begin
        commit_id_valid_q <= 1'b0;
      end else begin
        if (clear_i || commit_id_valid_flush) begin
          commit_id_valid_q <= 1'b0;
        end else begin
          commit_id_valid_q <= commit_id_valid_d;
        end
      end
    end

    assign commit_id_valid_d     = (x_commit_valid_i && ~x_commit_i.commit_kill && x_commit_i.hartid == i) ? 1'b1 : commit_id_valid_q;
    assign commit_id_valid_flush = issue_pop && cur_issue[i].id == commit_id_d && ~issue_fifo_empty[i];

    always_ff @(posedge clk_i or negedge rst_ni) begin : kill_id_register
      if (~rst_ni) begin
        kill_id_q <= '0;
      end else begin
        if (clear_i) begin
          kill_id_q <= '0;
        end else begin
          kill_id_q <= kill_id_d;
        end
      end
    end

    assign kill_id_d = (x_commit_valid_i && x_commit_i.commit_kill && x_commit_i.hartid == i) ? x_commit_i.id : kill_id_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin : kill_id_valid_register
      if (~rst_ni) begin
        kill_id_valid_q <= 1'b0;
      end else begin
        if (clear_i || kill_id_valid_flush) begin
          kill_id_valid_q <= 1'b0;
        end else begin
          kill_id_valid_q <= kill_id_valid_d;
        end
      end
    end

    assign kill_id_valid_d       = (x_commit_valid_i && x_commit_i.commit_kill && x_commit_i.hartid == i) ? 1'b1 : kill_id_valid_q;
    assign kill_id_valid_flush   = fifo_flush;

    assign fifo_flush   = cur_issue[i].id == kill_id_d && kill_id_valid_d && ~issue_fifo_empty[i];

    assign issue_push   = x_issue_valid_i && legal_inst && ~issue_fifo_full[i] && x_commit_i.hartid == i;
    assign issue_pop    = winner == i && pop_enable && x_result_ready_i && ~issue_fifo_empty[i] && ~register_fifo_empty[i];
    assign register_pop = issue_pop;

    fifo_v3 #(
      .FALL_THROUGH ( 0             ),
      .DEPTH        ( InstFifoDepth ),
      .dtype        ( x_issue_req_t )
    ) i_instr_fifo (
      .clk_i      ( clk_i                 ),
      .rst_ni     ( rst_ni                ),
      .flush_i    ( clear_i || fifo_flush ),
      .testmode_i ( '0                    ),
      .full_o     ( issue_fifo_full[i]    ),
      .empty_o    ( issue_fifo_empty[i]   ),
      .usage_o    ( issue_util            ),
      .data_i     ( x_issue_req_i         ),
      .push_i     ( issue_push            ),
      .data_o     ( cur_issue[i]          ),
      .pop_i      ( issue_pop             )
    );

    if (XifIssueRegisterSplit == 0) begin : gen_register_fifo // Register packets are guaranteed to arrive at the same time as the issue signal
      assign register_push = x_register_valid_i & legal_inst & x_commit_i.hartid == i;

      fifo_v3 #(
        .FALL_THROUGH ( 0             ),
        .DEPTH        ( InstFifoDepth ),
        .dtype        ( x_register_t  )
      ) i_instr_fifo (
        .clk_i      ( clk_i                  ),
        .rst_ni     ( rst_ni                 ),
        .flush_i    ( clear_i || fifo_flush  ),
        .testmode_i ( '0                     ),
        .full_o     ( register_fifo_full[i]  ),
        .empty_o    ( register_fifo_empty[i] ),
        .usage_o    (                        ),
        .data_i     ( x_register_i           ),
        .push_i     ( register_push          ),
        .data_o     ( cur_register[i]        ),
        .pop_i      ( register_pop           )
      );

    end else begin : gen_register_buffer // If register split is enabled, we could receive register packets out of order
      // When an instruction is marked as valid, reserve a slot for the instruction in the buffer

      // The buffer has a number of slots equal to InstFifoDepth

      // TODO: implement
    end

    logic [1:0] tree_cnt;

    always_ff @(posedge clk_i or negedge rst_ni) begin : tree_counter
      if (~rst_ni) begin
        tree_cnt <= 0;
      end else begin
        if (clear_i || irq_clr[i]) begin
          tree_cnt <= 0;
        end else if (~issue_fifo_empty[i] && tree_cnt != 2 && winner == i) begin
          tree_cnt <= tree_cnt + 1;
        end
      end
    end

    // Variables for FSSYNCI
    logic [IdWidthRs+1:0] fssynci_id;
    logic [AggrWidthRs:0] fssynci_aggr;

    assign fssynci_id   = {cur_issue[i].instr[17:15],cur_issue[i].instr[11:7]};
    assign fssynci_aggr = {1'b0,cur_issue[i].instr[28:27],cur_issue[i].instr[24:18]};

    always_comb begin : fsync_assignment
      irq_clr[i]        = 1'b0;
      sync_num_valid[i] = 1'b0;
      sync_num_ht[i]    = '0;
      sync_num_hn[i]    = '0;
      sync_num_vt[i]    = '0;
      sync_num_vn[i]    = '0;
      fsync_req_ht[i]   = '0;
      fsync_req_hn[i]   = '0;
      fsync_req_vt[i]   = '0;
      fsync_req_vn[i]   = '0;

      unique case ({cur_issue[i].instr[26:25],cur_issue[i].instr[14:12],cur_issue[i].instr[6:0]})
        FSSYNC: begin
          sync_num_valid[i] = ~issue_fifo_empty[i];
          sync_num_ht[i]    = cur_register[i].rs[1][15] + cur_register[i].rs[2][15];
          sync_num_hn[i]    = cur_register[i].rs[0][15];
          sync_num_vt[i]    = cur_register[i].rs[1][31] + cur_register[i].rs[2][31];
          sync_num_vn[i]    = cur_register[i].rs[0][31];

          fsync_req_ht[i].sync     = cur_register[i].rs[1+tree_cnt[0]][15] && (tree_cnt != 2) && ~issue_fifo_empty[i];
          fsync_req_ht[i].sig.aggr = {1'b0,cur_register[i].rs[1+tree_cnt[0]][6+:AggrWidthRs]};
          fsync_req_ht[i].sig.id   = {cur_register[i].rs[1+tree_cnt[0]][0+:IdWidthRs],2'b00};

          fsync_req_hn[i].sync     = cur_register[i].rs[0][15] && (tree_cnt == 0) && ~issue_fifo_empty[i];
          fsync_req_hn[i].sig.aggr = {1'b0,cur_register[i].rs[0][6+:AggrWidthRs]};
          fsync_req_hn[i].sig.id   = {cur_register[i].rs[0][0+:IdWidthRs],2'b10};

          fsync_req_vt[i].sync     = cur_register[i].rs[1+tree_cnt[0]][31] && (tree_cnt != 2) && ~issue_fifo_empty[i];
          fsync_req_vt[i].sig.aggr = {1'b0,cur_register[i].rs[1+tree_cnt[0]][22+:AggrWidthRs]};
          fsync_req_vt[i].sig.id   = {cur_register[i].rs[1+tree_cnt[0]][16+:IdWidthRs],2'b01};

          fsync_req_vn[i].sync     = cur_register[i].rs[0][31] && (tree_cnt == 0) && ~issue_fifo_empty[i];
          fsync_req_vn[i].sig.aggr = {1'b0,cur_register[i].rs[0][22+:AggrWidthRs]};
          fsync_req_vn[i].sig.id   = {cur_register[i].rs[0][16+:IdWidthRs],2'b11};
        end
        FSSYNCI: begin
          sync_num_valid[i] = ~issue_fifo_empty[i];

          case (fssynci_id[1:0])
            2'b00: begin
              sync_num_ht[i] = 1;

              fsync_req_ht[i].sync     = (tree_cnt == 0) && ~issue_fifo_empty[i];
              fsync_req_ht[i].sig.aggr = fssynci_aggr;
              fsync_req_ht[i].sig.id   = fssynci_id;
            end
            2'b10: begin
              sync_num_hn[i] = 1;

              fsync_req_hn[i].sync     = (tree_cnt == 0) && ~issue_fifo_empty[i];
              fsync_req_hn[i].sig.aggr = fssynci_aggr;
              fsync_req_hn[i].sig.id   = fssynci_id;
            end
            2'b01: begin
              sync_num_vt[i] = 1;

              fsync_req_vt[i].sync     = (tree_cnt == 0) && ~issue_fifo_empty[i];
              fsync_req_vt[i].sig.aggr = fssynci_aggr;
              fsync_req_vt[i].sig.id   = fssynci_id;
            end
            2'b11: begin
              sync_num_vn[i] = 1;

              fsync_req_vn[i].sync     = (tree_cnt == 0) && ~issue_fifo_empty[i];
              fsync_req_vn[i].sig.aggr = fssynci_aggr;
              fsync_req_vn[i].sig.id   = fssynci_id;
            end
          endcase
        end
        FSCLR: begin
          irq_clr[i]   = 1'b1;
        end
        default: begin
          irq_clr[i]        = 1'b0;
          sync_num_valid[i] = 1'b0;
          sync_num_ht[i]    = '0;
          sync_num_hn[i]    = '0;
          sync_num_vt[i]    = '0;
          sync_num_vn[i]    = '0;
          fsync_req_ht[i]   = '0;
          fsync_req_hn[i]   = '0;
          fsync_req_vt[i]   = '0;
          fsync_req_vn[i]   = '0;
        end
      endcase

      irq_clr[i] = irq_clr[i] || irq_en && winner == i && issue_util != 1 || irq_q[i] && issue_push;
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin : irq_register
      if (~rst_ni) begin
        irq_q[i] <= 1'b0;
      end else begin
        if (irq_clr[i] || clear_i) begin
          irq_q[i] <= 1'b0;
        end else if (irq_en && winner == i) begin
          irq_q[i] <= 1'b1;
        end
      end
    end

    assign irq_o[i] = (irq_en && winner == i) | irq_q[i];
  end

  logic [1:0] sync_cnt_ht;
  logic       sync_cnt_hn;
  logic [1:0] sync_cnt_vt;
  logic       sync_cnt_vn;

  always_ff @(posedge clk_i or negedge rst_ni) begin : sync_counter_ht
    if (~rst_ni) begin
      sync_cnt_ht <= '0;
    end else begin
      if (irq_o[winner] && irq_clr[winner] || clear_i) begin
        sync_cnt_ht <= '0;
      end else if (fsync_rsp_ht_i.wake) begin
        sync_cnt_ht <= sync_cnt_ht + 1;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : sync_counter_hn
    if (~rst_ni) begin
      sync_cnt_hn <= '0;
    end else begin
      if (irq_o[winner] && irq_clr[winner] || clear_i) begin
        sync_cnt_hn <= '0;
      end else if (fsync_rsp_hn_i.wake) begin
        sync_cnt_hn <= sync_cnt_hn + 1;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : sync_counter_vt
    if (~rst_ni) begin
      sync_cnt_vt <= '0;
    end else begin
      if (irq_o[winner] && irq_clr[winner] || clear_i) begin
        sync_cnt_vt <= '0;
      end else if (fsync_rsp_vt_i.wake) begin
        sync_cnt_vt <= sync_cnt_vt + 1;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin : sync_counter_vn
    if (~rst_ni) begin
      sync_cnt_vn <= '0;
    end else begin
      if (irq_o[winner] && irq_clr[winner] || clear_i) begin
        sync_cnt_vn <= '0;
      end else if (fsync_rsp_vn_i.wake) begin
        sync_cnt_vn <= sync_cnt_vn + 1;
      end
    end
  end

  assign irq_en = sync_cnt_ht == sync_num_ht[winner] && sync_cnt_hn == sync_num_hn[winner] && sync_cnt_vt == sync_num_vt[winner] && sync_cnt_vn == sync_num_vn[winner] && sync_num_valid[winner];

  assign fsync_req_ht_o = fsync_req_ht[winner];
  assign fsync_req_hn_o = fsync_req_hn[winner];
  assign fsync_req_vt_o = fsync_req_vt[winner];
  assign fsync_req_vn_o = fsync_req_vn[winner];

endmodule