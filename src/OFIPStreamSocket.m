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

#define OF_IP_STREAM_SOCKET_M
#define __NO_EXT_QNX

#include "config.h"

#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef HAVE_FCNTL_H
# include <fcntl.h>
#endif

#import "OFIPStreamSocket.h"
#import "OFIPStreamSocket+Private.h"
#import "OFDNSResolver.h"
#import "OFData.h"
#import "OFDate.h"
#import "OFRunLoop+Private.h"
#import "OFRunLoop.h"
#import "OFString.h"
#import "OFTCPSocket.h"
#import "OFThread.h"
#import "OFTimer.h"

#import "OFAcceptFailedException.h"
#import "OFBindFailedException.h"
#import "OFConnectionFailedException.h"
#import "OFInvalidArgumentException.h"
#import "OFInvalidFormatException.h"
#import "OFListenFailedException.h"
#import "OFNotImplementedException.h"
#import "OFNotOpenException.h"
#import "OFOutOfMemoryException.h"
#import "OFOutOfRangeException.h"

#import "socket.h"
#import "socket_helpers.h"

/* TODO: Move SOCKS5 code to OFTCPSocket */

static const of_run_loop_mode_t connectRunLoopMode =
    @"of_ip_stream_socket_connect_mode";

@interface OFIPStreamSocketAsyncConnectDelegate: OFObject <
    OFIPStreamSocketDelegate, OFIPStreamSocketDelegate_Private,
    OFDNSResolverHostDelegate>
{
	OFIPStreamSocket *_socket;
	OFString *_host;
	uint16_t _port;
	id <OFIPStreamSocketDelegate> _delegate;
#ifdef OF_HAVE_BLOCKS
	of_ip_stream_socket_async_connect_block_t _block;
#endif
	id _exception;
	OFData *_socketAddresses;
	size_t _socketAddressesIndex;
	enum {
		SOCKS5_STATE_SEND_AUTHENTICATION = 1,
		SOCKS5_STATE_READ_VERSION,
		SOCKS5_STATE_SEND_REQUEST,
		SOCKS5_STATE_READ_RESPONSE,
		SOCKS5_STATE_READ_ADDRESS,
		SOCKS5_STATE_READ_ADDRESS_LENGTH,
	} _SOCKS5State;
	/* Longest read is domain name (max 255 bytes) + port */
	unsigned char _buffer[257];
	OFMutableData *_request;
}

- (instancetype)initWithSocket: (OFIPStreamSocket *)sock
			  host: (OFString *)host
			  port: (uint16_t)port
		      delegate: (id <OFIPStreamSocketDelegate>)delegate;
#ifdef OF_HAVE_BLOCKS
- (instancetype)initWithSocket: (OFIPStreamSocket *)sock
			  host: (OFString *)host
			  port: (uint16_t)port
			 block: (of_ip_stream_socket_async_connect_block_t)
				    block;
#endif
- (void)didConnect;
- (void)tryNextAddressWithRunLoopMode: (of_run_loop_mode_t)runLoopMode;
- (void)startWithRunLoopMode: (of_run_loop_mode_t)runLoopMode;
- (void)sendSOCKS5Request;
@end

@interface OFIPStreamSocketConnectDelegate: OFObject <OFIPStreamSocketDelegate>
{
@public
	bool _done;
	id _exception;
}
@end

@implementation OFIPStreamSocketAsyncConnectDelegate
- (instancetype)initWithSocket: (OFIPStreamSocket *)sock
			  host: (OFString *)host
			  port: (uint16_t)port
		      delegate: (id <OFIPStreamSocketDelegate>)delegate
{
	self = [super init];

	@try {
		_socket = [sock retain];
		_host = [host copy];
		_port = port;
		_delegate = [delegate retain];

		_socket.delegate = self;
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}

#ifdef OF_HAVE_BLOCKS
- (instancetype)initWithSocket: (OFIPStreamSocket *)sock
			  host: (OFString *)host
			  port: (uint16_t)port
			 block: (of_ip_stream_socket_async_connect_block_t)block
{
	self = [super init];

	@try {
		_socket = [sock retain];
		_host = [host copy];
		_port = port;
		_block = [block copy];
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}
#endif

- (void)dealloc
{
#ifdef OF_HAVE_BLOCKS
	if (_block == NULL)
#endif
		if (_socket.delegate == self)
			_socket.delegate = _delegate;

	[_socket release];
	[_host release];
	[_delegate release];
#ifdef OF_HAVE_BLOCKS
	[_block release];
#endif
	[_exception release];
	[_socketAddresses release];
	[_request release];

	[super dealloc];
}

- (void)didConnect
{
	if (_exception == nil)
		_socket.blocking = true;

#ifdef OF_HAVE_BLOCKS
	if (_block != NULL)
		_block(_socket, _exception);
	else {
#endif
		_socket.delegate = _delegate;

		if ([_delegate respondsToSelector:
		    @selector(socket:didConnectToHost:port:exception:)])
			[_delegate    socket: _socket
			    didConnectToHost: _host
					port: _port
				   exception: _exception];
#ifdef OF_HAVE_BLOCKS
	}
#endif
}

- (void)of_socketDidConnect: (OFIPStreamSocket *)sock
		  exception: (id)exception
{
	if (exception != nil) {
		/*
		 * self might be retained only by the pending async requests,
		 * which we're about to cancel.
		 */
		[[self retain] autorelease];

		[sock cancelAsyncRequests];
		[sock of_closeSocket];

		if (_socketAddressesIndex >= _socketAddresses.count) {
			_exception = [exception retain];
			[self didConnect];
		} else {
			/*
			 * We must not call it before returning, as otherwise
			 * the new socket would be removed from the queue upon
			 * return.
			 */
			OFRunLoop *runLoop = [OFRunLoop currentRunLoop];
			SEL selector =
			    @selector(tryNextAddressWithRunLoopMode:);
			OFTimer *timer = [OFTimer
			    timerWithTimeInterval: 0
					   target: self
					 selector: selector
					   object: runLoop.currentMode
					  repeats: false];
			[runLoop addTimer: timer
				  forMode: runLoop.currentMode];
		}

		return;
	}

	if ([sock isKindOfClass: [OFTCPSocket class]] &&
	    ((OFTCPSocket *)sock).SOCKS5Host != nil)
		[self sendSOCKS5Request];
	else
		[self didConnect];
}

- (void)tryNextAddressWithRunLoopMode: (of_run_loop_mode_t)runLoopMode
{
	of_socket_address_t address = *(const of_socket_address_t *)
	    [_socketAddresses itemAtIndex: _socketAddressesIndex++];
	int errNo;

	if ([_socket isKindOfClass: [OFTCPSocket class]] &&
	    ((OFTCPSocket *)_socket).SOCKS5Host != nil)
		of_socket_address_set_port(&address,
		    ((OFTCPSocket *)_socket).SOCKS5Port);
	else
		of_socket_address_set_port(&address, _port);

	if (![_socket of_createSocketForAddress: &address
					  errNo: &errNo]) {
		if (_socketAddressesIndex >= _socketAddresses.count) {
			_exception = [[OFConnectionFailedException alloc]
			    initWithHost: _host
				    port: _port
				  socket: _socket
				   errNo: errNo];
			[self didConnect];
			return;
		}

		[self tryNextAddressWithRunLoopMode: runLoopMode];
		return;
	}

#if defined(OF_NINTENDO_3DS) || defined(OF_WII)
	/*
	 * On Wii and 3DS, connect() fails if non-blocking is enabled.
	 *
	 * Additionally, on Wii, there is no getsockopt(), so it would not be
	 * possible to get the error (or success) after connecting anyway.
	 *
	 * So for now, connecting is blocking on Wii and 3DS.
	 *
	 * FIXME: Use a different thread as a work around.
	 */
	_socket.blocking = true;
#else
	_socket.blocking = false;
#endif

	if (![_socket of_connectSocketToAddress: &address
					  errNo: &errNo]) {
#if !defined(OF_NINTENDO_3DS) && !defined(OF_WII)
		if (errNo == EINPROGRESS) {
			[OFRunLoop
			    of_addAsyncConnectForIPStreamSocket: _socket
							   mode: runLoopMode
						       delegate: self];
			return;
		} else {
#endif
			[_socket of_closeSocket];

			if (_socketAddressesIndex >= _socketAddresses.count) {
				_exception = [[OFConnectionFailedException
				    alloc] initWithHost: _host
						   port: _port
						 socket: _socket
						  errNo: errNo];
				[self didConnect];
				return;
			}

			[self tryNextAddressWithRunLoopMode: runLoopMode];
			return;
#if !defined(OF_NINTENDO_3DS) && !defined(OF_WII)
		}
#endif
	}

#if defined(OF_NINTENDO_3DS) || defined(OF_WII)
	_socket.blocking = false;
#endif

	[self didConnect];
}

- (void)resolver: (OFDNSResolver *)resolver
  didResolveHost: (OFString *)host
       addresses: (OFData *)addresses
       exception: (id)exception
{
	if (exception != nil) {
		_exception = [exception retain];
		[self didConnect];
		return;
	}

	_socketAddresses = [addresses copy];

	[self tryNextAddressWithRunLoopMode:
	    [OFRunLoop currentRunLoop].currentMode];
}

- (void)startWithRunLoopMode: (of_run_loop_mode_t)runLoopMode
{
	OFString *host;
	uint16_t port;

	if ([_socket isKindOfClass: [OFTCPSocket class]] &&
	    ((OFTCPSocket *)_socket).SOCKS5Host != nil) {
		if (_host.UTF8StringLength > 255)
			@throw [OFOutOfRangeException exception];

		host = ((OFTCPSocket *)_socket).SOCKS5Host;
		port = ((OFTCPSocket *)_socket).SOCKS5Port;
	} else {
		host = _host;
		port = _port;
	}

	@try {
		of_socket_address_t address =
		    of_socket_address_parse_ip(host, port);

		_socketAddresses = [[OFData alloc]
		    initWithItems: &address
			 itemSize: sizeof(address)
			    count: 1];

		[self tryNextAddressWithRunLoopMode: runLoopMode];
		return;
	} @catch (OFInvalidFormatException *e) {
	}

	[[OFThread DNSResolver]
	    asyncResolveAddressesForHost: host
			   addressFamily: OF_SOCKET_ADDRESS_FAMILY_ANY
			     runLoopMode: runLoopMode
				delegate: self];
}

- (void)sendSOCKS5Request
{
	OFData *data = [OFData dataWithItems: "\x05\x01\x00"
				       count: 3];

	_SOCKS5State = SOCKS5_STATE_SEND_AUTHENTICATION;
	[_socket asyncWriteData: data
		    runLoopMode: [OFRunLoop currentRunLoop].currentMode];
}

-      (bool)stream: (OFStream *)sock
  didReadIntoBuffer: (void *)buffer
	     length: (size_t)length
	  exception: (id)exception
{
	of_run_loop_mode_t runLoopMode;
	unsigned char *SOCKSVersion;
	uint8_t hostLength;
	unsigned char port[2];
	unsigned char *response, *addressLength;

	if (exception != nil) {
		_exception = [exception retain];
		[self didConnect];
		return false;
	}

	runLoopMode = [OFRunLoop currentRunLoop].currentMode;

	switch (_SOCKS5State) {
	case SOCKS5_STATE_READ_VERSION:
		SOCKSVersion = buffer;

		if (SOCKSVersion[0] != 5 || SOCKSVersion[1] != 0) {
			_exception = [[OFConnectionFailedException alloc]
			    initWithHost: _host
				    port: _port
				  socket: self
				   errNo: EPROTONOSUPPORT];
			[self didConnect];
			return false;
		}

		[_request release];
		_request = [[OFMutableData alloc] init];

		[_request addItems: "\x05\x01\x00\x03"
			     count: 4];

		hostLength = (uint8_t)_host.UTF8StringLength;
		[_request addItem: &hostLength];
		[_request addItems: _host.UTF8String
			     count: hostLength];

		port[0] = _port >> 8;
		port[1] = _port & 0xFF;
		[_request addItems: port
			     count: 2];

		_SOCKS5State = SOCKS5_STATE_SEND_REQUEST;
		[_socket asyncWriteData: _request
			    runLoopMode: runLoopMode];
		return false;
	case SOCKS5_STATE_READ_RESPONSE:
		response = buffer;

		if (response[0] != 5 || response[2] != 0) {
			_exception = [[OFConnectionFailedException alloc]
			    initWithHost: _host
				    port: _port
				  socket: self
				   errNo: EPROTONOSUPPORT];
			[self didConnect];
			return false;
		}

		if (response[1] != 0) {
			int errNo;

			switch (response[1]) {
			case 0x02:
				errNo = EPERM;
				break;
			case 0x03:
				errNo = ENETUNREACH;
				break;
			case 0x04:
				errNo = EHOSTUNREACH;
				break;
			case 0x05:
				errNo = ECONNREFUSED;
				break;
			case 0x06:
				errNo = ETIMEDOUT;
				break;
			case 0x07:
				errNo = EOPNOTSUPP;
				break;
			case 0x08:
				errNo = EAFNOSUPPORT;
				break;
			default:
#ifdef EPROTO
				errNo = EPROTO;
#else
				errNo = 0;
#endif
				break;
			}

			_exception = [[OFConnectionFailedException alloc]
			    initWithHost: _host
				    port: _port
				  socket: _socket
				   errNo: errNo];
			[self didConnect];
			return false;
		}

		/* Skip the rest of the response */
		switch (response[3]) {
		case 1: /* IPv4 */
			_SOCKS5State = SOCKS5_STATE_READ_ADDRESS;
			[_socket asyncReadIntoBuffer: _buffer
					 exactLength: 4 + 2
					 runLoopMode: runLoopMode];
			return false;
		case 3: /* Domain name */
			_SOCKS5State = SOCKS5_STATE_READ_ADDRESS_LENGTH;
			[_socket asyncReadIntoBuffer: _buffer
					 exactLength: 1
					 runLoopMode: runLoopMode];
			return false;
		case 4: /* IPv6 */
			_SOCKS5State = SOCKS5_STATE_READ_ADDRESS;
			[_socket asyncReadIntoBuffer: _buffer
					 exactLength: 16 + 2
					 runLoopMode: runLoopMode];
			return false;
		default:
			_exception = [[OFConnectionFailedException alloc]
			    initWithHost: _host
				    port: _port
				  socket: self
				   errNo: EPROTONOSUPPORT];
			[self didConnect];
			return false;
		}

		return false;
	case SOCKS5_STATE_READ_ADDRESS:
		[self didConnect];
		return false;
	case SOCKS5_STATE_READ_ADDRESS_LENGTH:
		addressLength = buffer;

		_SOCKS5State = SOCKS5_STATE_READ_ADDRESS;
		[_socket asyncReadIntoBuffer: _buffer
				 exactLength: addressLength[0] + 2
				 runLoopMode: runLoopMode];
		return false;
	default:
		assert(0);
		return false;
	}
}

- (OFData *)stream: (OFStream *)sock
      didWriteData: (OFData *)data
      bytesWritten: (size_t)bytesWritten
	 exception: (id)exception
{
	of_run_loop_mode_t runLoopMode;

	if (exception != nil) {
		_exception = [exception retain];
		[self didConnect];
		return nil;
	}

	runLoopMode = [OFRunLoop currentRunLoop].currentMode;

	switch (_SOCKS5State) {
	case SOCKS5_STATE_SEND_AUTHENTICATION:
		_SOCKS5State = SOCKS5_STATE_READ_VERSION;
		[_socket asyncReadIntoBuffer: _buffer
				 exactLength: 2
				 runLoopMode: runLoopMode];
		return nil;
	case SOCKS5_STATE_SEND_REQUEST:
		[_request release];
		_request = nil;

		_SOCKS5State = SOCKS5_STATE_READ_RESPONSE;
		[_socket asyncReadIntoBuffer: _buffer
				 exactLength: 4
				 runLoopMode: runLoopMode];
		return nil;
	default:
		assert(0);
		return nil;
	}
}
@end

@implementation OFIPStreamSocketConnectDelegate
- (void)dealloc
{
	[_exception release];

	[super dealloc];
}

-     (void)socket: (OFIPStreamSocket *)sock
  didConnectToHost: (OFString *)host
	      port: (uint16_t)port
	 exception: (id)exception
{
	_done = true;
	_exception = [exception retain];
}
@end

@implementation OFIPStreamSocket
@dynamic delegate;

- (instancetype)init
{
	self = [super init];

	_socket = INVALID_SOCKET;

	return self;
}

- (bool)of_createSocketForAddress: (const of_socket_address_t *)address
			    errNo: (int *)errNo
{
	@throw [OFNotImplementedException exceptionWithSelector: _cmd
							 object: self];
}

- (bool)of_connectSocketToAddress: (const of_socket_address_t *)address
			    errNo: (int *)errNo
{
	if (_socket == INVALID_SOCKET)
		@throw [OFNotOpenException exceptionWithObject: self];

	if (connect(_socket, (struct sockaddr *)&address->sockaddr.sockaddr,
	    address->length) != 0) {
		*errNo = of_socket_errno();
		return false;
	}

	return true;
}

- (void)of_closeSocket
{
	closesocket(_socket);
	_socket = INVALID_SOCKET;
}

#ifndef OF_WII
- (int)of_socketError
{
	int errNo;
	socklen_t len = sizeof(errNo);

	if (getsockopt(_socket, SOL_SOCKET, SO_ERROR, (char *)&errNo,
	    &len) != 0)
		return of_socket_errno();

	return errNo;
}
#endif

- (void)connectToHost: (OFString *)host
		 port: (uint16_t)port
{
	void *pool = objc_autoreleasePoolPush();
	id <OFIPStreamSocketDelegate> delegate = [_delegate retain];
	OFIPStreamSocketConnectDelegate *connectDelegate =
	    [[[OFIPStreamSocketConnectDelegate alloc] init] autorelease];
	OFRunLoop *runLoop = [OFRunLoop currentRunLoop];

	self.delegate = connectDelegate;
	[self asyncConnectToHost: host
			    port: port
		     runLoopMode: connectRunLoopMode];

	while (!connectDelegate->_done)
		[runLoop runMode: connectRunLoopMode
		      beforeDate: nil];

	/* Cleanup */
	[runLoop runMode: connectRunLoopMode
	      beforeDate: [OFDate date]];

	if (connectDelegate->_exception != nil)
		@throw connectDelegate->_exception;

	self.delegate = delegate;

	objc_autoreleasePoolPop(pool);
}

- (void)asyncConnectToHost: (OFString *)host
		      port: (uint16_t)port
{
	[self asyncConnectToHost: host
			    port: port
		     runLoopMode: of_run_loop_mode_default];
}

- (void)asyncConnectToHost: (OFString *)host
		      port: (uint16_t)port
	       runLoopMode: (of_run_loop_mode_t)runLoopMode
{
	void *pool = objc_autoreleasePoolPush();

	[[[[OFIPStreamSocketAsyncConnectDelegate alloc]
		  initWithSocket: self
			    host: host
			    port: port
			delegate: _delegate] autorelease]
	    startWithRunLoopMode: runLoopMode];

	objc_autoreleasePoolPop(pool);
}

#ifdef OF_HAVE_BLOCKS
- (void)asyncConnectToHost: (OFString *)host
		      port: (uint16_t)port
		     block: (of_ip_stream_socket_async_connect_block_t)block
{
	[self asyncConnectToHost: host
			    port: port
		     runLoopMode: of_run_loop_mode_default
			   block: block];
}

- (void)asyncConnectToHost: (OFString *)host
		      port: (uint16_t)port
	       runLoopMode: (of_run_loop_mode_t)runLoopMode
		     block: (of_ip_stream_socket_async_connect_block_t)block
{
	void *pool = objc_autoreleasePoolPush();

	[[[[OFIPStreamSocketAsyncConnectDelegate alloc]
		  initWithSocket: self
			    host: host
			    port: port
			   block: block] autorelease]
	    startWithRunLoopMode: runLoopMode];

	objc_autoreleasePoolPop(pool);
}
#endif

- (uint16_t)bindToHost: (OFString *)host
		  port: (uint16_t)port
{
	const int one = 1;
	void *pool = objc_autoreleasePoolPush();
	OFData *socketAddresses;
	of_socket_address_t address;
	int errNo;

	socketAddresses = [[OFThread DNSResolver]
	    resolveAddressesForHost: host
		      addressFamily: OF_SOCKET_ADDRESS_FAMILY_ANY];

	address = *(of_socket_address_t *)[socketAddresses itemAtIndex: 0];
	of_socket_address_set_port(&address, port);

	if (![self of_createSocketForAddress: &address
				       errNo: &errNo])
		@throw [OFBindFailedException
		    exceptionWithHost: host
				 port: port
			       socket: self
				errNo: errNo];

	setsockopt(_socket, SOL_SOCKET, SO_REUSEADDR,
	    (char *)&one, (socklen_t)sizeof(one));

	_blocking = true;

#if defined(OF_WII) || defined(OF_NINTENDO_3DS)
	if (port != 0) {
#endif
		if (bind(_socket, &address.sockaddr.sockaddr,
		    address.length) != 0) {
			errNo = of_socket_errno();

			closesocket(_socket);
			_socket = INVALID_SOCKET;

			@throw [OFBindFailedException exceptionWithHost: host
								   port: port
								 socket: self
								  errNo: errNo];
		}
#if defined(OF_WII) || defined(OF_NINTENDO_3DS)
	} else {
		for (;;) {
			uint16_t rnd = 0;
			int ret;

			while (rnd < 1024)
				rnd = (uint16_t)rand();

			of_socket_address_set_port(&address, rnd);

			if ((ret = bind(_socket, &address.sockaddr.sockaddr,
			    address.length)) == 0) {
				port = rnd;
				break;
			}

			if (of_socket_errno() != EADDRINUSE) {
				errNo = of_socket_errno();

				closesocket(_socket);
				_socket = INVALID_SOCKET;

				@throw [OFBindFailedException
				    exceptionWithHost: host
						 port: port
					       socket: self
						errNo: errNo];
			}
		}
	}
#endif

	objc_autoreleasePoolPop(pool);

	if (port > 0)
		return port;

#if !defined(OF_WII) && !defined(OF_NINTENDO_3DS)
	memset(&address, 0, sizeof(address));

	address.length = (socklen_t)sizeof(address.sockaddr);
	if (of_getsockname(_socket, &address.sockaddr.sockaddr,
	    &address.length) != 0) {
		errNo = of_socket_errno();

		closesocket(_socket);
		_socket = INVALID_SOCKET;

		@throw [OFBindFailedException exceptionWithHost: host
							   port: port
							 socket: self
							  errNo: errNo];
	}

	if (address.sockaddr.sockaddr.sa_family == AF_INET)
		return OF_BSWAP16_IF_LE(address.sockaddr.in.sin_port);
# ifdef OF_HAVE_IPV6
	else if (address.sockaddr.sockaddr.sa_family == AF_INET6)
		return OF_BSWAP16_IF_LE(address.sockaddr.in6.sin6_port);
# endif
	else {
		closesocket(_socket);
		_socket = INVALID_SOCKET;

		@throw [OFBindFailedException exceptionWithHost: host
							   port: port
							 socket: self
							  errNo: EAFNOSUPPORT];
	}
#else
	closesocket(_socket);
	_socket = INVALID_SOCKET;
	@throw [OFBindFailedException exceptionWithHost: host
						   port: port
						 socket: self
						  errNo: EADDRNOTAVAIL];
#endif
}

- (void)listen
{
	[self listenWithBacklog: SOMAXCONN];
}

- (void)listenWithBacklog: (int)backlog
{
	if (_socket == INVALID_SOCKET)
		@throw [OFNotOpenException exceptionWithObject: self];

	if (listen(_socket, backlog) == -1)
		@throw [OFListenFailedException
		    exceptionWithSocket: self
				backlog: backlog
				  errNo: of_socket_errno()];

	_listening = true;
}

- (instancetype)accept
{
	OFIPStreamSocket *client = [[[[self class] alloc] init] autorelease];
#if (!defined(HAVE_PACCEPT) && !defined(HAVE_ACCEPT4)) || !defined(SOCK_CLOEXEC)
# if defined(HAVE_FCNTL) && defined(FD_CLOEXEC)
	int flags;
# endif
#endif

	client->_remoteAddress.length =
	    (socklen_t)sizeof(client->_remoteAddress.sockaddr);

#if defined(HAVE_PACCEPT) && defined(SOCK_CLOEXEC)
	if ((client->_socket = paccept(_socket,
	    &client->_remoteAddress.sockaddr.sockaddr,
	    &client->_remoteAddress.length, NULL, SOCK_CLOEXEC)) ==
	    INVALID_SOCKET)
		@throw [OFAcceptFailedException
		    exceptionWithSocket: self
				  errNo: of_socket_errno()];
#elif defined(HAVE_ACCEPT4) && defined(SOCK_CLOEXEC)
	if ((client->_socket = accept4(_socket,
	    &client->_remoteAddress.sockaddr.sockaddr,
	    &client->_remoteAddress.length, SOCK_CLOEXEC)) == INVALID_SOCKET)
		@throw [OFAcceptFailedException
		    exceptionWithSocket: self
				  errNo: of_socket_errno()];
#else
	if ((client->_socket = accept(_socket,
	    &client->_remoteAddress.sockaddr.sockaddr,
	    &client->_remoteAddress.length)) == INVALID_SOCKET)
		@throw [OFAcceptFailedException
		    exceptionWithSocket: self
				  errNo: of_socket_errno()];

# if defined(HAVE_FCNTL) && defined(FD_CLOEXEC)
	if ((flags = fcntl(client->_socket, F_GETFD, 0)) != -1)
		fcntl(client->_socket, F_SETFD, flags | FD_CLOEXEC);
# endif
#endif

	assert(client->_remoteAddress.length <=
	    (socklen_t)sizeof(client->_remoteAddress.sockaddr));

	switch (client->_remoteAddress.sockaddr.sockaddr.sa_family) {
	case AF_INET:
		client->_remoteAddress.family = OF_SOCKET_ADDRESS_FAMILY_IPV4;
		break;
#ifdef OF_HAVE_IPV6
	case AF_INET6:
		client->_remoteAddress.family = OF_SOCKET_ADDRESS_FAMILY_IPV6;
		break;
#endif
	default:
		client->_remoteAddress.family =
		    OF_SOCKET_ADDRESS_FAMILY_UNKNOWN;
		break;
	}

	return client;
}

- (void)asyncAccept
{
	[self asyncAcceptWithRunLoopMode: of_run_loop_mode_default];
}

- (void)asyncAcceptWithRunLoopMode: (of_run_loop_mode_t)runLoopMode
{
	[OFRunLoop of_addAsyncAcceptForIPStreamSocket: self
						 mode: runLoopMode
# ifdef OF_HAVE_BLOCKS
						     block: NULL
# endif
						     delegate: _delegate];
}

#ifdef OF_HAVE_BLOCKS
- (void)asyncAcceptWithBlock: (of_ip_stream_socket_async_accept_block_t)block
{
	[self asyncAcceptWithRunLoopMode: of_run_loop_mode_default
				   block: block];
}

- (void)asyncAcceptWithRunLoopMode: (of_run_loop_mode_t)runLoopMode
			     block: (of_ip_stream_socket_async_accept_block_t)
					block
{
	[OFRunLoop of_addAsyncAcceptForIPStreamSocket: self
						 mode: runLoopMode
						block: block
					     delegate: nil];
}
#endif

- (const of_socket_address_t *)remoteAddress
{
	if (_socket == INVALID_SOCKET)
		@throw [OFNotOpenException exceptionWithObject: self];

	if (_remoteAddress.length == 0)
		@throw [OFInvalidArgumentException exception];

	if (_remoteAddress.length > (socklen_t)sizeof(_remoteAddress.sockaddr))
		@throw [OFOutOfRangeException exception];

	return &_remoteAddress;
}

- (bool)isListening
{
	return _listening;
}

- (void)close
{
	_listening = false;

	memset(&_remoteAddress, 0, sizeof(_remoteAddress));

#ifdef OF_WII
	_port = 0;
#endif

	[super close];
}
@end
