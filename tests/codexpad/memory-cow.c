#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include "kernel/memory.h"

// pthread_barrier_t is not available on Darwin.
struct barrier {
    pthread_mutex_t lock;
    pthread_cond_t changed;
    unsigned count, generation, total;
};
#define BARRIER(n) {PTHREAD_MUTEX_INITIALIZER, PTHREAD_COND_INITIALIZER, 0, 0, n}
static struct barrier begin = BARRIER(3), readers = BARRIER(2), done = BARRIER(3);
static struct mem memory;
enum { rounds = 256, address = PAGE_SIZE };

static void barrier_wait(struct barrier *barrier) {
    pthread_mutex_lock(&barrier->lock);
    unsigned generation = barrier->generation;
    if (++barrier->count == barrier->total) {
        barrier->count = 0;
        barrier->generation++;
        pthread_cond_broadcast(&barrier->changed);
    } else {
        while (generation == barrier->generation)
            pthread_cond_wait(&barrier->changed, &barrier->lock);
    }
    pthread_mutex_unlock(&barrier->lock);
}

static void *writer(void *argument) {
    uintptr_t index = (uintptr_t) argument;
    for (int i = 0; i < rounds; i++) {
        barrier_wait(&begin);
        read_wrlock(&memory.lock);
        // Both threads hold the old page's read lock before either faults.
        // The old implementation snapshots a backing pointer, drops this lock,
        // and copies freed memory when the other writer wins lock promotion.
        barrier_wait(&readers);
        uint32_t *word = mem_ptr(&memory, address + index * sizeof(uint32_t), MEM_WRITE);
        assert(word != NULL);
        *word = 0x12340000 + index;
        read_wrunlock(&memory.lock);
        barrier_wait(&done);
    }
    return NULL;
}

int main(void) {
    mem_init(&memory);
    pthread_t threads[2];
    for (uintptr_t i = 0; i < 2; i++)
        assert(pthread_create(&threads[i], NULL, writer, (void *) i) == 0);
    for (int i = 0; i < rounds; i++) {
        write_wrlock(&memory.lock);
        // This is the state after fork's child exits: a sole surviving backing
        // reference, still marked copy-on-write in the multithreaded parent.
        assert(pt_map_nothing(&memory, PAGE(address), 1, P_READ | P_WRITE | P_COW) == 0);
        write_wrunlock(&memory.lock);
        barrier_wait(&begin);
        barrier_wait(&done);
        read_wrlock(&memory.lock);
        uint32_t *words = mem_ptr(&memory, address, MEM_READ);
        assert(words[0] == 0x12340000 && words[1] == 0x12340001);
        read_wrunlock(&memory.lock);
    }
    for (int i = 0; i < 2; i++)
        assert(pthread_join(threads[i], NULL) == 0);
    // Non-writable and unmapped accesses must still fail, not be "fixed" by
    // granting permissions to arbitrary guest addresses.
    write_wrlock(&memory.lock);
    assert(pt_set_flags(&memory, PAGE(address), 1, P_READ) == 0);
    write_wrunlock(&memory.lock);
    read_wrlock(&memory.lock);
    assert(mem_ptr(&memory, address, MEM_WRITE) == NULL);
    assert(mem_ptr(&memory, address + PAGE_SIZE, MEM_READ) == NULL);
    assert(mem_ptr(&memory, address, MEM_WRITE_PTRACE) != NULL);
    read_wrunlock(&memory.lock);
    mem_destroy(&memory);
    puts("PASS: concurrent copy-on-write faults preserve both writers across 256 rounds");
    return 0;
}
