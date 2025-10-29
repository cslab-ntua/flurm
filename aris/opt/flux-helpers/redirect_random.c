#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <stdarg.h>
#include <unistd.h>

int open(const char *pathname, int flags, ...) {
    static int (*real_open)(const char *, int, ...) = NULL;
    if (!real_open)
        real_open = dlsym(RTLD_NEXT, "open");

    if (strcmp(pathname, "/dev/random") == 0)
        pathname = "/dev/urandom";

    va_list args;
    va_start(args, flags);
    int fd = real_open(pathname, flags, args);
    va_end(args);
    return fd;
}
