#!/usr/bin/perl
use strict;
use warnings;
use utf8;
use autodie;
use 5.10.0;
use POSIX qw/strftime/;
use JSON;
use XML::Feed;
use WWW::Mechanize;
use HTML::Strip;
use Readonly;
use MIME::Lite;

Readonly my $CONFIGPATH => 'crab2mail.json';
Readonly my $SEEN  => 'crab2mail-seen';

my $config = get_config();
my $mech   = do_crabgrass_login($config);

open my $in, '<:utf8', $SEEN;
my @seen = <$in>;
close $in;
my %seen = map { chomp; $_ => 1 } @seen;

my @entries = get_crabgrass_updates($config, $mech); 

my $max_items = $config->{max_items};
my $new_items = 0;
my $msg_body = '';

open my $out, '>>:utf8', $SEEN;
for(@entries) {
	next if ($seen{$_->id});
	my $msg = '';
	$msg_body .= format_msg($_->summary->body) if ($_->summary && $_->summary->body);
	# $msg_body .= format_msg($_->content->body) if ($_->content && $_->content->body);
	$msg_body .= "\nRead more at: " 
			. $_->link if ($_->link);
	$msg_body .= "\n=====\n\n";
	$new_items++;
	print $out $_->id . "\n"; 
	last unless $new_items < $max_items;
}
close $out;

send_mail($config, $msg_body);

sub get_config {
	open my $in, '<:utf8', $CONFIGPATH;
	my @lines = <$in>;
	close $in;
	my $config = decode_json "@lines";
	return $config;
}

sub do_crabgrass_login {
    my $config    = shift;
    my $login_url = "https://" . $config->{host} ;
    my $mech      = WWW::Mechanize->new();
    $mech->get($login_url);
    my $res  = $mech->submit_form(
        form_id => 'loginform',
        fields  => {
            'password' => $config->{password},
            'login'    => $config->{username},
            'commit'   => 'Log in',
        },
    );
    die
        "Fuck it, can't login. Maybe you need to change the login details in $CONFIGPATH?"
        unless $res->is_success;

    return $mech;
}

sub get_crabgrass_updates {
	my ($config,$mech) = (shift,shift);
	my $res = $mech->get("https://" . $config->{host} ."/me/search/descending/updated_at/rss" );
	die "Fuck no response" unless $res->is_success;
	my $content = $mech->content; 
	die "Fuck no content" unless $content;
	my $feed = XML::Feed->parse(\$content);
	return $feed->entries;
}

sub format_msg {
	my $msg = shift;
	my $hs = HTML::Strip->new();
	return $hs->parse( $msg );
}

sub send_mail {
	my ($config, $body) = (shift, shift);
	my $recipient = $config->{recipient};
	my $sender = $config->{sender};

	my $mimelite = MIME::Lite->new (
		From    => $sender,
		To      => $recipient,
		Data    => $body,
		Subject => strftime("%Y-%m-%d", localtime())." Crabgrass Updates",
	);

	if($config->{mailhost} && $config->{mailuser} && $config->{mailpass}) {
        $mimelite->send(
            'smtp', $config->{mailhost},
            AuthUser => $config->{mailuser},
            AuthPass => $config->{mailpass}
        );
	} 
	elsif ($config->{mailhost}) {
		$mimelite->send('smtp', $config->{mailhost});
	} 
	else {
		$mimelite->send;
	}
}
__END__

=head1 NAME

crab2mail.pl : Get your crabgrass updates RSS sent to your email.

=head2 VERSION

0.1

=head1 SYNOPSIS

Edit crab2mail.json to set up your account details then just:

$ crab2mail.pl 

You probably want to run this as a cronjob

=head1 DESCRIPTION

Install by untarring with 

$ tar xvzf crab2mail.tar.gz

Then

$ cd crab2mail

You'll need to make sure you have Perl 5.10.0 and the CPAN dependencies. 

$ sudo cpan XML::Feed Readonly HTML::Strip Data::Dumper WWW::Mechanize MIME::Lite

Then copy the example config file and edit it to something more to your taste.

$ cp crab2mail.json.example crab2mail.json

You should make crab2mail.pl executable wiith

$ chmod 750 crab2mail.pl

Finally you can start updating your feed with

$ ./crab2mail.pl

You may want to put that in a cron job.

=head2 OPTIONS

All options are set in crab2mail.json . I used JSON rather than YAML to reduce dependencies

=head1 REQUIREMENTS

Perl 5.10.0 
Data::Dumper
JSON
XML::Feed
WWW::Mechanize
HTML::Strip
Readonly
POSIX
MIME::Lite

=head1 COPYRIGHT AND LICENCE

           Copyright (C)2012 Charlie Harvey

 This program is free software; you can redistribute it and/or
 modify it under the terms of the GNU General Public License
 as published by the Free Software Foundation; either version 
 2 of the License, or (at your option) any later version.

 This program is distributed in the hope that it will be 
 useful, but WITHOUT ANY WARRANTY; without even the implied 
 warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR 
 PURPOSE.  See the GNU General Public License for more 
 details.

 You should have received a copy of the GNU General Public 
 License along with this program; if not, write to the Free
 Software Foundation, Inc., 59 Temple Place - Suite 330,
 Boston, MA  02111-1307, USA.
 Also available on line: http://www.gnu.org/copyleft/gpl.html

=cut
