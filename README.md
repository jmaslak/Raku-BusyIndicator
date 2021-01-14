NAME
====

busy-indicator.raku - Luxafor Indicators based on Google Calendar and Webcam Status

SYNOPSIS
========

    # busy-indicator.rakuo --calendar=you@example.com

DESCRIPTION
===========

This controls Luxafor flag indicators based on a combination of Google Calendar meetings (when in a meeting, the flag is on, as well as two minutes before and after the meeting) and webcam usage (when the webcam is in use, it turns the Luxafor flag on). It also provides for manual control of the Luxafor flag.

This allows people to know if I'm "busy" or not without disturbing me or a conference call I might be on.

OPTIONAL PARAMETERS
===================

--calendar=<calendar>
---------------------

This is a comma-seperated list of Google calendars your Google account has access to examine and which you want to use to control the Luxafor flag.

To access these calendars, this program uses the `gcalcli` program. Thus, you need to install `gcalcli` before using this option. You also need to execute gcalcli once from the command line (which will open a browser for you to authenticate to Google) to have `gcalcli` cache a Google access token.

If you don't want to use Google calendar integration, simply don't provide this option.

--interval=<seconds>
--------------------

This determines how often the script fetches Google calendar entries and writes a status line to the screen. The default is `60` seconds.

--port=<udp port>
-----------------

This determines what control port is used for this script. By default, it is 0 (disabled). If you use a control port (this is an advanced usage), you must specify a port number. Note that no authentication is used for this port, so it must not be firewalled or otherwise protected from outside access.

USER INTERFACE
==============

Once you run the program, every minute (or whatever you specified for the `--interval` option) it will update the screen with a status. This status will indicate if you are currently in a meeting or, otherwise, the next meeting that is scheduled for today.

There are some keyboard commands that can be used to override the automatic busy indications:

The "b" command will turn the light(s) on (with a red light).

The "o" command will turn the light(s) off until the next meeting.

The "g" command will turn the light on, but as a green light.

The "n" displays the next meeting on your calendar.

The "a" shows you an "agenda" view of your upcoming meetings.

INSTALLATION PREREQUISITES
==========================

You must have a Luxafor flag to use this program.

You must install `LibUSB` development libraries. On Ubuntu, this is done with:

    sudo apt-get install libusb-1.0-0-dev

You must also install `gcalcli` if using the Google Calendar integration. To do that on Ubuntu:

    sudo apt-get install gcalcli

You must ensure that the Luxafor Flag is not bound to the `usbhid` module. To do that on Ubuntu, create a file `/etc/modprobe.d/luxafor.conf` that contains:

    options usbhid quirks=0x04d8:0xf372:0x0004

You will need to reboot after making this change for it to take effect.

If you wish to run this program as a standard user (highly recommended), you also need to create a file named `/etc/udev/rules.d/luxafor.rules` with the following content:

    SUBSYTEM=="usb", ATTR{idVendor}="04d8", ATTR{idProduct}=="f372" MODE="0664" OWNER="jmaslak"

Replace `jmaslak` in the above file with your username. Then you will need to reboot for this change to take effect.

COPYRIGHT
=========

Copyright © 2019-2021 Joelle Maslak This application is free software; you can distribute it and/or modify it under the Artistic License 2.0

Also included is a modified version of Travis Gibson's `LibUSB` which has a copyright: Copyright © 2020 Travis Gibson It is also licensed under the Artistic License 2.0.

