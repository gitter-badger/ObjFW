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

#import "OFException.h"

#ifndef OF_HAVE_SOCKETS
# error No sockets available!
#endif

OF_ASSUME_NONNULL_BEGIN

@class OFHTTPRequest;
@class OFHTTPResponse;

/**
 * @class OFHTTPRequestFailedException \
 *	  OFHTTPRequestFailedException.h \
 *	  ObjFW/OFHTTPRequestFailedException.h
 *
 * @brief An exception indicating that an HTTP request failed.
 */
@interface OFHTTPRequestFailedException: OFException
{
	OFHTTPRequest *_request;
	OFHTTPResponse *_response;
}

/**
 * @brief The HTTP request which failed.
 */
@property (readonly, nonatomic) OFHTTPRequest *request;

/**
 * @brief The response for the failed HTTP request.
 */
@property (readonly, nonatomic) OFHTTPResponse *response;

+ (instancetype)exception OF_UNAVAILABLE;

/**
 * @brief Creates a new, autoreleased HTTP request failed exception.
 *
 * @param request The HTTP request which failed
 * @param response The response for the failed HTTP request
 * @return A new, autoreleased HTTP request failed exception
 */
+ (instancetype)exceptionWithRequest: (OFHTTPRequest *)request
			    response: (OFHTTPResponse *)response;

- (instancetype)init OF_UNAVAILABLE;

/**
 * @brief Initializes an already allocated HTTP request failed exception.
 *
 * @param request The HTTP request which failed
 * @param response The response for the failed HTTP request
 * @return A new HTTP request failed exception
 */
- (instancetype)initWithRequest: (OFHTTPRequest *)request
		       response: (OFHTTPResponse *)response
    OF_DESIGNATED_INITIALIZER;
@end

OF_ASSUME_NONNULL_END
