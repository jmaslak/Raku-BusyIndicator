#!/usr/bin/env perl6
use v6;

#
# Copyright © 2019-2021 Joelle Maslak
# All Rights Reserved - See License
#

my $MODULES-FILE = "/proc/modules";
my $CAMERA-MOD   = "uvcvideo";

sub MAIN(Str:D $udp-host, Int:D $udp-port = 3333) {
    # Camera monitor
    my $camera = False;
    react {
        whenever Supply.interval(1) {
            my $socket = IO::Socket::Async.udp();
            await $socket.print-to($udp-host, $udp-port, "CAMERA " ~ get-camera);
        }
    }
}

sub get-camera(-->Str:D) {
    my @modules = $MODULES-FILE.IO.lines».split(" ");
    for @modules -> $module {
        if $module[0] eq $CAMERA-MOD {
            if $module[2] ≠ 0 {
                return "ON";
            } else {
                return "OFF";
            }
        }
    }
    return "OFF";
}

