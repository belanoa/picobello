// Copyright 2023 ETH Zurich and University of Bologna.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <stdint.h>

#include "pb_addrmap.h"

#include "snrt.h"
#include "data/pulptorrent.h"

void fence() {
    asm volatile("fence \n" ::: "memory");
    return;
}


int main() {

    int error = 0;

    if (snrt_cluster_idx() > 0) return 0;

    uint32_t core_idx = snrt_global_core_idx();

    // 1. NrRedH * NrRedW == NrMicroH * NrMicroW * NrRedPerMicro
    // 2. NrRedPerMicro <= NrCcPerMicro
    // 3. NrFPUPerMicro <= NrCcPerMicro

    if (core_idx == 0) {
        
        if ( NrRedH * NrRedW != NrMicroH * NrMicroW * NrRedPerMicro ||
            NrRedPerMicro > NrCcPerMicro ||
            NrFPUPerMicro > NrCcPerMicro
        ) (*((uint32_t *) PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR)) = 110000;
        else (*((uint32_t *) PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR)) = 0;
    }

    fence();
    snrt_cluster_hw_barrier();

    if ((*((uint32_t *) PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR)) != 0) {
        if (core_idx == 0) {
            if ((error + (*((uint32_t *) PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR))) == 0) {
                return 100000;
            }
            return error + (*((uint32_t *) PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR));
        } else {
            return 0;
        }
    }

    fence();
    snrt_cluster_hw_barrier();

    // START L1 CHECKS
    if (core_idx == 0) {
        for (uint32_t i = 0; i < CFG_CLUSTER_NR_CORES+1; i++) {
            (*(((uint32_t *) PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR) + i)) = CFG_CLUSTER_NR_CORES-i;
            (*(((uint32_t *) (PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR + PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_SIZE/2)) + i)) = 0;
        }
    }

    fence();
    snrt_cluster_hw_barrier();

    (*(((uint32_t *) (PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR + PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_SIZE/2)) + core_idx)) = core_idx;
    uint32_t max = (*((uint32_t *) PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR));
    if ( core_idx > max ) error++;
    else {
        *(((uint32_t *) PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR) + max - core_idx) = 0;
    }

    fence();
    snrt_cluster_hw_barrier();

    if (core_idx == 0) {
        if ((*((uint32_t *) PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR)) == 0) {
            error++;
            (*((uint32_t *) PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR)) = 1000;
        } else {
            (*((uint32_t *) PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR)) = 0;
        }
        for (uint32_t i = 1; i < CFG_CLUSTER_NR_CORES; i++) {
            if ((*(((uint32_t *) (PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR + PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_SIZE/2)) + i)) == 0) {
                error++;
                (*((uint32_t *) PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR)) = 10000;
            }
        }
    }

    fence();
    snrt_cluster_hw_barrier();
    // END L1 CHECKS

    if ((*((uint32_t *) PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR)) != 0) {
        if (core_idx == 0) {
            if ((error + (*((uint32_t *) PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR))) == 0) {
                return 100000;
            }
            return error + (*((uint32_t *) PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR));
        } else {
            return 0;
        }
    }

    fence();
    snrt_cluster_hw_barrier();

    
    // START L0 CHECKS
    int count = 0;
    if (NrBanksL0 != 0) {
        if (core_idx != 0) {
            for (uint32_t i = 0; i < CFG_CLUSTER_NR_CORES; i++) {
                (*(((uint32_t *) SNITCH_CLUSTER_ADDRMAP_L0_BASE) + i)) = 0;
                (*(((uint32_t *) (SNITCH_CLUSTER_ADDRMAP_L0_BASE + SNITCH_CLUSTER_ADDRMAP_L0_SIZE)) - 1 - i)) = 0;
            }
        }

        fence();
        snrt_cluster_hw_barrier();

        if (core_idx != 0) {
            (*(((uint32_t *) SNITCH_CLUSTER_ADDRMAP_L0_BASE) + core_idx)) = core_idx;
        }

        fence();
        snrt_cluster_hw_barrier();

        int micro_idx = (core_idx-1) / NrCcPerMicro;

        if (core_idx != 0) {
            for (uint32_t i = 0; i < CFG_CLUSTER_NR_CORES; i++) {
                if ((*(((uint32_t *) SNITCH_CLUSTER_ADDRMAP_L0_BASE) + i)) != 0) {
                    count++;
                    if (
                        (*(((uint32_t *) SNITCH_CLUSTER_ADDRMAP_L0_BASE) + i)) <= micro_idx*NrCcPerMicro || 
                        (*(((uint32_t *) SNITCH_CLUSTER_ADDRMAP_L0_BASE) + i)) > (micro_idx+1)*NrCcPerMicro 
                    ) {
                        error++;
                    }
                }
            }
            if (count != NrCcPerMicro) error++;
        }

        fence();
        snrt_cluster_hw_barrier();

        if (core_idx != 0) {
            (*(((uint32_t *) (SNITCH_CLUSTER_ADDRMAP_L0_BASE + SNITCH_CLUSTER_ADDRMAP_L0_SIZE)) - core_idx)) = micro_idx+1;
        }

        fence();
        snrt_cluster_hw_barrier();

        count = 0;

        if (core_idx != 0) {
            for (uint32_t i = 0; i < CFG_CLUSTER_NR_CORES; i++) {
                count+= (*(((uint32_t *) (SNITCH_CLUSTER_ADDRMAP_L0_BASE + SNITCH_CLUSTER_ADDRMAP_L0_SIZE)) - 1 - i));
            }
            if (count != NrCcPerMicro*(micro_idx+1)) error++;
        }

        fence();
        snrt_cluster_hw_barrier();
    }
    // END L0 CHECKS

    (*(((uint32_t *) PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR) + core_idx + 1)) = error;

    fence();
    snrt_cluster_hw_barrier();

    count = 0;
    if (core_idx == 0) {
        for (uint32_t i = 0; i < CFG_CLUSTER_NR_CORES+1; i++) {
            count+= (*(((uint32_t *) PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR) + i));
        }
        return count;
    } else {
        return 0;
    }

    return 1;
}