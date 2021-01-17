use LibUSB::Raw;
use X::LibUSB;

use NativeCall;

constant MAX-BUFFER-SIZE = 256;

unit class BusyIndicator::LibUSB:ver<0.0.5>:auth<cpan:JMASLAK>;

has libusb_context $!ctx .= new;
has libusb_device_handle $!handle;
has libusb_device $!dev;

method init() {
  libusb_init($!ctx);
}

method exit {
  libusb_exit($!ctx);
}

method close {
  libusb_close($!handle);
  $!dev = Nil;
}

multi submethod BUILD() {}

multi submethod BUILD(:$!dev!) {}

method !get-error(Int $err --> Exception) {
  given libusb_error($err) {
    when LIBUSB_ERROR_IO { X::LibUSB::IO.new }
    when LIBUSB_ERROR_INVALID_PARAM { X::LibUSB::Invalid-Param.new }
    when LIBUSB_ERROR_ACCESS { X::LibUSB::Access.new }
    when LIBUSB_ERROR_NO_DEVICE { X::LibUSB::No-Device.new }
    when LIBUSB_ERROR_NOT_FOUND { X::LibUSB::Not-Found.new }
    when LIBUSB_ERROR_BUSY { X::LibUSB::Busy.new }
    when LIBUSB_ERROR_TIMEOUT { X::LibUSB::Timeout.new }
    when LIBUSB_ERROR_OVERFLOW { X::LibUSB::Overflow.new }
    when LIBUSB_ERROR_PIPE { X::LibUSB::Pipe.new }
    when LIBUSB_ERROR_INTERRUPTED { X::LibUSB::Interrupted.new }
    when LIBUSB_ERROR_NO_MEM { X::LibUSB::No-Memory.new }
    when LIBUSB_ERROR_NOT_SUPPORTED { X::LibUSB::Not-Supported.new }
    when LIBUSB_ERROR_OTHER { X::LibUSB::Other.new }
    default { X::AdHoc.new("Unknown error") }
  }
}

multi method get-device(Int $target-vid, Int $target-pid) {
  self.get-device(-> $desc { $desc.idVendor == $target-vid && $desc.idProduct == $target-pid});
}

multi method get-device(&check:($desc)) {
  my int64 $listptr .= new;
  my $size = libusb_get_device_list($!ctx, $listptr);
  my $array = nativecast(CArray[libusb_device], Pointer[libusb_device].new($listptr));

  my $i = 0;
  repeat {
    my libusb_device $dev = $array[$i];
    my libusb_device_descriptor $desc .= new;
    my $err = libusb_get_device_descriptor($dev, $desc);
    return self!get-error($err) if $err;
    if &check($desc) {
      $!dev = $dev;
      return;
    }
    $i++;
  } while $i < $size;
  LEAVE {
    libusb_free_device_list(nativecast(Pointer[libusb_device], $array), 1) if $size;
  }
}

method get-parent(--> LibUSB) {
  return self.new(:dev(libusb_get_parent($!dev)))
}

method set-configuration(int32 $config -->int32) {
  fail X::LibUSB::No-Device-Selected unless $!dev;
  return libusb_set_configuration($!handle, $config);
}

method vid() {
  fail X::LibUSB::No-Device-Selected unless $!dev;
  my libusb_device_descriptor $desc .= new;
  my $err = libusb_get_device_descriptor($!dev, $desc);
  return self!get-error($err) if $err;
  return $desc.idVendor;
}

method pid() {
  fail X::LibUSB::No-Device-Selected unless $!dev;
  my libusb_device_descriptor $desc .= new;
  my $err = libusb_get_device_descriptor($!dev, $desc);
  return self!get-error($err) if $err;
  return $desc.idProduct;
}

method open(--> Nil) {
  fail X::LibUSB::No-Device-Selected unless $!dev;
  $!handle .= new;
  my $err = libusb_open($!dev, $!handle);
  die self!get-error($err) if $err;
}

method bus-number(--> Int) {
  return libusb_get_bus_number($!dev);
}

method address(--> Int) {
  return libusb_get_device_address($!dev);
}

method speed(--> libusb_speed) {
  return libusb_speed(libusb_get_device_speed($!dev));
}

multi method control-transfer(
                        uint8 $request-type,
                        uint8 $request,
                        uint16 $value,
                        uint16 $index,
                        buf8 $data,
                        uint16 $elems,
                        uint32 $timeout = 0
                        ) {
  self.control-transfer(:$request-type, :$request, :$value, :$index, :$data, :$elems, :$timeout);
}

multi method control-transfer(
                        uint8 :$request-type!,
                        uint8 :$request!,
                        uint16 :$value!,
                        uint16 :$index!,
                        buf8 :$data!,
                        uint16 :$elems!,
                        uint32 :$timeout = 0
                        ) {
  fail X::LibUSB::No-Device-Selected unless $!dev;
  fail "Device not open" unless $!handle;
  my $err = libusb_control_transfer($!handle, $request-type, $request, $value, $index, nativecast(Pointer[uint8], $data), $elems, $timeout);
  die self!get-error($err) if $err < 0;
  return $err;
}

multi method interrupt-transfer(
                        uint8 $endpoint,
                        buf8 $data,
                        int32 $length,
                        int32 $transferred is rw,
                        uint32 $timeout
                        ) {
  self.interrupt-transfer(:$endpoint, :$data, :$length, :$transferred, :$timeout);
}

multi method interrupt-transfer(
                        :$endpoint!,
                        buf8 :$data!,
                        :$length!,
                        int32 :$transferred! is rw,
                        :$timeout!
                        ) {
  fail X::LibUSB::No-Device-Selected unless $!dev;
  fail "Device not open" unless $!handle;
  my $err = libusb_interrupt_transfer($!handle, $endpoint, nativecast(Pointer[uint8], $data), $length, $transferred, $timeout);
  die self!get-error($err) if $err < 0;
  return $err;
}

=begin pod

=head1 NAME

LibUSB - OO binding to libusb

=head1 SYNOPSIS

=begin code :lang<raku>

constant VID = <vid>
constant PID = <pid>

use LibUSB;
my LibUSB $dev .= new;
$dev.init;
$dev.get-device(VID, PID);
$dev.open()  # Will require elevated privileges

# Do things with the device

$dev.close();
$dev.exit()

=end code

=head1 DESCRIPTION

LibUSB is an OO Raku binding to the libusb library, allowing for access to 
USB devices from Raku.

This interface is experimental and incomplete.

=head2 Methods

=head3 init
  
Initialize the libusb library for this device object.

=head3 get-device (multi)

Find the first device that matches the parameters and select it.

=head4 Params

=head5 Int $vid

The VID of the device.

=head5 Int $pid

The PID of the device.

=head3 get-device (multi)

Find the first device with a user-defined check.

=head4 Params

=head5 &check($desc)

Find the first device for which &check returns true. $desc is a 
libusb_device_descriptor as found in the libusb documentation.

=head3 open()

Open the selected device.

=head3 close()

Close the device.

=head3 exit()

Close down the libusb library for this device object.

=head3 vid()

Returns the VID of the device.

=head3 pid()

Returns the PID of the device.

=head3 bus-number()

Returns the bus number of the device.

=head3 address()

Returns the address of the device.

=head3 speed()

Returns the speed of the device.

=head3 control-transfer

Perform a control transfer to the device. It supports named parameters in any
order, or positional parameters in the order below.

=head4 Params

=head5 uint8 $request-type

The USB control transfer request type.

=head5 uint8 $request

The USB control transfer request.

=head5 uint16 $value

The USB control transfer value.

=head5 uint16 $index

The USB control transfer index.

=head5 buf8 $data

A buffer containing data to send, or containing space to receive data.

=head5 uint16 $elems

The number of elems in $data.

=head5 uint32 $timeout

How long to wait before timing out. Defaults to 0 (never time out).

=head1 AUTHOR

Travis Gibson <TGib.Travis@protonmail.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2020 Travis Gibson

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod
