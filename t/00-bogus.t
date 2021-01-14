use v6.c;
use Test;

#
# Copyright © 2018-2019 Joelle Maslak
# All Rights Reserved - See License
#

use Net::BGP::Conversions;

my byte $b0 = 0;
my byte $b1 = 1;

subtest 'nuint16' => {

    is nuint16(           $b0, $b0 ), 0;
    is nuint16( ($b0,$b0)          ), 0;
    is nuint16( buf8.new(0,0)      ), 0;

    is nuint16(           $b0, $b1 ), 1;
    is nuint16( ($b0,$b1)          ), 1;
    is nuint16( buf8.new(0,1)      ), 1;

    is nuint16(           $b1, $b0 ), 256;
    is nuint16( ($b1,$b0)          ), 256;
    is nuint16( buf8.new(1,0)      ), 256;

    is nuint16(           $b1, $b1 ), 257;
    is nuint16( ($b1,$b1)          ), 257;
    is nuint16( buf8.new(1,1)      ), 257;

    is nuint16(nuint16-buf8(0)),     0;
    is nuint16(nuint16-buf8(1)),     1;
    is nuint16(nuint16-buf8(256)), 256;
    is nuint16(nuint16-buf8(257)), 257;

    is nuint16-buf8(258).list.join("."), '1.2', "258 is encoded properly";

    done-testing;
}

subtest 'nunit32' => {
    is nuint32(               $b0, $b0, $b0, $b0 ), 0;
    is nuint32( ($b0,$b0,$b0,$b0)                ), 0;
    is nuint32( buf8.new(0,0,0,0)                ), 0;

    is nuint32(               $b0, $b0, $b0, $b1 ), 1;
    is nuint32( ($b0,$b0,$b0,$b1)                ), 1;
    is nuint32( buf8.new(0,0,0,1)                ), 1;

    is nuint32(               $b0, $b0, $b1, $b0 ), 256;
    is nuint32( ($b0,$b0,$b1,$b0)                ), 256;
    is nuint32( buf8.new(0,0,1,0)                ), 256;

    is nuint32(               $b0, $b1, $b0, $b0 ), 65536;
    is nuint32( ($b0,$b1,$b0,$b0)                ), 65536;
    is nuint32( buf8.new(0,1,0,0)                ), 65536;

    is nuint32(               $b1, $b1, $b1, $b1 ), 16843009;
    is nuint32( ($b1,$b1,$b1,$b1)                ), 16843009;
    is nuint32( buf8.new(1,1,1,1)                ), 16843009;

    is nuint32(nuint32-buf8(0)),               0;
    is nuint32(nuint32-buf8(1)),               1;
    is nuint32(nuint32-buf8(256)),           256;
    is nuint32(nuint32-buf8(257)),           257;
    is nuint32(nuint32-buf8(65536)),       65536;
    is nuint32(nuint32-buf8(16843009)), 16843009;

    done-testing;
}

subtest 'nunit128' => {
    is nuint128(1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16),
        1339673755198158349044581307228491536;
    is nuint128( (1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16) ),
        1339673755198158349044581307228491536;
    is nuint128( buf8.new(1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16) ),
        1339673755198158349044581307228491536;

    is nuint128(nuint128-buf8(0)),               0;
    is nuint128(nuint128-buf8(1)),               1;
    is nuint128(nuint128-buf8(256)),           256;
    is nuint128(nuint128-buf8(257)),           257;
    is nuint128(nuint128-buf8(65536)),       65536;
    is nuint128(nuint128-buf8(16843009)), 16843009;
    is nuint128(nuint128-buf8(2¹²⁷)),         2¹²⁷;
    is nuint128(nuint128-buf8((2¹²⁸)-1)), (2¹²⁸)-1;
}

done-testing;

