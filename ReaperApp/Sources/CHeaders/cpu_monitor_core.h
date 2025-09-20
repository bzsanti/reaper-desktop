#ifndef CPU_MONITOR_CORE_H
#define CPU_MONITOR_CORE_H

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>

typedef struct CProcessInfo {
  uint32_t pid;
  char *name;
  float cpu_usage;
  double memory_mb;
  char *status;
  uint32_t parent_pid;
  uintptr_t thread_count;
  uint64_t run_time;
} CProcessInfo;

typedef struct CProcessList {
  struct CProcessInfo *processes;
  uintptr_t count;
} CProcessList;

typedef struct CCpuMetrics {
  float total_usage;
  uintptr_t core_count;
  double load_avg_1;
  double load_avg_5;
  double load_avg_15;
  uint64_t frequency_mhz;
} CCpuMetrics;

void monitor_init(void);

void monitor_refresh(void);

struct CProcessList *get_all_processes(void);

struct CProcessList *get_high_cpu_processes(float threshold);

struct CCpuMetrics *get_cpu_metrics(void);

void free_process_list(struct CProcessList *list);

void free_cpu_metrics(struct CCpuMetrics *metrics);

void free_string(char *s);

#endif /* CPU_MONITOR_CORE_H */
