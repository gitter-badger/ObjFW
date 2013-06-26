/*
 * Copyright (c) 2008, 2009, 2010, 2011, 2012, 2013
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

#define _WIN32_WINNT 0x0501
#define __NO_EXT_QNX

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <unistd.h>

#ifdef HAVE_NETINET_IN_H
# include <netinet/in.h>
#endif
#ifdef HAVE_ARPA_INET_H
# include <arpa/inet.h>
#endif
#ifdef HAVE_NETDB_H
# include <netdb.h>
#endif

#import "OFTCPSocket.h"
#import "OFTCPSocket+SOCKS5.h"
#import "OFString.h"
#import "OFThread.h"
#import "OFTimer.h"
#import "OFRunLoop.h"

#import "OFAcceptFailedException.h"
#import "OFAlreadyConnectedException.h"
#import "OFAddressTranslationFailedException.h"
#import "OFBindFailedException.h"
#import "OFConnectionFailedException.h"
#import "OFInvalidArgumentException.h"
#import "OFListenFailedException.h"
#import "OFNotConnectedException.h"
#import "OFNotImplementedException.h"
#import "OFSetOptionFailedException.h"

#import "autorelease.h"
#import "macros.h"

#ifndef INVALID_SOCKET
# define INVALID_SOCKET -1
#endif

#ifdef HAVE_THREADSAFE_GETADDRINFO
# ifndef AI_NUMERICSERV
#  define AI_NUMERICSERV 0
# endif
# ifndef AI_NUMERICHOST
#  define AI_NUMERICHOST 0
# endif
#endif

#ifndef SOMAXCONN
# define SOMAXCONN 32
#endif

#if defined(OF_HAVE_THREADS) && !defined(HAVE_THREADSAFE_GETADDRINFO)
# import "OFMutex.h"
# import "OFDataArray.h"

static OFMutex *mutex = nil;
#endif

#ifdef _WIN32
# define close(sock) closesocket(sock)
#endif

#ifdef _PSP
/* PSP defines AF_INET6, even though sockaddr_in6 is missing */
# undef AF_INET6
struct sockaddr_storage {
	uint8_t	       ss_len;
	sa_family_t    ss_family;
	in_port_t      ss_data1;
	struct in_addr ss_data2;
	int8_t	       ss_data3[8];
};
#endif

#ifdef __wii__
# define accept(sock, addr, addrlen) net_accept(sock, addr, addrlen)
# define bind(sock, addr, addrlen) net_bind(sock, addr, addrlen)
# define close(sock) net_close(sock)
# define connect(sock, addr, addrlen) net_connect(sock, addr, addrlen)
# define gethostbyname(name) net_gethostbyname(name)
# define listen(sock, backlog) net_listen(sock, backlog)
# define setsockopt(sock, level, name, value, len) \
	net_setsockopt(sock, level, name, value, len)
# define socket(domain, type, proto) net_socket(domain, type, proto)
typedef u32 in_addr_t;

struct sockaddr_storage {
	u8 ss_len;
	u8 ss_family;
	u8 ss_data[14];
};
#endif

/* References for static linking */
void _references_to_categories_of_OFTCPSocket(void)
{
	_OFTCPSocket_SOCKS5_reference = 1;
}

Class of_tls_socket_class = Nil;

static OFString *defaultSOCKS5Host = nil;
static uint16_t defaultSOCKS5Port = 1080;

#ifdef __wii__
static uint16_t freePort = 65532;
#endif

#ifdef OF_HAVE_THREADS
@interface OFTCPSocket_ConnectThread: OFThread
{
	OFThread *_sourceThread;
	OFTCPSocket *_socket;
	OFString *_host;
	uint16_t _port;
	id _target;
	SEL _selector;
# ifdef OF_HAVE_BLOCKS
	of_tcpsocket_async_connect_block_t _connectBlock;
# endif
	OFException *_exception;
}

- initWithSourceThread: (OFThread*)sourceThread
		socket: (OFTCPSocket*)socket
		  host: (OFString*)host
		  port: (uint16_t)port
		target: (id)target
	      selector: (SEL)selector;
# ifdef OF_HAVE_BLOCKS
- initWithSourceThread: (OFThread*)sourceThread
		socket: (OFTCPSocket*)socket
		  host: (OFString*)host
		  port: (uint16_t)port
		 block: (of_tcpsocket_async_connect_block_t)block;
# endif
@end

@implementation OFTCPSocket_ConnectThread
- initWithSourceThread: (OFThread*)sourceThread
		socket: (OFTCPSocket*)socket
		  host: (OFString*)host
		  port: (uint16_t)port
		target: (id)target
	      selector: (SEL)selector
{
	self = [super init];

	@try {
		_sourceThread = [sourceThread retain];
		_socket = [socket retain];
		_host = [host copy];
		_port = port;
		_target = [target retain];
		_selector = selector;
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}

# ifdef OF_HAVE_BLOCKS
- initWithSourceThread: (OFThread*)sourceThread
		socket: (OFTCPSocket*)socket
		  host: (OFString*)host
		  port: (uint16_t)port
		 block: (of_tcpsocket_async_connect_block_t)block
{
	self = [super init];

	@try {
		_sourceThread = [sourceThread retain];
		_socket = [socket retain];
		_host = [host copy];
		_port = port;
		_connectBlock = [block copy];
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}
# endif

- (void)dealloc
{
	[_sourceThread release];
	[_socket release];
	[_host release];
	[_target release];
# ifdef OF_HAVE_BLOCKS
	[_connectBlock release];
# endif
	[_exception release];

	[super dealloc];
}

- (void)didConnect
{
	[self join];

# ifdef OF_HAVE_BLOCKS
	if (_connectBlock != NULL)
		_connectBlock(_socket, _exception);
	else {
# endif
		void (*func)(id, SEL, OFTCPSocket*, OFException*) =
		    (void(*)(id, SEL, OFTCPSocket*, OFException*))[_target
		    methodForSelector: _selector];

		func(_target, _selector, _socket, _exception);
# ifdef OF_HAVE_BLOCKS
	}
# endif
}

- (id)main
{
	void *pool = objc_autoreleasePoolPush();

	@try {
		[_socket connectToHost: _host
				  port: _port];
	} @catch (OFException *e) {
		_exception = [[e retain] autorelease];
	}

	[self performSelector: @selector(didConnect)
		     onThread: _sourceThread
		waitUntilDone: false];

	objc_autoreleasePoolPop(pool);

	return nil;
}
@end
#endif

@implementation OFTCPSocket
#if defined(OF_HAVE_THREADS) && !defined(HAVE_THREADSAFE_GETADDRINFO)
+ (void)initialize
{
	if (self == [OFTCPSocket class])
		mutex = [[OFMutex alloc] init];
}
#endif

+ (void)setSOCKS5Host: (OFString*)host
{
	id old = defaultSOCKS5Host;
	defaultSOCKS5Host = [host copy];
	[old release];
}

+ (OFString*)SOCKS5Host
{
	return [[defaultSOCKS5Host copy] autorelease];
}

+ (void)setSOCKS5Port: (uint16_t)port
{
	defaultSOCKS5Port = port;
}

+ (uint16_t)SOCKS5Port
{
	return defaultSOCKS5Port;
}

- init
{
	self = [super init];

	@try {
		_socket = INVALID_SOCKET;
		_sockAddr = NULL;
		_SOCKS5Host = [defaultSOCKS5Host copy];
		_SOCKS5Port = defaultSOCKS5Port;
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}

- (void)dealloc
{
	[_SOCKS5Host release];

	[super dealloc];
}

- (void)setSOCKS5Host: (OFString*)SOCKS5Host
{
	OF_SETTER(_SOCKS5Host, SOCKS5Host, true, 1)
}

- (OFString*)SOCKS5Host
{
	OF_GETTER(_SOCKS5Host, true)
}

- (void)setSOCKS5Port: (uint16_t)SOCKS5Port
{
	_SOCKS5Port = SOCKS5Port;
}

- (uint16_t)SOCKS5Port
{
	return _SOCKS5Port;
}

- (void)connectToHost: (OFString*)host
		 port: (uint16_t)port
{
	OFString *destinationHost = host;
	uint16_t destinationPort = port;

	if (_socket != INVALID_SOCKET)
		@throw [OFAlreadyConnectedException exceptionWithSocket: self];

	if (_SOCKS5Host != nil) {
		/* Connect to the SOCKS5 proxy instead */
		host = _SOCKS5Host;
		port = _SOCKS5Port;
	}

#ifdef HAVE_THREADSAFE_GETADDRINFO
	struct addrinfo hints, *res, *res0;
	char portCString[7];

	memset(&hints, 0, sizeof(struct addrinfo));
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;
	hints.ai_flags = AI_NUMERICSERV;
	snprintf(portCString, 7, "%" PRIu16, port);

	if (getaddrinfo([host cStringWithEncoding: OF_STRING_ENCODING_NATIVE],
	    portCString, &hints, &res0))
		@throw [OFAddressTranslationFailedException
		    exceptionWithHost: host
			       socket: self];

	for (res = res0; res != NULL; res = res->ai_next) {
		if ((_socket = socket(res->ai_family, res->ai_socktype,
		    res->ai_protocol)) == INVALID_SOCKET)
			continue;

		if (connect(_socket, res->ai_addr, res->ai_addrlen) == -1) {
			close(_socket);
			_socket = INVALID_SOCKET;
			continue;
		}

		break;
	}

	freeaddrinfo(res0);
#else
	bool connected = false;
	struct hostent *he;
	struct sockaddr_in addr;
	char **ip;
# ifdef OF_HAVE_THREADS
	OFDataArray *addrlist;
# endif

	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = OF_BSWAP16_IF_LE(port);

	if ((addr.sin_addr.s_addr = inet_addr([host cStringWithEncoding:
	    OF_STRING_ENCODING_NATIVE])) != (in_addr_t)(-1)) {
		if ((_socket = socket(AF_INET, SOCK_STREAM,
		    0)) == INVALID_SOCKET) {
			@throw [OFConnectionFailedException
			    exceptionWithHost: host
					 port: port
				       socket: self];
		}

		if (connect(_socket, (struct sockaddr*)&addr,
		    sizeof(addr)) == -1) {
			close(_socket);
			_socket = INVALID_SOCKET;
			@throw [OFConnectionFailedException
			    exceptionWithHost: host
					 port: port
				       socket: self];
		}

		if (_SOCKS5Host != nil)
			[self OF_SOCKS5ConnectToHost: destinationHost
						port: destinationPort];

		return;
	}

# ifdef OF_HAVE_THREADS
	addrlist = [[OFDataArray alloc] initWithItemSize: sizeof(char**)];
	[mutex lock];
# endif

	if ((he = gethostbyname([host cStringWithEncoding:
	    OF_STRING_ENCODING_NATIVE])) == NULL) {
# ifdef OF_HAVE_THREADS
		[addrlist release];
		[mutex unlock];
# endif
		@throw [OFAddressTranslationFailedException
		    exceptionWithHost: host
			       socket: self];
	}

	if (he->h_addrtype != AF_INET ||
	    (_socket = socket(AF_INET, SOCK_STREAM, 0)) == INVALID_SOCKET) {
# ifdef OF_HAVE_THREADS
		[addrlist release];
		[mutex unlock];
# endif
		@throw [OFConnectionFailedException exceptionWithHost: host
								 port: port
							       socket: self];
	}

# ifdef OF_HAVE_THREADS
	@try {
		for (ip = he->h_addr_list; *ip != NULL; ip++)
			[addrlist addItem: ip];

		/* Add the terminating NULL */
		[addrlist addItem: ip];
	} @catch (id e) {
		[addrlist release];
		@throw e;
	} @finally {
		[mutex unlock];
	}

	for (ip = [addrlist items]; *ip != NULL; ip++) {
# else
	for (ip = he->h_addr_list; *ip != NULL; ip++) {
# endif
		memcpy(&addr.sin_addr.s_addr, *ip, he->h_length);

		if (connect(_socket, (struct sockaddr*)&addr,
		    sizeof(addr)) == -1)
			continue;

		connected = true;
		break;
	}

# ifdef OF_HAVE_THREADS
	[addrlist release];
# endif

	if (!connected) {
		close(_socket);
		_socket = INVALID_SOCKET;
	}
#endif

	if (_socket == INVALID_SOCKET)
		@throw [OFConnectionFailedException exceptionWithHost: host
								 port: port
							       socket: self];

	if (_SOCKS5Host != nil)
		[self OF_SOCKS5ConnectToHost: destinationHost
					port: destinationPort];
}

#ifdef OF_HAVE_THREADS
- (void)asyncConnectToHost: (OFString*)host
		      port: (uint16_t)port
		    target: (id)target
		  selector: (SEL)selector
{
	void *pool = objc_autoreleasePoolPush();

	[[[[OFTCPSocket_ConnectThread alloc]
	    initWithSourceThread: [OFThread currentThread]
			  socket: self
			    host: host
			    port: port
			  target: target
			selector: selector] autorelease] start];

	objc_autoreleasePoolPop(pool);
}

# ifdef OF_HAVE_BLOCKS
- (void)asyncConnectToHost: (OFString*)host
		      port: (uint16_t)port
		     block: (of_tcpsocket_async_connect_block_t)block
{
	void *pool = objc_autoreleasePoolPush();

	[[[[OFTCPSocket_ConnectThread alloc]
	    initWithSourceThread: [OFThread currentThread]
			  socket: self
			    host: host
			    port: port
			   block: block] autorelease] start];

	objc_autoreleasePoolPop(pool);
}
# endif
#endif

- (uint16_t)bindToHost: (OFString*)host
		  port: (uint16_t)port
{
	const int one = 1;
	union {
		struct sockaddr_storage storage;
		struct sockaddr_in in;
#ifdef AF_INET6
		struct sockaddr_in6 in6;
#endif
	} addr;
#ifndef __wii__
	socklen_t addrLen;
#endif

	if (_socket != INVALID_SOCKET)
		@throw [OFAlreadyConnectedException exceptionWithSocket: self];

	if (_SOCKS5Host != nil)
		@throw [OFNotImplementedException exceptionWithSelector: _cmd
								 object: self];

#ifdef __wii__
	if (port == 0)
		port = freePort--;
#endif

#ifdef HAVE_THREADSAFE_GETADDRINFO
	struct addrinfo hints, *res;
	char portCString[7];

	memset(&hints, 0, sizeof(struct addrinfo));
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;
	hints.ai_flags = AI_NUMERICSERV | AI_PASSIVE;
	snprintf(portCString, 7, "%" PRIu16, port);

	if (getaddrinfo([host cStringWithEncoding: OF_STRING_ENCODING_NATIVE],
	    portCString, &hints, &res))
		@throw [OFAddressTranslationFailedException
		    exceptionWithHost: host
			       socket: self];

	if ((_socket = socket(res->ai_family, SOCK_STREAM,
	    0)) == INVALID_SOCKET)
		@throw [OFBindFailedException exceptionWithHost: host
							   port: port
							 socket: self];

	if (setsockopt(_socket, SOL_SOCKET, SO_REUSEADDR, (const char*)&one,
	    sizeof(one)))
		@throw [OFSetOptionFailedException exceptionWithStream: self];

	if (bind(_socket, res->ai_addr, res->ai_addrlen) == -1) {
		freeaddrinfo(res);
		close(_socket);
		_socket = INVALID_SOCKET;
		@throw [OFBindFailedException exceptionWithHost: host
							   port: port
							 socket: self];
	}

	freeaddrinfo(res);
#else
	memset(&addr, 0, sizeof(addr));
	addr.in.sin_family = AF_INET;
	addr.in.sin_port = OF_BSWAP16_IF_LE(port);

	if ((addr.in.sin_addr.s_addr = inet_addr([host cStringWithEncoding:
	    OF_STRING_ENCODING_NATIVE])) == (in_addr_t)(-1)) {
# ifdef OF_HAVE_THREADS
		[mutex lock];
		@try {
# endif
			struct hostent *he;

			if ((he = gethostbyname([host cStringWithEncoding:
			    OF_STRING_ENCODING_NATIVE])) == NULL)
				@throw [OFAddressTranslationFailedException
				    exceptionWithHost: host
					       socket: self];

			if (he->h_addrtype != AF_INET ||
			    he->h_addr_list[0] == NULL) {
				@throw [OFAddressTranslationFailedException
				    exceptionWithHost: host
					       socket: self];
			}

			memcpy(&addr.in.sin_addr.s_addr, he->h_addr_list[0],
			    he->h_length);
# ifdef OF_HAVE_THREADS
		} @finally {
			[mutex unlock];
		}
# endif
	}

	if ((_socket = socket(AF_INET, SOCK_STREAM, 0)) == INVALID_SOCKET)
		@throw [OFBindFailedException exceptionWithHost: host
							   port: port
							 socket: self];

	if (setsockopt(_socket, SOL_SOCKET, SO_REUSEADDR, (const char*)&one,
	    sizeof(one)))
		@throw [OFSetOptionFailedException exceptionWithStream: self];

	if (bind(_socket, (struct sockaddr*)&addr.in, sizeof(addr.in)) == -1) {
		close(_socket);
		_socket = INVALID_SOCKET;
		@throw [OFBindFailedException exceptionWithHost: host
							   port: port
							 socket: self];
	}
#endif

	if (port > 0)
		return port;

#ifndef __wii__
	addrLen = sizeof(addr.storage);
	if (getsockname(_socket, (struct sockaddr*)&addr, &addrLen)) {
		close(_socket);
		_socket = INVALID_SOCKET;
		@throw [OFBindFailedException exceptionWithHost: host
							   port: port
							 socket: self];
	}

	if (addr.storage.ss_family == AF_INET)
		return OF_BSWAP16_IF_LE(addr.in.sin_port);
# ifdef AF_INET6
	if (addr.storage.ss_family == AF_INET6)
		return OF_BSWAP16_IF_LE(addr.in6.sin6_port);
# endif
#endif

	close(_socket);
	_socket = INVALID_SOCKET;
	@throw [OFBindFailedException exceptionWithHost: host
						   port: port
						 socket: self];
}

- (void)listenWithBackLog: (int)backLog
{
	if (_socket == INVALID_SOCKET)
		@throw [OFNotConnectedException exceptionWithSocket: self];

	if (listen(_socket, backLog) == -1)
		@throw [OFListenFailedException exceptionWithSocket: self
							    backLog: backLog];

	_listening = true;
}

- (void)listen
{
	[self listenWithBackLog: SOMAXCONN];
}

- (instancetype)accept
{
	OFTCPSocket *client;
	struct sockaddr_storage *addr;
	socklen_t addrLen;
	int socket;

	client = [[[[self class] alloc] init] autorelease];
	addrLen = sizeof(*addr);
	addr = [client allocMemoryWithSize: addrLen];

	if ((socket = accept(_socket, (struct sockaddr*)addr,
	    &addrLen)) == INVALID_SOCKET)
		@throw [OFAcceptFailedException exceptionWithSocket: self];

	client->_socket = socket;
	client->_sockAddr = addr;
	client->_sockAddrLen = addrLen;

	return client;
}

- (void)asyncAcceptWithTarget: (id)target
		     selector: (SEL)selector
{
	[OFRunLoop OF_addAsyncAcceptForTCPSocket: self
					  target: target
					selector: selector];
}

#ifdef OF_HAVE_BLOCKS
- (void)asyncAcceptWithBlock: (of_tcpsocket_async_accept_block_t)block
{
	[OFRunLoop OF_addAsyncAcceptForTCPSocket: self
					   block: block];
}
#endif

- (void)setKeepAlivesEnabled: (bool)enable
{
	int v = enable;

	if (setsockopt(_socket, SOL_SOCKET, SO_KEEPALIVE, (char*)&v, sizeof(v)))
		@throw [OFSetOptionFailedException exceptionWithStream: self];
}

- (OFString*)remoteAddress
{
	char *host;

	if (_sockAddr == NULL || _sockAddrLen == 0)
		@throw [OFNotConnectedException exceptionWithSocket: self];

#ifdef HAVE_THREADSAFE_GETADDRINFO
	host = [self allocMemoryWithSize: NI_MAXHOST];

	@try {
		if (getnameinfo((struct sockaddr*)_sockAddr, _sockAddrLen, host,
		    NI_MAXHOST, NULL, 0, NI_NUMERICHOST | NI_NUMERICSERV))
			@throw [OFAddressTranslationFailedException
			    exceptionWithSocket: self];

		return [OFString stringWithCString: host
					  encoding: OF_STRING_ENCODING_NATIVE];
	} @finally {
		[self freeMemory: host];
	}
#else
# ifdef OF_HAVE_THREADS
	[mutex lock];

	@try {
# endif
		host = inet_ntoa(((struct sockaddr_in*)_sockAddr)->sin_addr);

		if (host == NULL)
			@throw [OFAddressTranslationFailedException
			    exceptionWithSocket: self];

		return [OFString stringWithCString: host
					  encoding: OF_STRING_ENCODING_NATIVE];
# ifdef OF_HAVE_THREADS
	} @finally {
		[mutex unlock];
	}
# endif
#endif

	/* Get rid of a warning, never reached anyway */
	OF_ENSURE(0);
}

- (bool)isListening
{
	return _listening;
}

- (void)close
{
	[super close];

	_listening = false;
	[self freeMemory: _sockAddr];
	_sockAddr = NULL;
	_sockAddrLen = 0;
}
@end
