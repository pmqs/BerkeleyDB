#!./perl -w

# ID: 1.2, 7/17/97

use strict ;

BEGIN {
    unless(grep /blib/, @INC) {
        chdir 't' if -d 't';
        @INC = '../lib' if -d '../lib';
    }
}

use BerkDB; 
use File::Path qw(rmtree);

print "1..16\n";


{
    package LexFile ;

    sub new
    {
        my $self = shift ;
        unlink @_ ;
        bless [ @_ ], $self ;
    }

    sub DESTROY
    {
        my $self = shift ;
        unlink @{ $self } ;
    }
}

sub ok
{
    my $no = shift ;
    my $result = shift ;
 
    print "not " unless $result ;
    print "ok $no\n" ;
}

my $Dfile = "dbhash.tmp";

umask(0);

{
    # db version stuff
    my ($major, $minor, $patch) = (0, 0, 0) ;

    ok 1, my $VER = BerkDB::DB_VERSION_STRING ;
    ok 2, my $ver = BerkDB::db_version($major, $minor, $patch) ;
    ok 3, $VER eq $ver ;
    ok 4, $major > 1 ;
    ok 5, defined $minor ;
    ok 6, defined $patch ;
}

{
    # Check for invalid parameters
    my $env ;
    eval ' $env = new BerkDB::Env( -Stupid => 3) ; ' ;
    ok 7, $@ =~ /unknown key value\(s\) Stupid/  ;

    eval ' $env = new BerkDB::Env( -Bad => 2, -Home => "/tmp", -Stupid => 3) ; ' ;
    ok 8, $@ =~ /unknown key value\(s\) Bad Stupid/  ;

    eval ' $env = new BerkDB::Env( -Config => {"fred" => ""} ) ; ' ;
    ok 9, !$env ;
    ok 10, $BerkDB::Error =~ /^illegal name-value pair/ ;
}

{
    # create a very simple environment
    ok 11, my $env = new BerkDB::Env   ;
}

{
    # create an environment with a Home
    my $home = "./fred" ;
    ok 12, -d $home ? chmod 0777, $home : mkdir($home, 0777) ;
    ok 13, my $env = new BerkDB::Env -Home => $home;

    rmtree $home ;
}

{
    # make new fail.
    my $home = "./fred" ;
    ok 14, mkdir($home, 0) ;
    my $env = new BerkDB::Env -Home => $home,
			      -Flags => DB_INIT_LOCK ;
    ok 15, ! $env ;
    ok 16, $! =~ /permission denied/i ;

    rmtree $home ;
}

# test -Config
# test -ErrFile/-ErrPrefix
# test -Flags
# test -LockMax
# test -LogMax
# test -TxnMax
