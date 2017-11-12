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

#include <errno.h>

#ifdef HAVE_DIRENT_H
# include <dirent.h>
#endif
#include "unistd_wrapper.h"

#ifdef HAVE_SYS_STAT_H
# include <sys/stat.h>
#endif

#ifdef HAVE_PWD_H
# include <pwd.h>
#endif
#ifdef HAVE_GRP_H
# include <grp.h>
#endif

#import "OFArray.h"
#import "OFDate.h"
#import "OFDictionary.h"
#import "OFFile.h"
#import "OFFileManager.h"
#import "OFLocalization.h"
#import "OFNumber.h"
#import "OFString.h"
#import "OFSystemInfo.h"
#import "OFURL.h"

#ifdef OF_HAVE_THREADS
# import "OFMutex.h"
#endif

#import "OFChangeCurrentDirectoryPathFailedException.h"
#import "OFCopyItemFailedException.h"
#import "OFCreateDirectoryFailedException.h"
#import "OFCreateSymbolicLinkFailedException.h"
#import "OFInitializationFailedException.h"
#import "OFInvalidArgumentException.h"
#import "OFLinkFailedException.h"
#import "OFLockFailedException.h"
#import "OFMoveItemFailedException.h"
#import "OFNotImplementedException.h"
#import "OFOpenItemFailedException.h"
#import "OFOutOfMemoryException.h"
#import "OFOutOfRangeException.h"
#import "OFReadFailedException.h"
#import "OFRemoveItemFailedException.h"
#import "OFRetrieveItemAttributesFailedException.h"
#import "OFSetItemAttributesFailedException.h"
#import "OFUndefinedKeyException.h"
#import "OFUnlockFailedException.h"

#ifdef OF_WINDOWS
# include <windows.h>
# include <direct.h>
# include <ntdef.h>
#endif

#ifdef OF_MORPHOS
# define BOOL EXEC_BOOL
# include <proto/dos.h>
# include <proto/locale.h>
# undef BOOL
#endif

#if defined(OF_WINDOWS)
typedef struct __stat64 of_stat_t;
#elif defined(OF_MORPHOS)
typedef struct {
	of_offset_t st_size;
	mode_t st_mode;
	of_time_interval_t st_atime, st_mtime, st_ctime;
} of_stat_t;
#elif defined(OF_HAVE_OFF64_T)
typedef struct stat64 of_stat_t;
#else
typedef struct stat of_stat_t;
#endif

#ifndef S_ISLNK
# define S_ISLNK(s) 0
#endif

@interface OFFileManager_default: OFFileManager
@end

static OFFileManager *defaultManager;

const of_file_attribute_key_t of_file_attribute_key_size =
    @"of_file_attribute_key_size";
const of_file_attribute_key_t of_file_attribute_key_type =
    @"of_file_attribute_key_type";
const of_file_attribute_key_t of_file_attribute_key_posix_permissions =
    @"of_file_attribute_key_posix_permissions";
const of_file_attribute_key_t of_file_attribute_key_posix_uid =
    @"of_file_attribute_key_posix_uid";
const of_file_attribute_key_t of_file_attribute_key_posix_gid =
    @"of_file_attribute_key_posix_gid";
const of_file_attribute_key_t of_file_attribute_key_owner =
    @"of_file_attribute_key_owner";
const of_file_attribute_key_t of_file_attribute_key_group =
    @"of_file_attribute_key_group";
const of_file_attribute_key_t of_file_attribute_key_last_access_date =
    @"of_file_attribute_key_last_access_date";
const of_file_attribute_key_t of_file_attribute_key_modification_date =
    @"of_file_attribute_key_modification_date";
const of_file_attribute_key_t of_file_attribute_key_status_change_date =
    @"of_file_attribute_key_status_change_date";
const of_file_attribute_key_t of_file_attribute_key_symbolic_link_destination =
    @"of_file_attribute_key_symbolic_link_destination";

const of_file_type_t of_file_type_regular = @"of_file_type_regular";
const of_file_type_t of_file_type_directory = @"of_file_type_directory";
const of_file_type_t of_file_type_symbolic_link = @"of_file_type_symbolic_link";
const of_file_type_t of_file_type_fifo = @"of_file_type_fifo";
const of_file_type_t of_file_type_character_special =
    @"of_file_type_character_special";
const of_file_type_t of_file_type_block_special = @"of_file_type_block_special";
const of_file_type_t of_file_type_socket = @"of_file_type_socket";

#if defined(OF_HAVE_CHOWN) && defined(OF_HAVE_THREADS) && !defined(OF_MORPHOS)
static OFMutex *passwdMutex;
#endif
#if !defined(HAVE_READDIR_R) && defined(OF_HAVE_THREADS) && !defined(OF_WINDOWS)
static OFMutex *readdirMutex;
#endif

#ifdef OF_WINDOWS
static WINAPI BOOLEAN (*func_CreateSymbolicLinkW)(LPCWSTR, LPCWSTR, DWORD);
#endif

#ifdef OF_MORPHOS
static bool dirChanged = false;
static BPTR originalDirLock = 0;

OF_DESTRUCTOR()
{
	if (dirChanged)
		UnLock(CurrentDir(originalDirLock));
}
#endif

static int
of_stat(OFString *path, of_stat_t *buffer)
{
#if defined(OF_WINDOWS)
	return _wstat64([path UTF16String], buffer);
#elif defined(OF_MORPHOS)
	BPTR lock;
	struct FileInfoBlock fib;
	of_time_interval_t timeInterval;
	struct Locale *locale;

	if ((lock = Lock([path cStringWithEncoding: [OFLocalization encoding]],
	    SHARED_LOCK)) == 0) {
		switch (IoErr()) {
		case ERROR_OBJECT_IN_USE:
		case ERROR_DISK_NOT_VALIDATED:
			errno = EBUSY;
			break;
		case ERROR_OBJECT_NOT_FOUND:
			errno = ENOENT;
			break;
		default:
			errno = 0;
			break;
		}

		return -1;
	}

	if (!Examine64(lock, &fib, TAG_DONE)) {
		UnLock(lock);

		errno = 0;
		return -1;
	}

	UnLock(lock);

	buffer->st_size = fib.fib_Size64;
	buffer->st_mode = (fib.fib_DirEntryType > 0 ? S_IFDIR : S_IFREG);

	timeInterval = 252460800;	/* 1978-01-01 */

	locale = OpenLocale(NULL);
	/*
	 * FIXME: This does not take DST into account. But unfortunately, there
	 * is no way to figure out if DST was in effect when the file was
	 * modified.
	 */
	timeInterval += locale->loc_GMTOffset * 60.0;
	CloseLocale(locale);

	timeInterval += fib.fib_Date.ds_Days * 86400.0;
	timeInterval += fib.fib_Date.ds_Minute * 60.0;
	timeInterval +=
	    fib.fib_Date.ds_Tick / (of_time_interval_t)TICKS_PER_SECOND;

	buffer->st_atime = buffer->st_mtime = buffer->st_ctime = timeInterval;

	return 0;
#elif defined(OF_HAVE_OFF64_T)
	return stat64([path cStringWithEncoding: [OFLocalization encoding]],
	    buffer);
#else
	return stat([path cStringWithEncoding: [OFLocalization encoding]],
	    buffer);
#endif
}

static int
of_lstat(OFString *path, of_stat_t *buffer)
{
#if defined(HAVE_LSTAT) && !defined(OF_WINDOWS) && !defined(OF_MORPHOS)
# ifdef OF_HAVE_OFF64_T
	return lstat64([path cStringWithEncoding: [OFLocalization encoding]],
	    buffer);
# else
	return lstat([path cStringWithEncoding: [OFLocalization encoding]],
	    buffer);
# endif
#else
	return of_stat(path, buffer);
#endif
}

static void
setTypeAttribute(of_mutable_file_attributes_t attributes, of_stat_t *s)
{
	if (S_ISREG(s->st_mode))
		[attributes setObject: of_file_type_regular
			       forKey: of_file_attribute_key_type];
	else if (S_ISDIR(s->st_mode))
		[attributes setObject: of_file_type_directory
			       forKey: of_file_attribute_key_type];
#ifdef S_ISLNK
	else if (S_ISLNK(s->st_mode))
		[attributes setObject: of_file_type_symbolic_link
			       forKey: of_file_attribute_key_type];
#endif
#ifdef S_ISFIFO
	else if (S_ISFIFO(s->st_mode))
		[attributes setObject: of_file_type_fifo
			       forKey: of_file_attribute_key_type];
#endif
#ifdef S_ISCHR
	else if (S_ISCHR(s->st_mode))
		[attributes setObject: of_file_type_character_special
			       forKey: of_file_attribute_key_type];
#endif
#ifdef S_ISBLK
	else if (S_ISBLK(s->st_mode))
		[attributes setObject: of_file_type_block_special
			       forKey: of_file_attribute_key_type];
#endif
#ifdef S_ISSOCK
	else if (S_ISSOCK(s->st_mode))
		[attributes setObject: of_file_type_socket
			       forKey: of_file_attribute_key_type];
#endif
}

static void
setDateAttributes(of_mutable_file_attributes_t attributes, of_stat_t *s)
{
	/* FIXME: We could be more precise on some OSes */
	[attributes
	    setObject: [OFDate dateWithTimeIntervalSince1970: s->st_atime]
	       forKey: of_file_attribute_key_last_access_date];
	[attributes
	    setObject: [OFDate dateWithTimeIntervalSince1970: s->st_mtime]
	       forKey: of_file_attribute_key_modification_date];
	[attributes
	    setObject: [OFDate dateWithTimeIntervalSince1970: s->st_ctime]
	       forKey: of_file_attribute_key_status_change_date];
}

static void
setOwnerAndGroupAttributes(of_mutable_file_attributes_t attributes,
    of_stat_t *s)
{
#ifdef OF_FILE_MANAGER_SUPPORTS_OWNER
	[attributes setObject: [NSNumber numberWithUInt16: s->st_uid]
		       forKey: of_file_attribute_key_posix_uid];
	[attributes setObject: [NSNumber numberWithUInt16: s->st_gid]
		       forKey: of_file_attribute_key_posix_gid];

# ifdef OF_HAVE_THREADS
	[passwdMutex lock];
	@try {
# endif
		of_string_encoding_t encoding = [OFLocalization encoding];
		struct passwd *passwd = getpwuid(s->st_uid);
		struct group *group_ = getgrgid(s->st_gid);

		if (passwd != NULL) {
			OFString *owner = [OFString
			    stringWithCString: passwd->pw_name
				     encoding: encoding];

			[attributes setObject: owner
				       forKey: of_file_attribute_key_owner];
		}

		if (group_ != NULL) {
			OFString *group = [OFString
			    stringWithCString: group_->gr_name
				     encoding: encoding];

			[attributes setObject: group
				       forKey: of_file_attribute_key_group];
		}
# ifdef OF_HAVE_THREADS
	} @finally {
		[passwdMutex unlock];
	}
# endif
#endif
}

static void
setSymbolicLinkDestinationAttribute(of_mutable_file_attributes_t attributes,
    of_stat_t *s, OFString *path)
{
#ifdef OF_FILE_MANAGER_SUPPORTS_SYMLINKS
# ifndef OF_WINDOWS
	if (S_ISLNK(s->st_mode)) {
		of_string_encoding_t encoding = [OFLocalization encoding];
		char destinationC[PATH_MAX];
		ssize_t length;
		OFString *destination;
		of_file_attribute_key_t key;

		length = readlink([path cStringWithEncoding: encoding],
		    destinationC, PATH_MAX);

		if (length < 0)
			@throw [OFRetrieveItemAttributesFailedException
			    exceptionWithPath: path
					errNo: errno];

		destination = [OFString stringWithCString: destinationC
						 encoding: encoding
						   length: length];

		key = of_file_attribute_key_symbolic_link_destination;
		[attributes setObject: destination
			       forKey: key];
	}
# else
	WIN32_FIND_DATAW data;

	if (func_CreateSymbolicLinkW != NULL &&
	    FindFirstFileW([path UTF16String], &data) &&
	    (data.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) &&
	    data.dwReserved0 == IO_REPARSE_TAG_SYMLINK) {
		HANDLE handle;
		OFString *destination;

		if ((handle = CreateFileW([path UTF16String], 0,
		    (FILE_SHARE_READ | FILE_SHARE_WRITE), NULL, OPEN_EXISTING,
		    FILE_FLAG_OPEN_REPARSE_POINT, NULL)) ==
		    INVALID_HANDLE_VALUE)
			@throw [OFRetrieveItemAttributesFailedException
			    exceptionWithPath: path
					errNo: 0];

		@try {
			union {
				char bytes[MAXIMUM_REPARSE_DATA_BUFFER_SIZE];
				REPARSE_DATA_BUFFER data;
			} buffer;
			DWORD size;
			wchar_t *tmp;
			of_file_attribute_key_t key;

			if (!DeviceIoControl(handle, FSCTL_GET_REPARSE_POINT,
			    NULL, 0, buffer.bytes,
			    MAXIMUM_REPARSE_DATA_BUFFER_SIZE, &size, NULL))
				@throw [OFRetrieveItemAttributesFailedException
				    exceptionWithPath: path
						errNo: 0];

			if (buffer.data.ReparseTag != IO_REPARSE_TAG_SYMLINK)
				@throw [OFRetrieveItemAttributesFailedException
				    exceptionWithPath: path
						errNo: 0];

#  define slrb buffer.data.SymbolicLinkReparseBuffer
			tmp = slrb.PathBuffer +
			    (slrb.SubstituteNameOffset / sizeof(wchar_t));

			destination = [OFString
			    stringWithUTF16String: tmp
					   length: slrb.SubstituteNameLength /
						   sizeof(wchar_t)];

			[attributes setObject: of_file_type_symbolic_link
				       forKey: of_file_attribute_key_type];
			key = of_file_attribute_key_symbolic_link_destination;
			[attributes setObject: destination
				       forKey: key];
#  undef slrb
		} @finally {
			CloseHandle(handle);
		}
	}
# endif
#endif
}

static id
attributeForKeyOrException(of_file_attributes_t attributes,
    of_file_attribute_key_t key)
{
	id object = [attributes objectForKey: key];

	if (object == nil)
		@throw [OFUndefinedKeyException exceptionWithObject: attributes
								key: key];

	return object;
}

@implementation OFFileManager
+ (void)initialize
{
#ifdef OF_WINDOWS
	HMODULE module;
#endif

	if (self != [OFFileManager class])
		return;

	/*
	 * Make sure OFFile is initialized.
	 * On some systems, this is needed to initialize the file system driver.
	 */
	[OFFile class];

#if defined(OF_HAVE_CHOWN) && defined(OF_HAVE_THREADS)
	passwdMutex = [[OFMutex alloc] init];
#endif
#if !defined(HAVE_READDIR_R) && !defined(OF_WINDOWS) && defined(OF_HAVE_THREADS)
	readdirMutex = [[OFMutex alloc] init];
#endif

#ifdef OF_WINDOWS
	if ((module = LoadLibrary("kernel32.dll")) != NULL)
		func_CreateSymbolicLinkW =
		    (WINAPI BOOLEAN (*)(LPCWSTR, LPCWSTR, DWORD))
		    GetProcAddress(module, "CreateSymbolicLinkW");
#endif

	defaultManager = [[OFFileManager_default alloc] init];
}

+ (OFFileManager *)defaultManager
{
	return defaultManager;
}

- (OFString *)currentDirectoryPath
{
#if defined(OF_WINDOWS)
	OFString *ret;
	wchar_t *buffer = _wgetcwd(NULL, 0);

	@try {
		ret = [OFString stringWithUTF16String: buffer];
	} @finally {
		free(buffer);
	}

	return ret;
#elif defined(OF_MORPHOS)
	char buffer[512];

	if (!NameFromLock(((struct Process *)FindTask(NULL))->pr_CurrentDir,
	    buffer, 512)) {
		if (IoErr() == ERROR_LINE_TOO_LONG)
			@throw [OFOutOfRangeException exception];

		return nil;
	}

	return [OFString stringWithCString: buffer
				  encoding: [OFLocalization encoding]];
#else
	OFString *ret;
	char *buffer = getcwd(NULL, 0);

	@try {
		ret = [OFString
		    stringWithCString: buffer
			     encoding: [OFLocalization encoding]];
	} @finally {
		free(buffer);
	}

	return ret;
#endif
}

- (OFURL *)currentDirectoryURL
{
	OFMutableURL *URL = [OFMutableURL URL];
	void *pool = objc_autoreleasePoolPush();
	OFString *path;

	[URL setScheme: @"file"];

#if OF_PATH_DELIMITER != '/'
	path = [[[self currentDirectoryPath] pathComponents]
	    componentsJoinedByString: @"/"];
#else
	path = [self currentDirectoryPath];
#endif

#ifndef OF_PATH_STARTS_WITH_SLASH
	path = [path stringByPrependingString: @"/"];
#endif

	[URL setPath: [path stringByAppendingString: @"/"]];

	[URL makeImmutable];

	objc_autoreleasePoolPop(pool);

	return URL;
}

- (of_file_attributes_t)attributesOfItemAtPath: (OFString *)path
{
	of_mutable_file_attributes_t ret = [OFMutableDictionary dictionary];
	void *pool = objc_autoreleasePoolPush();
	of_stat_t s;

	if (path == nil)
		@throw [OFInvalidArgumentException exception];

	if (of_lstat(path, &s) == -1)
		@throw [OFRetrieveItemAttributesFailedException
		    exceptionWithPath: path
				errNo: errno];

	if (s.st_size < 0)
		@throw [OFOutOfRangeException exception];

	[ret setObject: [NSNumber numberWithUIntMax: s.st_size]
		forKey: of_file_attribute_key_size];

	setTypeAttribute(ret, &s);

	[ret setObject: [NSNumber numberWithUInt16: s.st_mode & 07777]
		forKey: of_file_attribute_key_posix_permissions];

	setOwnerAndGroupAttributes(ret, &s);
	setDateAttributes(ret, &s);
	setSymbolicLinkDestinationAttribute(ret, &s, path);

	objc_autoreleasePoolPop(pool);

	return ret;
}

- (of_file_attributes_t)attributesOfItemAtURL: (OFURL *)URL
{
	void *pool = objc_autoreleasePoolPush();
	of_file_attributes_t ret = [self attributesOfItemAtPath:
	    [URL fileSystemRepresentation]];

	[ret retain];

	objc_autoreleasePoolPop(pool);

	return [ret autorelease];
}

- (void)of_setPOSIXPermissions: (OFNumber *)permissions
		  ofItemAtPath: (OFString *)path
		    attributes: (of_file_attributes_t)attributes
{
#ifdef OF_FILE_MANAGER_SUPPORTS_PERMISSIONS
	uint16_t mode = [permissions uInt16Value] & 0777;

# ifndef OF_WINDOWS
	if (chmod([path cStringWithEncoding: [OFLocalization encoding]],
	    mode) != 0)
# else
	if (_wchmod([path UTF16String], mode) != 0)
# endif
		@throw [OFSetItemAttributesFailedException
		    exceptionWithPath: path
			   attributes: attributes
		      failedAttribute: of_file_attribute_key_posix_permissions
				errNo: errno];
#else
	@throw [OFNotImplementedException exceptionWithSelector: _cmd
							 object: self];
#endif
}

- (void)of_setOwner: (OFString *)owner
	   andGroup: (OFString *)group
       ofItemAtPath: (OFString *)path
       attributeKey: (of_file_attribute_key_t)attributeKey
	 attributes: (of_file_attributes_t)attributes
{
#ifdef OF_FILE_MANAGER_SUPPORTS_OWNER
	uid_t uid = -1;
	gid_t gid = -1;
	of_string_encoding_t encoding;

	if (owner == nil && group == nil)
		@throw [OFInvalidArgumentException exception];

	encoding = [OFLocalization encoding];

# ifdef OF_HAVE_THREADS
	[passwdMutex lock];
	@try {
# endif
		if (owner != nil) {
			struct passwd *passwd;

			if ((passwd = getpwnam([owner
			    cStringWithEncoding: encoding])) == NULL)
				@throw [OFSetItemAttributesFailedException
				    exceptionWithPath: path
					   attributes: attributes
				      failedAttribute: attributeKey
						errNo: errno];

			uid = passwd->pw_uid;
		}

		if (group != nil) {
			struct group *group_;

			if ((group_ = getgrnam([group
			    cStringWithEncoding: encoding])) == NULL)
				@throw [OFSetItemAttributesFailedException
				    exceptionWithPath: path
					   attributes: attributes
				      failedAttribute: attributeKey
						errNo: errno];

			gid = group_->gr_gid;
		}
# ifdef OF_HAVE_THREADS
	} @finally {
		[passwdMutex unlock];
	}
# endif

	if (chown([path cStringWithEncoding: encoding], uid, gid) != 0)
		@throw [OFSetItemAttributesFailedException
		    exceptionWithPath: path
			   attributes: attributes
		      failedAttribute: attributeKey
				errNo: errno];
#else
	@throw [OFNotImplementedException exceptionWithSelector: _cmd
							 object: self];
#endif
}

- (void)setAttributes: (of_file_attributes_t)attributes
	 ofItemAtPath: (OFString *)path
{
	void *pool;
	OFEnumerator OF_GENERIC(of_file_attribute_key_t) *keyEnumerator;
	OFEnumerator *objectEnumerator;
	of_file_attribute_key_t key;
	id object;

	if (path == nil)
		@throw [OFInvalidArgumentException exception];

	pool = objc_autoreleasePoolPush();
	keyEnumerator = [attributes keyEnumerator];
	objectEnumerator = [attributes objectEnumerator];

	while ((key = [keyEnumerator nextObject]) != nil &&
	    (object = [objectEnumerator nextObject]) != nil) {
		if ([key isEqual: of_file_attribute_key_posix_permissions])
			[self of_setPOSIXPermissions: object
					ofItemAtPath: path
					  attributes: attributes];
		else if ([key isEqual: of_file_attribute_key_owner])
			[self of_setOwner: object
				 andGroup: nil
			     ofItemAtPath: path
			     attributeKey: key
			       attributes: attributes];
		else if ([key isEqual: of_file_attribute_key_group])
			[self of_setOwner: nil
				 andGroup: object
			     ofItemAtPath: path
			     attributeKey: key
			       attributes: attributes];
		else
			@throw [OFInvalidArgumentException exception];
	}

	objc_autoreleasePoolPop(pool);
}

- (void)setAttributes: (of_file_attributes_t)attributes
	  ofItemAtURL: (OFURL *)URL
{
	void *pool = objc_autoreleasePoolPush();

	[self setAttributes: attributes
	       ofItemAtPath: [URL fileSystemRepresentation]];

	objc_autoreleasePoolPop(pool);
}

- (bool)fileExistsAtPath: (OFString *)path
{
	of_stat_t s;

	if (path == nil)
		@throw [OFInvalidArgumentException exception];

	if (of_stat(path, &s) == -1)
		return false;

	return S_ISREG(s.st_mode);
}

- (bool)fileExistsAtURL: (OFURL *)URL
{
	void *pool = objc_autoreleasePoolPush();
	bool ret = [self fileExistsAtPath: [URL fileSystemRepresentation]];

	objc_autoreleasePoolPop(pool);

	return ret;
}

- (bool)directoryExistsAtPath: (OFString *)path
{
	of_stat_t s;

	if (path == nil)
		@throw [OFInvalidArgumentException exception];

	if (of_stat(path, &s) == -1)
		return false;

	return S_ISDIR(s.st_mode);
}

- (bool)directoryExistsAtURL: (OFURL *)URL
{
	void *pool = objc_autoreleasePoolPush();
	bool ret = [self directoryExistsAtPath: [URL fileSystemRepresentation]];

	objc_autoreleasePoolPop(pool);

	return ret;
}

- (void)createDirectoryAtPath: (OFString *)path
{
	if (path == nil)
		@throw [OFInvalidArgumentException exception];

#if defined(OF_WINDOWS)
	if (_wmkdir([path UTF16String]) != 0)
		@throw [OFCreateDirectoryFailedException
		    exceptionWithPath: path
				errNo: errno];
#elif defined(OF_MORPHOS)
	BPTR lock;

	if ((lock = CreateDir(
	    [path cStringWithEncoding: [OFLocalization encoding]])) == 0) {
		int errNo;

		switch (IoErr()) {
		case ERROR_NO_FREE_STORE:
		case ERROR_DISK_FULL:
			errNo = ENOSPC;
			break;
		case ERROR_OBJECT_IN_USE:
		case ERROR_DISK_NOT_VALIDATED:
			errNo = EBUSY;
			break;
		case ERROR_OBJECT_EXISTS:
			errNo = EEXIST;
			break;
		case ERROR_OBJECT_NOT_FOUND:
			errNo = ENOENT;
			break;
		case ERROR_DISK_WRITE_PROTECTED:
			errNo = EROFS;
			break;
		default:
			errNo = 0;
			break;
		}

		@throw [OFCreateDirectoryFailedException
		    exceptionWithPath: path
				errNo: errNo];
	}

	UnLock(lock);
#else
	if (mkdir([path cStringWithEncoding: [OFLocalization encoding]],
	    0777) != 0)
		@throw [OFCreateDirectoryFailedException
		    exceptionWithPath: path
				errNo: errno];
#endif
}

- (void)createDirectoryAtPath: (OFString *)path
		createParents: (bool)createParents
{
	OFString *currentPath = nil;

	if (!createParents) {
		[self createDirectoryAtPath: path];
		return;
	}

	if (path == nil)
		@throw [OFInvalidArgumentException exception];

	for (OFString *component in [path pathComponents]) {
		void *pool = objc_autoreleasePoolPush();

		if (currentPath != nil)
			currentPath = [currentPath
			    stringByAppendingPathComponent: component];
		else
			currentPath = component;

		if ([currentPath length] > 0 &&
		    ![self directoryExistsAtPath: currentPath])
			[self createDirectoryAtPath: currentPath];

		[currentPath retain];

		objc_autoreleasePoolPop(pool);

		[currentPath autorelease];
	}
}

- (void)createDirectoryAtURL: (OFURL *)URL
{
	void *pool = objc_autoreleasePoolPush();

	[self createDirectoryAtPath: [URL fileSystemRepresentation]];

	objc_autoreleasePoolPop(pool);
}

- (void)createDirectoryAtURL: (OFURL *)URL
	       createParents: (bool)createParents
{
	void *pool = objc_autoreleasePoolPush();

	[self createDirectoryAtPath: [URL fileSystemRepresentation]
		      createParents: createParents];

	objc_autoreleasePoolPop(pool);
}

- (OFArray *)contentsOfDirectoryAtPath: (OFString *)path
{
	OFMutableArray *files;

	if (path == nil)
		@throw [OFInvalidArgumentException exception];

	files = [OFMutableArray array];

#if defined(OF_WINDOWS)
	void *pool = objc_autoreleasePoolPush();
	HANDLE handle;
	WIN32_FIND_DATAW fd;

	path = [path stringByAppendingString: @"\\*"];

	if ((handle = FindFirstFileW([path UTF16String],
	    &fd)) == INVALID_HANDLE_VALUE) {
		int errNo = 0;

		if (GetLastError() == ERROR_FILE_NOT_FOUND)
			errNo = ENOENT;

		@throw [OFOpenItemFailedException exceptionWithPath: path
							       mode: nil
							      errNo: errNo];
	}

	@try {
		do {
			OFString *file;

			if (!wcscmp(fd.cFileName, L".") ||
			    !wcscmp(fd.cFileName, L".."))
				continue;

			file = [OFString stringWithUTF16String: fd.cFileName];
			@try {
				[files addObject: file];
			} @finally {
				[file release];
			}
		} while (FindNextFileW(handle, &fd));

		if (GetLastError() != ERROR_NO_MORE_FILES)
			@throw [OFReadFailedException exceptionWithObject: self
							  requestedLength: 0
								    errNo: EIO];
	} @finally {
		FindClose(handle);
	}

	objc_autoreleasePoolPop(pool);
#elif defined(OF_MORPHOS)
	of_string_encoding_t encoding = [OFLocalization encoding];
	BPTR lock;
	struct FileInfoBlock fib;

	if ((lock = Lock([path cStringWithEncoding: encoding],
	    SHARED_LOCK)) == 0) {
		int errNo;

		switch (IoErr()) {
		case ERROR_OBJECT_IN_USE:
		case ERROR_DISK_NOT_VALIDATED:
			errNo = EBUSY;
			break;
		case ERROR_OBJECT_NOT_FOUND:
			errNo = ENOENT;
			break;
		default:
			errNo = 0;
			break;
		}

		@throw [OFOpenItemFailedException exceptionWithPath: path
							       mode: nil
							      errNo: errNo];
	}

	@try {
		if (!Examine(lock, &fib))
			@throw [OFOpenItemFailedException
			    exceptionWithPath: path
					 mode: nil
					errNo: 0];

		while (ExNext(lock, &fib)) {
			OFString *file;

			file = [[OFString alloc]
			    initWithCString: fib.fib_FileName
				   encoding: encoding];
			@try {
				[files addObject: file];
			} @finally {
				[file release];
			}
		}

		if (IoErr() != ERROR_NO_MORE_ENTRIES)
			@throw [OFReadFailedException
			    exceptionWithObject: self
				requestedLength: 0
					  errNo: EIO];
	} @finally {
		UnLock(lock);
	}
#else
	of_string_encoding_t encoding = [OFLocalization encoding];
	DIR *dir;

	if ((dir = opendir([path cStringWithEncoding: encoding])) == NULL)
		@throw [OFOpenItemFailedException exceptionWithPath: path
							       mode: nil
							      errNo: errno];

# if !defined(HAVE_READDIR_R) && defined(OF_HAVE_THREADS)
	@try {
		[readdirMutex lock];
	} @catch (id e) {
		closedir(dir);
		@throw e;
	}
# endif

	@try {
		for (;;) {
			struct dirent *dirent;
# ifdef HAVE_READDIR_R
			struct dirent buffer;
# endif
			OFString *file;

# ifdef HAVE_READDIR_R
			if (readdir_r(dir, &buffer, &dirent) != 0)
				@throw [OFReadFailedException
				    exceptionWithObject: self
					requestedLength: 0
						  errNo: errno];

			if (dirent == NULL)
				break;
# else
			errno = 0;
			if ((dirent = readdir(dir)) == NULL) {
				if (errno == 0)
					break;
				else
					@throw [OFReadFailedException
					    exceptionWithObject: self
						requestedLength: 0
							  errNo: errno];
			}
# endif

			if (strcmp(dirent->d_name, ".") == 0 ||
			    strcmp(dirent->d_name, "..") == 0)
				continue;

			file = [[OFString alloc] initWithCString: dirent->d_name
							encoding: encoding];
			@try {
				[files addObject: file];
			} @finally {
				[file release];
			}
		}
	} @finally {
		closedir(dir);
# if !defined(HAVE_READDIR_R) && defined(OF_HAVE_THREADS)
		[readdirMutex unlock];
# endif
	}
#endif

	[files makeImmutable];

	return files;
}

- (OFArray *)contentsOfDirectoryAtURL: (OFURL *)URL
{
	void *pool = objc_autoreleasePoolPush();
	OFArray *ret = [self contentsOfDirectoryAtPath:
	    [URL fileSystemRepresentation]];

	[ret retain];

	objc_autoreleasePoolPop(pool);

	return [ret autorelease];
}

- (void)changeCurrentDirectoryPath: (OFString *)path
{
	if (path == nil)
		@throw [OFInvalidArgumentException exception];

#if defined(OF_WINDOWS)
	if (_wchdir([path UTF16String]) != 0)
		@throw [OFChangeCurrentDirectoryPathFailedException
		    exceptionWithPath: path
				errNo: errno];
#elif defined(OF_MORPHOS)
	BPTR lock, oldLock;

	if ((lock = Lock([path cStringWithEncoding: [OFLocalization encoding]],
	    SHARED_LOCK)) == 0) {
		int errNo;

		switch (IoErr()) {
		case ERROR_OBJECT_IN_USE:
		case ERROR_DISK_NOT_VALIDATED:
			errNo = EBUSY;
			break;
		case ERROR_OBJECT_NOT_FOUND:
			errNo = ENOENT;
			break;
		default:
			errNo = 0;
			break;
		}

		@throw [OFChangeCurrentDirectoryPathFailedException
		    exceptionWithPath: path
				errNo: errNo];
	}

	oldLock = CurrentDir(lock);

	if (!dirChanged)
		originalDirLock = oldLock;
	else
		UnLock(oldLock);

	dirChanged = true;
#else
	if (chdir([path cStringWithEncoding: [OFLocalization encoding]]) != 0)
		@throw [OFChangeCurrentDirectoryPathFailedException
		    exceptionWithPath: path
				errNo: errno];
#endif
}

- (void)changeCurrentDirectoryURL: (OFURL *)URL
{
	void *pool = objc_autoreleasePoolPush();

	[self changeCurrentDirectoryPath: [URL fileSystemRepresentation]];

	objc_autoreleasePoolPop(pool);
}

- (void)copyItemAtPath: (OFString *)source
		toPath: (OFString *)destination
{
	void *pool;
	of_file_attributes_t attributes;
	of_file_type_t type;

	if (source == nil || destination == nil)
		@throw [OFInvalidArgumentException exception];

	pool = objc_autoreleasePoolPush();

	if ([self fileExistsAtPath: destination])
		@throw [OFCopyItemFailedException
		    exceptionWithSourcePath: source
			    destinationPath: destination
				      errNo: EEXIST];

	@try {
		attributes = [self attributesOfItemAtPath: source];
	} @catch (OFRetrieveItemAttributesFailedException *e) {
		@throw [OFCopyItemFailedException
		    exceptionWithSourcePath: source
			    destinationPath: destination
				      errNo: [e errNo]];
	}

	type = [attributes fileType];

	if ([type isEqual: of_file_type_directory]) {
		OFArray *contents;

		@try {
			[self createDirectoryAtPath: destination];

#ifdef OF_FILE_MANAGER_SUPPORTS_PERMISSIONS
			of_file_attribute_key_t key =
			    of_file_attribute_key_posix_permissions;
			OFNumber *permissions = [attributes objectForKey: key];
			of_file_attributes_t destinationAttributes =
			    [OFDictionary dictionaryWithObject: permissions
							forKey: key];

			[self setAttributes: destinationAttributes
			       ofItemAtPath: destination];
#endif

			contents = [self contentsOfDirectoryAtPath: source];
		} @catch (id e) {
			/*
			 * Only convert exceptions to OFCopyItemFailedException
			 * that have an errNo property. This covers all I/O
			 * related exceptions from the operations used to copy
			 * an item, all others should be left as is.
			 */
			if ([e respondsToSelector: @selector(errNo)])
				@throw [OFCopyItemFailedException
				    exceptionWithSourcePath: source
					    destinationPath: destination
						      errNo: [e errNo]];

			@throw e;
		}

		for (OFString *item in contents) {
			void *pool2 = objc_autoreleasePoolPush();
			OFString *sourcePath, *destinationPath;

			sourcePath =
			    [source stringByAppendingPathComponent: item];
			destinationPath =
			    [destination stringByAppendingPathComponent: item];

			[self copyItemAtPath: sourcePath
				      toPath: destinationPath];

			objc_autoreleasePoolPop(pool2);
		}
	} else if ([type isEqual: of_file_type_regular]) {
		size_t pageSize = [OFSystemInfo pageSize];
		OFFile *sourceFile = nil;
		OFFile *destinationFile = nil;
		char *buffer;

		if ((buffer = malloc(pageSize)) == NULL)
			@throw [OFOutOfMemoryException
			    exceptionWithRequestedSize: pageSize];

		@try {
			sourceFile = [OFFile fileWithPath: source
						     mode: @"r"];
			destinationFile = [OFFile fileWithPath: destination
							  mode: @"w"];

			while (![sourceFile isAtEndOfStream]) {
				size_t length;

				length = [sourceFile readIntoBuffer: buffer
							     length: pageSize];
				[destinationFile writeBuffer: buffer
						      length: length];
			}

#ifdef OF_FILE_MANAGER_SUPPORTS_PERMISSIONS
			of_file_attribute_key_t key =
			    of_file_attribute_key_posix_permissions;
			OFNumber *permissions = [attributes objectForKey: key];
			of_file_attributes_t destinationAttributes =
			    [OFDictionary dictionaryWithObject: permissions
							forKey: key];

			[self setAttributes: destinationAttributes
			       ofItemAtPath: destination];
#endif
		} @catch (id e) {
			/*
			 * Only convert exceptions to OFCopyItemFailedException
			 * that have an errNo property. This covers all I/O
			 * related exceptions from the operations used to copy
			 * an item, all others should be left as is.
			 */
			if ([e respondsToSelector: @selector(errNo)])
				@throw [OFCopyItemFailedException
				    exceptionWithSourcePath: source
					    destinationPath: destination
						      errNo: [e errNo]];

			@throw e;
		} @finally {
			[sourceFile close];
			[destinationFile close];
			free(buffer);
		}
#ifdef OF_FILE_MANAGER_SUPPORTS_SYMLINKS
	} else if ([type isEqual: of_file_type_symbolic_link]) {
		@try {
			source = [attributes fileSymbolicLinkDestination];

			[self createSymbolicLinkAtPath: destination
				   withDestinationPath: source];
		} @catch (id e) {
			/*
			 * Only convert exceptions to OFCopyItemFailedException
			 * that have an errNo property. This covers all I/O
			 * related exceptions from the operations used to copy
			 * an item, all others should be left as is.
			 */
			if ([e respondsToSelector: @selector(errNo)])
				@throw [OFCopyItemFailedException
				    exceptionWithSourcePath: source
					    destinationPath: destination
						      errNo: [e errNo]];

			@throw e;
		}
#endif
	} else
		@throw [OFCopyItemFailedException
		    exceptionWithSourcePath: source
			    destinationPath: destination
				      errNo: EINVAL];

	objc_autoreleasePoolPop(pool);
}

- (void)copyItemAtURL: (OFURL *)source
		toURL: (OFURL *)destination
{
	void *pool = objc_autoreleasePoolPush();

	[self copyItemAtPath: [source fileSystemRepresentation]
		      toPath: [destination fileSystemRepresentation]];

	objc_autoreleasePoolPop(pool);
}

- (void)moveItemAtPath: (OFString *)source
		toPath: (OFString *)destination
{
	of_stat_t s;

	if (source == nil || destination == nil)
		@throw [OFInvalidArgumentException exception];

	if (of_lstat(destination, &s) == 0)
		@throw [OFMoveItemFailedException
		    exceptionWithSourcePath: source
			    destinationPath: destination
				      errNo: EEXIST];

#if defined(OF_WINDOWS)
	void *pool = objc_autoreleasePoolPush();

	if (_wrename([source UTF16String], [destination UTF16String]) != 0) {
		if (errno != EXDEV)
			@throw [OFMoveItemFailedException
			    exceptionWithSourcePath: source
				    destinationPath: destination
					      errNo: errno];
#elif defined(OF_MORPHOS)
	of_string_encoding_t encoding = [OFLocalization encoding];

	if (!Rename([source cStringWithEncoding: encoding],
	    [destination cStringWithEncoding: encoding]) != 0) {
		LONG err;

		if ((err = IoErr()) != ERROR_RENAME_ACROSS_DEVICES) {
			int errNo;

			switch (err) {
			case ERROR_OBJECT_IN_USE:
			case ERROR_DISK_NOT_VALIDATED:
				errNo = EBUSY;
				break;
			case ERROR_OBJECT_EXISTS:
				errNo = EEXIST;
				break;
			case ERROR_OBJECT_NOT_FOUND:
				errNo = ENOENT;
				break;
			case ERROR_DISK_WRITE_PROTECTED:
				errNo = EROFS;
				break;
			default:
				errNo = 0;
				break;
			}

			@throw [OFMoveItemFailedException
			    exceptionWithSourcePath: source
				    destinationPath: destination
					      errNo: errNo];
		}
#else
	of_string_encoding_t encoding = [OFLocalization encoding];

	if (rename([source cStringWithEncoding: encoding],
	    [destination cStringWithEncoding: encoding]) != 0) {
		if (errno != EXDEV)
			@throw [OFMoveItemFailedException
			    exceptionWithSourcePath: source
				    destinationPath: destination
					      errNo: errno];
#endif

		@try {
			[self copyItemAtPath: source
				      toPath: destination];
		} @catch (OFCopyItemFailedException *e) {
			[self removeItemAtPath: destination];

			@throw [OFMoveItemFailedException
			    exceptionWithSourcePath: source
				    destinationPath: destination
					      errNo: [e errNo]];
		}

		@try {
			[self removeItemAtPath: source];
		} @catch (OFRemoveItemFailedException *e) {
			@throw [OFMoveItemFailedException
			    exceptionWithSourcePath: source
				    destinationPath: destination
					      errNo: [e errNo]];
		}
	}

#ifdef OF_WINDOWS
	objc_autoreleasePoolPop(pool);
#endif
}

- (void)moveItemAtURL: (OFURL *)source
		toURL: (OFURL *)destination
{
	void *pool = objc_autoreleasePoolPush();

	[self moveItemAtPath: [source fileSystemRepresentation]
		      toPath: [destination fileSystemRepresentation]];

	objc_autoreleasePoolPop(pool);
}

- (void)removeItemAtPath: (OFString *)path
{
	void *pool;
	of_stat_t s;

	if (path == nil)
		@throw [OFInvalidArgumentException exception];

	pool = objc_autoreleasePoolPush();

	if (of_lstat(path, &s) != 0)
		@throw [OFRemoveItemFailedException exceptionWithPath: path
								errNo: errno];

	if (S_ISDIR(s.st_mode)) {
		OFArray *contents;

		@try {
			contents = [self contentsOfDirectoryAtPath: path];
		} @catch (id e) {
			/*
			 * Only convert exceptions to
			 * OFRemoveItemFailedException that have an errNo
			 * property. This covers all I/O related exceptions
			 * from the operations used to remove an item, all
			 * others should be left as is.
			 */
			if ([e respondsToSelector: @selector(errNo)])
				@throw [OFRemoveItemFailedException
				    exceptionWithPath: path
						errNo: [e errNo]];

			@throw e;
		}

		for (OFString *item in contents) {
			void *pool2 = objc_autoreleasePoolPush();

			[self removeItemAtPath:
			    [path stringByAppendingPathComponent: item]];

			objc_autoreleasePoolPop(pool2);
		}

#ifndef OF_MORPHOS
# ifndef OF_WINDOWS
		if (rmdir([path cStringWithEncoding:
		    [OFLocalization encoding]]) != 0)
# else
		if (_wrmdir([path UTF16String]) != 0)
# endif
			@throw [OFRemoveItemFailedException
				exceptionWithPath: path
					    errNo: errno];
	} else {
# ifndef OF_WINDOWS
		if (unlink([path cStringWithEncoding:
		    [OFLocalization encoding]]) != 0)
# else
		if (_wunlink([path UTF16String]) != 0)
# endif
			@throw [OFRemoveItemFailedException
			    exceptionWithPath: path
					errNo: errno];
#endif
	}

#ifdef OF_MORPHOS
	if (!DeleteFile(
	    [path cStringWithEncoding: [OFLocalization encoding]])) {
		int errNo;

		switch (IoErr()) {
		case ERROR_OBJECT_IN_USE:
		case ERROR_DISK_NOT_VALIDATED:
			errNo = EBUSY;
			break;
		case ERROR_OBJECT_NOT_FOUND:
			errNo = ENOENT;
			break;
		case ERROR_DISK_WRITE_PROTECTED:
			errNo = EROFS;
			break;
		case ERROR_DELETE_PROTECTED:
			errNo = EACCES;
			break;
		default:
			errNo = 0;
			break;
		}

		@throw [OFRemoveItemFailedException exceptionWithPath: path
								errNo: errNo];
	}
#endif

	objc_autoreleasePoolPop(pool);
}

- (void)removeItemAtURL: (OFURL *)URL
{
	void *pool = objc_autoreleasePoolPush();

	[self removeItemAtPath: [URL fileSystemRepresentation]];

	objc_autoreleasePoolPop(pool);
}

#ifdef OF_FILE_MANAGER_SUPPORTS_LINKS
- (void)linkItemAtPath: (OFString *)source
		toPath: (OFString *)destination
{
	void *pool;

	if (source == nil || destination == nil)
		@throw [OFInvalidArgumentException exception];

	pool = objc_autoreleasePoolPush();

# ifndef OF_WINDOWS
	of_string_encoding_t encoding = [OFLocalization encoding];

	if (link([source cStringWithEncoding: encoding],
	    [destination cStringWithEncoding: encoding]) != 0)
		@throw [OFLinkFailedException
		    exceptionWithSourcePath: source
			    destinationPath: destination
				      errNo: errno];
# else
	if (!CreateHardLinkW([destination UTF16String],
	    [source UTF16String], NULL))
		@throw [OFLinkFailedException
		    exceptionWithSourcePath: source
			    destinationPath: destination
				      errNo: 0];

# endif

	objc_autoreleasePoolPop(pool);
}

- (void)linkItemAtURL: (OFURL *)source
		toURL: (OFURL *)destination
{
	void *pool = objc_autoreleasePoolPush();

	[self linkItemAtPath: [source fileSystemRepresentation]
		      toPath: [destination fileSystemRepresentation]];

	objc_autoreleasePoolPop(pool);
}
#endif

#ifdef OF_FILE_MANAGER_SUPPORTS_SYMLINKS
- (void)createSymbolicLinkAtPath: (OFString *)destination
	     withDestinationPath: (OFString *)source
{
	void *pool;

	if (source == nil || destination == nil)
		@throw [OFInvalidArgumentException exception];

	pool = objc_autoreleasePoolPush();

# ifndef OF_WINDOWS
	of_string_encoding_t encoding = [OFLocalization encoding];

	if (symlink([source cStringWithEncoding: encoding],
	    [destination cStringWithEncoding: encoding]) != 0)
		@throw [OFCreateSymbolicLinkFailedException
		    exceptionWithSourcePath: source
			    destinationPath: destination
				      errNo: errno];
# else
	if (func_CreateSymbolicLinkW == NULL)
		@throw [OFNotImplementedException exceptionWithSelector: _cmd
								 object: self];

	if (!func_CreateSymbolicLinkW([destination UTF16String],
	    [source UTF16String], 0))
		@throw [OFCreateSymbolicLinkFailedException
		    exceptionWithSourcePath: source
			    destinationPath: destination
				      errNo: 0];
# endif

	objc_autoreleasePoolPop(pool);
}

- (void)createSymbolicLinkAtURL: (OFURL *)destination
	     withDestinationURL: (OFURL *)source
{
	void *pool = objc_autoreleasePoolPush();

	[self createSymbolicLinkAtPath: [destination fileSystemRepresentation]
		   withDestinationPath: [source fileSystemRepresentation]];

	objc_autoreleasePoolPop(pool);
}
#endif
@end

@implementation OFDictionary (FileAttributes)
- (uintmax_t)fileSize
{
	return [attributeForKeyOrException(self, of_file_attribute_key_size)
	    uIntMaxValue];
}

- (of_file_type_t)fileType
{
	return attributeForKeyOrException(self, of_file_attribute_key_type);
}

- (uint16_t)filePOSIXPermissions
{
	return [attributeForKeyOrException(self,
	    of_file_attribute_key_posix_permissions) uInt16Value];
}

- (uint32_t)filePOSIXUID
{
	return [attributeForKeyOrException(self,
	    of_file_attribute_key_posix_uid) uInt32Value];
}

- (uint32_t)filePOSIXGID
{
	return [attributeForKeyOrException(self,
	    of_file_attribute_key_posix_gid) uInt32Value];
}

- (OFString *)fileOwner
{
	return attributeForKeyOrException(self, of_file_attribute_key_owner);
}

- (OFString *)fileGroup
{
	return attributeForKeyOrException(self, of_file_attribute_key_group);
}

- (OFDate *)fileLastAccessDate
{
	return attributeForKeyOrException(self,
	    of_file_attribute_key_last_access_date);
}

- (OFDate *)fileModificationDate
{
	return attributeForKeyOrException(self,
	    of_file_attribute_key_modification_date);
}

- (OFDate *)fileStatusChangeDate
{
	return attributeForKeyOrException(self,
	    of_file_attribute_key_status_change_date);
}

- (OFString *)fileSymbolicLinkDestination
{
	return attributeForKeyOrException(self,
	    of_file_attribute_key_symbolic_link_destination);
}
@end

@implementation OFFileManager_default
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
@end
