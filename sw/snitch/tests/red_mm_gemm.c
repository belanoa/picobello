// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <stdint.h>

#include "pb_addrmap.h"

#include "snrt.h"
#include "data/red_mm_gemm.h"

#define STRINGIFY2(X) #X
#define STRINGIFY(X) STRINGIFY2(X)

#define OPCODE STRINGIFY(0)
#define RD STRINGIFY(7)
#define FUNCT3 STRINGIFY(12)
#define RS1 STRINGIFY(15)
#define RS2 STRINGIFY(20)
#define FUNCT2 STRINGIFY(25)
#define RS3 STRINGIFY(27)

int check_output(uint32_t* actual, uint32_t* golden, int len)
{
  int errors = len; 
  for (int i=0; i<len; i++){
    uint32_t actual_data = *(actual+i);
    uint32_t golden_data = *(golden+i);
    if(actual_data == golden_data)
      errors--;
    //else 
      //printf("idx:%d, errors=%d, actual_data=%x, golden_data=%x, actual_ptr=%x, golden_ptr=%x\n", i, errors, actual_data, golden_data, (actual+i), (golden+i));
  }
  return errors;
}

int main (void) {

  if (snrt_cluster_idx() > 0) return 0;

  uint32_t core_idx = snrt_global_core_idx();

  uint16_t* local_x_mm   = (uint16_t *) (0x20000000 + 0x0000);
  uint16_t* local_w_mm   = (uint16_t *) (0x20000000 + 0x0800);
  uint16_t* local_x_gemm = (uint16_t *) (0x20000000 + 0x8000);
  uint16_t* local_w_gemm = (uint16_t *) (0x20000000 + 0x8800);
  uint16_t* local_z      = (uint16_t *) (0x20000000 + 0x18000);
  uint16_t* golden       = (uint16_t *) (0x20000000 + 0x10000);

  uint16_t x_size = M_SIZE * N_SIZE * sizeof(uint16_t);
  uint16_t w_size = N_SIZE * K_SIZE * sizeof(uint16_t);
  uint16_t y_size = M_SIZE * K_SIZE * sizeof(uint16_t);
  uint16_t z_size = M_SIZE * K_SIZE * sizeof(uint16_t);

  if (snrt_is_dm_core()) {
    snrt_dma_start_1d(local_x_mm,   x_mm, x_size);
    snrt_dma_start_1d(local_w_mm,   w_mm, w_size);
    snrt_dma_start_1d(local_x_gemm, x_gemm, x_size);
    snrt_dma_start_1d(local_w_gemm, w_gemm, w_size);
    snrt_dma_start_1d(golden      , z_gemm, z_size);
    snrt_dma_wait_all();
  }

  snrt_cluster_hw_barrier();

  if (core_idx == 1) {
    int unsigned is_x_receive = 0;
    int unsigned is_x_send    = 0;
    int unsigned is_w_receive = 0;
    int unsigned is_w_send    = 0;

    uint32_t x_addr   = (uint32_t) local_x_mm;
    uint32_t w_addr   = (uint32_t) local_w_mm;
    uint32_t y_addr   = (uint32_t) local_z;
    uint32_t z_addr   = (uint32_t) local_z;
    uint32_t y_offs   = ((uint32_t) y_addr) - z_addr;
    uint32_t volatile cfg_reg0;
    uint32_t volatile cfg_reg1;

    cfg_reg0 = ((K_SIZE << 16) | (M_SIZE << 0));
    cfg_reg1 = ((1 << 20) | (is_w_send << 19) | (is_w_receive << 18) | (is_x_send << 17) | (is_x_receive << 16) | (N_SIZE << 0));

    int unsigned op_id, cur_op;

    asm volatile("addi t0, %[x_addr], 0 \n \
                addi t1, %[w_addr]  , 0 \n \
                addi t2, %[z_addr]  , 0 \n \
                addi t3, %[cfg0]    , 0 \n \
                addi t4, %[cfg1]    , 0 \n \
                addi t5, %[y_offs]  , 0 \n \
                .word (0b0001011 << " OPCODE ") | \
                      (0b00000   << " RD     ") | \
                      (0b000     << " FUNCT3 ") | \
                      (0b11100   << " RS1    ") | \
                      (0b11101   << " RS2    ") | \
                      (0b00      << " FUNCT2 ") | \
                      (0b11110   << " RS3    ")   \n \
                .word (0b0001011 << " OPCODE ") | \
                      (0b11110   << " RD     ") | \
                      (0b001     << " FUNCT3 ") | \
                      (0b00101   << " RS1    ") | \
                      (0b00110   << " RS2    ") | \
                      (0b00      << " FUNCT2 ") | \
                      (0b00111   << " RS3    ")   \n \
                addi %[op_id], t5, 0 \n " : [op_id] "=r"(op_id) : [x_addr] "r"(x_addr), [w_addr] "r"(w_addr), [z_addr] "r"(z_addr), [cfg0] "r"(cfg_reg0), [cfg1] "r"(cfg_reg1), [y_offs] "r"(y_offs) : "t0", "t1", "t2", "t3", "t4", "+t5", "memory");

    x_addr = (uint32_t) local_x_gemm;
    w_addr = (uint32_t) local_w_gemm;

    cfg_reg0 = ((K_SIZE << 16) | (M_SIZE << 0));
    cfg_reg1 = ((is_w_send << 19) | (is_w_receive << 18) | (is_x_send << 17) | (is_x_receive << 16) | (N_SIZE << 0));

    asm volatile("addi t0, %[x_addr], 0 \n \
                addi t1, %[w_addr]  , 0 \n \
                addi t2, %[z_addr]  , 0 \n \
                addi t3, %[cfg0]    , 0 \n \
                addi t4, %[cfg1]    , 0 \n \
                addi t5, %[y_offs]  , 0 \n \
                .word (0b0001011 << " OPCODE ") | \
                      (0b00000   << " RD     ") | \
                      (0b000     << " FUNCT3 ") | \
                      (0b11100   << " RS1    ") | \
                      (0b11101   << " RS2    ") | \
                      (0b00      << " FUNCT2 ") | \
                      (0b11110   << " RS3    ")   \n \
                .word (0b0001011 << " OPCODE ") | \
                      (0b11110   << " RD     ") | \
                      (0b001     << " FUNCT3 ") | \
                      (0b00101   << " RS1    ") | \
                      (0b00110   << " RS2    ") | \
                      (0b00      << " FUNCT2 ") | \
                      (0b00111   << " RS3    ")   \n \
                addi %[op_id], t5, 0 \n " : [op_id] "=r"(op_id) : [x_addr] "r"(x_addr), [w_addr] "r"(w_addr), [z_addr] "r"(z_addr), [cfg0] "r"(cfg_reg0), [cfg1] "r"(cfg_reg1), [y_offs] "r"(y_offs) : "t0", "t1", "t2", "t3", "t4", "+t5", "memory");


      do {
            asm volatile(".word (0b0001011 << " OPCODE ") | \
                              (0b11110   << " RD     ") | \
                              (0b010     << " FUNCT3 ") | \
                              (0b00000   << " RS1    ") | \
                              (0b00000   << " RS2    ") | \
                              (0b00      << " FUNCT2 ") | \
                              (0b00000   << " RS3    ")   \n \
                        addi %[op_cnt], t5, 0 \n" : [op_cnt] "=r"(cur_op) :: "+t5");
      } while (cur_op != op_id);
  }

  snrt_cluster_hw_barrier();

  if (core_idx == 1) {
    *( (uint32_t*) (0x20000000)) = 1;
    int errors = check_output((uint32_t *)local_z, (uint32_t *)golden, z_size/4);
    //printf("errors = %d\n", errors);
    *( (uint32_t*) (0x20000000)) = errors;
    snrt_cluster_hw_barrier();
    
    return 0;
  }
  snrt_cluster_hw_barrier();

  if (snrt_is_dm_core()) {
      return *( (uint32_t*) (0x20000000));
  }

  return 0;
}
