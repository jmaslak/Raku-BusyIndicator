#!/usr/bin/env perl6
use v6;

#
# Copyright © 2019-2021 Joelle Maslak
# All Rights Reserved - See License
#

use BusyIndicator::Luxafor;
use Term::ReadKey;
use Term::termios;
use Terminal::ANSIColor;

my @GCAL-CMD = <gcalcli --nocolor --calendar _CALENDAR_ agenda --military --tsv --nodeclined>;
my $MODULES-FILE = "/proc/modules";
my $CAMERA-MOD   = "uvcvideo";

class Appointment {
    has DateTime:D $.start       is required;
    has DateTime:D $.end         is required;
    has Str:D      $.description is required;

    method in-meeting(UInt:D :$fuzz = 120 -->Bool) {
        my $fz = Duration.new($fuzz);
        if ($.start - $fz) ≤ DateTime.now ≤ ($.end + $fz) {
            return True;
        } else {
            return False;
        }
    }

    method future-meeting(UInt:D :$fuzz = 0 -->Bool) {
        my $fz = Duration.new($fuzz);
        if ($.start - $fz) ≥ DateTime.now {
            return True;
        } else {
            return False;
        }
    }

    method is-long-meeting(UInt:D :$long = 3600*4 -->Bool) {

        # We don't want to show the LED for the fake meeting used by the
        # pseudo-appointment the camera app adds.
        my $fake-long-meeting = 3600*24*365*1000; # 1000 years

        my $duration = $.end - $.start;
        return $long < $duration < $fake-long-meeting;
    }

    method Str(-->Str) { return "$.start $.end $.description" }

    method human-printable(-->Str) {
        return "%02d:%02d %s".sprintf($.start.hour, $.start.minute, $.description);
    }
}

sub MAIN(Str :$calendar, UInt:D :$interval = 60, UInt:D :$port = 0) {
    my Channel:D $channel = Channel.new;
    my Str:D @calendar;

    @calendar = $calendar.split(",") if $calendar.defined;

    start-background(@calendar, $channel, $interval, $port);

    time-note "Fetching meetings from Google" if @calendar.elems;

    my $luxafor = BusyIndicator::Luxafor.new;

    # Main loop
    react {
        my @appointments;
        my Bool:D $camera = False;
        my Bool:D $remote-camera = False;
        my Bool:D $google-success = False;
        whenever $channel -> $key {
            if $key ~~ List {
                @appointments = $key<>;
                if ! $google-success {
                    $google-success = True;
                    display-future-meetings(@appointments);
                    display($luxafor, @appointments, $camera, $remote-camera);
                }
            } elsif $key eq 'tick' {
                display($luxafor, @appointments, $camera, $remote-camera) if $google-success;
            } elsif $key eq 'camera on' {
                $camera = True;
                display($luxafor, @appointments, $camera, $remote-camera);
            } elsif $key eq 'camera off' {
                $camera = False;
                display($luxafor, @appointments, $camera, $remote-camera);
            } elsif $key eq 'remote-camera on' {
                $remote-camera = True;
                display($luxafor, @appointments, $camera, $remote-camera);
            } elsif $key eq 'remote-camera off' {
                $remote-camera = False;
                display($luxafor, @appointments, $camera, $remote-camera);
            } elsif $key eq 'h'|'?' {
                display-help;
            } elsif $key eq 'b' {
                # Turn light on for (B)usy
                time-say 'red', "Setting indicator to BUSY";
                display($luxafor, :red, @appointments, $camera, $remote-camera);
            } elsif $key eq 'o' {
                # Turn light (O)ff for this meeting
                time-note "Turning indicator to OFF until next meeting";
                display($luxafor, :off, @appointments, $camera, $remote-camera);
            } elsif $key eq 'g' {
                # Turn light to (G)reen
                time-say 'green', "Turning indicator to GREEN";
                display($luxafor, :green, @appointments, $camera, $remote-camera);
            } elsif $key eq 'q' {
                time-note "Quitting";
                my $flags := Term::termios.new(:fd($*IN.native-descriptor)).getattr;
                $flags.set_lflags('ECHO');
                $flags.setattr(:NOW);
                exit;
            } elsif $key eq 'n' {
                display-next-meeting(@appointments);
            } elsif $key eq 'a' {
                display-future-meetings(@appointments);
            } elsif $key eq '.' {
                display($luxafor, @appointments, $camera, $remote-camera);
            } else {
                time-note "Unknown key press";
                display($luxafor, @appointments, $camera, $remote-camera);
            }
        }
    }
}

sub start-background(Str:D @calendar, Channel:D $channel, UInt:D $interval, UInt:D $port --> Nil) {
    # Start ticks
    start {
        my $now = DateTime.now;
        if $now.second {
            # Start at 00:00
            sleep 60 - $now.second if $now.second; # Start at 00:00
        }

        react {
            whenever Supply.interval($interval) { $channel.send('tick') }
        }
    }

    # Google Monitor
    start {
        my @appointments = get-appointments-from-google(@calendar)<>;
        $channel.send(@appointments);

        react {
            whenever Supply.interval($interval) {
                @appointments = get-appointments-from-google(@calendar)<>;
                $channel.send(@appointments);
            }
        }
    }

    # Remote Network monitor
    if $port ≠ 0 {
        start-network-background($channel, $port)
    }

    # Camera monitor
    start {
        my $camera = False;
        react {
            whenever Supply.interval(1) {
                my $new-camera = get-camera();
                if $new-camera ≠ $camera {
                    $camera = $new-camera;
                    $channel.send: 'camera ' ~ ( $camera ?? "on" !! "off" );
                }
            }
        }
    }

    # Key presses
    start {
        react {
            whenever key-pressed(:!echo) {
                $channel.send(.fc);
            }
        }
    }
}

sub start-network-background(Channel:D $channel, UInt:D $port --> Nil) {
    start start-network-server($channel, $port);
}

sub start-network-server(Channel:D $channel, UInt:D $port --> Nil) {
    my $camera = False;
    my $socket = IO::Socket::Async.bind-udp('::', $port);

    react {
        whenever $socket.Supply -> $v {
            if $v ~~ m/ ^ "CAMERA " [ON || OFF] $/ {
                my $new-camera = False;
                if $v eq "CAMERA ON" {
                    $new-camera = True;
                }
                if $new-camera ≠ $camera {
                    $camera = $new-camera;
                    $channel.send: 'remote-camera ' ~ ( $camera ?? "on" !! "off" );
                }
            } elsif $v ~~ m/ ^ "KEY " (.) $/ {
                $channel.send($0.Str.fc);
            }
        }
    }
}


sub display(
    BusyIndicator::Luxafor $luxafor,
    @appointments is copy,
    Bool $camera,
    Bool $remote-camera,
    :$off,
    :$red,
    :$green
    --> Nil
) {
    state @ignores;
    state $manual;
    state $last-green;

    my $next = @appointments.grep(*.future-meeting).first;

    # Add fake appointment if we're in a call.
    if $camera or $remote-camera {
        my $start = DateTime.new("1900-01-01T00:00:00Z");
        my $end   = DateTime.new("9999-01-01T00:00:00Z");
        @appointments.push: Appointment.new( :$start, :$end, :description("In video call") );
    }

    my @current = @appointments.grep(*.in-meeting).grep(! *.is-long-meeting);

    if $off {
        @ignores    = @current;
        $manual     = False;
        $last-green = False;
    }

    if @current.elems == 0 and @ignores.elems {
        @ignores = ();
    }

    @current = @current.grep(*.Str ∉  @ignores».Str);

    if $red {
        $manual     = True;
        $last-green = False;
    } elsif $green {
        $manual     = False;
        $last-green = True;
    }

    if $manual {
        time-say 'red', "Busy indicator turned on manually";
        light-red($luxafor);
    } elsif $last-green {
        time-say 'green', "Indicator turned green manually";
        light-green($luxafor);
    } elsif @current.elems {
        my @active      = @current.grep(*.in-meeting(:fuzz(0)));
        my $now-meeting = @active.elems ?? @active[0] !! @current[0];

        time-say 'red', "In meeting: {$now-meeting.description}";
        light-red($luxafor);
    } else {
        if @ignores.elems {
            time-note "Not in a meeting (manual override)";
        } else {
            if $next.defined {
                time-note "Not in a meeting (next: {$next.human-printable})";
            } else {
                time-note "Not in a meeting";
            }
        }
        light-off($luxafor);
    }

    CATCH: {
        return; # Just vaccum up the errors
    }
}

sub display-future-meetings(@appointments is copy --> Nil) {
    my @future = @appointments.grep(*.future-meeting)<>;
    if @future.elems > 0 {
        time-note "Today's meetings:";
        for @future -> $meeting {
            time-note "    " ~ $meeting.human-printable;
        }
    } else {
        time-note "Today's meetings: no meetings today";
    }
}

sub display-next-meeting(@appointments is copy --> Nil) {
    my $next = @appointments.grep(*.future-meeting).first;
    if $next.defined {
        time-note "Next meeting: " ~ $next.human-printable;
    } else {
        time-note "Next meeting: No more meetings today";
    }
}

sub display-help(--> Nil) {
    time-note "HELP:";
    time-note "  a = display all future meetings";
    time-note "  b = set light to busy (red)";
    time-note "  g = set light to green";
    time-note "  o = turn light to off (until next meeting)";
    time-note "  n = display next meeting";
    time-note "  q = quit";
    time-note "  . = refresh";
}

sub get-camera(-->Bool:D) {
    my @modules = $MODULES-FILE.IO.lines».split(" ");
    for @modules -> $module {
        if $module[0] eq $CAMERA-MOD {
            return $module[2] ≠ 0;
        }
    }
    return False;
}

sub get-appointments-from-google(Str:D @calendar) {
    my $now      = DateTime.now;
    my $offset   = S/^.* <?before <[ + \- ]> >// with ~$now;
    my $tomorrow = $now.later(:1day);

    my @output = gather {
        for @calendar -> $calendar {
            my @gcal = @GCAL-CMD.map: { $^a eq '_CALENDAR_' ?? $calendar !! $^a };

            my $proc = run @gcal, $now.yyyy-mm-dd, $tomorrow.yyyy-mm-dd, :out;
            my @appts = $proc.out.slurp(:close).lines;
            for @appts -> $appt-line {
                my ($startdt, $starttm, $enddt, $endtm, $desc) = $appt-line.split("\t");
                my $start = DateTime.new("{$startdt}T{$starttm}:00{$offset}");
                my $end   = DateTime.new("{$enddt}T{$endtm}:00{$offset}");

                take Appointment.new( :$start, :$end, :description($desc) );
            }
        }
    }

    return @output.sort.unique;
}

sub light-red($luxafor)   { light-command($luxafor, 20,  0, 0) }
sub light-green($luxafor) { light-command($luxafor, 0, 20, 0) }
sub light-off($luxafor)   { light-command($luxafor, 0,  0, 0) }

sub light-command($luxafor, $r, $g, $b) {
    state $last = '';
    state $sent-times = 0;

    if "$r $g $b" eq $last {
        $sent-times++;
        return if $sent-times > 2;
    } else {
        $sent-times = 1;
    }

    try {
        CATCH {
            default {
                time-say 'red', "ERROR: LED not properly responding";
            }
        }
        $luxafor.indicate($r, $g, $b);
    }

    return;
}

sub time-say(Str:D $color is copy, +@args --> Nil) {
    if $color eq 'red' {
        $color = 'inverse red';
    }
    my $now = DateTime.now;
    print color($color);
    say "{$now.yyyy-mm-dd} {$now.hh-mm-ss} ", |@args;
    print color($color);
    print INVERSE_OFF();
}

sub time-note(+@args --> Nil) { time-say "white", |@args }

