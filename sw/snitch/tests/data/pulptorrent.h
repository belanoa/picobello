#define NrRedH 2
#define NrRedW 2
#define NrCcPerMicro  1
#define NrRedPerMicro 1
#define NrFPUPerMicro 1
#define NrMicroH 2
#define NrMicroW 2
#define NrRedHLocal ((NrRedH/NrMicroH))
#define NrRedWLocal ((NrRedW/NrMicroW))
#define MuxNarrowPort 1
#define NrNarrowPortsPerCc ((MuxNarrowPort ? 1 : 3))
#define NrBanksL0 8 
#define TCDMDepthL0 512


#define SNITCH_CLUSTER_ADDRMAP_L0_BASE ((PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_BASE_ADDR + PICOBELLO_ADDRMAP_CLUSTER_0_TCDM_SIZE))
#define SNITCH_CLUSTER_ADDRMAP_L0_SIZE ((NrBanksL0 * TCDMDepthL0 * SNRT_TCDM_BANK_WIDTH))