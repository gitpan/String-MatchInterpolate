#!/usr/bin/perl -w

use strict;
use Test::More tests => 3;
use Test::Exception;

use String::MatchInterpolate;

my $smi = String::MatchInterpolate->new( 'nm${NAME/\w+/}', allow_trail => 1 );

ok( defined $smi, 'defined $smi with trail' );

my $vars;

$vars = $smi->match( "nmMyName" );
is_deeply( $vars, { NAME => 'MyName', _trail => '' }, 'matchd with empty trail' );

$vars = $smi->match( "nmMyName with values" );
is_deeply( $vars, { NAME => 'MyName', _trail => ' with values' }, 'matchd with trail' );
