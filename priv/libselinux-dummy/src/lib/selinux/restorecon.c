#include <sys/types.h>
#include <stdarg.h>
struct selabel_handle;
extern int selinux_restorecon(const char *pathname,
				    unsigned int restorecon_flags){return 0;}
#define SELINUX_RESTORECON_IGNORE_DIGEST		0x00001
#define SELINUX_RESTORECON_NOCHANGE			0x00002
#define SELINUX_RESTORECON_SET_SPECFILE_CTX		0x00004
#define SELINUX_RESTORECON_RECURSE			0x00008
#define SELINUX_RESTORECON_VERBOSE			0x00010
#define SELINUX_RESTORECON_PROGRESS			0x00020
#define SELINUX_RESTORECON_REALPATH			0x00040
#define SELINUX_RESTORECON_XDEV				0x00080
#define SELINUX_RESTORECON_ADD_ASSOC			0x00100
#define SELINUX_RESTORECON_ABORT_ON_ERROR		0x00200
#define SELINUX_RESTORECON_SYSLOG_CHANGES		0x00400
#define SELINUX_RESTORECON_LOG_MATCHES			0x00800
#define SELINUX_RESTORECON_IGNORE_NOENTRY		0x01000
#define SELINUX_RESTORECON_IGNORE_MOUNTS		0x02000
#define SELINUX_RESTORECON_MASS_RELABEL			0x04000
#define SELINUX_RESTORECON_SKIP_DIGEST			0x08000
#define SELINUX_RESTORECON_CONFLICT_ERROR		0x10000
extern void selinux_restorecon_set_sehandle(struct selabel_handle *hndl){}
extern struct selabel_handle *selinux_restorecon_default_handle(void);
extern void selinux_restorecon_set_exclude_list(const char **exclude_list);
extern int selinux_restorecon_set_alt_rootpath(const char *alt_rootpath){return 0;}
enum digest_result {
	MATCH = 0,
	NOMATCH,
	DELETED_MATCH,
	DELETED_NOMATCH,
	ERROR
};

struct dir_xattr {
	char *directory;
	char *digest; /* A hex encoded string that can be printed. */
	enum digest_result result;
	struct dir_xattr *next;
};
extern int selinux_restorecon_xattr(const char *pathname,
				    unsigned int xattr_flags,
				    struct dir_xattr ***xattr_list){return 0;}
#define SELINUX_RESTORECON_XATTR_RECURSE			0x0001
#define SELINUX_RESTORECON_XATTR_DELETE_NONMATCH_DIGESTS	0x0002
#define SELINUX_RESTORECON_XATTR_DELETE_ALL_DIGESTS		0x0004
#define SELINUX_RESTORECON_XATTR_IGNORE_MOUNTS			0x0008
