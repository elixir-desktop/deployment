#include <stdint.h>
#include <errno.h>
#include <stdlib.h>
struct security_class_t;
struct selinux_opt;
struct av_decision;
struct avc_cleanup;
struct security_id {
	char * ctx;
	unsigned int refcnt;
};
typedef unsigned short security_class_t;
typedef unsigned int access_vector_t;
typedef struct security_id *security_id_t;
#define SECSID_WILD (security_id_t)NULL	/* unspecified SID */
extern int avc_sid_to_context(security_id_t sid, char ** ctx){}
extern int avc_sid_to_context_raw(security_id_t sid, char ** ctx){return 0;}
extern int avc_context_to_sid(const char * ctx, security_id_t * sid){}
extern int avc_context_to_sid_raw(const char * ctx, security_id_t * sid){return 0;}
extern int sidget(security_id_t sid){return 0;}
extern int sidput(security_id_t sid){return 0;}
extern int avc_get_initial_sid(const char *name, security_id_t * sid){return 0;}
struct avc_entry;
struct avc_entry_ref {
	struct avc_entry *ae;
};
#define avc_entry_ref_init(aeref) ((aeref)->ae = NULL)
struct avc_memory_callback {
	/* malloc() equivalent. */
	void *(*func_malloc) (size_t size);
	/* free() equivalent. */
	void (*func_free) (void *ptr);
	/* Note that these functions should set errno on failure.
	   If not, some avc routines may return -1 without errno set. */
};

struct avc_log_callback {
	/* log the printf-style format and arguments. */
	void
	(*func_log) (const char *fmt, ...);
	/* store a string representation of auditdata (corresponding
	   to the given security class) into msgbuf. */
	void (*func_audit) (void *auditdata, security_class_t cls,
			    char *msgbuf, size_t msgbufsize);
};

struct avc_thread_callback {
	/* create and start a thread, returning an opaque pointer to it; 
	   the thread should run the given function. */
	void *(*func_create_thread) (void (*run) (void));
	/* cancel a given thread and free its resources. */
	void (*func_stop_thread) (void *thread);
};

struct avc_lock_callback {
	/* create a lock and return an opaque pointer to it. */
	void *(*func_alloc_lock) (void);
	/* obtain a given lock, blocking if necessary. */
	void (*func_get_lock) (void *lock);
	/* release a given lock. */
	void (*func_release_lock) (void *lock);
	/* destroy a given lock (free memory, etc.) */
	void (*func_free_lock) (void *lock);
};

#define AVC_OPT_UNUSED		0
#define AVC_OPT_SETENFORCE	1
extern int avc_init(const char *msgprefix,
		    const struct avc_memory_callback *mem_callbacks,
		    const struct avc_log_callback *log_callbacks,
		    const struct avc_thread_callback *thread_callbacks,
		    const struct avc_lock_callback *lock_callbacks){return 0;}
extern int avc_open(struct selinux_opt *opts, unsigned nopts){return 0;}
extern void avc_cleanup(void){}
extern int avc_reset(void){return 0;}
extern void avc_destroy(void){}
extern int avc_has_perm_noaudit(security_id_t ssid,
				security_id_t tsid,
				security_class_t tclass,
				access_vector_t requested,
				struct avc_entry_ref *aeref, struct av_decision *avd){return 0;}
extern int avc_has_perm(security_id_t ssid, security_id_t tsid,
			security_class_t tclass, access_vector_t requested,
			struct avc_entry_ref *aeref, void *auditdata){return 0;}
extern void avc_audit(security_id_t ssid, security_id_t tsid,
		      security_class_t tclass, access_vector_t requested,
		      struct av_decision *avd, int result, void *auditdata){}
extern int avc_compute_create(security_id_t ssid,
			      security_id_t tsid,
			      security_class_t tclass, security_id_t * newsid){return 0;}
extern int avc_compute_member(security_id_t ssid,
			      security_id_t tsid,
			      security_class_t tclass, security_id_t * newsid){return 0;}
#define AVC_CALLBACK_GRANT		1
#define AVC_CALLBACK_TRY_REVOKE		2
#define AVC_CALLBACK_REVOKE		4
#define AVC_CALLBACK_RESET		8
#define AVC_CALLBACK_AUDITALLOW_ENABLE	16
#define AVC_CALLBACK_AUDITALLOW_DISABLE	32
#define AVC_CALLBACK_AUDITDENY_ENABLE	64
#define AVC_CALLBACK_AUDITDENY_DISABLE	128
extern int avc_add_callback(int (*callback)
			     (uint32_t event, security_id_t ssid,
			      security_id_t tsid, security_class_t tclass,
			      access_vector_t perms,
			      access_vector_t * out_retained),
			    uint32_t events, security_id_t ssid,
			    security_id_t tsid, security_class_t tclass,
			    access_vector_t perms){return 0;}

#define AVC_CACHE_STATS     1

struct avc_cache_stats {
	unsigned entry_lookups;
	unsigned entry_hits;
	unsigned entry_misses;
	unsigned entry_discards;
	unsigned cav_lookups;
	unsigned cav_hits;
	unsigned cav_probes;
	unsigned cav_misses;
};
extern void avc_cache_stats(struct avc_cache_stats *stats){}
extern void avc_av_stats(void){}
extern void avc_sid_stats(void){}
extern int avc_netlink_open(int blocking){return 0;}
extern void avc_netlink_loop(void){}
extern void avc_netlink_close(void){}
extern int avc_netlink_acquire_fd(void){return 0;}
extern void avc_netlink_release_fd(void){}
extern int avc_netlink_check_nb(void){return 0;}
extern int selinux_status_open(int fallback){return 0;}
extern void selinux_status_close(void){}
extern int selinux_status_updated(void){return 0;}
extern int selinux_status_getenforce(void){return 0;}
extern int selinux_status_policyload(void){return 0;}
extern int selinux_status_deny_unknown(void){return 0;}

