#!./perl -w

# ID: 1.4, 10/23/97   

use strict ;

BEGIN {
    unless(grep /blib/, @INC) {
        chdir 't' if -d 't';
        @INC = '../lib' if -d '../lib';
    }
}

#use Config;
#
#BEGIN {
#    if(-d "lib" && -f "TEST") {
#        if ($Config{'extensions'} !~ /\bBerkDB\b/ ) {
#            print "1..74\n";
#            exit 0;
#        }
#    }
#}

use BerkDB; 
use File::Path qw(rmtree);

print "1..130\n";

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
    eval ' $db = new BerkDB::Hash  -Stupid => 3 ; ' ;
    ok 1, $@ =~ /unknown key value\(s\) Stupid/  ;

    eval ' $db = new BerkDB::Hash -Bad => 2, -Mode => 0345, -Stupid => 3; ' ;
    ok 2, $@ =~ /unknown key value\(s\) Bad Stupid/  ;

    eval ' $db = new BerkDB::Hash -Env => 2 ' ;
    ok 3, $@ =~ /^Env not of type BerkDB::Env/ ;

    eval ' $db = new BerkDB::Hash -Txn => "fred" ' ;
    ok 4, $@ =~ /^Txn not of type BerkDB::Txn/ ;

    my $obj = bless [], "main" ;
    eval ' $db = new BerkDB::Hash -Env => $obj ' ;
    ok 5, $@ =~ /^Env not of type BerkDB::Env/ ;
}

# Now check the interface to HASH

{
    my $lex = new LexFile $Dfile ;

    ok 6, my $db = new BerkDB::Hash -Filename => $Dfile, 
				    -Flags    => DB_CREATE ;

    # Add a k/v pair
    my $value ;
    ok 7, $db->db_put("some key", "some value") == 0  ;
    ok 8, $db->db_get("some key", $value) == 0 ;
    ok 9, $value eq "some value" ;
    ok 10, $db->db_put("key", "value") == 0  ;
    ok 11, $db->db_get("key", $value) == 0 ;
    ok 12, $value eq "value" ;
    ok 13, $db->db_del("some key") == 0 ;
    ok 14, $db->db_get("some key", $value) == DB_NOTFOUND ;

    ok 15, $db->db_sync() == 0 ;

    # Check NOOVERWRITE will make put fail when attempting to overwrite
    # an existing record.

    ok 16, $db->db_put( 'key', 'x', DB_NOOVERWRITE) == DB_KEYEXIST ;

    # check that the value of the key  has not been changed by the
    # previous test
    ok 17, $db->db_get("key", $value) == 0 ;
    ok 18, $value eq "value" ;


}

{
    # Check simple env works with a hash.
    my $lex = new LexFile $Dfile ;

    ok 19, my $env = new BerkDB::Env ;
    ok 20, my $db = new BerkDB::Hash -Filename => $Dfile, 
				    -Env      => $env,
				    -Flags    => DB_CREATE ;

    # Add a k/v pair
    my $value ;
    ok 21, $db->db_put("some key", "some value") == 0 ;
    ok 22, $db->db_get("some key", $value) == 0 ;
    ok 23, $value eq "some value" ;
}

{
    # override default hash
    my $lex = new LexFile $Dfile ;
    my $value ;
    $::count = 0 ;
    ok 24, my $db = new BerkDB::Hash -Filename => $Dfile, 
				     -Hash     => sub {  ++$::count ; length $_[0] },
				     -Flags    => DB_CREATE ;

    ok 25, $db->db_put("some key", "some value") == 0 ;
    ok 26, $db->db_get("some key", $value) == 0 ;
    ok 27, $value eq "some value" ;
    ok 28, $::count > 0 ;

}
 
{
    # cursors

    my $lex = new LexFile $Dfile ;
    my %hash ;
    my ($k, $v) ;
    ok 29, my $db = new BerkDB::Hash -Filename => $Dfile, 
				     -Flags    => DB_CREATE ;

    # create some data
    my %data =  (
		"red"	=> 2,
		"green"	=> "house",
		"blue"	=> "sea",
		) ;

    my $ret = 0 ;
    while (($k, $v) = each %data) {
        $ret += $db->db_put($k, $v) ;
    }
    ok 30, $ret == 0 ;

    # create the cursor
    ok 31, my $cursor = $db->db_cursor() ;

    $k = $v = "" ;
    my %copy = %data ;
    my $extras = 0 ;
    # sequence forwards
    while ($cursor->c_get($k, $v, DB_NEXT) == 0) {
        if ( $copy{$k} eq $v ) 
            { delete $copy{$k} }
	else
	    { ++ $extras }
    }
    ok 32, keys %copy == 0 ;
    ok 33, $extras == 0 ;

    # sequence backwards
    %copy = %data ;
    $extras = 0 ;
    for ( my $status = $cursor->c_get($k, $v, DB_LAST) ;
	  $status == 0 ;
    	  $status = $cursor->c_get($k, $v, DB_PREV)) {
        if ( $copy{$k} eq $v ) 
            { delete $copy{$k} }
	else
	    { ++ $extras }
    }
    ok 34, keys %copy == 0 ;
    ok 35, $extras == 0 ;
}
 
{
    # Tied Hash interface

    my $lex = new LexFile $Dfile ;
    my %hash ;
    ok 36, tie %hash, 'BerkDB::Hash', -Filename => $Dfile,
                                      -Flags    => DB_CREATE ;

    # check "each" with an empty database
    my $count = 0 ;
    while (my ($k, $v) = each %hash) {
	++ $count ;
    }
    ok 37, $count == 0 ;

    # Add a k/v pair
    my $value ;
    $hash{"some key"} = "some value";
    ok 38, $hash{"some key"} eq "some value";
    ok 39, defined $hash{"some key"} ;
    ok 40, exists $hash{"some key"} ;
    ok 41, !defined $hash{"jimmy"} ;
    ok 42, !exists $hash{"jimmy"} ;

    delete $hash{"some key"} ;
    ok 43, ! defined $hash{"some key"} ;
    ok 44, ! exists $hash{"some key"} ;

    $hash{1} = 2 ;
    $hash{10} = 20 ;
    $hash{1000} = 2000 ;

    my ($keys, $values) = (0,0);
    $count = 0 ;
    while (my ($k, $v) = each %hash) {
        $keys += $k ;
	$values += $v ;
	++ $count ;
    }
    ok 45, $count == 3 ;
    ok 46, $keys == 1011 ;
    ok 47, $values == 2022 ;

    # now clear the hash
    %hash = () ;
    ok 48, keys %hash == 0 ;

    untie %hash ;
}

{
    # in-memory file

    my $lex = new LexFile $Dfile ;
    my %hash ;
    my $fd ;
    my $value ;
    ok 49, my $db = tie %hash, 'BerkDB::Hash' ;

    ok 50, $db->db_put("some key", "some value") == 0  ;
    ok 51, $db->db_get("some key", $value) == 0 ;
    ok 52, $value eq "some value" ;

}
 
{
    # partial
    # check works via API

    my $lex = new LexFile $Dfile ;
    my %hash ;
    my $value ;
    ok 53, my $env = new BerkDB::Env ;
    ok 54, my $db = tie %hash, 'BerkDB::Hash', -Filename => $Dfile,
                                      	       -Flags    => DB_CREATE ,
					       -Env 	 => $env ;

    # create some data
    my %data =  (
		"red"	=> "boat",
		"green"	=> "house",
		"blue"	=> "sea",
		) ;

    my $ret = 0 ;
    while (my ($k, $v) = each %data) {
        $ret += $db->db_put($k, $v) ;
    }
    ok 55, $ret == 0 ;


    # do a partial get
    my($pon, $off, $len) = $db->partial_set(0,2) ;
    ok 56, $pon == 0 && $off == 0 && $len == 0 ;
    ok 57, ! $db->db_get("red", $value) && $value eq "bo" ;
    ok 58, ! $db->db_get("green", $value) && $value eq "ho" ;
    ok 59, ! $db->db_get("blue", $value) && $value eq "se" ;

    # do a partial get, off end of data
    ($pon, $off, $len) = $db->partial_set(3,2) ;
    ok 60, $pon ;
    ok 61, $off == 0 ;
    ok 62, $len == 2 ;
    ok 63, ! $db->db_get("red", $value) && $value eq "t" ;
    ok 64, ! $db->db_get("green", $value) && $value eq "se" ;
    ok 65, ! $db->db_get("blue", $value) && $value eq "" ;

    # switch of partial mode
    ($pon, $off, $len) = $db->partial_clear() ;
    ok 66, $pon ;
    ok 67, $off == 3 ;
    ok 68, $len == 2 ;
    ok 69, ! $db->db_get("red", $value) && $value eq "boat" ;
    ok 70, ! $db->db_get("green", $value) && $value eq "house" ;
    ok 71, ! $db->db_get("blue", $value) && $value eq "sea" ;

    # now partial put
    ($pon, $off, $len) = $db->partial_set(0,2) ;
    ok 72, ! $pon ;
    ok 73, $off == 0 ;
    ok 74, $len == 0 ;
    ok 75, ! $db->db_put("red", "") ;
    ok 76, ! $db->db_put("green", "AB") ;
    ok 77, ! $db->db_put("blue", "XYZ") ;
    ok 78, ! $db->db_put("new", "KLM") ;

    $db->partial_clear() ;
    ok 79, ! $db->db_get("red", $value) && $value eq "at" ;
    ok 80, ! $db->db_get("green", $value) && $value eq "ABuse" ;
    ok 81, ! $db->db_get("blue", $value) && $value eq "XYZa" ;
    ok 82, ! $db->db_get("new", $value) && $value eq "KLM" ;

    # now partial put
    $db->partial_set(3,2) ;
    ok 83, ! $db->db_put("red", "PPP") ;
    ok 84, ! $db->db_put("green", "Q") ;
    ok 85, ! $db->db_put("blue", "XYZ") ;
    ok 86, ! $db->db_put("new", "--") ;

    ($pon, $off, $len) = $db->partial_clear() ;
    ok 87, $pon ;
    ok 88, $off == 3 ;
    ok 89, $len == 2 ;
    ok 90, ! $db->db_get("red", $value) && $value eq "at\0PPP" ;
    ok 91, ! $db->db_get("green", $value) && $value eq "ABuQ" ;
    ok 92, ! $db->db_get("blue", $value) && $value eq "XYZXYZ" ;
    ok 93, ! $db->db_get("new", $value) && $value eq "KLM--" ;
}

{
    # partial
    # check works via tied hash 

    my $lex = new LexFile $Dfile ;
    my %hash ;
    my $value ;
    ok 94, my $env = new BerkDB::Env ;
    ok 95, my $db = tie %hash, 'BerkDB::Hash', -Filename => $Dfile,
                                      	       -Flags    => DB_CREATE ,
					       -Env 	 => $env ;

    # create some data
    my %data =  (
		"red"	=> "boat",
		"green"	=> "house",
		"blue"	=> "sea",
		) ;

    while (my ($k, $v) = each %data) {
	$hash{$k} = $v ;
    }


    # do a partial get
    $db->partial_set(0,2) ;
    ok 96, $hash{"red"} eq "bo" ;
    ok 97, $hash{"green"} eq "ho" ;
    ok 98, $hash{"blue"}  eq "se" ;

    # do a partial get, off end of data
    $db->partial_set(3,2) ;
    ok 99, $hash{"red"} eq "t" ;
    ok 100, $hash{"green"} eq "se" ;
    ok 101, $hash{"blue"} eq "" ;

    # switch of partial mode
    $db->partial_clear() ;
    ok 102, $hash{"red"} eq "boat" ;
    ok 103, $hash{"green"} eq "house" ;
    ok 104, $hash{"blue"} eq "sea" ;

    # now partial put
    $db->partial_set(0,2) ;
    ok 105, $hash{"red"} = "" ;
    ok 106, $hash{"green"} = "AB" ;
    ok 107, $hash{"blue"} = "XYZ" ;
    ok 108, $hash{"new"} = "KLM" ;

    $db->partial_clear() ;
    ok 109, $hash{"red"} eq "at" ;
    ok 110, $hash{"green"} eq "ABuse" ;
    ok 111, $hash{"blue"} eq "XYZa" ;
    ok 112, $hash{"new"} eq "KLM" ;

    # now partial put
    $db->partial_set(3,2) ;
    ok 113, $hash{"red"} = "PPP" ;
    ok 114, $hash{"green"} = "Q" ;
    ok 115, $hash{"blue"} = "XYZ" ;
    ok 116, $hash{"new"} = "TU" ;

    $db->partial_clear() ;
    ok 117, $hash{"red"} eq "at\0PPP" ;
    ok 118, $hash{"green"} eq "ABuQ" ;
    ok 119, $hash{"blue"} eq "XYZXYZ" ;
    ok 120, $hash{"new"} eq "KLMTU" ;
}

{
    # transaction

    my $lex = new LexFile $Dfile ;
    my %hash ;
    my $value ;

    my $home = "./fred" ;
    rmtree $home if -e $home ;
    ok 121, mkdir($home, 0777) ;
    ok 122, my $env = new BerkDB::Env -Home => $home,
				     -Flags => DB_CREATE|DB_INIT_TXN|
					  	DB_INIT_MPOOL|DB_INIT_LOCK ;
    ok 123, my $txn = $env->txn_begin() ;
    ok 124, my $db1 = tie %hash, 'BerkDB::Hash', -Filename => $Dfile,
                                      	       	-Flags     => DB_CREATE ,
					       	-Env 	   => $env,
					    	-Txn	   => $txn  ;

    
    # create some data
    my %data =  (
		"red"	=> "boat",
		"green"	=> "house",
		"blue"	=> "sea",
		) ;

    my $ret = 0 ;
    while (my ($k, $v) = each %data) {
        $ret += $db1->db_put($k, $v) ;
    }
    ok 125, $ret == 0 ;

    # should be able to see all the records

    ok 126, my $cursor = $db1->db_cursor() ;
    my ($k, $v) = ("", "") ;
    my $count = 0 ;
    # sequence forwards
    while ($cursor->c_get($k, $v, DB_NEXT) == 0) {
        ++ $count ;
    }
    ok 127, $count == 3 ;
    undef $cursor ;

    # now abort the transaction
    ok 128, $txn->txn_abort() == 0 ;

    # there shouldn't be any records in the database
    $count = 0 ;
    # sequence forwards
    ok 129, $cursor = $db1->db_cursor() ;
    while ($cursor->c_get($k, $v, DB_NEXT) == 0) {
        ++ $count ;
    }
    ok 130, $count == 0 ;

    undef $txn ;
    undef $cursor ;
    undef $db1 ;
    undef $env ;
    rmtree $home ;
}
