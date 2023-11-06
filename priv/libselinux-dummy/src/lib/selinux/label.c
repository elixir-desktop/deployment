struct selabel_handle;
struct selinux_opt;
#include <sys/types.h>
#include <stdint.h>
#include <stdbool.h>
#define SELABEL_X_SELN 5
#define SELABEL_X_PROP 1
#define SELABEL_X_POLYSELN 7
#define SELABEL_X_POLYPROP 6
#define SELABEL_X_EXT 2
#define SELABEL_X_EVENT 4
#define SELABEL_X_CLIENT 3
#define SELABEL_OPT_VALIDATE 1
#define SELABEL_OPT_UNUSED 0
#define SELABEL_OPT_SUBSET 4
#define SELABEL_OPT_PATH 3
#define SELABEL_OPT_DIGEST 5
#define SELABEL_OPT_BASEONLY 2
#define SELABEL_NOPT 6
#define _SELABEL_H_
#define SELABEL_DB_VIEW 6
#define SELABEL_DB_TUPLE 9
#define SELABEL_DB_TABLE 3
#define SELABEL_DB_SEQUENCE 5
#define SELABEL_DB_SCHEMA 2
#define SELABEL_DB_PROCEDURE 7
#define SELABEL_DB_LANGUAGE 10
#define SELABEL_DB_EXCEPTION 11
#define SELABEL_DB_DATATYPE 12
#define SELABEL_DB_DATABASE 1
#define SELABEL_DB_COLUMN 4
#define SELABEL_DB_BLOB 8
#define SELABEL_CTX_X 2
#define SELABEL_CTX_MEDIA 1
#define SELABEL_CTX_FILE 0
#define SELABEL_CTX_DB 3
#define SELABEL_CTX_ANDROID_SERVICE 5
#define SELABEL_CTX_ANDROID_PROP 4
extern void selabel_stats(struct selabel_handle *handle){}
extern void selabel_close(struct selabel_handle *handle){}
extern struct selabel_handle *selabel_open(unsigned int backend, const struct selinux_opt *opts, unsigned nopts){}
extern int selabel_lookup(struct selabel_handle *handle, char **con, const char *key, int type){return 0;}
extern int selabel_lookup_raw(struct selabel_handle *handle, char **con, const char *key, int type){return 0;}
extern int selabel_lookup_best_match(struct selabel_handle *rec, char **con, const char *key, const char **aliases, int type){return 0;}
extern int selabel_lookup_best_match_raw(struct selabel_handle *rec, char **con, const char *key, const char **aliases, int type){return 0;}
extern int selabel_digest(struct selabel_handle *rec, unsigned char **digest, size_t *digest_len, char ***specfiles, size_t *num_specfiles){return 0;}
extern enum selabel_cmp_result selabel_cmp(struct selabel_handle *h1, struct selabel_handle *h2);
extern bool selabel_partial_match(struct selabel_handle *handle, const char *key){return 0;}
extern bool selabel_hash_all_partial_matches(struct selabel_handle *rec, const char *key, uint8_t* digest){return 0;}
extern bool selabel_get_digests_all_partial_matches(struct selabel_handle *rec, const char *key, uint8_t **calculated_digest, uint8_t **xattr_digest, size_t *digest_len){return 0;}
