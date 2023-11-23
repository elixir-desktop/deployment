// gcc -g -D_GNU_SOURCE -O -Wall -fPIC -shared -o redirector.so redirector.c -ldl `pkg-config --cflags glib-2.0` `pkg-config --libs glib-2.0`
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <glib.h>
#include <gio/gio.h>

struct Lib {
    void *hdl;
    char *name;
};

struct Lib def = {RTLD_NEXT, "RTLD_NEXT"};
struct Lib gio = {NULL, "libgio-2.0.so.0"};
struct Lib glib = {NULL, "libglib-2.0.so.0"};

struct Pair {
    const char *from;
    const char *to;
    int fromlen;
    int tolen;
};

struct Pair *getpairs() {
    static struct Pair *pairs = NULL;

    if (pairs == NULL) {
        // fprintf(stderr, "Initialzing getpairs()\n");

        char *reds = getenv("REDIRECTIONS");
        if (reds == NULL) {
            return pairs = calloc(1, sizeof(struct Pair*));
        }
        reds = strdup(reds);

        int count = 1;
        {
            char *oreds = reds;
            while(strchr(reds, ';') != NULL) {
                count++;
                reds = strchr(reds, ';') + 1;
            }
            reds = oreds;
        }

        struct Pair * pp = pairs = calloc(sizeof(struct Pair), count + 1);
        char *pch = strtok(reds, ";");
        while(pch != NULL) {
            char *from = pch;
            char *to = strchr(pch, '=');
            if (to == NULL) {
                fprintf(stderr, "Invalid redirection: %s\n", pch);
                exit(1);
            }
            *to = '\0';
            to++;
            pp->from = from;
            pp->fromlen = strlen(from);
            pp->to = to;
            pp->tolen = strlen(to);
            pp++;
            // fprintf(stderr, "Setup redirect %s to %s\n", from, to);

            pch = strtok(NULL, ";");
        }
    }
    return pairs;
}

#define redirect(path) \
    struct Pair *_pair = getredirect(path); \
    char* _redirect = NULL; \
    if (_pair != NULL) { \
        int len = strlen(path); \
        _redirect = alloca(len - _pair->fromlen + _pair->tolen + 1); \
        memcpy(_redirect, _pair->to, _pair->tolen); \
        strcpy(_redirect + _pair->tolen, path + _pair->fromlen); \
        fprintf(stderr, "Redirecting %s to %s\n", path, _redirect); \
        path = _redirect; \
    }


struct Pair *getredirect(const char *path) {
    if (path == 0) return NULL;
    struct Pair *pairs = getpairs();
    if (pairs == NULL) return NULL;

    while(pairs->from != NULL) {
        if (memcmp(path, pairs->from, pairs->fromlen) == 0) {
            return pairs;
        }
        pairs++;
    }
    return NULL;
}

void *dlsym_lib(struct Lib* lib, const char *name) {
    if (lib->hdl == NULL) {
        lib->hdl = dlopen(lib->name, RTLD_LAZY);
        if (lib->hdl == NULL) {
            fprintf(stderr, "failed loading lib %s: %s\n", lib->name, dlerror());
            exit(1);
        }
    }
    void *ret = dlsym(lib->hdl, name);
    if (ret == 0) {
        fprintf(stderr, "failed loading fun %s->%s: %s\n", lib->name, name, dlerror());
        exit(1);
    }
    return ret;
}

GSubprocess*
g_subprocess_launcher_spawnv (
  GSubprocessLauncher* self,
  const gchar* const* argv,
  GError** error
) {
    GSubprocess *(*original_spawnv)(GSubprocessLauncher*, const gchar* const*, GError**) = dlsym_lib(&gio, "g_subprocess_launcher_spawnv");
    if (argv != 0) {
        const gchar** margv = (const gchar**)argv;
        redirect(margv[0]);
    }
    return original_spawnv(self, argv, error);
}

gchar* g_build_filename(const gchar *first_element, ...) {
    gchar* (*original_build_filename)(const gchar *, ...) = dlsym_lib(&glib, "g_build_filename");
    gchar* (*original_g_strdup)(const gchar *) = dlsym_lib(&glib, "g_strdup");
    gchar* (*original_g_free)(void *) = dlsym_lib(&glib, "g_free");
    gchar* ret = original_g_strdup(first_element);
    va_list args1;
    va_start(args1, first_element);

    gchar *str;
    while ((str = va_arg(args1, gchar*)) != NULL) {
        gchar *newret = original_build_filename(ret, str, NULL);
        original_g_free(ret);
        ret = newret;
    }

    va_end(args1);
    redirect(ret);
    if (_redirect == NULL) {
        return ret;
    } else {
        return original_g_strdup(_redirect);
    }
}

FILE *fopen(const char *path, const char *mode) {
    void *(*original_fopen)(const char *, const char *) = dlsym_lib(&def, "fopen");
    redirect(path);
    return original_fopen(path, mode);
}

int open(const char *path, int oflag, ...) {
    int (*original_open)(const char *, int, ...) = dlsym_lib(&def, "open");
    int ret;
    redirect(path);
    va_list args;
    va_start(args, oflag);
    if (oflag & O_CREAT) {
        ret = original_open(path, oflag, (mode_t)va_arg(args, mode_t));
    } else {
        ret = original_open(path, oflag);
    }
    va_end(args);
    return ret;
}