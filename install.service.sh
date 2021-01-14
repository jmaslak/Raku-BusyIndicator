#!/bin/bash

#
# Copyright (C) 2020-2021 Joelle Maslak
# All Rights Reserved - See License
#

doit() {
    cp camera-monitor.service /etc/systemd/system/.
    systemctl enable camera-monitor
    systemctl start camera-monitor
}

doit "$@"


