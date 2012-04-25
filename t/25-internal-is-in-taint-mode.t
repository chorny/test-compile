#!perl

use strict;
use warnings;

use Test::Compile::OO;

use Test::More ;

my $tco = Test::Compile::OO->new();


my $TAINT = $tco->_is_in_taint_mode('t/scripts/taint.pl');
is($TAINT,"T","Found taint flag");

my $taint = $tco->_is_in_taint_mode('t/scripts/CVS/taint2.pl');
is($taint,"t","Found taint warning flag");

my $not = $tco->_is_in_taint_mode('t/scripts/subdir/success.pl');
is($not,"","No taint found in notaint.pl");

done_testing();
