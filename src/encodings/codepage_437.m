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

#import "OFString.h"

#import "common.h"

const of_char16_t of_codepage_437_table[] = {
	0x00C7, 0x00FC, 0x00E9, 0x00E2, 0x00E4, 0x00E0, 0x00E5, 0x00E7,
	0x00EA, 0x00EB, 0x00E8, 0x00EF, 0x00EE, 0x00EC, 0x00C4, 0x00C5,
	0x00C9, 0x00E6, 0x00C6, 0x00F4, 0x00F6, 0x00F2, 0x00FB, 0x00F9,
	0x00FF, 0x00D6, 0x00DC, 0x00A2, 0x00A3, 0x00A5, 0x20A7, 0x0192,
	0x00E1, 0x00ED, 0x00F3, 0x00FA, 0x00F1, 0x00D1, 0x00AA, 0x00BA,
	0x00BF, 0x2310, 0x00AC, 0x00BD, 0x00BC, 0x00A1, 0x00AB, 0x00BB,
	0x2591, 0x2592, 0x2593, 0x2502, 0x2524, 0x2561, 0x2562, 0x2556,
	0x2555, 0x2563, 0x2551, 0x2557, 0x255D, 0x255C, 0x255B, 0x2510,
	0x2514, 0x2534, 0x252C, 0x251C, 0x2500, 0x253C, 0x255E, 0x255F,
	0x255A, 0x2554, 0x2569, 0x2566, 0x2560, 0x2550, 0x256C, 0x2567,
	0x2568, 0x2564, 0x2565, 0x2559, 0x2558, 0x2552, 0x2553, 0x256B,
	0x256A, 0x2518, 0x250C, 0x2588, 0x2584, 0x258C, 0x2590, 0x2580,
	0x03B1, 0x00DF, 0x0393, 0x03C0, 0x03A3, 0x03C3, 0x00B5, 0x03C4,
	0x03A6, 0x0398, 0x03A9, 0x03B4, 0x221E, 0x03C6, 0x03B5, 0x2229,
	0x2261, 0x00B1, 0x2265, 0x2264, 0x2320, 0x2321, 0x00F7, 0x2248,
	0x00B0, 0x2219, 0x00B7, 0x221A, 0x207F, 0x00B2, 0x25A0, 0x00A0
};
const size_t of_codepage_437_table_offset =
    256 - (sizeof(of_codepage_437_table) / sizeof(*of_codepage_437_table));

static const unsigned char page0[] = {
	0xFF, 0xAD, 0x9B, 0x9C, 0x00, 0x9D, 0x00, 0x00,
	0x00, 0x00, 0xA6, 0xAE, 0xAA, 0x00, 0x00, 0x00,
	0xF8, 0xF1, 0xFD, 0x00, 0x00, 0xE6, 0x00, 0xFA,
	0x00, 0x00, 0xA7, 0xAF, 0xAC, 0xAB, 0x00, 0xA8,
	0x00, 0x00, 0x00, 0x00, 0x8E, 0x8F, 0x92, 0x80,
	0x00, 0x90, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0xA5, 0x00, 0x00, 0x00, 0x00, 0x99, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x9A, 0x00, 0x00, 0xE1,
	0x85, 0xA0, 0x83, 0x00, 0x84, 0x86, 0x91, 0x87,
	0x8A, 0x82, 0x88, 0x89, 0x8D, 0xA1, 0x8C, 0x8B,
	0x00, 0xA4, 0x95, 0xA2, 0x93, 0x00, 0x94, 0xF6,
	0x00, 0x97, 0xA3, 0x96, 0x81, 0x00, 0x00, 0x98
};
static const uint8_t page0Start = 0xA0;

static const unsigned char page1[] = {
	0x9F
};
static const uint8_t page1Start = 0x92;

static const unsigned char page3[] = {
	0xE2, 0x00, 0x00, 0x00, 0x00, 0xE9, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0xE4, 0x00, 0x00, 0xE8, 0x00, 0x00, 0xEA, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xE0, 0x00,
	0x00, 0xEB, 0xEE, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0xE3, 0x00, 0x00,
	0xE5, 0xE7, 0x00, 0xED
};
static const uint8_t page3Start = 0x93;

static const unsigned char page20[] = {
	0xFC, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x9E
};
static const uint8_t page20Start = 0x7F;

static const unsigned char page22[] = {
	0xF9, 0xFB, 0x00, 0x00, 0x00, 0xEC, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0xEF, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF7,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0xF0, 0x00, 0x00, 0xF3, 0xF2
};
static const uint8_t page22Start = 0x19;

static const unsigned char page23[] = {
	0xA9, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0xF4, 0xF5
};
static const uint8_t page23Start = 0x10;

static const unsigned char page25[] = {
	0xC4, 0x00, 0xB3, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0xDA, 0x00, 0x00, 0x00,
	0xBF, 0x00, 0x00, 0x00, 0xC0, 0x00, 0x00, 0x00,
	0xD9, 0x00, 0x00, 0x00, 0xC3, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0xB4, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0xC2, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0xC1, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0xC5, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0xCD, 0xBA, 0xD5, 0xD6, 0xC9, 0xB8, 0xB7, 0xBB,
	0xD4, 0xD3, 0xC8, 0xBE, 0xBD, 0xBC, 0xC6, 0xC7,
	0xCC, 0xB5, 0xB6, 0xB9, 0xD1, 0xD2, 0xCB, 0xCF,
	0xD0, 0xCA, 0xD8, 0xD7, 0xCE, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0xDF, 0x00, 0x00, 0x00, 0xDC, 0x00, 0x00, 0x00,
	0xDB, 0x00, 0x00, 0x00, 0xDD, 0x00, 0x00, 0x00,
	0xDE, 0xB0, 0xB1, 0xB2, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
	0xFE
};
static const uint8_t page25Start = 0x00;

bool
of_unicode_to_codepage_437(const of_unichar_t *input, unsigned char *output,
    size_t length, bool lossy)
{
	for (size_t i = 0; i < length; i++) {
		of_unichar_t c = input[i];

		if OF_UNLIKELY (c > 0x7F) {
			uint8_t index;

			if OF_UNLIKELY (c > 0xFFFF) {
				if (lossy) {
					output[i] = '?';
					continue;
				} else
					return false;
			}

			switch (c >> 8) {
			CASE_MISSING_IS_ERROR(0)
			CASE_MISSING_IS_ERROR(1)
			CASE_MISSING_IS_ERROR(3)
			CASE_MISSING_IS_ERROR(20)
			CASE_MISSING_IS_ERROR(22)
			CASE_MISSING_IS_ERROR(23)
			CASE_MISSING_IS_ERROR(25)
			default:
				if (lossy) {
					output[i] = '?';
					continue;
				} else
					return false;
			}
		} else
			output[i] = (unsigned char)c;
	}

	return true;
}