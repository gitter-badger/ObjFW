/*
 * Copyright (c) 2008, 2009, 2010, 2011, 2012
 *   Jonathan Schleifer <js@webkeks.org>
 *
 * All rights reserved.
 *
 * This file is part of ObjFW. It may be distributed under the terms of the
 * Q Public License 1.0, which can be found in the file LICENSE.QPL included in
 * the packaging of this file.
 *
 * Alternatively, it may be distributed under the terms of the GNU General
 * Public License, either version 2 or 3, which can be found in the file
 * LICENSE.GPLv2 or LICENSE.GPLv3 respectively included in the packaging of this
 * file.
 */

#import "threading.h"

struct objc_abi_class {
	struct objc_abi_class *metaclass;
	const char *superclass;
	const char *name;
	unsigned long version;
	unsigned long info;
	unsigned long instance_size;
	void *ivars;
	struct objc_abi_method_list *methodlist;
	void *dtable;
	void *subclass_list;
	void *sibling_class;
	void *protocols;
	void *gc_object_type;
	long abi_version;
	void *ivar_offsets;
	void *properties;
};

struct objc_abi_method {
	const char *name;
	const char *types;
	IMP imp;
};

struct objc_abi_method_list {
	struct objc_abi_method_list *next;
	unsigned int count;
	struct objc_abi_method methods[1];
};

struct objc_abi_selector {
	const char *name;
	const char *types;
};

struct objc_abi_category {
	const char *category_name;
	const char *class_name;
	struct objc_abi_method_list *instance_methods;
	struct objc_abi_method_list *class_methods;
	struct objc_protocol_list *protocols;
};

struct objc_abi_method_description {
	const char *name;
	const char *types;
};

struct objc_abi_method_description_list {
	int count;
	struct objc_abi_method_description list[1];
};

struct objc_abi_static_instances {
	const char *class_name;
	id instances[1];
};

struct objc_abi_symtab {
	unsigned long unknown;
	struct objc_abi_selector *sel_refs;
	uint16_t cls_def_cnt;
	uint16_t cat_def_cnt;
	void *defs[1];
};

struct objc_abi_module {
	unsigned long version;	/* 9 = non-fragile */
	unsigned long size;
	const char *name;
	struct objc_abi_symtab *symtab;
};

struct objc_hashtable_bucket {
	const char *key;
	const void *obj;
	uint32_t hash;
};

struct objc_hashtable {
	uint32_t count;
	uint32_t last_idx;
	struct objc_hashtable_bucket **data;
};

struct objc_sparsearray {
	struct objc_sparsearray_level2 *buckets[256];
};

struct objc_sparsearray_level2 {
	struct objc_sparsearray_level3 *buckets[256];
	BOOL empty;
};

struct objc_sparsearray_level3 {
	const void *buckets[256];
	BOOL empty;
};

enum objc_abi_class_info {
	OBJC_CLASS_INFO_CLASS	    = 0x001,
	OBJC_CLASS_INFO_METACLASS   = 0x002,
	OBJC_CLASS_INFO_SETUP	    = 0x100,
	OBJC_CLASS_INFO_LOADED	    = 0x200,
	OBJC_CLASS_INFO_INITIALIZED = 0x400
};

typedef struct {
	of_mutex_t mutex;
	of_thread_t owner;
	int count;
} objc_mutex_t;

extern void objc_register_all_categories(struct objc_abi_symtab*);
extern struct objc_category** objc_categories_for_class(Class);
extern void objc_free_all_categories(void);
extern void objc_update_dtable(Class);
extern void objc_register_all_classes(struct objc_abi_symtab*);
extern Class objc_classname_to_class(const char*);
extern void objc_free_all_classes(void);
extern uint32_t objc_hash_string(const char*);
extern struct objc_hashtable* objc_hashtable_alloc(uint32_t);
extern void objc_hashtable_set(struct objc_hashtable*, const char*,
    const void*);
extern const void* objc_hashtable_get(struct objc_hashtable*, const char*);
extern void objc_hashtable_free(struct objc_hashtable *h);
extern BOOL objc_hashtable_warn_on_collision;
extern void objc_register_selector(struct objc_abi_selector*);
extern void objc_register_all_selectors(struct objc_abi_symtab*);
extern void objc_free_all_selectors(void);
extern struct objc_sparsearray* objc_sparsearray_new(void);
extern void objc_sparsearray_copy(struct objc_sparsearray*,
    struct objc_sparsearray*);
extern void objc_sparsearray_set(struct objc_sparsearray*, uint32_t,
    const void*);
extern void objc_sparsearray_free(struct objc_sparsearray*);
extern void objc_sparsearray_free_when_singlethreaded(struct objc_sparsearray*);
extern void objc_sparsearray_cleanup(void);
extern void objc_init_static_instances(struct objc_abi_symtab*);
extern void __objc_exec_class(struct objc_abi_module*);
extern BOOL objc_mutex_new(objc_mutex_t*);
extern BOOL objc_mutex_lock(objc_mutex_t*);
extern BOOL objc_mutex_unlock(objc_mutex_t*);
extern BOOL objc_mutex_free(objc_mutex_t*);
extern void objc_global_mutex_lock(void);
extern void objc_global_mutex_unlock(void);
extern void objc_global_mutex_free(void);
extern void objc_free_when_singlethreaded(void*);

static inline const void*
objc_sparsearray_get(const struct objc_sparsearray *s, uint32_t idx)
{
	uint8_t i = idx >> 16;
	uint8_t j = idx >>  8;
	uint8_t k = idx;

	return s->buckets[i]->buckets[j]->buckets[k];
}

#define ERROR(...)							\
	{								\
		fprintf(stderr, "[objc @ " __FILE__ ":%d] ", __LINE__);	\
		fprintf(stderr, __VA_ARGS__);				\
		fputs("\n", stderr);					\
		abort();						\
	}
