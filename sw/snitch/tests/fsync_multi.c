// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// In this program, we test the parallel synchronization capabilities of FractalSync. Tile 0 synchronizes concurrently with Tiles 1 and 2

#include <stdint.h>

#include "pb_addrmap.h"

#include "snrt.h"

#define STRINGIFY2(X) #X
#define STRINGIFY(X) STRINGIFY2(X)

#define OPCODE STRINGIFY(0)
#define RD STRINGIFY(7)
#define FUNCT3 STRINGIFY(12)
#define RS1 STRINGIFY(15)
#define RS2 STRINGIFY(20)
#define FUNCT2 STRINGIFY(25)
#define RS3 STRINGIFY(27)

int main (void) {
  if (snrt_cluster_idx() > 2) return 0;

  uint32_t rs2_g = 0;
  uint32_t rs2_l = 0;
  uint32_t rs3_l = 0;

  if (snrt_cluster_idx() == 0) {
    rs2_g = 0x00008140;
    rs2_l = 0x00008040;
    rs3_l = 0x00008101;
  } else if (snrt_cluster_idx() == 1) {
    rs2_g = 0x00008140;
    rs2_l = 0x00008040;
  } else {
    rs2_g = 0x00008100;
    rs2_l = 0x00008101;
  }

  snrt_interrupt_enable(IRQ_M_ACC);

  snrt_cluster_hw_barrier();

  if (snrt_is_dm_core()) {
    asm volatile("  addi t0, %[rs2], 0 \n \
                    .word (0b0001011 << " OPCODE ") | \
                          (0b00000   << " RD     ") | \
                          (0b100     << " FUNCT3 ") | \
                          (0b00000   << " RS1    ") | \
                          (0b00101   << " RS2    ") | \
                          (0b00      << " FUNCT2 ") | \
                          (0b00000   << " RS3    ")   \n \
                    wfi \n                            \
                    .word (0b0001011 << " OPCODE ") | \
                          (0b00000   << " RD     ") | \
                          (0b101     << " FUNCT3 ") | \
                          (0b00000   << " RS1    ") | \
                          (0b00000   << " RS2    ") | \
                          (0b00      << " FUNCT2 ") | \
                          (0b00000   << " RS3    ")   \n"
                    :: [rs2] "r"(rs2_g) : "t0", "memory");

    asm volatile("  addi t0, %[rs2], 0 \n \
                    addi t1, %[rs3], 0 \n \
                    .word (0b0001011 << " OPCODE ") | \
                          (0b00000   << " RD     ") | \
                          (0b100     << " FUNCT3 ") | \
                          (0b00000   << " RS1    ") | \
                          (0b00101   << " RS2    ") | \
                          (0b00      << " FUNCT2 ") | \
                          (0b00110   << " RS3    ")   \n \
                    wfi \n                            \
                    .word (0b0001011 << " OPCODE ") | \
                          (0b00000   << " RD     ") | \
                          (0b101     << " FUNCT3 ") | \
                          (0b00000   << " RS1    ") | \
                          (0b00000   << " RS2    ") | \
                          (0b00      << " FUNCT2 ") | \
                          (0b00000   << " RS3    ")   \n"
                    :: [rs2] "r"(rs2_l), [rs3] "r"(rs3_l) : "t0", "t1", "memory");
  }

  snrt_cluster_hw_barrier();

  return 0;
}
