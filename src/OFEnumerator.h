/*
 * Copyright (c) 2008 - 2009
 *   Jonathan Schleifer <js@webkeks.org>
 *
 * All rights reserved.
 *
 * This file is part of ObjFW. It may be distributed under the terms of the
 * Q Public License 1.0, which can be found in the file LICENSE included in
 * the packaging of this file.
 */

#import "OFObject.h"

/**
 * The OFEnumerator class provides methods to enumerate through collections.
 */
@interface OFEnumerator: OFObject {}
/**
 * \return The next object
 */
- (id)nextObject;

/**
 * Resets the enumerator, so the next call to nextObject returns the first
 * object again.
 */
- reset;
@end

/*
 * This needs to be exactly like this because it's hardcoded in the compiler.
 *
 * We need this bad check to see if we already imported Cocoa, which defines
 * this as well.
 */
#define of_fast_enumeration_state_t NSFastEnumerationState
#ifndef NSINTEGER_DEFINED
typedef struct __of_fast_enumeration_state {
	/// Arbitrary state information for the enumeration
	unsigned long state;
	/// Pointer to a C array of objects to return
	id *itemsPtr;
	/// Arbitrary state information to detect mutations
	unsigned long *mutationsPtr;
	/// Additional arbitrary state information
	unsigned long extra[5];
} of_fast_enumeration_state_t;
#endif

/**
 * The OFFastEnumeration protocol needs to be implemented by all classes
 * supporting fast enumeration.
 */
@protocol OFFastEnumeration
- (int)countByEnumeratingWithState: (of_fast_enumeration_state_t*)state
			   objects: (id*)objects
			     count: (int)count;
@end
