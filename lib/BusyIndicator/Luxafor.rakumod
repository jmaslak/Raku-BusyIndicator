use v6.d;

#
# Copyright © 2020-2021 Joelle Maslak
# All Rights Reserved - See License
#

unit class BusyIndicator::Luxafor:ver<0.2.1>:auth<zef:jmaslak>;

use LibUSB;
use LibUSB::Raw;

my Int:D $SETCOLOR = 0x01;

has LibUSB @.device;
has UInt:D $.vid     is default(0x04d8);
has UInt:D $.pid     is default(0xf372);
has UInt:D $.timeout is default(1000) is rw;
has UInt:D $.l       is default(255)  is rw;

submethod BUILD() {
    my $index = 0;

    my LibUSB $dev = self.get-device($index);
    while ($dev.defined) {
        @!device.push: $dev;
        $dev = self.get-device(++$index);
    }
}

submethod DESTROY() {
    for @!device -> $device {
        $device.close;
        $device.exit;
    }
}

method get-device(Int:D $index --> LibUSB) {
    my LibUSB $dev .= new;
    $dev.init;

    my uint16 $vid = $!vid;
    my uint16 $pid = $!pid;

    my $found = False;
    my $match = 0;
    $dev.get-device: -> $d {
        if $d.idVendor == $vid && $d.idProduct == $pid {
            if $match++ == $index {
                $found = True;
                True;
            } else {
                False;
            }
        }
    }

    if $found {
        $dev.open;
        # libusb_set_auto_detach_kernel_driver($dev.handle, 1);
        libusb_set_configuration($dev.handle, 2); # XXX Why "2"?
        return $dev;
    } else {
        $dev.close;
        $dev.exit;
        return LibUSB;
    }
}

method indicate(
    Int:D $r,
    Int:D $g,
    Int:D $b,
) {
    for @!device -> $dev {
        try {
            CATCH {
                default {
                    # Just try again.
                    sleep .25;
                    self.indicate-device($dev, $r, $g, $b);
                }
            }
            self.indicate-device($dev, $r, $g, $b);
        }
    }
}

method indicate-device(
    $device,
    Int:D    $r,
    Int:D    $g,
    Int:D    $b,
) {
    my $data = buf8.new($SETCOLOR, $!l, $r, $g, $b, 0, 0);
    my int32 $transferred;
    my uint8 $endpoint = 1;
    my int32 $length = $data.bytes;
    my uint32 $to = $!timeout;
    $device.interrupt-transfer($endpoint, $data, $length, $transferred, $to);
}
