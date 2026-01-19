// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// In this program, we test the global synchronization using FractalSync

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

static inline void fssync_imm(const uint32_t id, const uint32_t aggr) {
  const uint32_t imm_0_4   = id & 0b11111;
  const uint32_t imm_5_14  = (id >> 5) | ((aggr & 0b1111111) << 3);
  const uint32_t imm_15_19 = aggr >> 7;

  asm volatile(
    ".word (0b0001011    << " OPCODE ") |  "
    "      (%[imm_0_4]   << " RD     ") |  "
    "      (0b100        << " FUNCT3 ") |  "
    "      (%[imm_5_14]  << " RS1    ") |  "
    "      (0b01         << " FUNCT2 ") |  "
    "      (%[imm_15_19] << " RS3    ") \n "
    "wfi                                \n "
    :
    : [imm_0_4] "i"(imm_0_4), [imm_5_14] "i"(imm_5_14), [imm_15_19] "i"(imm_15_19)
    : "memory"
  );
}

int main (void) {
  snrt_interrupt_enable(IRQ_M_ACC);

  snrt_cluster_hw_barrier();

  if (snrt_is_dm_core()) {
    fssync_imm(0b01,0b1111);
    fssync_imm(0b01,0b1111);
  }

  snrt_cluster_hw_barrier();

  return 0;
}
