#!perl -w
use strict;
use warnings;
    
use Test::More;

eval "use Test::Compile::OO";
plan(skip_all => "Test::Compile::OO required for testing compilation") if $@;

my $test = Test::Compile::OO->new();
$test->all_files_ok();
