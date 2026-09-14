#include <assert.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <time.h>
#include "util/sync.h"

// Exercise the host lock independently of guest execution, COW and the JIT.
enum { workers = 6, iterations = 40000 };
static wrlock_t shared;
static atomic_int ready, completed;
static atomic_bool started, stopping;
static unsigned value;

static void ignore_signal(int signal) { (void) signal; }

static void *worker(void *argument) {
    (void) argument;
    atomic_fetch_add(&ready, 1);
    while (!atomic_load(&started)) sched_yield();
    for (unsigned i = 0; i < iterations; i++) {
        read_wrlock(&shared);
        assert(value <= workers * iterations / 4);
        read_wrunlock(&shared);
        if (i % 4 == 0) {
            write_wrlock(&shared);
            value++;
            write_wrunlock(&shared);
        }
    }
    atomic_fetch_add(&completed, 1);
    // Keep every pthread alive until the signal sender has stopped.
    while (!atomic_load(&stopping)) sched_yield();
    return NULL;
}

int main(void) {
    struct sigaction action = {.sa_handler = ignore_signal};
    sigemptyset(&action.sa_mask);
    assert(sigaction(SIGUSR1, &action, NULL) == 0);
    for (int signals = 0; signals <= 1; signals++) {
        wrlock_init(&shared);
        ready = completed = value = 0;
        started = stopping = false;
        pthread_t threads[workers];
        for (int i = 0; i < workers; i++)
            assert(pthread_create(&threads[i], NULL, worker, NULL) == 0);
        while (atomic_load(&ready) != workers) sched_yield();
        struct timespec begin, now, pause = {.tv_nsec = 100000};
        clock_gettime(CLOCK_MONOTONIC, &begin);
        started = true;
        while (atomic_load(&completed) != workers) {
            if (signals)
                for (int i = 0; i < workers; i++)
                    assert(pthread_kill(threads[i], SIGUSR1) == 0);
            nanosleep(&pause, NULL);
            clock_gettime(CLOCK_MONOTONIC, &now);
            if (now.tv_sec - begin.tv_sec > 20) {
                fprintf(stderr, "FAIL: host rwlock stalled; signals=%d completed=%d active=%d\n",
                        signals, atomic_load(&completed), atomic_load(&shared.val));
                return 1;
            }
        }
        stopping = true;
        for (int i = 0; i < workers; i++) assert(pthread_join(threads[i], NULL) == 0);
        assert(value == workers * iterations / 4);
        wrlock_destroy(&shared);
        printf("PASS: host rwlock stress (%s SIGUSR1)\n", signals ? "with" : "without");
        fflush(stdout);
    }
}
