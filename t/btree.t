#!./perl -w

# ID: 1.2, 10/23/97   

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

print "1..131\n";

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
my $Dfile2 = "dbhash2.tmp";
my $Dfile3 = "dbhash3.tmp";
unlink $Dfile;

umask(0) ;


# Check for invalid parameters
{
    # Check for invalid parameters
    my $db ;
    eval ' $db = new BerkDB::Btree  -Stupid => 3 ; ' ;
    ok 1, $@ =~ /unknown key value\(s\) Stupid/  ;

    eval ' $db = new BerkDB::Btree -Bad => 2, -Mode => 0345, -Stupid => 3; ' ;
    ok 2, $@ =~ /unknown key value\(s\) Bad Stupid/  ;

    eval ' $db = new BerkDB::Btree -Env => 2 ' ;
    ok 3, $@ =~ /^Env not of type BerkDB::Env/ ;

    eval ' $db = new BerkDB::Btree -Txn => "x" ' ;
    ok 4, $@ =~ /^Txn not of type BerkDB::Txn/ ;

    my $obj = bless [], "main" ;
    eval ' $db = new BerkDB::Btree -Env => $obj ' ;
    ok 5, $@ =~ /^Env not of type BerkDB::Env/ ;
}

# Now check the interface to Btree

{
    my $lex = new LexFile $Dfile ;

    ok 6, my $db = new BerkDB::Btree -Filename => $Dfile, 
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
    ok 20, my $db = new BerkDB::Btree -Filename => $Dfile, 
				    -Env      => $env,
				    -Flags    => DB_CREATE ;

    # Add a k/v pair
    my $value ;
    ok 21, $db->db_put("some key", "some value") == 0 ;
    ok 22, $db->db_get("some key", $value) == 0 ;
    ok 23, $value eq "some value" ;
}

 
{
    # cursors

    my $lex = new LexFile $Dfile ;
    my %hash ;
    my ($k, $v) ;
    ok 24, my $db = new BerkDB::Btree -Filename => $Dfile, 
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
    ok 25, $ret == 0 ;

    # create the cursor
    ok 26, my $cursor = $db->db_cursor() ;

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
    ok 27, keys %copy == 0 ;
    ok 28, $extras == 0 ;

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
    ok 29, keys %copy == 0 ;
    ok 30, $extras == 0 ;
}
 
{
    # Tied Hash interface

    my $lex = new LexFile $Dfile ;
    my %hash ;
    ok 31, tie %hash, 'BerkDB::Btree', -Filename => $Dfile,
                                      -Flags    => DB_CREATE ;

    # check "each" with an empty database
    my $count = 0 ;
    while (my ($k, $v) = each %hash) {
	++ $count ;
    }
    ok 32, $count == 0 ;

    # Add a k/v pair
    my $value ;
    $hash{"some key"} = "some value";
    ok 33, $hash{"some key"} eq "some value";
    ok 34, defined $hash{"some key"} ;
    ok 35, exists $hash{"some key"} ;
    ok 36, !defined $hash{"jimmy"} ;
    ok 37, !exists $hash{"jimmy"} ;

    delete $hash{"some key"} ;
    ok 38, ! defined $hash{"some key"} ;
    ok 39, ! exists $hash{"some key"} ;

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
    ok 40, $count == 3 ;
    ok 41, $keys == 1011 ;
    ok 42, $values == 2022 ;

    # now clear the hash
    %hash = () ;
    ok 43, keys %hash == 0 ;

    untie %hash ;
}

{
    # override default compare
    my $lex = new LexFile $Dfile, $Dfile2, $Dfile3 ;
    my $value ;
    my (%h, %g, %k) ;
    my @Keys = qw( 0123 12 -1234 9 987654321 def  ) ; 
    ok 44, tie %h, "BerkDB::Btree", -Filename => $Dfile, 
				     -Compare   => sub { $_[0] <=> $_[1] },
				     -Flags    => DB_CREATE ;

    ok 45, tie %g, 'BerkDB::Btree', -Filename => $Dfile2, 
				     -Compare   => sub { $_[0] cmp $_[1] },
				     -Flags    => DB_CREATE ;

    ok 46, tie %k, 'BerkDB::Btree', -Filename => $Dfile3, 
				   -Compare   => sub { length $_[0] <=> length $_[1] },
				   -Flags    => DB_CREATE ;

    my @srt_1 ;
    { local $^W = 0 ;
      @srt_1 = sort { $a <=> $b } @Keys ; 
    }
    my @srt_2 = sort { $a cmp $b } @Keys ;
    my @srt_3 = sort { length $a <=> length $b } @Keys ;

    foreach (@Keys) {
        local $^W = 0 ;
        $h{$_} = 1 ; 
        $g{$_} = 1 ;
        $k{$_} = 1 ;
    }

    sub ArrayCompare
    {
        my($a, $b) = @_ ;
    
        return 0 if @$a != @$b ;
    
        foreach (1 .. length @$a)
        {
            return 0 unless $$a[$_] eq $$b[$_] ;
        }

        1 ;
    }

    ok 47, ArrayCompare (\@srt_1, [keys %h]);
    ok 48, ArrayCompare (\@srt_2, [keys %g]);
    ok 49, ArrayCompare (\@srt_3, [keys %k]);

}

{
    # in-memory file

    my $lex = new LexFile $Dfile ;
    my %hash ;
    my $fd ;
    my $value ;
    ok 50, my $db = tie %hash, 'BerkDB::Btree' ;

    ok 51, $db->db_put("some key", "some value") == 0  ;
    ok 52, $db->db_get("some key", $value) == 0 ;
    ok 53, $value eq "some value" ;

}
 
{
    # partial
    # check works via API

    my $lex = new LexFile $Dfile ;
    my $value ;
    ok 54, my $env = new BerkDB::Env ;
    ok 55, my $db = new BerkDB::Btree, -Filename => $Dfile,
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
    ok 56, $ret == 0 ;


    # do a partial get
    my ($pon, $off, $len) = $db->partial_set(0,2) ;
    ok 57, ! $pon && $off == 0 && $len == 0 ;
    ok 58, ! $db->db_get("red", $value) && $value eq "bo" ;
    ok 59, ! $db->db_get("green", $value) && $value eq "ho" ;
    ok 60, ! $db->db_get("blue", $value) && $value eq "se" ;

    # do a partial get, off end of data
    ($pon, $off, $len) = $db->partial_set(3,2) ;
    ok 61, $pon ;
    ok 62, $off == 0 ;
    ok 63, $len == 2 ;
    ok 64, ! $db->db_get("red", $value) && $value eq "t" ;
    ok 65, ! $db->db_get("green", $value) && $value eq "se" ;
    ok 66, ! $db->db_get("blue", $value) && $value eq "" ;

    # switch of partial mode
    ($pon, $off, $len) = $db->partial_clear() ;
    ok 67, $pon ;
    ok 68, $off == 3 ;
    ok 69, $len == 2 ;
    ok 70, ! $db->db_get("red", $value) && $value eq "boat" ;
    ok 71, ! $db->db_get("green", $value) && $value eq "house" ;
    ok 72, ! $db->db_get("blue", $value) && $value eq "sea" ;

    # now partial put
    $db->partial_set(0,2) ;
    ok 73, ! $db->db_put("red", "") ;
    ok 74, ! $db->db_put("green", "AB") ;
    ok 75, ! $db->db_put("blue", "XYZ") ;
    ok 76, ! $db->db_put("new", "KLM") ;

    ($pon, $off, $len) = $db->partial_clear() ;
    ok 77, $pon ;
    ok 78, $off == 0 ;
    ok 79, $len == 2 ;
    ok 80, ! $db->db_get("red", $value) && $value eq "at" ;
    ok 81, ! $db->db_get("green", $value) && $value eq "ABuse" ;
    ok 82, ! $db->db_get("blue", $value) && $value eq "XYZa" ;
    ok 83, ! $db->db_get("new", $value) && $value eq "KLM" ;

    # now partial put
    ($pon, $off, $len) = $db->partial_set(3,2) ;
    ok 84, ! $pon ;
    ok 85, $off == 0 ;
    ok 86, $len == 0 ;
    ok 87, ! $db->db_put("red", "PPP") ;
    ok 88, ! $db->db_put("green", "Q") ;
    ok 89, ! $db->db_put("blue", "XYZ") ;
    ok 90, ! $db->db_put("new", "TU") ;

    $db->partial_clear() ;
    ok 91, ! $db->db_get("red", $value) && $value eq "at\0PPP" ;
    ok 92, ! $db->db_get("green", $value) && $value eq "ABuQ" ;
    ok 93, ! $db->db_get("blue", $value) && $value eq "XYZXYZ" ;
    ok 94, ! $db->db_get("new", $value) && $value eq "KLMTU" ;
}

{
    # partial
    # check works via tied hash 

    my $lex = new LexFile $Dfile ;
    my %hash ;
    my $value ;
    ok 95, my $env = new BerkDB::Env ;
    ok 96, my $db = tie %hash, 'BerkDB::Btree', -Filename => $Dfile,
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
    ok 97, $hash{"red"} eq "bo" ;
    ok 98, $hash{"green"} eq "ho" ;
    ok 99, $hash{"blue"}  eq "se" ;

    # do a partial get, off end of data
    $db->partial_set(3,2) ;
    ok 100, $hash{"red"} eq "t" ;
    ok 101, $hash{"green"} eq "se" ;
    ok 102, $hash{"blue"} eq "" ;

    # switch of partial mode
    $db->partial_clear() ;
    ok 103, $hash{"red"} eq "boat" ;
    ok 104, $hash{"green"} eq "house" ;
    ok 105, $hash{"blue"} eq "sea" ;

    # now partial put
    $db->partial_set(0,2) ;
    ok 106, $hash{"red"} = "" ;
    ok 107, $hash{"green"} = "AB" ;
    ok 108, $hash{"blue"} = "XYZ" ;
    ok 109, $hash{"new"} = "KLM" ;

    $db->partial_clear() ;
    ok 110, $hash{"red"} eq "at" ;
    ok 111, $hash{"green"} eq "ABuse" ;
    ok 112, $hash{"blue"} eq "XYZa" ;
    ok 113, $hash{"new"} eq "KLM" ;

    # now partial put
    $db->partial_set(3,2) ;
    ok 114, $hash{"red"} = "PPP" ;
    ok 115, $hash{"green"} = "Q" ;
    ok 116, $hash{"blue"} = "XYZ" ;
    ok 117, $hash{"new"} = "TU" ;

    $db->partial_clear() ;
    ok 118, $hash{"red"} eq "at\0PPP" ;
    ok 119, $hash{"green"} eq "ABuQ" ;
    ok 120, $hash{"blue"} eq "XYZXYZ" ;
    ok 121, $hash{"new"} eq "KLMTU" ;
}

{
    # transaction

    my $lex = new LexFile $Dfile ;
    my %hash ;
    my $value ;

    my $home = "./fred" ;
    rmtree $home if -e $home ;
    ok 122, mkdir($home, 0777) ;
    ok 123, my $env = new BerkDB::Env -Home => $home,
				     -Flags => DB_CREATE|DB_INIT_TXN|
					  	DB_INIT_MPOOL|DB_INIT_LOCK ;
    ok 124, my $txn = $env->txn_begin() ;
    ok 125, my $db1 = tie %hash, 'BerkDB::Btree', -Filename => $Dfile,
                                      	       -Flags    =>  DB_CREATE ,
					       -Env 	 => $env,
					       -Txn	 => $txn ;

    
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
    ok 126, $ret == 0 ;

    # should be able to see all the records

    ok 127, my $cursor = $db1->db_cursor() ;
    my ($k, $v) = ("", "") ;
    my $count = 0 ;
    # sequence forwards
    while ($cursor->c_get($k, $v, DB_NEXT) == 0) {
        ++ $count ;
    }
    ok 128, $count == 3 ;
    undef $cursor ;

    # now abort the transaction
    ok 129, $txn->txn_abort() == 0 ;

    # there shouldn't be any records in the database
    $count = 0 ;
    # sequence forwards
    ok 130, $cursor = $db1->db_cursor() ;
    while ($cursor->c_get($k, $v, DB_NEXT) == 0) {
        ++ $count ;
    }
    ok 131, $count == 0 ;

    undef $txn ;
    undef $cursor ;
    undef $db1 ;
    undef $env ;
    rmtree $home ;
}
