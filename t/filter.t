#!./perl -w

# ID: %I%, %G%   

use strict ;

BEGIN {
    unless(grep /blib/, @INC) {
        chdir 't' if -d 't';
        @INC = '../lib' if -d '../lib';
    }
}

use BerkeleyDB; 
use File::Path qw(rmtree);

print "1..36\n";

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
unlink $Dfile;

umask(0) ;


# Check for invalid parameters
{
    # Check for invalid parameters
    my $db ;
    eval ' $db = new BerkeleyDB::Hash  -Stupid => 3 ; ' ;
    ok 1, $@ =~ /unknown key value\(s\) Stupid/  ;

    eval ' $db = new BerkeleyDB::Hash -Bad => 2, -Mode => 0345, -Stupid => 3; ' ;
    ok 2, $@ =~ /unknown key value\(s\) (Bad |Stupid ){2}/  ;

    eval ' $db = new BerkeleyDB::Hash -Env => 2 ' ;
    ok 3, $@ =~ /^Env not of type BerkeleyDB::Env/ ;

    eval ' $db = new BerkeleyDB::Hash -Txn => "fred" ' ;
    ok 4, $@ =~ /^Txn not of type BerkeleyDB::Txn/ ;

    my $obj = bless [], "main" ;
    eval ' $db = new BerkeleyDB::Hash -Env => $obj ' ;
    ok 5, $@ =~ /^Env not of type BerkeleyDB::Env/ ;
}


{
    my %hash ;
    my $db ;
    my $lex = new LexFile $Dfile ;
    my ($read_key, $write_key, $read_value, $write_value) = ("") x 4 ;

    ok 6, $db = tie %hash, 'BerkeleyDB::Hash', 
    		-Filename   => $Dfile, 
	        -Flags      => DB_CREATE, 
	        -ReadKey    => sub { $read_key = $_ },
	        -WriteKey   => sub { $write_key = $_ },
	        -ReadValue  => sub { $read_value = $_ },
	        -WriteValue => sub { $write_value = $_ };

    $hash{"fred"} = "joe" ;
    ok 7, $write_key eq "fred" ;
    ok 8, $write_value eq "joe" ;
    ok 9, $read_key eq "" ;
    ok 10, $read_value eq "" ;

    ($read_key, $write_key, $read_value, $write_value) = ("") x 4 ;
    ok 11, $db->db_put("abc", "def") == 0 ;
    ok 12, $write_key eq "abc" ;
    ok 13, $write_value eq "def" ;
    ok 14, $read_key eq "" ;
    ok 15, $read_value eq "" ;

    ($read_key, $write_key, $read_value, $write_value) = ("") x 4 ;
    ok 16, $hash{"fred"} eq "joe" ;
    ok 17, $write_key eq "fred" ;
    ok 18, $write_value eq "" ;
    ok 19, $read_key eq "" ;
    ok 20, $read_value eq "joe" ;

    ($read_key, $write_key, $read_value, $write_value) = ("") x 4 ;
    my $value = "xyz" ;
    ok 21, $db->db_get("abc", $value) == 0 ;
    ok 22, $value eq "def" ;
    ok 23, $write_key eq "abc" ;
    ok 24, $write_value eq "" ;
    ok 25, $read_key eq "" ;
    ok 26, $read_value eq "def" ;

    my $cursor = $db->db_cursor() ;
    my $key = "ABC";
    $value = "DEF" ;
    ($read_key, $write_key, $read_value, $write_value) = ("") x 4 ;
    ok 27, $cursor->c_get($key, $value, DB_FIRST) == 0 ;
    ok 28, $write_key eq "ABC" ;
    ok 29, $write_value eq "" ;
    ok 30, $key ne "" && $read_key eq $key ;
    ok 31, $value ne "" && $read_value eq $value ;
    
}

{    
    # closure

    my %hash ;
    my $db ;
    my $lex = new LexFile $Dfile ;

    my %result = () ;
    sub Closure
    {
        my ($name) = @_ ;
	my $count = 0 ;
	my @kept = () ;

	return sub { ++$count ; 
		     push @kept, $_ ; 
		     $result{$name} = "$name - $count: [@kept]" ;
		   }
    }

    ok 32, $db = tie %hash, 'BerkeleyDB::Hash', 
    		-Filename   => $Dfile, 
	        -Flags      => DB_CREATE, 
	        -WriteKey   => Closure("abc"), 
	        -WriteValue => Closure("def") ;

    $hash{"fred"} = "joe" ;
    ok 33, $result{"abc"} eq "abc - 1: [fred]" ;
    ok 34, $result{"def"} eq "def - 1: [joe]" ;
    $hash{"jim"}  = "john" ;
    ok 35, $result{"abc"} eq "abc - 2: [fred jim]" ;
    ok 36, $result{"def"} eq "def - 2: [joe john]" ;
}		

# check that filters still work when a user-defined sort key is being used.
