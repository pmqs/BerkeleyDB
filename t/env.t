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

print "1..49\n";


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

    ok 21, my $txn_mgr = $env->TxnMgr() ;
    ok 22, my $txn = $txn_mgr->txn_begin() ;

    my %hash ;
    ok 23, tie %hash, 'BerkeleyDB::Hash', -Filename => $data_file,
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
    ok 24, my $env = new BerkeleyDB::Env( -ErrFile => $errfile ) ;
    my $db = new BerkeleyDB::Hash -Filename => $Dfile,
			     -Env      => $env,
			     -Flags    => -1;
    ok 25, !$db ;

    ok 26, $BerkeleyDB::Error =~ /^illegal flag specified to db_open/;
    ok 27, -e $errfile ;
    my $contents = docat($errfile) ;
    chomp $contents ;
    ok 28, $BerkeleyDB::Error eq $contents ;

}

{
    # -ErrFile with a filehandle
    use IO ;
    my $errfile = "./errfile" ;
    my $lex = new LexFile $errfile ;
    ok 29, my $ef  = new IO::File ">$errfile" ;
    ok 30, my $env = new BerkeleyDB::Env( -ErrFile => $ef ) ;
    my $db = new BerkeleyDB::Hash -Filename => $Dfile,
			     -Env      => $env,
			     -Flags    => -1;
    ok 31, !$db ;

    ok 32, $BerkeleyDB::Error =~ /^illegal flag specified to db_open/;
    $ef->close() ;
    ok 33, -e $errfile ;
    my $contents = docat($errfile) ;
    chomp $contents ;
    ok 34, $BerkeleyDB::Error eq $contents ;
}

{
    # -ErrPrefix
    use IO ;
    my $errfile = "./errfile" ;
    my $lex = new LexFile $errfile ;
    ok 35, my $env = new BerkeleyDB::Env( -ErrFile => $errfile,
					-ErrPrefix => "PREFIX" ) ;
    my $db = new BerkeleyDB::Hash -Filename => $Dfile,
			     -Env      => $env,
			     -Flags    => -1;
    ok 36, !$db ;

    ok 37, $BerkeleyDB::Error =~ /^PREFIX: illegal flag specified to db_open/;
    ok 38, -e $errfile ;
    my $contents = docat($errfile) ;
    chomp $contents ;
    ok 39, $BerkeleyDB::Error eq $contents ;

    # change the prefix on the fly
    my $old = $env->errPrefix("NEW ONE") ;
    ok 40, $old eq "PREFIX" ;

    $db = new BerkeleyDB::Hash -Filename => $Dfile,
			     -Env      => $env,
			     -Flags    => -1;
    ok 41, !$db ;
    ok 42, $BerkeleyDB::Error =~ /^NEW ONE: illegal flag specified to db_open/;
    $contents = docat($errfile) ;
    chomp $contents ;
    ok 43, $contents =~ /$BerkeleyDB::Error$/ ;
}

{
    # test db_appexit
    use Cwd ;
    my $cwd = cwd() ;
    my $home = "$cwd/fred" ;
    my $data_dir = "$home/data_dir" ;
    my $log_dir = "$home/log_dir" ;
    my $data_file = "data.db" ;
    ok 44, -d $home ? chmod 0777, $home : mkdir($home, 0777) ;
    ok 45, -d $data_dir ? chmod 0777, $data_dir : mkdir($data_dir, 0777) ;
    ok 46, -d $log_dir ? chmod 0777, $log_dir : mkdir($log_dir, 0777) ;
    my $env = new BerkeleyDB::Env -Home   => $home,
			      -Config => { DB_DATA_DIR => $data_dir,
					   DB_LOG_DIR  => $log_dir
					 },
			      -Flags  => DB_CREATE|DB_INIT_TXN|DB_INIT_LOG|
					 DB_INIT_MPOOL|DB_INIT_LOCK ;
    ok 47, $env ;

    ok 48, my $txn_mgr = $env->TxnMgr() ;

    ok 49, $env->db_appexit() == 0 ;

    rmtree $home ;
}

# test -Verbose
# test -Flags
# db_value_set
