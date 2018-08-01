/*
 * Copyright (c) 2008, 2009, 2010, 2011, 2012, 2013, 2014, 2015, 2016, 2017,
 *               2018
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

#import "OFDNSResourceRecord.h"
#import "OFData.h"

#import "OFInvalidFormatException.h"

OFString *
of_dns_resource_record_class_to_string(
    of_dns_resource_record_class_t recordClass)
{
	switch (recordClass) {
	case OF_DNS_RESOURCE_RECORD_CLASS_IN:
		return @"IN";
	case OF_DNS_RESOURCE_RECORD_CLASS_ANY:
		return @"any";
	default:
		return [OFString stringWithFormat: @"%u", recordClass];
	}
}

OFString *
of_dns_resource_record_type_to_string(of_dns_resource_record_type_t recordType)
{
	switch (recordType) {
	case OF_DNS_RESOURCE_RECORD_TYPE_A:
		return @"A";
	case OF_DNS_RESOURCE_RECORD_TYPE_NS:
		return @"NS";
	case OF_DNS_RESOURCE_RECORD_TYPE_CNAME:
		return @"CNAME";
	case OF_DNS_RESOURCE_RECORD_TYPE_SOA:
		return @"SOA";
	case OF_DNS_RESOURCE_RECORD_TYPE_PTR:
		return @"PTR";
	case OF_DNS_RESOURCE_RECORD_TYPE_HINFO:
		return @"HINFO";
	case OF_DNS_RESOURCE_RECORD_TYPE_MX:
		return @"MX";
	case OF_DNS_RESOURCE_RECORD_TYPE_TXT:
		return @"TXT";
	case OF_DNS_RESOURCE_RECORD_TYPE_AAAA:
		return @"AAAA";
	case OF_DNS_RESOURCE_RECORD_TYPE_ALL:
		return @"all";
	default:
		return [OFString stringWithFormat: @"%u", recordType];
	}
}

@implementation OFDNSResourceRecord
@synthesize name = _name, recordClass = _recordClass, recordType = _recordType;
@synthesize TTL = _TTL;

- (instancetype)initWithName: (OFString *)name
		 recordClass: (of_dns_resource_record_class_t)recordClass
		  recordType: (of_dns_resource_record_type_t)recordType
			 TTL: (uint32_t)TTL
{
	self = [super init];

	@try {
		_name = [name copy];
		_recordClass = recordClass;
		_recordType = recordType;
		_TTL = TTL;
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}

- (void)dealloc
{
	[_name release];

	[super dealloc];
}

- (OFString *)description
{
	return [OFString stringWithFormat:
	    @"<%@:\n"
	    @"\tName = %@\n"
	    @"\tClass = %@\n"
	    @"\tType = %@\n"
	    @"\tTTL = %" PRIu32 "\n"
	    @">",
	    [self className], _name,
	    of_dns_resource_record_class_to_string(_recordClass),
	    of_dns_resource_record_type_to_string(_recordType), _TTL];
}
@end

@implementation OFADNSResourceRecord
@synthesize address = _address;

- (instancetype)initWithName: (OFString *)name
		 recordClass: (of_dns_resource_record_class_t)recordClass
		  recordType: (of_dns_resource_record_type_t)recordType
			 TTL: (uint32_t)TTL
{
	OF_INVALID_INIT_METHOD
}

- (instancetype)initWithName: (OFString *)name
		     address: (OFString *)address
			 TTL: (uint32_t)TTL
{
	self = [super initWithName: name
		       recordClass: OF_DNS_RESOURCE_RECORD_CLASS_IN
			recordType: OF_DNS_RESOURCE_RECORD_TYPE_A
			       TTL: TTL];

	@try {
		_address = [address copy];
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}

- (void)dealloc
{
	[_address release];

	[super dealloc];
}

- (bool)isEqual: (id)otherObject
{
	OFADNSResourceRecord *otherRecord;

	if (![otherObject isKindOfClass: [OFADNSResourceRecord class]])
		return false;

	otherRecord = otherObject;

	if (otherRecord->_name != _name && ![otherRecord->_name isEqual: _name])
		return false;

	if (otherRecord->_recordClass != _recordClass)
		return false;

	if (otherRecord->_recordType != _recordType)
		return false;

	if (otherRecord->_address != _address &&
	    ![otherRecord->_address isEqual: _address])
		return false;

	return true;
}

- (uint32_t)hash
{
	uint32_t hash;

	OF_HASH_INIT(hash);

	OF_HASH_ADD_HASH(hash, [_name hash]);
	OF_HASH_ADD(hash, _recordClass >> 8);
	OF_HASH_ADD(hash, _recordClass);
	OF_HASH_ADD(hash, _recordType >> 8);
	OF_HASH_ADD(hash, _recordType);
	OF_HASH_ADD_HASH(hash, [_address hash]);

	OF_HASH_FINALIZE(hash);

	return hash;
}

- (OFString *)description
{
	return [OFString stringWithFormat:
	    @"<%@:\n"
	    @"\tName = %@\n"
	    @"\tAddress = %@\n"
	    @"\tTTL = %" PRIu32 "\n"
	    @">",
	    [self className], _name, _address, _TTL];
}
@end

@implementation OFAAAADNSResourceRecord
@synthesize address = _address;

- (instancetype)initWithName: (OFString *)name
		 recordClass: (of_dns_resource_record_class_t)recordClass
		  recordType: (of_dns_resource_record_type_t)recordType
			 TTL: (uint32_t)TTL
{
	OF_INVALID_INIT_METHOD
}

- (instancetype)initWithName: (OFString *)name
		     address: (OFString *)address
			 TTL: (uint32_t)TTL
{
	self = [super initWithName: name
		       recordClass: OF_DNS_RESOURCE_RECORD_CLASS_IN
			recordType: OF_DNS_RESOURCE_RECORD_TYPE_AAAA
			       TTL: TTL];

	@try {
		_address = [address copy];
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}

- (void)dealloc
{
	[_address release];

	[super dealloc];
}

- (bool)isEqual: (id)otherObject
{
	OFAAAADNSResourceRecord *otherRecord;

	if (![otherObject isKindOfClass: [OFAAAADNSResourceRecord class]])
		return false;

	otherRecord = otherObject;

	if (otherRecord->_name != _name && ![otherRecord->_name isEqual: _name])
		return false;

	if (otherRecord->_recordClass != _recordClass)
		return false;

	if (otherRecord->_recordType != _recordType)
		return false;

	if (otherRecord->_address != _address &&
	    ![otherRecord->_address isEqual: _address])
		return false;

	return true;
}

- (uint32_t)hash
{
	uint32_t hash;

	OF_HASH_INIT(hash);

	OF_HASH_ADD_HASH(hash, [_name hash]);
	OF_HASH_ADD(hash, _recordClass >> 8);
	OF_HASH_ADD(hash, _recordClass);
	OF_HASH_ADD(hash, _recordType >> 8);
	OF_HASH_ADD(hash, _recordType);
	OF_HASH_ADD_HASH(hash, [_address hash]);

	OF_HASH_FINALIZE(hash);

	return hash;
}

- (OFString *)description
{
	return [OFString stringWithFormat:
	    @"<%@:\n"
	    @"\tName = %@\n"
	    @"\tAddress = %@\n"
	    @"\tTTL = %" PRIu32 "\n"
	    @">",
	    [self className], _name, _address, _TTL];
}
@end

@implementation OFCNAMEDNSResourceRecord
@synthesize alias = _alias;

- (instancetype)initWithName: (OFString *)name
		 recordClass: (of_dns_resource_record_class_t)recordClass
		  recordType: (of_dns_resource_record_type_t)recordType
			 TTL: (uint32_t)TTL
{
	OF_INVALID_INIT_METHOD
}

- (instancetype)initWithName: (OFString *)name
		 recordClass: (of_dns_resource_record_class_t)recordClass
		       alias: (OFString *)alias
			 TTL: (uint32_t)TTL
{
	self = [super initWithName: name
		       recordClass: recordClass
			recordType: OF_DNS_RESOURCE_RECORD_TYPE_CNAME
			       TTL: TTL];

	@try {
		_alias = [alias copy];
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}

- (void)dealloc
{
	[_alias release];

	[super dealloc];
}

- (bool)isEqual: (id)otherObject
{
	OFCNAMEDNSResourceRecord *otherRecord;

	if (![otherObject isKindOfClass: [OFCNAMEDNSResourceRecord class]])
		return false;

	otherRecord = otherObject;

	if (otherRecord->_name != _name && ![otherRecord->_name isEqual: _name])
		return false;

	if (otherRecord->_recordClass != _recordClass)
		return false;

	if (otherRecord->_recordType != _recordType)
		return false;

	if (otherRecord->_alias != _alias &&
	    ![otherRecord->_alias isEqual: _alias])
		return false;

	return true;
}

- (uint32_t)hash
{
	uint32_t hash;

	OF_HASH_INIT(hash);

	OF_HASH_ADD_HASH(hash, [_name hash]);
	OF_HASH_ADD(hash, _recordClass >> 8);
	OF_HASH_ADD(hash, _recordClass);
	OF_HASH_ADD(hash, _recordType >> 8);
	OF_HASH_ADD(hash, _recordType);
	OF_HASH_ADD_HASH(hash, [_alias hash]);

	OF_HASH_FINALIZE(hash);

	return hash;
}

- (OFString *)description
{
	return [OFString stringWithFormat:
	    @"<%@:\n"
	    @"\tName = %@\n"
	    @"\tClass = %@\n"
	    @"\tAlias = %@\n"
	    @"\tTTL = %" PRIu32 "\n"
	    @">",
	    [self className], _name,
	    of_dns_resource_record_class_to_string(_recordClass), _alias, _TTL];
}
@end

@implementation OFMXDNSResourceRecord
@synthesize preference = _preference, mailExchange = _mailExchange;

- (instancetype)initWithName: (OFString *)name
		 recordClass: (of_dns_resource_record_class_t)recordClass
		  recordType: (of_dns_resource_record_type_t)recordType
			 TTL: (uint32_t)TTL
{
	OF_INVALID_INIT_METHOD
}

- (instancetype)initWithName: (OFString *)name
		 recordClass: (of_dns_resource_record_class_t)recordClass
		  preference: (uint16_t)preference
		mailExchange: (OFString *)mailExchange
			 TTL: (uint32_t)TTL
{
	self = [super initWithName: name
		       recordClass: recordClass
			recordType: OF_DNS_RESOURCE_RECORD_TYPE_MX
			       TTL: TTL];

	@try {
		_preference = preference;
		_mailExchange = [mailExchange copy];
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}

- (void)dealloc
{
	[_mailExchange release];

	[super dealloc];
}

- (bool)isEqual: (id)otherObject
{
	OFMXDNSResourceRecord *otherRecord;

	if (![otherObject isKindOfClass: [OFMXDNSResourceRecord class]])
		return false;

	otherRecord = otherObject;

	if (otherRecord->_name != _name && ![otherRecord->_name isEqual: _name])
		return false;

	if (otherRecord->_recordClass != _recordClass)
		return false;

	if (otherRecord->_recordType != _recordType)
		return false;

	if (otherRecord->_preference != _preference)
		return false;

	if (otherRecord->_mailExchange != _mailExchange &&
	    ![otherRecord->_mailExchange isEqual: _mailExchange])
		return false;

	return true;
}

- (uint32_t)hash
{
	uint32_t hash;

	OF_HASH_INIT(hash);

	OF_HASH_ADD_HASH(hash, [_name hash]);
	OF_HASH_ADD(hash, _recordClass >> 8);
	OF_HASH_ADD(hash, _recordClass);
	OF_HASH_ADD(hash, _recordType >> 8);
	OF_HASH_ADD(hash, _recordType);
	OF_HASH_ADD(hash, _preference >> 8);
	OF_HASH_ADD(hash, _preference);
	OF_HASH_ADD_HASH(hash, [_mailExchange hash]);

	OF_HASH_FINALIZE(hash);

	return hash;
}

- (OFString *)description
{
	return [OFString stringWithFormat:
	    @"<%@:\n"
	    @"\tName = %@\n"
	    @"\tClass = %@\n"
	    @"\tPreference = %" PRIu16 "\n"
	    @"\tMail Exchange = %@\n"
	    @"\tTTL = %" PRIu32 "\n"
	    @">",
	    [self className], _name,
	    of_dns_resource_record_class_to_string(_recordClass), _preference,
	    _mailExchange, _TTL];
}
@end

@implementation OFNSDNSResourceRecord
@synthesize authoritativeHost = _authoritativeHost;

- (instancetype)initWithName: (OFString *)name
		 recordClass: (of_dns_resource_record_class_t)recordClass
		  recordType: (of_dns_resource_record_type_t)recordType
			 TTL: (uint32_t)TTL
{
	OF_INVALID_INIT_METHOD
}

- (instancetype)initWithName: (OFString *)name
		 recordClass: (of_dns_resource_record_class_t)recordClass
	   authoritativeHost: (OFString *)authoritativeHost
			 TTL: (uint32_t)TTL
{
	self = [super initWithName: name
		       recordClass: recordClass
			recordType: OF_DNS_RESOURCE_RECORD_TYPE_NS
			       TTL: TTL];

	@try {
		_authoritativeHost = [authoritativeHost copy];
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}

- (void)dealloc
{
	[_authoritativeHost release];

	[super dealloc];
}

- (bool)isEqual: (id)otherObject
{
	OFNSDNSResourceRecord *otherRecord;

	if (![otherObject isKindOfClass: [OFNSDNSResourceRecord class]])
		return false;

	otherRecord = otherObject;

	if (otherRecord->_name != _name && ![otherRecord->_name isEqual: _name])
		return false;

	if (otherRecord->_recordClass != _recordClass)
		return false;

	if (otherRecord->_recordType != _recordType)
		return false;

	if (otherRecord->_authoritativeHost != _authoritativeHost &&
	    ![otherRecord->_authoritativeHost isEqual: _authoritativeHost])
		return false;

	return true;
}

- (uint32_t)hash
{
	uint32_t hash;

	OF_HASH_INIT(hash);

	OF_HASH_ADD_HASH(hash, [_name hash]);
	OF_HASH_ADD(hash, _recordClass >> 8);
	OF_HASH_ADD(hash, _recordClass);
	OF_HASH_ADD(hash, _recordType >> 8);
	OF_HASH_ADD(hash, _recordType);
	OF_HASH_ADD_HASH(hash, [_authoritativeHost hash]);

	OF_HASH_FINALIZE(hash);

	return hash;
}

- (OFString *)description
{
	return [OFString stringWithFormat:
	    @"<%@:\n"
	    @"\tName = %@\n"
	    @"\tClass = %@\n"
	    @"\tAuthoritative Host = %@\n"
	    @"\tTTL = %" PRIu32 "\n"
	    @">",
	    [self className], _name,
	    of_dns_resource_record_class_to_string(_recordClass),
	    _authoritativeHost, _TTL];
}
@end

@implementation OFPTRDNSResourceRecord
@synthesize domainName = _domainName;

- (instancetype)initWithName: (OFString *)name
		 recordClass: (of_dns_resource_record_class_t)recordClass
		  recordType: (of_dns_resource_record_type_t)recordType
			 TTL: (uint32_t)TTL
{
	OF_INVALID_INIT_METHOD
}

- (instancetype)initWithName: (OFString *)name
		 recordClass: (of_dns_resource_record_class_t)recordClass
		  domainName: (OFString *)domainName
			 TTL: (uint32_t)TTL
{
	self = [super initWithName: name
		       recordClass: recordClass
			recordType: OF_DNS_RESOURCE_RECORD_TYPE_PTR
			       TTL: TTL];

	@try {
		_domainName = [domainName copy];
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}

- (void)dealloc
{
	[_domainName release];

	[super dealloc];
}

- (bool)isEqual: (id)otherObject
{
	OFPTRDNSResourceRecord *otherRecord;

	if (![otherObject isKindOfClass: [OFPTRDNSResourceRecord class]])
		return false;

	otherRecord = otherObject;

	if (otherRecord->_name != _name && ![otherRecord->_name isEqual: _name])
		return false;

	if (otherRecord->_recordClass != _recordClass)
		return false;

	if (otherRecord->_recordType != _recordType)
		return false;

	if (otherRecord->_domainName != _domainName &&
	    ![otherRecord->_domainName isEqual: _domainName])
		return false;

	return true;
}

- (uint32_t)hash
{
	uint32_t hash;

	OF_HASH_INIT(hash);

	OF_HASH_ADD_HASH(hash, [_name hash]);
	OF_HASH_ADD(hash, _recordClass >> 8);
	OF_HASH_ADD(hash, _recordClass);
	OF_HASH_ADD(hash, _recordType >> 8);
	OF_HASH_ADD(hash, _recordType);
	OF_HASH_ADD_HASH(hash, [_domainName hash]);

	OF_HASH_FINALIZE(hash);

	return hash;
}

- (OFString *)description
{
	return [OFString stringWithFormat:
	    @"<%@:\n"
	    @"\tName = %@\n"
	    @"\tClass = %@\n"
	    @"\tDomain Name = %@\n"
	    @"\tTTL = %" PRIu32 "\n"
	    @">",
	    [self className], _name,
	    of_dns_resource_record_class_to_string(_recordClass), _domainName,
	    _TTL];
}
@end

@implementation OFTXTDNSResourceRecord
@synthesize textData = _textData;

- (instancetype)initWithName: (OFString *)name
		 recordClass: (of_dns_resource_record_class_t)recordClass
		  recordType: (of_dns_resource_record_type_t)recordType
			 TTL: (uint32_t)TTL
{
	OF_INVALID_INIT_METHOD
}

- (instancetype)initWithName: (OFString *)name
		 recordClass: (of_dns_resource_record_class_t)recordClass
		    textData: (OFData *)textData
			 TTL: (uint32_t)TTL
{
	self = [super initWithName: name
		       recordClass: recordClass
			recordType: OF_DNS_RESOURCE_RECORD_TYPE_TXT
			       TTL: TTL];

	@try {
		_textData = [textData copy];
	} @catch (id e) {
		[self release];
		@throw e;
	}

	return self;
}

- (void)dealloc
{
	[_textData release];

	[super dealloc];
}

- (bool)isEqual: (id)otherObject
{
	OFTXTDNSResourceRecord *otherRecord;

	if (![otherObject isKindOfClass: [OFTXTDNSResourceRecord class]])
		return false;

	otherRecord = otherObject;

	if (otherRecord->_name != _name && ![otherRecord->_name isEqual: _name])
		return false;

	if (otherRecord->_recordClass != _recordClass)
		return false;

	if (otherRecord->_recordType != _recordType)
		return false;

	if (otherRecord->_textData != _textData &&
	    ![otherRecord->_textData isEqual: _textData])
		return false;

	return true;
}

- (uint32_t)hash
{
	uint32_t hash;

	OF_HASH_INIT(hash);

	OF_HASH_ADD_HASH(hash, [_name hash]);
	OF_HASH_ADD(hash, _recordClass >> 8);
	OF_HASH_ADD(hash, _recordClass);
	OF_HASH_ADD(hash, _recordType >> 8);
	OF_HASH_ADD(hash, _recordType);
	OF_HASH_ADD_HASH(hash, [_textData hash]);

	OF_HASH_FINALIZE(hash);

	return hash;
}

- (OFString *)description
{
	return [OFString stringWithFormat:
	    @"<%@:\n"
	    @"\tName = %@\n"
	    @"\tClass = %@\n"
	    @"\tText Data = %@\n"
	    @"\tTTL = %" PRIu32 "\n"
	    @">",
	    [self className], _name,
	    of_dns_resource_record_class_to_string(_recordClass), _textData,
	    _TTL];
}
@end