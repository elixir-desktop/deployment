#include <sys/types.h>
#include <stdarg.h>
#include <stddef.h>

#define SELINUX_WARNING1
#define SELINUX_TRANS_DIR "/var/run/setrans"
#define SELINUX_INFO2
#define SELINUX_ERROR 0
#define SELINUX_CB_VALIDATE2
#define SELINUX_CB_SETENFORCE3
#define SELINUX_CB_POLICYLOAD4
#define SELINUX_CB_LOG0
#define SELINUX_CB_AUDIT1
#define SELINUX_AVD_FLAGS_PERMISSIVE0x0001
#define SELINUX_AVC3
#define MATCHPATHCON_VALIDATE 4
#define MATCHPATHCON_NOTRANS 2
#define MATCHPATHCON_BASEONLY 1

typedef unsigned short security_class_t;
typedef unsigned int access_vector_t;
struct av_decision;
typedef struct {
	char *name;
	int value;
} SELboolean;

extern void set_selinuxmnt(const char *mnt){
}
extern void set_matchpathcon_printf(void){
}
extern void set_matchpathcon_invalidcon(int i){
}
extern void set_matchpathcon_flags(unsigned int flags){
}
extern void set_matchpathcon_canoncon(int i){
}
extern void selinux_set_callback(int type, int cb){
}
extern void selinux_reset_config(void){
}
extern void selinux_flush_class_cache(void){

}
extern void print_access_vector(security_class_t tclass, access_vector_t av){

}
extern void matchpathcon_fini(void){

}
extern void matchpathcon_filespec_eval(void){

}
extern void matchpathcon_filespec_destroy(void){

}
extern void matchpathcon_checkmatches(char *str){

}
extern void freecon(char * con){

}
extern void freeconary(char ** con){

}
extern void fini_selinuxmnt(void){

}
extern security_class_t string_to_security_class(const char *name){
	return 0;
}
extern security_class_t mode_to_security_class(mode_t mode){
	return 0;
}
extern int setsockcreatecon_raw(const char * context){
	return 0;
}
extern int setsockcreatecon(const char * context){
	return 0;
}
extern int setkeycreatecon_raw(const char * context){
	return 0;
}
extern int setkeycreatecon(const char * context){
	return 0;
}
extern int setfscreatecon_raw(const char * context){
	return 0;
}
extern int setfscreatecon(const char * context){
	return 0;
}
extern int setfilecon_raw(const char *path, const char * con){
	return 0;
}
extern int setfilecon(const char *path, const char * con){
	return 0;
}
extern int setexecfilecon(const char *filename, const char *fallback_type){
	return 0;
}
extern int setexeccon_raw(const char * con){
	return 0;
}
extern int setexeccon(const char * con){
	return 0;
}
extern int setcon_raw(const char * con){
	return 0;
}
extern int setcon(const char * con){
	return 0;
}
extern int selinux_trans_to_raw_context(const char * trans, char ** rawp){
	return 0;
}
extern int selinux_set_policy_root(const char *rootpath){
	return 0;
}
extern int selinux_set_mapping(int map){
	return 0;
}
extern int selinux_raw_to_trans_context(const char * raw, char ** transp){
	return 0;
}
extern int selinux_raw_context_to_color(const char * raw, char **color_str){
	return 0;
}
extern int selinux_mkload_policy(int preservebools){
	return 0;
}
extern int selinux_lsetfilecon_default(const char *path){
	return 0;
}
extern int selinux_init_load_policy(int *enforce){
	return 0;
}
extern int selinux_getpolicytype(char **policytype){
	return 0;
}
extern int selinux_getenforcemode(int *enforce){
	return 0;
}
extern int selinuxfs_exists(void){
	return 0;
}
extern int selinux_file_context_verify(const char *path, mode_t mode){
	return 0;
}
extern int selinux_file_context_cmp(const char * a, const char * b){
	return 0;
}
extern int selinux_check_securetty_context(const char * tty_context){
	return 0;
}
extern int selinux_check_passwd_access(access_vector_t requested){
	return 0;
}
extern int selinux_check_access(const char * scon, const char * tcon, const char *tclass, const char *perm, void *auditdata){
	return 0;
}
extern int security_validatetrans_raw(const char *scon, const char *tcon, security_class_t tclass, const char *newcon){
	return 0;
}
extern int security_validatetrans(const char *scon, const char *tcon, security_class_t tclass, const char *newcon){
	return 0;
}
extern int security_setenforce(int value){
	return 0;
}
extern int security_set_boolean_list(size_t boolcnt, SELboolean * boollist, int permanent){
	return 0;
}
extern int security_set_boolean(const char *name, int value){
	return 0;
}
extern int security_reject_unknown(void){
	return 0;
}
extern int security_policyvers(void){
	return 0;
}
extern int security_load_policy(void *data, size_t len){
	return 0;
}
extern int security_load_booleans(char *path){
	return 0;
}
extern int security_get_initial_context_raw(const char *name, char ** con){
	return 0;
}
extern int security_get_initial_context(const char *name,char ** con){
	return 0;
}
extern int security_getenforce(void){
	return 0;
}
extern int security_get_checkreqprot(void){
	return 0;
}
extern int security_get_boolean_pending(const char *name){
	return 0;
}
extern int security_get_boolean_names(char ***names, int *len){
	return 0;
}
extern int security_get_boolean_active(const char *name){
	return 0;
}
extern int security_disable(void){
	return 0;
}
extern int security_deny_unknown(void){
	return 0;
}
extern int security_compute_user_raw(const char * scon, const char *username, char *** con){
	return 0;
}
extern int security_compute_user(const char * scon, const char *username, char *** con){
	return 0;
}
extern int security_compute_relabel_raw(const char * scon,const char * tcon,security_class_t tclass,char ** newcon){
	return 0;
}
extern int security_compute_relabel(const char * scon, const char * tcon, security_class_t tclass, char ** newcon){
	return 0;
}
extern int security_compute_member_raw(const char * scon, const char * tcon, security_class_t tclass, char ** newcon){
	return 0;
}
extern int security_compute_member(const char * scon, const char * tcon, security_class_t tclass, char ** newcon){
	return 0;
}
extern int security_compute_create_raw(const char * scon, const char * tcon, security_class_t tclass, char ** newcon){
	return 0;
}
extern int security_compute_create_name_raw(const char * scon, const char * tcon, security_class_t tclass, const char *objname, char ** newcon){
	return 0;
}
extern int security_compute_create_name(const char * scon,const char * tcon,security_class_t tclass,const char *objname,char ** newcon){
	return 0;
}
extern int security_compute_create(const char * scon, const char * tcon, security_class_t tclass, char ** newcon){
	return 0;
}
extern int security_compute_av_raw(const char * scon, const char * tcon, security_class_t tclass, access_vector_t requested, struct av_decision *avd){
	return 0;
}
extern int security_compute_av_flags_raw(const char * scon, const char * tcon, security_class_t tclass, access_vector_t requested, struct av_decision *avd){
	return 0;
}
extern int security_compute_av_flags(const char * scon, const char * tcon, security_class_t tclass, access_vector_t requested, struct av_decision *avd){
	return 0;
}
extern int security_compute_av(const char * scon, const char * tcon, security_class_t tclass, access_vector_t requested, struct av_decision *avd){
	return 0;
}
extern int security_commit_booleans(void){
	return 0;
}
extern int security_check_context_raw(const char * con){
	return 0;
}
extern int security_check_context(const char * con){
	return 0;
}
extern int security_canonicalize_context_raw(const char * con, char ** canoncon){
	return 0;
}
extern int security_canonicalize_context(const char * con, char ** canoncon){
	return 0;
}
extern int security_av_string(int av, char **result){
	return 0;
}
extern int rpm_execcon(unsigned int verified, const char *filename, char *const argv[], char *const envp[]){
	return 0;
}
extern int realpath_not_final(const char *name, char *resolved_path){
	return 0;
}
extern int matchpathcon_init_prefix(const char *path, const char *prefix){
	return 0;
}
extern int matchpathcon_init(const char *path){
	return 0;
}
extern int matchpathcon_index(const char *path, mode_t mode, char ** con){
	return 0;
}
extern int matchpathcon_filespec_add(ino_t ino, int specind, const char *file){
	return 0;
}
extern int matchpathcon(const char *path, mode_t mode, char ** con){
	return 0;
}
extern int matchmediacon(const char *media, char ** con){
	return 0;
}
extern int lsetfilecon_raw(const char *path, const char * con){
	return 0;
}
extern int lsetfilecon(const char *path, const char * con){
	return 0;
}
extern int lgetfilecon_raw(const char *path, char ** con){
	return 0;
}
extern int lgetfilecon(const char *path, char ** con){
	return 0;
}
extern int is_selinux_mls_enabled(void){
	return 0;
}
extern int is_selinux_enabled(void){
	return 0;
}
extern int is_context_customizable(const char * scontext){
	return 0;
}
extern int getsockcreatecon_raw(char ** con){
	return 0;
}
extern int getsockcreatecon(char ** con){
	return 0;
}
extern int getseuser(const char *username, const char *service, char **r_seuser, char **r_level){
	return 0;
}
extern int getseuserbyname(const char *linuxuser, char **seuser, char **level){
	return 0;
}
extern int getprevcon_raw(char ** con){
	return 0;
}
extern int getprevcon(char ** con){
	return 0;
}
extern int getpidcon_raw(pid_t pid, char ** con){
	return 0;
}
extern int getpidcon(pid_t pid, char ** con){
	return 0;
}
extern int getpeercon_raw(int fd, char ** con){
	return 0;
}
extern int getpeercon(int fd, char ** con){
	return 0;
}
extern int getkeycreatecon_raw(char ** con){
	return 0;
}
extern int getkeycreatecon(char ** con){
	return 0;
}
extern int getfscreatecon_raw(char ** con){
	return 0;
}
extern int getfscreatecon(char ** con){
	return 0;
}
extern int getfilecon_raw(const char *path, char ** con){
	return 0;
}
extern int getfilecon(const char *path, char ** con){
	return 0;
}
extern int getexeccon_raw(char ** con){
	return 0;
}
extern int getexeccon(char ** con){
	return 0;
}
extern int getcon_raw(char ** con){
	return 0;
}
extern int getcon(char ** con){
	return 0;
}
extern int fsetfilecon_raw(int fd, const char * con){
	return 0;
}
extern int fsetfilecon(int fd, const char * con){
	return 0;
}
extern int fgetfilecon_raw(int fd, char ** con){
	return 0;
}
extern int fgetfilecon(int fd, char ** con){
	return 0;
}
extern int checkPasswdAccess(access_vector_t requested){
	return 0;
}
extern const char *selinux_x_context_path(void){
	return 0;
}
extern const char *selinux_virtual_image_context_path(void){
	return 0;
}
extern const char *selinux_virtual_domain_context_path(void){
	return 0;
}
extern const char *selinux_users_path(void){
	return 0;
}
extern const char *selinux_usersconf_path(void){
	return 0;
}
extern const char *selinux_user_contexts_path(void){
	return 0;
}
extern const char *selinux_translations_path(void){
	return 0;
}
extern const char *selinux_systemd_contexts_path(void){
	return 0;
}
extern const char *selinux_snapperd_contexts_path(void){
	return 0;
}
extern const char *selinux_sepgsql_context_path(void){
	return 0;
}
extern const char *selinux_securetty_types_path(void){
	return 0;
}
extern const char *selinux_removable_context_path(void){
	return 0;
}
extern const char *selinux_policy_root(void){
	return 0;
}
extern const char *selinux_path(void){
	return 0;
}
extern const char *selinux_openssh_contexts_path(void){
	return 0;
}
extern const char *selinux_openrc_contexts_path(void){
	return 0;
}
extern const char *selinux_netfilter_context_path(void){
	return 0;
}
extern const char *selinux_media_context_path(void){
	return 0;
}
extern const char *selinux_lxc_contexts_path(void){
	return 0;
}
extern const char *selinux_homedir_context_path(void){
	return 0;
}
extern const char *selinux_file_context_subs_path(void){
	return 0;
}
extern const char *selinux_file_context_subs_dist_path(void){
	return 0;
}
extern const char *selinux_file_context_path(void){
	return 0;
}
extern const char *selinux_file_context_local_path(void){
	return 0;
}
extern const char *selinux_file_context_homedir_path(void){
	return 0;
}
extern const char *selinux_failsafe_context_path(void){
	return 0;
}
extern const char *selinux_default_context_path(void){
	return 0;
}
extern const char *selinux_customizable_types_path(void){
	return 0;
}
extern const char *selinux_current_policy_path(void){
	return 0;
}
extern const char *selinux_contexts_path(void){
	return 0;
}
extern const char *selinux_colors_path(void){
	return 0;
}
extern const char *selinux_booleans_subs_path(void){
	return 0;
}
extern const char *selinux_booleans_path(void){
	return 0;
}
extern const char *selinux_binary_policy_path(void){
	return 0;
}
extern const char *security_class_to_string(security_class_t cls){
	return 0;
}
extern const char *security_av_perm_to_string(security_class_t tclass, access_vector_t perm){
	return 0;
}
extern char *selinux_boolean_sub(const char *boolean_name){
	return 0;
}
extern void get_default_context(void){}
extern void get_ordered_context_list(void){}
extern void get_ordered_context_list_with_level(void){}
extern void manual_user_enter_context(void){}
extern void selabel_cmp(void){}
extern void selinux_get_callback(void){}
extern void selinux_mnt(void){}
extern void selinux_restorecon_default_handle(void){}
extern void selinux_restorecon_set_exclude_list(void){}
extern void string_to_av_perm(void){}

