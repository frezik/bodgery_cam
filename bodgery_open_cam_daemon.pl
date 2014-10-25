#!/usr/bin/perl
use v5.14;
use warnings;
use Device::WebIO;
use Device::WebIO::RaspberryPi;
use AnyEvent;
use File::Temp 'tempfile';

use constant DEBUG                => 1;
use constant INPUT_PIN            => 17;
use constant PICTURE_INTERVAL_SEC => 0.1 * 60;
use constant IMG_WIDTH            => 800;
use constant IMG_HEIGHT           => 600;
use constant DEFAULT_PIC          => 'bodgery_default.jpg';
use constant PRIVATE_KEY_FILE     => '/home/tmurray/proj/bodgery_cam/upload_key.rsa';
use constant SERVER_USERNAME      => 'bodgery_upload';
use constant SERVER_HOST          => '198.74.61.175';
use constant SERVER_UPLOAD_PATH   => '/var/local/www/vhosts/thebodgery/webcam_feed/feed.jpg';

my ($INPUT, $LAST_INPUT) = (0, 0);


my $rpi = Device::WebIO::RaspberryPi->new;
$rpi->set_as_input( INPUT_PIN );

$rpi->img_set_width( 0, IMG_WIDTH );
$rpi->img_set_height( 0, IMG_HEIGHT );


my $condvar = AnyEvent->condvar;
my $input_timer; $input_timer = AnyEvent->timer(
    after    => 1,
    interval => 1,
    cb       => sub {
        $INPUT = $rpi->input_pin( INPUT_PIN );
        say "Input: [$INPUT]" if DEBUG;
        $input_timer;
    },
);
my $take_picture_timer; $take_picture_timer = AnyEvent->timer(
    after    => 1,
    interval => PICTURE_INTERVAL_SEC,
    cb       => sub {
        if( $INPUT ) {
            say "Sending live image" if DEBUG;
            my $fh = $rpi->img_stream( 0, 'image/jpeg' );

            my ($tmp_fh, $tmp_filename) = tempfile;
            while( read( $fh, my $in, 4096 ) ) {
                print $tmp_fh $in;
            }

            close $fh;
            close $tmp_fh;

            send_pic( $tmp_filename );
            unlink $tmp_filename;
        }
        else {
            if( $INPUT != $LAST_INPUT ) {
                say "Sending default pic" if DEBUG;
                send_pic( DEFAULT_PIC );
            }
            else {
                say "No need to send default pic" if DEBUG;
            }
        }

        $LAST_INPUT = $INPUT;
        $take_picture_timer;
    },
);

say "Taking input . . . " if DEBUG;
$condvar->recv;


sub send_pic
{
    my ($filename) = @_;

    my @scp_command = (
        'scp',
        '-i', PRIVATE_KEY_FILE,
        $filename,
        SERVER_USERNAME . '@' . SERVER_HOST . ':' . SERVER_UPLOAD_PATH,
    );
    say "Executing: @scp_command" if DEBUG;
    (system( @scp_command ) == 0)
        or warn "Could not exec '@scp_command': $!\n";

    return 1;
}
