/*
 * Copyright (c) 2008 - 2009
 *   Jonathan Schleifer <js@webkeks.org>
 *
 * All rights reserved.
 *
 * This file is part of libobjfw. It may be distributed under the terms of the
 * Q Public License 1.0, which can be found in the file LICENSE included in
 * the packaging of this file.
 */

#include "config.h"

#include <stdio.h>
#include <string.h>

#import "OFString.h"
#import "OFArray.h"
#import "OFAutoreleasePool.h"
#import "OFExceptions.h"

#ifndef _WIN32
#define ZD "%zd"
#else
#define ZD "%u"
#endif

#define NUM_TESTS 47
#define SUCCESS								\
	printf("\r\033[1;%dmTests successful: " ZD "/%d\033[0m",	\
	    (i == NUM_TESTS - 1 ? 32 : 33), i + 1, NUM_TESTS);		\
	fflush(stdout);
#define FAIL								\
	printf("\r\033[K\033[1;31mTest " ZD "/%d failed!\033[m\n",	\
	    i + 1, NUM_TESTS);						\
	return 1;
#define CHECK(cond)							\
	if (cond) {							\
		SUCCESS							\
	} else {							\
		FAIL							\
	}								\
	i++;
#define CHECK_EXCEPT(code, exception)					\
	@try {								\
		code;							\
		FAIL							\
	} @catch (exception *e) {					\
		SUCCESS							\
	}								\
	i++;

int
main()
{
	size_t i = 0;
	size_t j = 0;

	OFAutoreleasePool *pool = [[OFAutoreleasePool alloc] init];
	OFString *s1 = [OFMutableString stringWithCString: "test"];
	OFString *s2 = [OFMutableString stringWithCString: ""];
	OFString *s3;
	OFString *s4 = [OFMutableString string];
	OFArray *a;

	s3 = [s1 copy];

	CHECK([s1 isEqual: s3])
	CHECK(![s1 isEqual: [[OFObject alloc] init]])
	CHECK([s1 hash] == [s3 hash])

	[s2 appendCString: "12"];
	[s2 appendString: @"3"];
	[s4 setToCString: [s2 cString]];

	CHECK(![s2 compare: s4])
	CHECK(!strcmp([[s1 appendString: s2] cString], "test123"))
	CHECK([s1 hash] == 0xC44F49A4)
	CHECK(strlen([s1 cString]) == [s1 length] && [s1 length] == 7)
	CHECK(!strcmp([[s1 reverse] cString], "321tset"))
	CHECK(!strcmp([[s1 upper] cString], "321TSET"))
	CHECK(!strcmp([[s1 lower] cString], "321tset"))

	/* Also clears all the memory of the returned C strings */
	[pool release];

	/* UTF-8 tests */
	CHECK_EXCEPT(s1 = [OFString stringWithCString: "\xE0\x80"],
	    OFInvalidEncodingException)
	CHECK_EXCEPT(s1 = [OFString stringWithCString: "\xF0\x80\x80\xC0"],
	    OFInvalidEncodingException)

	s1 = [OFMutableString stringWithCString: "äöü€𝄞"];
	CHECK(!strcmp([[s1 reverse] cString], "𝄞€üöä"))
	[s1 dealloc];

	/* Format tests */
	s1 = [OFMutableString stringWithFormat: @"%s: %d", "test", 123];
	CHECK(!strcmp([s1 cString], "test: 123"))

	[s1 appendWithFormat: @"%02X", 15];
	CHECK(!strcmp([s1 cString], "test: 1230F"))

	/* Find index tests */
	CHECK([@"foo" indexOfFirstOccurrenceOfString: @"oo"] == 1)
	CHECK([@"foo" indexOfLastOccurrenceOfString: @"oo"] == 1)
	CHECK([@"foo" indexOfFirstOccurrenceOfString: @"o"] == 1)
	CHECK([@"foo" indexOfLastOccurrenceOfString: @"o"] == 2)
	CHECK([@"foo" indexOfFirstOccurrenceOfString: @"f"] == 0)
	CHECK([@"foo" indexOfLastOccurrenceOfString: @"f"] == 0)
	CHECK([@"foo" indexOfFirstOccurrenceOfString: @"x"] == SIZE_MAX)
	CHECK([@"foo" indexOfLastOccurrenceOfString: @"x"] == SIZE_MAX)

	/* Substring tests */
	CHECK([[@"foo" substringFromIndex: 1
				  toIndex: 2] isEqual: @"o"]);
	CHECK([[@"foo" substringFromIndex: 3
				  toIndex: 3] isEqual: @""]);
	CHECK_EXCEPT([@"foo" substringFromIndex: 2
					toIndex: 4], OFOutOfRangeException)
	CHECK_EXCEPT([@"foo" substringFromIndex: 4
					toIndex: 4], OFOutOfRangeException)
	CHECK_EXCEPT([@"foo" substringFromIndex: 2
					toIndex: 0], OFInvalidArgumentException)

	/* Split tests */
	a = [@"fooXXbarXXXXbazXXXX" splitWithDelimiter: @"XX"];
	CHECK([[a objectAtIndex: j++] isEqual: @"foo"])
	CHECK([[a objectAtIndex: j++] isEqual: @"bar"])
	CHECK([[a objectAtIndex: j++] isEqual: @""])
	CHECK([[a objectAtIndex: j++] isEqual: @"baz"])
	CHECK([[a objectAtIndex: j++] isEqual: @""])
	CHECK([[a objectAtIndex: j++] isEqual: @""])

	/* URL encoding tests */
	CHECK([[@"foo\"ba'_$" stringByURLEncoding] isEqual: @"foo%22ba%27_%24"])
	CHECK([[@"foo%20bar%22%24" stringByURLDecoding] isEqual: @"foo bar\"$"])
	CHECK_EXCEPT([@"foo%bar" stringByURLDecoding],
	    OFInvalidEncodingException)
	CHECK_EXCEPT([@"foo%FFbar" stringByURLDecoding],
	    OFInvalidEncodingException)

	/* Replace tests */
	s1 = [@"asd fo asd fofo asd" mutableCopy];
	[s1 replaceOccurrencesOfString: @"fo"
			    withString: @"foo"];
	CHECK([s1 isEqual: @"asd foo asd foofoo asd"])
	s1 = [@"XX" mutableCopy];
	[s1 replaceOccurrencesOfString: @"X"
			    withString: @"XX"];
	CHECK([s1 isEqual: @"XXXX"])

	/* Whitespace removing tests */
	s1 = [@"  \t\t \tasd  \t \t\t" mutableCopy];
	s2 = [s1 mutableCopy];
	s3 = [s1 mutableCopy];
	CHECK([[s1 removeLeadingWhitespaces] isEqual: @"asd  \t \t\t"])
	CHECK([[s2 removeTrailingWhitespaces] isEqual: @"  \t\t \tasd"])
	CHECK([[s3 removeLeadingAndTrailingWhitespaces] isEqual: @"asd"])

	s1 = [@" \t\t  \t\t  \t \t" mutableCopy];
	s2 = [s1 mutableCopy];
	s3 = [s1 mutableCopy];
	CHECK([[s1 removeLeadingWhitespaces] isEqual: @""])
	CHECK([[s2 removeTrailingWhitespaces] isEqual: @""])
	CHECK([[s3 removeLeadingAndTrailingWhitespaces] isEqual: @""])

	/* XML escaping tests */
	s1 = [@"<hello> &world'\"!&" stringByXMLEscaping];
	CHECK([s1 isEqual: @"&lt;hello&gt; &amp;world&apos;&quot;!&amp;"])

	puts("");

	return 0;
}
