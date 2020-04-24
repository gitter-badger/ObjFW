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

#import "OFStream.h"

#import "socket.h"

OF_ASSUME_NONNULL_BEGIN

/*!
 * @class OFStreamSocket OFStreamSocket.h ObjFW/OFStreamSocket.h
 *
 * @brief A class which provides methods to create and use stream sockets.
 */
@interface OFStreamSocket: OFStream <OFReadyForReadingObserving,
    OFReadyForWritingObserving>
{
	of_socket_t _socket;
	bool _atEndOfStream;
	OF_RESERVE_IVARS(4)
}

/*!
 * @brief Returns a new, autoreleased OFStreamSocket.
 *
 * @return A new, autoreleased OFStreamSocket
 */
+ (instancetype)socket;
@end

OF_ASSUME_NONNULL_END
