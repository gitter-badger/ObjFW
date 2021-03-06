/*
 * Copyright (c) 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017,
 *               2018, 2019, 2020
 *   Jonathan Schleifer <js@nil.im>
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

#include "config.h"

#include <string.h>

#import "ObjFWRT.h"
#import "private.h"

#ifdef OF_HAVE_THREADS
# import "mutex.h"
# define NUM_SPINLOCKS 8	/* needs to be a power of 2 */
# define SPINLOCK_HASH(p) ((unsigned)((uintptr_t)p >> 4) & (NUM_SPINLOCKS - 1))
static of_spinlock_t spinlocks[NUM_SPINLOCKS];
#endif

#ifdef OF_HAVE_THREADS
OF_CONSTRUCTOR()
{
	for (size_t i = 0; i < NUM_SPINLOCKS; i++)
		if (!of_spinlock_new(&spinlocks[i]))
			OBJC_ERROR("Failed to initialize spinlocks!")
}
#endif

id
objc_getProperty(id self, SEL _cmd, ptrdiff_t offset, bool atomic)
{
	if (atomic) {
		id *ptr = (id *)(void *)((char *)self + offset);
#ifdef OF_HAVE_THREADS
		unsigned hash = SPINLOCK_HASH(ptr);

		OF_ENSURE(of_spinlock_lock(&spinlocks[hash]));
		@try {
			return [[*ptr retain] autorelease];
		} @finally {
			OF_ENSURE(of_spinlock_unlock(&spinlocks[hash]));
		}
#else
		return [[*ptr retain] autorelease];
#endif
	}

	return *(id *)(void *)((char *)self + offset);
}

void
objc_setProperty(id self, SEL _cmd, ptrdiff_t offset, id value, bool atomic,
    signed char copy)
{
	if (atomic) {
		id *ptr = (id *)(void *)((char *)self + offset);
#ifdef OF_HAVE_THREADS
		unsigned hash = SPINLOCK_HASH(ptr);

		OF_ENSURE(of_spinlock_lock(&spinlocks[hash]));
		@try {
#endif
			id old = *ptr;

			switch (copy) {
			case 0:
				*ptr = [value retain];
				break;
			case 2:
				*ptr = [value mutableCopy];
				break;
			default:
				*ptr = [value copy];
			}

			[old release];
#ifdef OF_HAVE_THREADS
		} @finally {
			OF_ENSURE(of_spinlock_unlock(&spinlocks[hash]));
		}
#endif

		return;
	}

	id *ptr = (id *)(void *)((char *)self + offset);
	id old = *ptr;

	switch (copy) {
	case 0:
		*ptr = [value retain];
		break;
	case 2:
		*ptr = [value mutableCopy];
		break;
	default:
		*ptr = [value copy];
	}

	[old release];
}

/* The following methods are only required for GCC >= 4.6 */
void
objc_getPropertyStruct(void *dest, const void *src, ptrdiff_t size, bool atomic,
    bool strong)
{
	if (atomic) {
#ifdef OF_HAVE_THREADS
		unsigned hash = SPINLOCK_HASH(src);

		OF_ENSURE(of_spinlock_lock(&spinlocks[hash]));
#endif
		memcpy(dest, src, size);
#ifdef OF_HAVE_THREADS
		OF_ENSURE(of_spinlock_unlock(&spinlocks[hash]));
#endif

		return;
	}

	memcpy(dest, src, size);
}

void
objc_setPropertyStruct(void *dest, const void *src, ptrdiff_t size, bool atomic,
    bool strong)
{
	if (atomic) {
#ifdef OF_HAVE_THREADS
		unsigned hash = SPINLOCK_HASH(src);

		OF_ENSURE(of_spinlock_lock(&spinlocks[hash]));
#endif
		memcpy(dest, src, size);
#ifdef OF_HAVE_THREADS
		OF_ENSURE(of_spinlock_unlock(&spinlocks[hash]));
#endif

		return;
	}

	memcpy(dest, src, size);
}

objc_property_t *
class_copyPropertyList(Class class, unsigned int *outCount)
{
	unsigned int i, count;
	struct objc_property_list *iter;
	objc_property_t *properties;

	if (class == Nil) {
		if (outCount != NULL)
			*outCount = 0;

		return NULL;
	}

	objc_global_mutex_lock();

	count = 0;
	if (class->info & OBJC_CLASS_INFO_NEW_ABI)
		for (iter = class->propertyList; iter != NULL;
		    iter = iter->next)
			count += iter->count;

	if (count == 0) {
		if (outCount != NULL)
			*outCount = 0;

		objc_global_mutex_unlock();
		return NULL;
	}

	properties = malloc((count + 1) * sizeof(objc_property_t));
	if (properties == NULL)
		OBJC_ERROR("Not enough memory to copy properties");

	i = 0;
	for (iter = class->propertyList; iter != NULL; iter = iter->next)
		for (unsigned int j = 0; j < iter->count; j++)
			properties[i++] = &iter->properties[j];
	OF_ENSURE(i == count);
	properties[count] = NULL;

	if (outCount != NULL)
		*outCount = count;

	objc_global_mutex_unlock();

	return properties;
}

const char *
property_getName(objc_property_t property)
{
	return property->name;
}

char *
property_copyAttributeValue(objc_property_t property, const char *name)
{
	char *ret = NULL;
	bool nullIsError = false;

	if (strlen(name) != 1)
		return NULL;

	switch (*name) {
	case 'T':
		ret = of_strdup(property->getter.typeEncoding);
		nullIsError = true;
		break;
	case 'G':
		if (property->attributes & OBJC_PROPERTY_GETTER) {
			ret = of_strdup(property->getter.name);
			nullIsError = true;
		}
		break;
	case 'S':
		if (property->attributes & OBJC_PROPERTY_SETTER) {
			ret = of_strdup(property->setter.name);
			nullIsError = true;
		}
		break;
#define BOOL_CASE(name, field, flag)		\
	case name:				\
		if (property->field & flag) {	\
			ret = calloc(1, 1);	\
			nullIsError = true;	\
		}				\
		break;

	BOOL_CASE('R', attributes, OBJC_PROPERTY_READONLY)
	BOOL_CASE('C', attributes, OBJC_PROPERTY_COPY)
	BOOL_CASE('&', attributes, OBJC_PROPERTY_RETAIN)
	BOOL_CASE('N', attributes, OBJC_PROPERTY_NONATOMIC)
	BOOL_CASE('D', extendedAttributes, OBJC_PROPERTY_DYNAMIC)
	BOOL_CASE('W', extendedAttributes, OBJC_PROPERTY_WEAK)
#undef BOOL_CASE
	}

	if (nullIsError && ret == NULL)
		OBJC_ERROR("Not enough memory to copy property attribute "
		    "value");

	return ret;
}
