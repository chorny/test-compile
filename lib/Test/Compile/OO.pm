package Test::Compile::OO;

use 5.006;
use warnings;
use strict;

use Test::Builder;
use File::Spec;
use UNIVERSAL::require;

our $VERSION = '0.17_01';

sub new {
    my $class = shift;

    my $self  = {
        TestBuilder => Test::Builder->new(),
    };

    bless ($self, $class);
    return $self;
}

sub pm_file_ok {
    my $self = shift;
    my $file = shift;
    my $name = @_ ? shift : "Compile test for $file";

    my $ok = $self->_run_in_subprocess(sub{$self->_check_syntax($file,1)});

    $self->{TestBuilder}->ok($ok, $name);
    $self->{TestBuilder}->diag("$file does not compile") unless $ok;
    return $ok;
}

sub pl_file_ok {
    my $self = shift;
    my $file = shift;
    my $name = @_ ? shift : "Compile test for $file";
    my $verbose = shift;

    # don't "use Devel::CheckOS" because Test::Compile is included by
    # Module::Install::StandardTests, and we don't want to have to ship
    # Devel::CheckOS with M::I::T as well.
    if (Devel::CheckOS->require) {

        # Exclude VMS because $^X doesn't work. In general perl is a symlink to
        # perlx.y.z but VMS stores symlinks differently...
        unless (Devel::CheckOS::os_is('OSFeatures::POSIXShellRedirection')
            and Devel::CheckOS::os_isnt('VMS')) {
            $self->{TestBuilder}->skip('Test not compatible with your OS');
            return;
        }
    }

    my $ok = $self->_run_in_subprocess(sub{$self->_check_syntax($file,0)},$verbose);

    $self->{TestBuilder}->ok($ok, $name);
    $self->{TestBuilder}->diag("$file does not compile") unless $ok;
    return $ok;
}

sub all_files_ok {
    my ($self) = @_;

    for my $module ( $self->all_pm_files() ) {
        $self->pm_file_ok($module);
    }
    for my $script ( $self->all_pl_files() ) {
        $self->pl_file_ok($script);
    }
    $self->{TestBuilder}->done_testing();
}

sub all_pm_files_ok {
    my $self = shift;
    my @files = @_ ? @_ : $self->all_pm_files();
    $self->{TestBuilder}->plan(tests => scalar @files);
    my $ok = 1;
    for (@files) {
        $self->pm_file_ok($_) or undef $ok;
    }
    $ok;
}

sub all_pl_files_ok {
    my $self = shift;
    my @files = @_ ? @_ : $self->all_pl_files();
    $self->{TestBuilder}->skip_all("no pl files found") unless @files;
    $self->{TestBuilder}->plan(tests => scalar @files);
    my $ok = 1;
    for (@files) {
        $self->pl_file_ok($_) or undef $ok;
    }
    $ok;
}

sub all_pm_files {
    my $self = shift;
    my @queue = @_ ? @_ : $self->_pm_starting_points();

    my @pm;
    for my $file ( $self->_find_files(@queue) ) {
        if (-f $file) {
            push @pm, $file if $file =~ /\.pm$/;
        }
    }
    return @pm;
}

sub all_pl_files {
    my $self = shift;
    my @queue = @_ ? @_ : $self->_pl_starting_points();

    my @pl;
    for my $file ( $self->_find_files(@queue) ) {
        if (defined($file) && -f $file) {
            # Only accept files with no extension or extension .pl
            push @pl, $file if $file =~ /(?:^[^.]+$|\.pl$)/;
        }
    }
    return @pl;
}

sub _run_in_subprocess {
    my ($self,$closure,$verbose) = @_;

    my $pid = fork();
    if ( ! defined($pid) ) {
        return 0;
    } elsif ( $pid ) {
        wait();
        return ($? ? 0 : 1);
    } else {
        if ( !$verbose ) {
          close(STDERR);
        }
        my $rv = $closure->();
        exit ($rv ? 0 : 1);
    }
}

sub _check_syntax {
    my ($self,$file,$require) = @_;

    if (-f $file) {
        if ( $require ) {
            my $module = $file;
            $module =~ s!^(blib[/\\])?lib[/\\]!!;
            $module =~ s![/\\]!::!g;
            $module =~ s/\.pm$//;
    
            $module->use;
            return ($@ ? 0 : 1);
        } else {
            my @perl5lib = split(':', ($ENV{PERL5LIB}||""));
            my $taint = $self->_is_in_taint_mode($file);
            unshift @perl5lib, 'blib/lib';
            system($^X, (map { "-I$_" } @perl5lib), "-c$taint", $file);
            return ($? ? 0 : 1);
        }
    }
}

sub _find_files {
    my ($self,@queue) = @_;

    for my $file (@queue) {
        if (defined($file) && -d $file) {
            local *DH;
            opendir DH, $file or next;
            my @newfiles = readdir DH;
            closedir DH;
            @newfiles = File::Spec->no_upwards(@newfiles);
            @newfiles = grep { $_ ne "CVS" && $_ ne ".svn" } @newfiles;
            for my $newfile (@newfiles) {
                my $filename = File::Spec->catfile($file, $newfile);
                if (-f $filename) {
                    push @queue, $filename;
                } else {
                    push @queue, File::Spec->catdir($file, $newfile);
                }
            }
        }
    }
    return @queue;
}

sub _pm_starting_points {
    return 'blib' if -e 'blib';
    return 'lib';
}

sub _pl_starting_points {
    return 'script' if -e 'script';
    return 'bin'    if -e 'bin';
}

sub _is_in_taint_mode {
    my ($self,$file) = @_;

    open(my $f, "<", $file) or die "could not open $file";
    my $shebang = <$f>;
    my $taint = "";
    if ($shebang =~ /^#![\/\w]+\s+\-w?([tT])/) {
        $taint = $1;
    }
    return $taint;
}

1;
__END__

=head1 NAME

Test::Compile::OO - Check whether Perl module files compile correctly

=head1 SYNOPSIS

    #!perl -w
    use Test::Compile:OO;
    my $test = Test::Compile::OO->new();
    $test->all_files_ok();

=head1 DESCRIPTION

C<Test::Compile::OO> lets you check the whether your perl modules and script
files compile properly, results are reported in standard C<Test::Simple> fashion.

Module authors can include the following in a F<t/00_compile.t> file and
have C<Test::Compile::OO> automatically find and check all Perl files in a
module distribution:

    #!perl -w
    use strict;
    use warnings;
    
    use Test::More;

    eval "use Test::Compile::OO";
    plan(skip_all => "Test::Compile::OO required for testing compilation") if $@;

    my $test = Test::Compile::OO->new();
    $test->all_files_ok();

=head1 METHODS

=over 4

=item C<new()>

Create a new Test::Compile::OO object

=item C<all_files_ok()>

=item C<pm_file_ok($filename,$testname,$verbose)>

C<pm_file_ok()> will okay the test if the Perl module C<$filename> compiles
correctly.

C<pl_file_ok> will choose a default name for the test unless you specify a
name in C<$testname>.

If C<$verbose> is true, compilation errors will be output for diagnostic 
information, the default is to suppress the output.

=item C<pl_file_ok($filename,$testname,$verbose)>

C<pl_file_ok()> will okay the test if the Perl script C<$filename> compiles
correctly. You need to give the path to the script relative to the
distribution's base directory. So if you put your scripts in a 'top-level'
directory called script the argument would be C<script/filename>.

C<pl_file_ok> will choose a default name for the test unless you specify a
name in C<$testname>.

If C<$verbose> is true, compilation errors will be output for diagnostic 
information, the default is to suppress the output.

=item C<all_pm_files_ok(@files)>

Checks all the files in C<@files> for compilation. It runs L<pm_file_ok()>
on each file, and calls the C<plan()> function for you - so you can't have
already called C<plan()>.

If C<@files> is empty or not passed, the function uses all_pm_files() to find
modules to test.

A Perl module file is one that ends with F<.pm>.

=item C<all_pl_files_ok(@files)>

Checks all the files in C<@files> for compilation. It runs L<pl_file_ok()>
on each file, and calls the C<plan()> function for you, so you can't have
already called C<plan()>.

If C<@files> is empty or not passed, the function uses all_pl_files() to find
scripts to test.

=item C<all_pm_files(@dirs)>

Returns a list of all the perl module files - that is, files ending in F<.pm>
- in I<$dir> and in directories below. If no directories are passed, it
defaults to F<blib> if F<blib> exists, or else F<lib>.

Skips any files in C<CVS> or C<.svn> directories.

The order of the files returned is machine-dependent. If you want them
sorted, you'll have to sort them yourself.

=item C<all_pl_files([@files/@dirs])>

Returns a list of all the perl script files - that is, files ending in F<.pl>
or with no extension. Directory arguments are searched recursively . If no
arguments are passed, it defaults to F<script> if F<script> exists, or else
F<bin> if it exists. 

Skips any files in C<CVS> or C<.svn> directories.

The order of the files returned is machine-dependent. If you want them
sorted, you'll have to sort them yourself.

=back

=head1 AUTHORS

Sagar R. Shah C<< <srshah@cpan.org> >>,
Marcel GrE<uuml>nauer, C<< <marcel@cpan.org> >>,
Evan Giles, C<< <egiles@cpan.org> >>

=head1 COPYRIGHT AND LICENSE

Copyright 2007-2012 by the authors.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Test::LoadAllModules> just handles modules, not script files, but has more
fine-grained control.

=cut
