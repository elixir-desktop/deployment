typedef struct {
	void *ptr;
} context_s_t;
typedef context_s_t *context_t;
extern context_t context_new(const char * name){}
extern char *context_str(int context_t){return 0;}
extern void context_free(int context_t){}
extern const char * context_type_get(int context_t){return 0;}
extern const char * context_range_get(int context_t){return 0;}
extern const char * context_role_get(int context_t){return 0;}
extern const char * context_user_get(int context_t){return 0;}
extern int context_type_set(int context_t, const char * name){return 0;}
extern int context_range_set(int context_t, const char * name){return 0;}
extern int context_role_set(int context_t, const char * name){return 0;}
extern int context_user_set(int context_t, const char * name){return 0;}
extern const char *selinux_default_type_path(void){}
extern int get_default_type(const char *role, char **type){}
extern char*  get_default_context_with_level(){}
extern char* get_default_context_with_rolelevel(){}
