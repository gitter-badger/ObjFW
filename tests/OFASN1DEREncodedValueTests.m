/*
 * Copyright (c) 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017,
 *               2018, 2019
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

#import "TestsAppDelegate.h"

static OFString *module;

@implementation TestsAppDelegate (OFASN1DEREncodedValueTests)
- (void)ASN1DEREncodedValueTests
{
	OFAutoreleasePool *pool = [[OFAutoreleasePool alloc] init];

	module = @"OFASN1Boolean";
	TEST(@"-[DEREncodedValue]",
	    [[[OFASN1Boolean booleanWithBooleanValue: false] DEREncodedValue]
	    isEqual: [OFData dataWithItems: "\x01\x01\x00"
				     count: 3]] &&
	    [[[OFASN1Boolean booleanWithBooleanValue: true] DEREncodedValue]
	    isEqual: [OFData dataWithItems: "\x01\x01\xFF"
				     count: 3]])

	[pool drain];
}
@end
