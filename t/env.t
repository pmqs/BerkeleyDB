#!./perl -w

# ID: 1.2, 7/17/97

use strict ;

BEGIN {
    unless(grep /blib/, @INC) {
        chdir 't' if -d 't';
        @INC = '../lib' if -d '../lib';
    }
}

use BerkeleyDB; 
use File::Path qw(rmtree);

print "1..42\n";


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

sub docat
{
    my $file = shift;
    local $/ = undef;
    open(CAT,$file) || die "Cannot open $file:$!";
    my $result = <CAT>;
    close(CAT);
    return $result;
}


my $Dfile = "dbhash.tmp";

umask(0);

{
    # db version stuff
    my ($major, $minor, $patch) = (0, 0, 0) ;

    ok 1, my $VER = BerkeleyDB::DB_VERSION_STRING ;
    ok 2, my $ver = BerkeleyDB::db_version($major, $minor, $patch) ;
    ok 3, $VER eq $ver ;
    ok 4, $major > 1 ;
    ok 5, defined $minor ;
    ok 6, defined $patch ;
}

{
    # Check for invalid parameters
    my $env ;
    eval ' $env = new BerkeleyDB::Env( -Stupid => 3) ; ' ;
    ok 7, $@ =~ /unknown key value\(s\) Stupid/  ;

    eval ' $env = new BerkeleyDB::Env( -Bad => 2, -Home => "/tmp", -Stupid => 3) ; ' ;
    ok 8, $@ =~ /unknown key value\(s\) Bad Stupid/  ;

    eval ' $env = new BerkeleyDB::Env( -Config => {"fred" => ""} ) ; ' ;
    ok 9, !$env ;
    ok 10, $BerkeleyDB::Error =~ /^illegal name-value pair/ ;
}

{
    # create a very simple environment
    ok 11, my $env = new BerkeleyDB::Env   ;
}

{
    # create an environment with a Home
    my $home = "./fred" ;
    ok 12, -d $home ? chmod 0777, $home : mkdir($home, 0777) ;
    ok 13, my $env = new BerkeleyDB::Env -Home => $home;

    rmtree $home ;
}

{
    # make new fail.
    my $home = "./fred" ;
    ok 14, mkdir($home, 0) ; # this needs to be more portable
    my $env = new BerkeleyDB::Env -Home => $home,
			      -Flags => DB_INIT_LOCK ;
    ok 15, ! $env ;
    ok 16,   $! != 0 ;

    rmtree $home ;
}

{
    # Config
    use Cwd ;
    my $cwd = cwd() ;
    my $home = "$cwd/fred" ;
    my $data_dir = "$home/data_dir" ;
    my $log_dir = "$home/log_dir" ;
    my $data_file = "data.db" ;
    ok 17, -d $home ? chmod 0777, $home : mkdir($home, 0777) ;
    ok 18, -d $data_dir ? chmod 0777, $data_dir : mkdir($data_dir, 0777) ;
    ok 19, -d $log_dir ? chmod 0777, $log_dir : mkdir($log_dir, 0777) ;
    my $env = new BerkeleyDB::Env -Home   => $home,
			      -Config => { DB_DATA_DIR => $data_dir,
					   DB_LOG_DIR  => $log_dir
					 },
			      -Flags  => DB_CREATE|DB_INIT_TXN|DB_INIT_LOG|
					 DB_INIT_MPOOL|DB_INIT_LOCK ;
    ok 20, $env ;

    ok 21, my $txn = $env->txn_begin() ;

    my %hash ;
    ok 22, tie %hash, 'BerkeleyDB::Hash', -Filename => $data_file,
                                       -Flags     => DB_CREATE ,
                                       -Env       => $env,
                                       -Txn       => $txn  ;

    $hash{"abc"} = 123 ;
    $hash{"def"} = 456 ;

    $txn->txn_commit() ;

    untie %hash ;

    rmtree $home ;
}

{
    # -ErrFile with a filename
    my $errfile = "./errfile" ;
    my $lex = new LexFile $errfile ;
    ok 23, my $env = new BerkeleyDB::Env( -ErrFile => $errfile ) ;
    my $db = new BerkeleyDB::Hash -Filename => $Dfile,
			     -Env      => $env,
			     -Flags    => -1;
    ok 24, !$db ;

    ok 25, $BerkeleyDB::Error =~ /^illegal flag specified to db_open/;
    ok 26, -e $errfile ;
    my $contents = docat($errfile) ;
    chomp $contents ;
    ok 27, $BerkeleyDB::Error eq $contents ;

}

{
    # -ErrFile with a filehandle
    use IO ;
    my $errfile = "./errfile" ;
    my $lex = new LexFile $errfile ;
    ok 28, my $ef  = new IO::File ">$errfile" ;
    ok 29, my $env = new BerkeleyDB::Env( -ErrFile => $ef ) ;
    my $db = new BerkeleyDB::Hash -Filename => $Dfile,
			     -Env      => $env,
			     -Flags    => -1;
    ok 30, !$db ;

    ok 31, $BerkeleyDB::Error =~ /^illegal flag specified to db_open/;
    $ef->close() ;
    ok 32, -e $errfile ;
    my $contents = docat($errfile) ;
    chomp $contents ;
    ok 33, $BerkeleyDB::Error eq $contents ;
}

{
    # -ErrPrefix
    use IO ;
    my $errfile = "./errfile" ;
    my $lex = new LexFile $errfile ;
    ok 34, my $env = new BerkeleyDB::Env( -ErrFile => $errfile,
					-ErrPrefix => "PREFIX" ) ;
    my $db = new BerkeleyDB::Hash -Filename => $Dfile,
			     -Env      => $env,
			     -Flags    => -1;
    ok 35, !$db ;

    ok 36, $BerkeleyDB::Error =~ /^PREFIX: illegal flag specified to db_open/;
    ok 37, -e $errfile ;
    my $contents = docat($errfile) ;
    chomp $contents ;
    ok 38, $BerkeleyDB::Error eq $contents ;

    # change the prefix on the fly
    my $old = $env->errPrefix("NEW ONE") ;
    ok 39, $old eq "PREFIX" ;

    $db = new BerkeleyDB::Hash -Filename => $Dfile,
			     -Env      => $env,
			     -Flags    => -1;
    ok 40, !$db ;
    ok 41, $BerkeleyDB::Error =~ /^NEW ONE: illegal flag specified to db_open/;
    $contents = docat($errfile) ;
    chomp $contents ;
    ok 42, $contents =~ /$BerkeleyDB::Error$/ ;
}

# test -Verbose
# test -Flags
# test -LockMax
# test -LogMax
# test -TxnMax
