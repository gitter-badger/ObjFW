/*
 * Copyright (c) 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017
 *   Jonathan Schleifer <js@heap.zone>
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

#include <stdlib.h>

#include <assert.h>

#import "OFDictionary.h"
#import "OFDictionary_hashtable.h"
#import "OFArray.h"
#import "OFCharacterSet.h"
#import "OFString.h"
#import "OFXMLElement.h"
#import "OFData.h"

#import "OFInvalidArgumentException.h"
#import "OFOutOfRangeException.h"
#import "OFUndefinedKeyException.h"

static struct {
	Class isa;
} placeholder;

static OFCharacterSet *URLQueryPartAllowedCharacterSet = nil;

@interface OFDictionary ()
- (OFString *)of_JSONRepresentationWithOptions: (int)options
					 depth: (size_t)depth;
@end

@interface OFDictionary_placeholder: OFDictionary
@end

@interface OFCharacterSet_URLQueryPartAllowed: OFCharacterSet
+ (OFCharacterSet *)URLQueryPartAllowedCharacterSet;
@end

@implementation OFDictionary_placeholder
- (instancetype)init
{
	return (id)[[OFDictionary_hashtable alloc] init];
}

- (instancetype)initWithDictionary: (OFDictionary *)dictionary
{
	return (id)[[OFDictionary_hashtable alloc]
	    initWithDictionary: dictionary];
}

- (instancetype)initWithObject: (id)object
			forKey: (id)key
{
	return (id)[[OFDictionary_hashtable alloc] initWithObject: object
							   forKey: key];
}

- (instancetype)initWithObjects: (OFArray *)objects
			forKeys: (OFArray *)keys
{
	return (id)[[OFDictionary_hashtable alloc] initWithObjects: objects
							   forKeys: keys];
}

- (instancetype)initWithObjects: (id const *)objects
			forKeys: (id const *)keys
			  count: (size_t)count
{
	return (id)[[OFDictionary_hashtable alloc] initWithObjects: objects
							   forKeys: keys
							     count: count];
}

- (instancetype)initWithKeysAndObjects: (id <OFCopying>)firstKey, ...
{
	id ret;
	va_list arguments;

	va_start(arguments, firstKey);
	ret = [[OFDictionary_hashtable alloc] initWithKey: firstKey
						arguments: arguments];
	va_end(arguments);

	return ret;
}

- (instancetype)initWithKey: (id <OFCopying>)firstKey
		  arguments: (va_list)arguments
{
	return (id)[[OFDictionary_hashtable alloc] initWithKey: firstKey
						     arguments: arguments];
}

- (instancetype)initWithSerialization: (OFXMLElement *)element
{
	return (id)[[OFDictionary_hashtable alloc]
	    initWithSerialization: element];
}

- (instancetype)retain
{
	return self;
}

- (instancetype)autorelease
{
	return self;
}

- (void)release
{
}

- (void)dealloc
{
	OF_DEALLOC_UNSUPPORTED
}
@end

@implementation OFCharacterSet_URLQueryPartAllowed
+ (void)initialize
{
	if (self != [OFCharacterSet_URLQueryPartAllowed class])
		return;

	URLQueryPartAllowedCharacterSet =
	    [[OFCharacterSet_URLQueryPartAllowed alloc] init];
}

+ (OFCharacterSet *)URLQueryPartAllowedCharacterSet
{
	return URLQueryPartAllowedCharacterSet;
}

- (instancetype)autorelease
{
	return self;
}

- (instancetype)retain
{
	return self;
}

- (void)release
{
}

- (unsigned int)retainCount
{
	return OF_RETAIN_COUNT_MAX;
}

- (bool)characterIsMember: (of_unichar_t)character
{
	if (character < CHAR_MAX && of_ascii_isalnum(character))
		return true;

	switch (character) {
	case '-':
	case '.':
	case '_':
	case '~':
	case '!':
	case '$':
	case '\'':
	case '(':
	case ')':
	case '*':
	case '+':
	case ',':
	case ';':
		return true;
	default:
		return false;
	}
}
@end

@implementation OFDictionary
+ (void)initialize
{
	if (self == [OFDictionary class])
		placeholder.isa = [OFDictionary_placeholder class];
}

+ (instancetype)alloc
{
	if (self == [OFDictionary class])
		return (id)&placeholder;

	return [super alloc];
}

+ (instancetype)dictionary
{
	return [[[self alloc] init] autorelease];
}

+ (instancetype)dictionaryWithDictionary: (OFDictionary *)dictionary
{
	return [[[self alloc] initWithDictionary: dictionary] autorelease];
}

+ (instancetype)dictionaryWithObject: (id)object
			      forKey: (id)key
{
	return [[[self alloc] initWithObject: object
				      forKey: key] autorelease];
}

+ (instancetype)dictionaryWithObjects: (OFArray *)objects
			      forKeys: (OFArray *)keys
{
	return [[[self alloc] initWithObjects: objects
				      forKeys: keys] autorelease];
}

+ (instancetype)dictionaryWithObjects: (id const *)objects
			      forKeys: (id const *)keys
		  count: (size_t)count
{
	return [[[self alloc] initWithObjects: objects
				      forKeys: keys
					count: count] autorelease];
}

+ (instancetype)dictionaryWithKeysAndObjects: (id)firstKey, ...
{
	id ret;
	va_list arguments;

	va_start(arguments, firstKey);
	ret = [[[self alloc] initWithKey: firstKey
			       arguments: arguments] autorelease];
	va_end(arguments);

	return ret;
}

- (instancetype)init
{
	if ([self isMemberOfClass: [OFDictionary class]]) {
		@try {
			[self doesNotRecognizeSelector: _cmd];
		} @catch (id e) {
			[self release];
			@throw e;
		}

		abort();
	}

	return [super init];
}

- (instancetype)initWithDictionary: (OFDictionary *)dictionary
{
	OF_INVALID_INIT_METHOD
}

- (instancetype)initWithObject: (id)object
			forKey: (id)key
{
	if (key == nil || object == nil)
		@throw [OFInvalidArgumentException exception];

	return [self initWithKeysAndObjects: key, object, nil];
}

- (instancetype)initWithObjects: (OFArray *)objects_
			forKeys: (OFArray *)keys_
{
	id const *objects, *keys;
	size_t count;

	@try {
		count = [objects_ count];

		if (count != [keys_ count])
			@throw [OFInvalidArgumentException exception];

		objects = [objects_ objects];
		keys = [keys_ objects];
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return [self initWithObjects: objects
			     forKeys: keys
			       count: count];
}

- (instancetype)initWithObjects: (id const *)objects
			forKeys: (id const *)keys
			  count: (size_t)count
{
	OF_INVALID_INIT_METHOD
}

- (instancetype)initWithKeysAndObjects: (id)firstKey, ...
{
	id ret;
	va_list arguments;

	va_start(arguments, firstKey);
	ret = [self initWithKey: firstKey
		      arguments: arguments];
	va_end(arguments);

	return ret;
}

- (instancetype)initWithKey: (id)firstKey
		  arguments: (va_list)arguments
{
	OF_INVALID_INIT_METHOD
}

- (instancetype)initWithSerialization: (OFXMLElement *)element
{
	OF_INVALID_INIT_METHOD
}

- (id)objectForKey: (id)key
{
	OF_UNRECOGNIZED_SELECTOR
}

- (id)objectForKeyedSubscript: (id)key
{
	return [self objectForKey: key];
}

- (id)valueForKey: (OFString *)key
{
	if ([key hasPrefix: @"@"]) {
		void *pool = objc_autoreleasePoolPush();
		id ret;

		key = [key substringWithRange: of_range(1, [key length] - 1)];
		ret = [[super valueForKey: key] retain];

		objc_autoreleasePoolPop(pool);

		return [ret autorelease];
	}

	return [self objectForKey: key];
}

- (void)setValue: (id)value
	  forKey: (OFString *)key
{
	if ([key hasPrefix: @"@"]) {
		void *pool = objc_autoreleasePoolPush();

		key = [key substringWithRange: of_range(1, [key length] - 1)];
		[super setValue: value
			 forKey: key];

		objc_autoreleasePoolPop(pool);
		return;
	}

	if (![self isKindOfClass: [OFMutableDictionary class]])
		@throw [OFUndefinedKeyException exceptionWithObject: self
								key: key
							      value: value];

	[(OFMutableDictionary *)self setObject: value
					forKey: key];
}

- (size_t)count
{
	OF_UNRECOGNIZED_SELECTOR
}

- (id)copy
{
	return [self retain];
}

- (id)mutableCopy
{
	return [[OFMutableDictionary alloc] initWithDictionary: self];
}

- (bool)isEqual: (id)object
{
	OFDictionary *otherDictionary;
	void *pool;
	OFEnumerator *keyEnumerator, *objectEnumerator;
	id key;

	if (![object isKindOfClass: [OFDictionary class]])
		return false;

	otherDictionary = object;

	if ([otherDictionary count] != [self count])
		return false;

	pool = objc_autoreleasePoolPush();

	keyEnumerator = [self keyEnumerator];
	objectEnumerator = [self objectEnumerator];
	while ((key = [keyEnumerator nextObject]) != nil &&
	    (object = [objectEnumerator nextObject]) != nil) {
		id otherObject = [otherDictionary objectForKey: key];

		if (otherObject == nil || ![otherObject isEqual: object]) {
			objc_autoreleasePoolPop(pool);
			return false;
		}
	}

	objc_autoreleasePoolPop(pool);

	return true;
}

- (bool)containsObject: (id)object
{
	void *pool;
	OFEnumerator *enumerator;
	id currentObject;

	if (object == nil)
		return false;

	pool = objc_autoreleasePoolPush();

	enumerator = [self objectEnumerator];
	while ((currentObject = [enumerator nextObject]) != nil) {
		if ([currentObject isEqual: object]) {
			objc_autoreleasePoolPop(pool);
			return true;
		}
	}

	objc_autoreleasePoolPop(pool);

	return false;
}

- (bool)containsObjectIdenticalTo: (id)object
{
	void *pool;
	OFEnumerator *enumerator;
	id currentObject;

	if (object == nil)
		return false;

	pool = objc_autoreleasePoolPush();

	enumerator = [self objectEnumerator];
	while ((currentObject = [enumerator nextObject]) != nil) {
		if (currentObject == object) {
			objc_autoreleasePoolPop(pool);
			return true;
		}
	}

	objc_autoreleasePoolPop(pool);

	return false;
}

- (OFArray *)allKeys
{
	OFMutableArray *ret = [OFMutableArray arrayWithCapacity: [self count]];

	for (id key in self)
		[ret addObject: key];

	[ret makeImmutable];

	return ret;
}

- (OFArray *)allObjects
{
	OFMutableArray *ret = [OFMutableArray arrayWithCapacity: [self count]];
	void *pool = objc_autoreleasePoolPush();
	OFEnumerator *enumerator = [self objectEnumerator];
	id object;

	while ((object = [enumerator nextObject]) != nil)
		[ret addObject: object];

	[ret makeImmutable];

	objc_autoreleasePoolPop(pool);

	return ret;
}

- (OFEnumerator *)keyEnumerator
{
	OF_UNRECOGNIZED_SELECTOR
}

- (OFEnumerator *)objectEnumerator
{
	OF_UNRECOGNIZED_SELECTOR
}

- (int)countByEnumeratingWithState: (of_fast_enumeration_state_t *)state
			   objects: (id *)objects
			     count: (int)count
{
	OF_UNRECOGNIZED_SELECTOR
}

#ifdef OF_HAVE_BLOCKS
- (void)enumerateKeysAndObjectsUsingBlock:
    (of_dictionary_enumeration_block_t)block
{
	bool stop = false;

	for (id key in self) {
		block(key, [self objectForKey: key], &stop);

		if (stop)
			break;
	}
}

- (OFDictionary *)mappedDictionaryUsingBlock: (of_dictionary_map_block_t)block
{
	OFMutableDictionary *new = [OFMutableDictionary dictionary];

	[self enumerateKeysAndObjectsUsingBlock: ^ (id key, id object,
	    bool *stop) {
		[new setObject: block(key, object)
			forKey: key];
	}];

	[new makeImmutable];

	return new;
}

- (OFDictionary *)filteredDictionaryUsingBlock:
    (of_dictionary_filter_block_t)block
{
	OFMutableDictionary *new = [OFMutableDictionary dictionary];

	[self enumerateKeysAndObjectsUsingBlock: ^ (id key, id object,
	    bool *stop) {
		if (block(key, object))
			[new setObject: object
				forKey: key];
	}];

	[new makeImmutable];

	return new;
}
#endif

- (uint32_t)hash
{
	void *pool = objc_autoreleasePoolPush();
	OFEnumerator *keyEnumerator = [self keyEnumerator];
	OFEnumerator *objectEnumerator = [self objectEnumerator];
	id key, object;
	uint32_t hash = 0;

	while ((key = [keyEnumerator nextObject]) != nil &&
	    (object = [objectEnumerator nextObject]) != nil) {
		hash += [key hash];
		hash += [object hash];
	}

	objc_autoreleasePoolPop(pool);

	return hash;
}

- (OFString *)description
{
	OFMutableString *ret;
	void *pool;
	OFEnumerator *keyEnumerator, *objectEnumerator;
	id key, object;
	size_t i, count = [self count];

	if (count == 0)
		return @"{}";

	ret = [OFMutableString stringWithString: @"{\n"];
	pool = objc_autoreleasePoolPush();
	keyEnumerator = [self keyEnumerator];
	objectEnumerator = [self objectEnumerator];

	i = 0;
	while ((key = [keyEnumerator nextObject]) != nil &&
	    (object = [objectEnumerator nextObject]) != nil) {
		void *pool2 = objc_autoreleasePoolPush();

		[ret appendString: [key description]];
		[ret appendString: @" = "];
		[ret appendString: [object description]];

		if (++i < count)
			[ret appendString: @";\n"];

		objc_autoreleasePoolPop(pool2);
	}
	[ret replaceOccurrencesOfString: @"\n"
			     withString: @"\n\t"];
	[ret appendString: @";\n}"];

	[ret makeImmutable];

	objc_autoreleasePoolPop(pool);

	return ret;
}

- (OFString *)stringByURLEncoding
{
	OFMutableString *ret = [OFMutableString string];
	void *pool = objc_autoreleasePoolPush();
	OFEnumerator *keyEnumerator = [self keyEnumerator];
	OFEnumerator *objectEnumerator = [self objectEnumerator];
	OFCharacterSet *allowed = [OFCharacterSet_URLQueryPartAllowed
	    URLQueryPartAllowedCharacterSet];
	bool first = true;
	id key, object;

	while ((key = [keyEnumerator nextObject]) != nil &&
	    (object = [objectEnumerator nextObject]) != nil) {
		if OF_UNLIKELY (first)
			first = false;
		else
			[ret appendString: @"&"];

		[ret appendString: [[key description]
		    stringByURLEncodingWithAllowedCharacters: allowed]];
		[ret appendString: @"="];
		[ret appendString: [[object description]
		    stringByURLEncodingWithAllowedCharacters: allowed]];
	}

	[ret makeImmutable];

	objc_autoreleasePoolPop(pool);

	return ret;
}

- (OFXMLElement *)XMLElementBySerializing
{
	void *pool = objc_autoreleasePoolPush();
	OFXMLElement *element;
	OFEnumerator *keyEnumerator, *objectEnumerator;
	id key, object;

	if ([self isKindOfClass: [OFMutableDictionary class]])
		element = [OFXMLElement elementWithName: @"OFMutableDictionary"
					      namespace: OF_SERIALIZATION_NS];
	else
		element = [OFXMLElement elementWithName: @"OFDictionary"
					      namespace: OF_SERIALIZATION_NS];

	keyEnumerator = [self keyEnumerator];
	objectEnumerator = [self objectEnumerator];
	while ((key = [keyEnumerator nextObject]) != nil &&
	       (object = [objectEnumerator nextObject]) != nil) {
		void *pool2 = objc_autoreleasePoolPush();
		OFXMLElement *keyElement, *objectElement;

		keyElement = [OFXMLElement
		    elementWithName: @"key"
			  namespace: OF_SERIALIZATION_NS];
		[keyElement addChild: [key XMLElementBySerializing]];

		objectElement = [OFXMLElement
		    elementWithName: @"object"
			  namespace: OF_SERIALIZATION_NS];
		[objectElement addChild: [object XMLElementBySerializing]];

		[element addChild: keyElement];
		[element addChild: objectElement];

		objc_autoreleasePoolPop(pool2);
	}

	[element retain];

	objc_autoreleasePoolPop(pool);

	return [element autorelease];
}

- (OFString *)JSONRepresentation
{
	return [self of_JSONRepresentationWithOptions: 0
						depth: 0];
}

- (OFString *)JSONRepresentationWithOptions: (int)options
{
	return [self of_JSONRepresentationWithOptions: options
						depth: 0];
}

- (OFString *)of_JSONRepresentationWithOptions: (int)options
					 depth: (size_t)depth
{
	OFMutableString *JSON = [OFMutableString stringWithString: @"{"];
	void *pool = objc_autoreleasePoolPush();
	OFEnumerator *keyEnumerator = [self keyEnumerator];
	OFEnumerator *objectEnumerator = [self objectEnumerator];
	size_t i, count = [self count];
	id key, object;

	if (options & OF_JSON_REPRESENTATION_PRETTY) {
		OFMutableString *indentation = [OFMutableString string];

		for (i = 0; i < depth; i++)
			[indentation appendString: @"\t"];

		[JSON appendString: @"\n"];

		i = 0;
		while ((key = [keyEnumerator nextObject]) != nil &&
		    (object = [objectEnumerator nextObject]) != nil) {
			void *pool2 = objc_autoreleasePoolPush();
			int identifierOptions =
			    options | OF_JSON_REPRESENTATION_IDENTIFIER;

			if (![key isKindOfClass: [OFString class]])
				@throw [OFInvalidArgumentException exception];

			[JSON appendString: indentation];
			[JSON appendString: @"\t"];
			[JSON appendString: [key
			    of_JSONRepresentationWithOptions: identifierOptions
						       depth: depth + 1]];
			[JSON appendString: @": "];
			[JSON appendString: [object
			    of_JSONRepresentationWithOptions: options
						       depth: depth + 1]];

			if (++i < count)
				[JSON appendString: @",\n"];
			else
				[JSON appendString: @"\n"];

			objc_autoreleasePoolPop(pool2);
		}

		[JSON appendString: indentation];
	} else {
		i = 0;
		while ((key = [keyEnumerator nextObject]) != nil &&
		    (object = [objectEnumerator nextObject]) != nil) {
			void *pool2 = objc_autoreleasePoolPush();
			int identifierOptions =
			    options | OF_JSON_REPRESENTATION_IDENTIFIER;

			if (![key isKindOfClass: [OFString class]])
				@throw [OFInvalidArgumentException exception];

			[JSON appendString: [key
			    of_JSONRepresentationWithOptions: identifierOptions
						       depth: depth + 1]];
			[JSON appendString: @":"];
			[JSON appendString: [object
			    of_JSONRepresentationWithOptions: options
						       depth: depth + 1]];

			if (++i < count)
				[JSON appendString: @","];

			objc_autoreleasePoolPop(pool2);
		}
	}

	[JSON appendString: @"}"];
	[JSON makeImmutable];

	objc_autoreleasePoolPop(pool);

	return JSON;
}

- (OFData *)messagePackRepresentation
{
	OFMutableData *data;
	size_t i, count;
	void *pool;
	OFEnumerator *keyEnumerator, *objectEnumerator;
	id key, object;

	data = [OFMutableData data];
	count = [self count];

	if (count <= 15) {
		uint8_t tmp = 0x80 | ((uint8_t)count & 0xF);
		[data addItem: &tmp];
	} else if (count <= UINT16_MAX) {
		uint8_t type = 0xDE;
		uint16_t tmp = OF_BSWAP16_IF_LE((uint16_t)count);

		[data addItem: &type];
		[data addItems: &tmp
			 count: sizeof(tmp)];
	} else if (count <= UINT32_MAX) {
		uint8_t type = 0xDF;
		uint32_t tmp = OF_BSWAP32_IF_LE((uint32_t)count);

		[data addItem: &type];
		[data addItems: &tmp
			 count: sizeof(tmp)];
	} else
		@throw [OFOutOfRangeException exception];

	pool = objc_autoreleasePoolPush();

	i = 0;
	keyEnumerator = [self keyEnumerator];
	objectEnumerator = [self objectEnumerator];
	while ((key = [keyEnumerator nextObject]) != nil &&
	    (object = [objectEnumerator nextObject]) != nil) {
		void *pool2 = objc_autoreleasePoolPush();
		OFData *child;

		i++;

		child = [key messagePackRepresentation];
		[data addItems: [child items]
			 count: [child count]];

		child = [object messagePackRepresentation];
		[data addItems: [child items]
			 count: [child count]];

		objc_autoreleasePoolPop(pool2);
	}

	assert(i == count);

	[data makeImmutable];

	objc_autoreleasePoolPop(pool);

	return data;
}
@end
