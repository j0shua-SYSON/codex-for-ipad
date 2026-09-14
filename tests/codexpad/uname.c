#include <assert.h>
#include <string.h>
#include "kernel/calls.h"

extern const char *uname_hostname_override;

int main(void) {
    struct {
        unsigned char before[16];
        struct uname value;
        unsigned char after[16];
    } guarded;
    char long_name[1024];
    memset(long_name, 'x', sizeof(long_name) - 1);
    long_name[sizeof(long_name) - 1] = 0;
    memset(&guarded, 0xa5, sizeof(guarded));
    uname_hostname_override = long_name;
    do_uname(&guarded.value);
    assert(strlen(guarded.value.hostname) == UNAME_LENGTH - 1);
    for (unsigned i = 0; i < UNAME_LENGTH - 1; i++)
        assert(guarded.value.hostname[i] == 'x');
    assert(strcmp(guarded.value.system, "Linux") == 0);
    assert(strcmp(guarded.value.release, "4.20.69-ish") == 0);
    assert(strcmp(guarded.value.arch, "i686") == 0);
    assert(strcmp(guarded.value.domain, "(none)") == 0);
    for (unsigned i = 0; i < sizeof(guarded.before); i++) {
        assert(guarded.before[i] == 0xa5);
        assert(guarded.after[i] == 0xa5);
    }
    uname_hostname_override = "short-host";
    do_uname(&guarded.value);
    assert(strcmp(guarded.value.hostname, "short-host") == 0);
    uname_hostname_override = NULL;
    return 0;
}
