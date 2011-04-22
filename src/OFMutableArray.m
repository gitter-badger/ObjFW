/*
 * Copyright (c) 2008, 2009, 2010, 2011
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

#include "config.h"

#include <string.h>

#import "OFMutableArray.h"
#import "OFDataArray.h"
#import "OFAutoreleasePool.h"

#import "OFEnumerationMutationException.h"
#import "OFInvalidArgumentException.h"
#import "OFOutOfRangeException.h"

@implementation OFMutableArray
- copy
{
	OFArray *copy = [[OFArray alloc] init];
	id *cArray = [array cArray];
	size_t i, count = [array count];

	[copy->array addNItems: count
		    fromCArray: cArray];

	for (i = 0; i < count; i++)
		[cArray[i] retain];

	return copy;
}

- (void)addObject: (id)object
{
	[array addItem: &object];
	[object retain];

	mutations++;
}

- (void)addObject: (id)object
	  atIndex: (size_t)index
{
	[array addItem: &object
	       atIndex: index];
	[object retain];

	mutations++;
}

- (void)replaceObject: (id)oldObject
	   withObject: (id)newObject
{
	id *cArray = [array cArray];
	size_t i, count = [array count];

	for (i = 0; i < count; i++) {
		if ([cArray[i] isEqual: oldObject]) {
			[newObject retain];
			[cArray[i] release];
			cArray[i] = newObject;

			return;
		}
	}
}

- (void)replaceObjectAtIndex: (size_t)index
		  withObject: (id)object
{
	id *cArray = [array cArray];
	id oldObject;

	if (index >= [array count])
		@throw [OFOutOfRangeException newWithClass: isa];

	oldObject = cArray[index];
	cArray[index] = [object retain];
	[oldObject release];
}

- (void)replaceObjectIdenticalTo: (id)oldObject
		      withObject: (id)newObject
{
	id *cArray = [array cArray];
	size_t i, count = [array count];

	for (i = 0; i < count; i++) {
		if (cArray[i] == oldObject) {
			[newObject retain];
			[cArray[i] release];
			cArray[i] = newObject;

			return;
		}
	}
}

- (void)removeObject: (id)object
{
	id *cArray = [array cArray];
	size_t i, count = [array count];

	for (i = 0; i < count; i++) {
		if ([cArray[i] isEqual: object]) {
			object = cArray[i];

			[array removeItemAtIndex: i];
			mutations++;

			[object release];

			return;
		}
	}
}

- (void)removeObjectIdenticalTo: (id)object
{
	id *cArray = [array cArray];
	size_t i, count = [array count];

	for (i = 0; i < count; i++) {
		if (cArray[i] == object) {
			[array removeItemAtIndex: i];
			mutations++;

			[object release];

			return;
		}
	}
}

- (void)removeObjectAtIndex: (size_t)index
{
	id object = [self objectAtIndex: index];
	[array removeItemAtIndex: index];
	[object release];

	mutations++;
}

- (void)removeNObjects: (size_t)nObjects
{
	id *cArray = [array cArray], *copy;
	size_t i, count = [array count];

	if (nObjects > count)
		@throw [OFOutOfRangeException newWithClass: isa];

	copy = [self allocMemoryForNItems: nObjects
				 withSize: sizeof(id)];
	memcpy(copy, cArray + (count - nObjects), nObjects * sizeof(id));

	@try {
		[array removeNItems: nObjects];
		mutations++;

		for (i = 0; i < nObjects; i++)
			[copy[i] release];
	} @finally {
		[self freeMemory: copy];
	}
}

- (void)removeNObjects: (size_t)nObjects
	       atIndex: (size_t)index
{
	id *cArray = [array cArray], *copy;
	size_t i, count = [array count];

	if (nObjects > count - index)
		@throw [OFOutOfRangeException newWithClass: isa];

	copy = [self allocMemoryForNItems: nObjects
				 withSize: sizeof(id)];
	memcpy(copy, cArray + index, nObjects * sizeof(id));

	@try {
		[array removeNItems: nObjects
			    atIndex: index];
		mutations++;

		for (i = 0; i < nObjects; i++)
			[copy[i] release];
	} @finally {
		[self freeMemory: copy];
	}
}

- (int)countByEnumeratingWithState: (of_fast_enumeration_state_t*)state
			   objects: (id*)objects
			     count: (int)count_
{
	size_t count = [array count];

	if (count > INT_MAX)
		@throw [OFOutOfRangeException newWithClass: isa];

	if (state->state >= count)
		return 0;

	state->state = count;
	state->itemsPtr = [array cArray];
	state->mutationsPtr = &mutations;

	return (int)count;
}

- (OFEnumerator*)objectEnumerator
{
	return [[[OFArrayEnumerator alloc]
	       initWithArray: self
		   dataArray: array
	    mutationsPointer: &mutations] autorelease];
}

#ifdef OF_HAVE_BLOCKS
- (void)enumerateObjectsUsingBlock: (of_array_enumeration_block_t)block
{
	OFAutoreleasePool *pool = [[OFAutoreleasePool alloc] init];
	id *cArray = [array cArray];
	size_t i, count = [array count];
	BOOL stop = NO;
	unsigned long mutations2 = mutations;

	for (i = 0; i < count && !stop; i++) {
		if (mutations != mutations2)
			@throw [OFEnumerationMutationException
			    newWithClass: isa
				  object: self];

		block(cArray[i], i, &stop);
		[pool releaseObjects];
	}

	[pool release];
}

- (void)replaceObjectsUsingBlock: (of_array_replace_block_t)block
{
	OFAutoreleasePool *pool = [[OFAutoreleasePool alloc] init];
	id *cArray = [array cArray];
	size_t i, count = [array count];
	BOOL stop = NO;
	unsigned long mutations2 = mutations;

	for (i = 0; i < count && !stop; i++) {
		id newObject;

		if (mutations != mutations2)
			@throw [OFEnumerationMutationException
			    newWithClass: isa
				  object: self];

		newObject = block(cArray[i], i, &stop);

		if (newObject == nil)
			@throw [OFInvalidArgumentException newWithClass: isa
							       selector: _cmd];

		[newObject retain];
		[cArray[i] release];
		cArray[i] = newObject;

		[pool releaseObjects];
	}

	[pool release];
}
#endif
@end
