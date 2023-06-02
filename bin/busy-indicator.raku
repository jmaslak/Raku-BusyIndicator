#!/usr/bin/env perl6
use v6;

#
# Copyright © 2019-2023 Joelle Maslak
# All Rights Reserved - See License
#

use BusyIndicator::Luxafor;
use Cro::HTTP::Router;
use Cro::HTTP::Router::WebSocket;
use Cro::HTTP::Server;
use Term::ReadKey;
use Term::termios;
use Terminal::ANSIColor;

my @GCAL-CMD = <gcalcli --nocolor --calendar _CALENDAR_ agenda --military --tsv --nodeclined>;
my $MODULES-FILE = "/proc/modules";
my $CAMERA-MOD   = "uvcvideo";

# Do not update the keys in this hash, as this is used across multiple
# threads! Instead, simply replace it with a new hashref.
my $STATUS = { type => "status", status => "off", minutes-to-next => Int }

class Message-Keypress {
    has Str:D $.key is required;
}

class Message-Tick { }

class Message-Camera {
    has Bool:D $.state is required;
}

class Message-Remote {
    has Bool:D $.state is required;
}

class Message-Appointments {
    has @.appointments is required;
}

class Message-Offset {
    has Int:D $.offset is required;
}

class Message-Offset-Error { }


# Appointment Class
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

    method is-ooo(-->Bool) {
        if $.description.fc eq "ooo".fc {
            return True;
        } else {
            return False;
        }
    }
}

class Main-Thread {
    has            @.calendar        is required;
    has Channel:D  $.channel         is required;
    has UInt:D     $.interval        is required;
    has UInt:D     $.port            is required;
    has Bool:D     $.ignore-ooo      is required;
    has Supplier:D $.client-supplier is required;
    has Str        $.externalrgb;

    has            @!appointments;
    has            @!ignores;
    has Bool:D     $!camera         = False;
    has Bool:D     $!remote-camera  = False;
    has Bool:D     $!google-success = False;
    has            $!luxafor        = BusyIndicator::Luxafor.new;
    has Bool:D     $!manual         = False;   # Light is manually on
    has Bool:D     $!last-green     = False;   # Light is manually green


    method start() {
        self.time-note("Fetching meetings from Google") if @!calendar.elems;

        # Main loop
        react {
            whenever $!channel -> $message {
                self.process-message($message);
            }
        }
    }

    method process-message($message) {
        given $message {
            when Message-Tick         { self.display if $!google-success   }
            when Message-Keypress     { self.handle-keypress($message)     }
            when Message-Camera       { self.handle-camera($message)       }
            when Message-Remote       { self.handle-remote($message)       }
            when Message-Appointments { self.handle-appointments($message) }
            when Message-Offset       { self.handle-offset($message)       }
            when Message-Offset-Error { self.handle-offset-error           }
            default                   { die("Unknown command type")        }
        }
    }

    method handle-keypress($message) {
        given $message.key {
            when 'h'|'?' { self.display-help                    }
            when 'b'     { self.keypress-busy                   }
            when 'o'     { self.keypress-off                    }
            when 'g'     { self.keypress-green                  }
            when 'q'     { self.keypress-quit                   }
            when 'n'     { self.display-next-meeting            }
            when 'c'     { self.display-next-or-current-meeting }
            when 'a'     { self.display-future-meetings         }
            when '.'     { self.display                         }
            default      { self.keypress-unknown                }
        }
    }

    method handle-camera($message) {
        $!camera = $message.state;
        self.display;
    }

    method handle-remote($message) {
        # Handle remote camera
        $!remote-camera = $message.state;
        self.display;
    }

    method handle-appointments($message) {
        @!appointments = $message.appointments<>;

        # On first fetch of Google Appointments
        if ! $!google-success {
            $!google-success = True;
            self.display-future-meetings;
            self.display;
        }
    }

    method handle-offset($message) {
        if $*TZ ≠ $message.offset {
            $*TZ = $message.offset;
            self.time-note("UTC offset change detected. New offset: $*TZ");
        }
    }

    method handle-offset-error() {
        self.time-note("Cannot monitor time zone offset changes");
    }

    method keypress-busy() {
        self.time-say('red', "Setting indicator to BUSY");
        self.display(:red);
    }

    method keypress-off() {
        self.time-note("Turning indicator to OFF until next meeting");
        self.display(:off);
    }

    method keypress-green() {
        self.time-say('green', "Turning indicator to GREEN");
        self.display(:green);
    }

    method keypress-quit() {
        self.time-note("Quitting");

        my $flags := Term::termios.new(:fd($*IN.native-descriptor)).getattr;
        $flags.set_lflags('ECHO');
        $flags.setattr(:NOW);

        exit;
    }

    method keypress-unknown() {
        self.time-note("Unknown key press");
        self.display;
    }

    method display(:$off, :$red, :$green --> Nil) {
        # Add fake appointment if we're in a call.
        if $!camera or $!remote-camera {
            my $start = DateTime.new("1900-01-01T00:00:00Z");
            my $end   = DateTime.new("9999-01-01T00:00:00Z");
            @!appointments.push: Appointment.new( :$start, :$end, :description("In video call") );
        }

        my @filtered = @!appointments;
        if $!ignore-ooo {
            @filtered = @filtered.grep(! *.is-ooo)<>;
        }

        my $next = @filtered.grep(*.future-meeting).first;

        my @current = @filtered.grep(*.in-meeting).grep(! *.is-long-meeting);

        if $off {
            @!ignores   = @current;
            $!manual     = False;
            $!last-green = False;
        }

        if @current.elems == 0 and @!ignores.elems { @!ignores = () }

        @current = @current.grep(*.Str ∉  @!ignores».Str);

        if $red {
            $!manual     = True;
            $!last-green = False;
        } elsif $green {
            $!manual     = False;
            $!last-green = True;
        }

        if $!manual {
            self.time-say('red', "Busy indicator turned on manually");
            self.light-red;
        } elsif $!last-green {
            self.time-say('green', "Indicator turned green manually");
            self.light-green;
        } elsif @current.elems {
            my @active      = @current.grep(*.in-meeting(:fuzz(0)));
            my $now-meeting = @active.elems ?? @active[0] !! @current[0];

            self.time-say('red', "In meeting: {$now-meeting.description}");
            self.light-red;
        } else {
            if @!ignores.elems {
                self.time-note("Not in a meeting (manual override)");
            } else {
                if $next.defined {
                    self.time-note("Not in a meeting (next: {$next.human-printable})");
                } else {
                    self.time-note("Not in a meeting");
                }
            }
            self.light-off;
        }

        $STATUS = self.build_status_message;
        $!client-supplier.emit($STATUS);

        CATCH: {
            return; # Just vaccum up the errors
        }
    }

    method display-future-meetings(--> Nil) {
        my @future = @!appointments.grep(*.future-meeting)<>;
        if $!ignore-ooo {
            @future = @future.grep(! *.is-ooo)<>;
        }

        if @future.elems > 0 {
            self.time-note("Today's meetings:");
            for @future -> $meeting {
                self.time-note("    " ~ $meeting.human-printable);
            }
        } else {
            self.time-note("Today's meetings: no meetings today");
        }
    }

    method minutes-to-current-or-next-meeting(--> Int) {
        my @mtgs = @!appointments.grep({ $^a.future-meeting or $^a.in-meeting(:fuzz(0))});
        @mtgs = @mtgs.grep(*.Str ∉  @!ignores».Str);
        my $next = @mtgs.first;

        if $next.defined {
            my $tm = $next.start - DateTime.now;
            return 0 unless $tm > 0;
            return Int($tm ÷ 60);
        } else {
            return Int;
        }
    }

    method display-next-or-current-meeting(--> Nil) {
        my @mtgs = @!appointments.grep({ $^a.future-meeting or $^a.in-meeting(:fuzz(0))});
        @mtgs = @mtgs.grep(*.Str ∉  @!ignores».Str);
        my $next = @mtgs.first;

        if $next.defined {
            self.time-note("Next meeting: " ~ $next.human-printable);
        } else {
            self.time-note("Next meeting: No more meetings today");
        }
    }

    method display-next-meeting(--> Nil) {
        my $next = @!appointments.grep(*.future-meeting).first;
        if $next.defined {
            self.time-note("Next meeting: " ~ $next.human-printable);
        } else {
            self.time-note("Next meeting: No more meetings today");
        }
    }

    method display-help(--> Nil) {
        self.time-note("HELP:");
        self.time-note("  a = display all future meetings");
        self.time-note("  b = set light to busy (red)");
        self.time-note("  g = set light to green");
        self.time-note("  o = turn light to off (until next meeting)");
        self.time-note("  n = display next meeting");
        self.time-note("  q = quit");
        self.time-note("  . = refresh");
    }

    method light-red()   { self.light-command(20,  0, 0, 255, 0, 0) }
    method light-green() { self.light-command( 0, 20, 0, 0, 255, 0) }
    method light-off()   { self.light-command( 0,  0, 0, 50, 0, 50) }

    method light-command($r, $g, $b, $extr, $extg, $extb) {
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
                    self.time-say('red', "ERROR: LED not properly responding");
                }
            }
            $!luxafor.indicate($r, $g, $b);
            run $!externalrgb, $extr, $extg, $extb if $!externalrgb.defined;
        }

        return;
    }

    method time-say(Str:D $color is copy, +@args --> Nil) {
        my $width = self.get-width();

        if $color eq 'red' {
            $color = 'inverse red';
        }
        my $now = DateTime.now;
        print color($color);

        my $out = "{$now.yyyy-mm-dd} {$now.hh-mm-ss} " ~ @args.join("");
        if $width { $out = $out.substr(0, $width) }

        say $out;

        print color($color);
        print INVERSE_OFF();
    }

    method time-note(+@args --> Nil) { self.time-say("white", |@args) }

    method get-width(-->UInt:D) {
        # Returns the screen width (or zero if not able to determine)
        CATCH {
            return 0;
        }

        return self.get-terminal-width;
    }

    method get-terminal-width(--> Int:D) {
        state $width = 0;
        state $tm    = 0;

        my $now = DateTime.now.posix.Int;
        return $width if $now == $tm;  # Use cache

        $tm = $now;

        my $stty = run("stty", "-a", :out, :err);
        my $out = $stty.out.slurp;

        return 0 unless $out.match(/ 'columns ' <( \d+ )> /);
        return $out.match(/ 'columns ' <( \d+ )> /).Int;
    }

    method build_status_message(-->Hash) {
        # Add fake appointment if we're in a call.
        my @filtered = @!appointments;
        if $!ignore-ooo {
            @filtered = @filtered.grep(! *.is-ooo)<>;
        }

        my @current = @filtered.grep(*.in-meeting).grep(! *.is-long-meeting);
        @current = @current.grep(*.Str ∉  @!ignores».Str);

        my $color;
        if $!manual {
            $color = "red";
        } elsif $!last-green {
            $color = "green";
        } elsif @current.elems {
            $color = "red";
        } else {
            $color = "off";
        }

        my $next = self.minutes-to-current-or-next-meeting;

        return {
            type => "status",
            status => $color,
            minutes-to-next => $next,
        }
    }

}

sub MAIN(
    Str :$calendar,
    UInt:D :$interval = 60,
    UInt:D :$port = 0,
    Bool:D :$ignore-ooo = False,
    UInt:D :$ws-port = 0,
    Str :$externalrgb,
) {
    my Channel:D $channel = Channel.new;
    my Supplier:D $client-supplier = Supplier.new;

    my Str:D @calendar;
    @calendar = $calendar.split(",") if $calendar.defined;

    start-background(@calendar, $channel, $interval, $port, $ignore-ooo, $ws-port, $client-supplier);

    my $main-thread = Main-Thread.new( :$channel, :@calendar, :$interval, :$port, :$ignore-ooo, :$client-supplier, :$externalrgb );
    $main-thread.start();
}

sub start-background(
    Str:D @calendar,
    Channel:D $channel,
    UInt:D $interval,
    UInt:D $port,
    Bool:D $ignore-ooo,
    UInt:D $ws-port,
    Supplier:D $client-supplier,
    --> Nil
) {
    start { background-ticks($channel, $interval)                      }
    start { background-google($channel, $interval, @calendar)          }
    start { background-network($channel, $port)                        }
    start { background-webserver($channel, $ws-port, $client-supplier) }
    start { background-camera($channel)                                }
    start { background-keypress($channel)                              }
    start { background-timezone($channel)                              }
}

sub background-ticks(Channel:D $channel, UInt:D $interval --> Nil) {
    my $now = DateTime.now;
    state $due = next-interval($interval);

    react {
        whenever Supply.interval(1) {
            my $now = DateTime.now;
            if $now >= $due {
                $channel.send(Message-Tick.new);
                $due = next-interval($interval);
            }
        }
    }
}

sub next-interval(UInt:D $interval --> DateTime:D) {
    my $now = DateTime.now.truncated-to('second', :timezone(0));
    
    my Numeric:D $new-posix = $now.posix - ($now.posix % $interval) + $interval;
    return DateTime.new($new-posix);
}

sub background-google(
    Channel:D $channel,
    UInt:D $interval,
    Str:D @calendar,
    --> Nil
) {
    my @appointments = get-appointments-from-google(@calendar)<>;
    $channel.send: Message-Appointments.new(:@appointments);

    react {
        whenever Supply.interval($interval) {
            @appointments = get-appointments-from-google(@calendar)<>;
            $channel.send: Message-Appointments.new(:@appointments);
        }
    }
}

sub background-network(Channel:D $channel, UInt:D $port --> Nil) {
    # Remote Network monitor
    return if $port == 0;

    my $camera = 0;
    my $socket = IO::Socket::Async.bind-udp('::', $port);

    react {
        whenever $socket.Supply -> $v {
            if $v eq "CAMERA ON" {
                # We need TWO camera "on" events before we change state
                if $camera++ == 1 {
                    $channel.send: Message-Remote.new(state => True);
                }
            } elsif $v eq "CAMERA OFF" {
                if $camera ≠ 0 {
                    $camera = 0;
                    $channel.send: Message-Remote.new(state => False);
                }
            } elsif $v ~~ m/ ^ "KEY " (.) $/ {
                $channel.send: Message-Keypress.new(key => $0.Str.fc);
            }
        }
    }
}

sub background-webserver(Channel:D $channel, UInt:D $ws-port, Supplier:D $client-supplier --> Nil) {
    # Remote Web Socket Connections
    return if $ws-port == 0;

    my $application = route {
        get -> '' {
            content 'text/plain', "Hello - This is the Busy Indicator service!\n";
        }

        get -> 'feed' {
            web-socket :json, -> $incoming {
                supply {
                    emit $STATUS;
                    whenever $incoming -> $message {
                        emit $message;
                    }
                    whenever $client-supplier -> $message {
                        emit $message;
                    }
                }
            }
        }
    }

    my Cro::Service $svc = Cro::HTTP::Server.new(
        :host<localhost>,
        :port($ws-port),
        :$application,
    );
    $svc.start;
}

sub background-camera(Channel:D $channel -->Nil) {
    my $camera = 0;

    react {
        whenever Supply.interval(1) {
            # We need TWO camera "on" events before we change state
            if get-camera() {
                if $camera++ == 2 {
                    $channel.send: Message-Camera.new( state => True );
                }
            } else {
                if $camera ≠ 0 {
                    $camera = 0;
                    $channel.send: Message-Camera.new( state => False );
                }
            }
        }
    }
}

sub background-keypress(Channel:D $channel -->Nil) {
    react {
        whenever key-pressed(:!echo) {
            $channel.send: Message-Keypress.new( key => $_.fc );
        }
    }
}

sub background-timezone(Channel:D $channel -->Nil) {
    CATCH {
        default { $channel.send: Message-Offset-Error.new }
    }

    react {
        whenever Supply.interval(60) {
            my $proc = run <date +%z>, :out;
            my $out = $proc.out.slurp(:close);
            my $i = +$out;
            my $sign = ($i+1) ÷ abs($i+1);

            # Format of "$i" is "<sign>HHMM" so we want to convert
            # to seconds.
            my $offset = Int($sign × (abs($i) ÷ 100).Int × 3600 + (abs($i) % 100) × 60);

            $channel.send: Message-Offset.new(:$offset);
        }
    }
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
    CATCH {
        # enable echo upon exception
        default {
            my $flags := Term::termios.new(:fd($*IN.native-descriptor)).getattr;
            $flags.set_lflags('ECHO');
            $flags.setattr(:NOW);
            .rethrow;
        }
    }

    my $now = DateTime.now;

    my $offset;
    if ~$now ~~ m/Z$/ {
        # Special case for UTC
        $offset = "+00:00";
    } else {
        $offset = S/^.* <?before <[ + \- ]> >// with ~$now;
    }

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
