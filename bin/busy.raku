#!/usr/bin/env raku
use v6;

#
# Copyright © 2019-2021 Joelle Maslak
# All Rights Reserved - See License
#

sub MAIN(Str:D $char, Str :$udp-host is copy, Int :$udp-port is copy) {
    my $config = read_config();
    $udp-host //= $config<udp-host>;
    $udp-port //= $config<udp-port>.Int;

    die("Must provide a single character") unless $char.chars == 1;
    die("Must provide a UDP host to connect to") unless $config<udp-host>.defined;

    my $socket = IO::Socket::Async.udp();
    await $socket.print-to($udp-host, $udp-port, "KEY {$char}");
}

sub read_config(-->Hash:D) {
    my $config = {};

    # Defaults
    $config<udp-port> = 3333;

    my $fn = $*HOME.add(".busy-indicator");

    if $fn.IO ~~ :r {
        for $fn.IO.lines -> $line is copy {
            $line = $line.trim();
            my @parts = $line.split("|");
            if @parts.elems == 2 {
                $config{@parts[0].fc} = @parts[1];
            }
        }
    }
    return $config;
}
