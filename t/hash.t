#!./perl -w

# ID: %I%, %G%   

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
#        if ($Config{'extensions'} !~ /\bBerkeleyDB\b/ ) {
#            print "1..74\n";
#            exit 0;
#        }
#    }
#}

use BerkeleyDB; 
use File::Path qw(rmtree);

print "1..172\n";

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
    ok 2, $@ =~ /unknown key value\(s\) Bad Stupid/  ;

    eval ' $db = new BerkeleyDB::Hash -Env => 2 ' ;
    ok 3, $@ =~ /^Env not of type BerkeleyDB::Env/ ;

    eval ' $db = new BerkeleyDB::Hash -Txn => "fred" ' ;
    ok 4, $@ =~ /^Txn not of type BerkeleyDB::Txn/ ;

    my $obj = bless [], "main" ;
    eval ' $db = new BerkeleyDB::Hash -Env => $obj ' ;
    ok 5, $@ =~ /^Env not of type BerkeleyDB::Env/ ;
}

# Now check the interface to HASH

{
    my $lex = new LexFile $Dfile ;

    ok 6, my $db = new BerkeleyDB::Hash -Filename => $Dfile, 
				    -Flags    => DB_CREATE ;

    # Add a k/v pair
    my $value ;
    my $status ;
    ok 7, $db->db_put("some key", "some value") == 0  ;
    ok 8, $db->status() == 0 ;
    ok 9, $db->db_get("some key", $value) == 0 ;
    ok 10, $value eq "some value" ;
    ok 11, $db->db_put("key", "value") == 0  ;
    ok 12, $db->db_get("key", $value) == 0 ;
    ok 13, $value eq "value" ;
    ok 14, $db->db_del("some key") == 0 ;
    ok 15, ($status = $db->db_get("some key", $value)) == DB_NOTFOUND ;
    ok 16, $status eq "Key/data pair not found (EOF)";
    ok 17, $db->status() == DB_NOTFOUND ;
    ok 18, $db->status() eq "Key/data pair not found (EOF)";

    ok 19, $db->db_sync() == 0 ;

    # Check NOOVERWRITE will make put fail when attempting to overwrite
    # an existing record.

    ok 20, $db->db_put( 'key', 'x', DB_NOOVERWRITE) == DB_KEYEXIST ;
    ok 21, $db->status() eq "The key/data pair already exists";
    ok 22, $db->status() == DB_KEYEXIST ;

    # check that the value of the key  has not been changed by the
    # previous test
    ok 23, $db->db_get("key", $value) == 0 ;
    ok 24, $value eq "value" ;


}

{
    # Check simple env works with a hash.
    my $lex = new LexFile $Dfile ;

    ok 25, my $env = new BerkeleyDB::Env ;
    ok 26, my $db = new BerkeleyDB::Hash -Filename => $Dfile, 
				    -Env      => $env,
				    -Flags    => DB_CREATE ;

    # Add a k/v pair
    my $value ;
    ok 27, $db->db_put("some key", "some value") == 0 ;
    ok 28, $db->db_get("some key", $value) == 0 ;
    ok 29, $value eq "some value" ;
}

{
    # override default hash
    my $lex = new LexFile $Dfile ;
    my $value ;
    $::count = 0 ;
    ok 30, my $db = new BerkeleyDB::Hash -Filename => $Dfile, 
				     -Hash     => sub {  ++$::count ; length $_[0] },
				     -Flags    => DB_CREATE ;

    ok 31, $db->db_put("some key", "some value") == 0 ;
    ok 32, $db->db_get("some key", $value) == 0 ;
    ok 33, $value eq "some value" ;
    ok 34, $::count > 0 ;

}
 
{
    # cursors

    my $lex = new LexFile $Dfile ;
    my %hash ;
    my ($k, $v) ;
    ok 35, my $db = new BerkeleyDB::Hash -Filename => $Dfile, 
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
    ok 36, $ret == 0 ;

    # create the cursor
    ok 37, my $cursor = $db->db_cursor() ;

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
    ok 38, $cursor->status() == DB_NOTFOUND ;
    ok 39, $cursor->status() eq "Key/data pair not found (EOF)";
    ok 40, keys %copy == 0 ;
    ok 41, $extras == 0 ;

    # sequence backwards
    %copy = %data ;
    $extras = 0 ;
    my $status ;
    for ( $status = $cursor->c_get($k, $v, DB_LAST) ;
	  $status == 0 ;
    	  $status = $cursor->c_get($k, $v, DB_PREV)) {
        if ( $copy{$k} eq $v ) 
            { delete $copy{$k} }
	else
	    { ++ $extras }
    }
    ok 42, $status == DB_NOTFOUND ;
    ok 43, $status eq "Key/data pair not found (EOF)";
    ok 44, $cursor->status() == $status ;
    ok 45, $cursor->status() eq $status ;
    ok 46, keys %copy == 0 ;
    ok 47, $extras == 0 ;
}
 
{
    # Tied Hash interface

    my $lex = new LexFile $Dfile ;
    my %hash ;
    ok 48, tie %hash, 'BerkeleyDB::Hash', -Filename => $Dfile,
                                      -Flags    => DB_CREATE ;

    # check "each" with an empty database
    my $count = 0 ;
    while (my ($k, $v) = each %hash) {
	++ $count ;
    }
    ok 49, (tied %hash)->status() == DB_NOTFOUND ;
    ok 50, $count == 0 ;

    # Add a k/v pair
    my $value ;
    $hash{"some key"} = "some value";
    ok 51, (tied %hash)->status() == 0 ;
    ok 52, $hash{"some key"} eq "some value";
    ok 53, defined $hash{"some key"} ;
    ok 54, (tied %hash)->status() == 0 ;
    ok 55, exists $hash{"some key"} ;
    ok 56, !defined $hash{"jimmy"} ;
    ok 57, (tied %hash)->status() == DB_NOTFOUND ;
    ok 58, !exists $hash{"jimmy"} ;
    ok 59, (tied %hash)->status() == DB_NOTFOUND ;

    delete $hash{"some key"} ;
    ok 60, (tied %hash)->status() == 0 ;
    ok 61, ! defined $hash{"some key"} ;
    ok 62, (tied %hash)->status() == DB_NOTFOUND ;
    ok 63, ! exists $hash{"some key"} ;
    ok 64, (tied %hash)->status() == DB_NOTFOUND ;

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
    ok 65, $count == 3 ;
    ok 66, $keys == 1011 ;
    ok 67, $values == 2022 ;

    # now clear the hash
    %hash = () ;
    ok 68, keys %hash == 0 ;

    untie %hash ;
}

{
    # in-memory file

    my $lex = new LexFile $Dfile ;
    my %hash ;
    my $fd ;
    my $value ;
    ok 69, my $db = tie %hash, 'BerkeleyDB::Hash' ;

    ok 70, $db->db_put("some key", "some value") == 0  ;
    ok 71, $db->db_get("some key", $value) == 0 ;
    ok 72, $value eq "some value" ;

}
 
{
    # partial
    # check works via API

    my $lex = new LexFile $Dfile ;
    my %hash ;
    my $value ;
    ok 73, my $env = new BerkeleyDB::Env ;
    ok 74, my $db = tie %hash, 'BerkeleyDB::Hash', -Filename => $Dfile,
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
    ok 75, $ret == 0 ;


    # do a partial get
    my($pon, $off, $len) = $db->partial_set(0,2) ;
    ok 76, $pon == 0 && $off == 0 && $len == 0 ;
    ok 77, ! $db->db_get("red", $value) && $value eq "bo" ;
    ok 78, ! $db->db_get("green", $value) && $value eq "ho" ;
    ok 79, ! $db->db_get("blue", $value) && $value eq "se" ;

    # do a partial get, off end of data
    ($pon, $off, $len) = $db->partial_set(3,2) ;
    ok 80, $pon ;
    ok 81, $off == 0 ;
    ok 82, $len == 2 ;
    ok 83, ! $db->db_get("red", $value) && $value eq "t" ;
    ok 84, ! $db->db_get("green", $value) && $value eq "se" ;
    ok 85, ! $db->db_get("blue", $value) && $value eq "" ;

    # switch of partial mode
    ($pon, $off, $len) = $db->partial_clear() ;
    ok 86, $pon ;
    ok 87, $off == 3 ;
    ok 88, $len == 2 ;
    ok 89, ! $db->db_get("red", $value) && $value eq "boat" ;
    ok 90, ! $db->db_get("green", $value) && $value eq "house" ;
    ok 91, ! $db->db_get("blue", $value) && $value eq "sea" ;

    # now partial put
    ($pon, $off, $len) = $db->partial_set(0,2) ;
    ok 92, ! $pon ;
    ok 93, $off == 0 ;
    ok 94, $len == 0 ;
    ok 95, ! $db->db_put("red", "") ;
    ok 96, ! $db->db_put("green", "AB") ;
    ok 97, ! $db->db_put("blue", "XYZ") ;
    ok 98, ! $db->db_put("new", "KLM") ;

    $db->partial_clear() ;
    ok 99, ! $db->db_get("red", $value) && $value eq "at" ;
    ok 100, ! $db->db_get("green", $value) && $value eq "ABuse" ;
    ok 101, ! $db->db_get("blue", $value) && $value eq "XYZa" ;
    ok 102, ! $db->db_get("new", $value) && $value eq "KLM" ;

    # now partial put
    $db->partial_set(3,2) ;
    ok 103, ! $db->db_put("red", "PPP") ;
    ok 104, ! $db->db_put("green", "Q") ;
    ok 105, ! $db->db_put("blue", "XYZ") ;
    ok 106, ! $db->db_put("new", "--") ;

    ($pon, $off, $len) = $db->partial_clear() ;
    ok 107, $pon ;
    ok 108, $off == 3 ;
    ok 109, $len == 2 ;
    ok 110, ! $db->db_get("red", $value) && $value eq "at\0PPP" ;
    ok 111, ! $db->db_get("green", $value) && $value eq "ABuQ" ;
    ok 112, ! $db->db_get("blue", $value) && $value eq "XYZXYZ" ;
    ok 113, ! $db->db_get("new", $value) && $value eq "KLM--" ;
}

{
    # partial
    # check works via tied hash 

    my $lex = new LexFile $Dfile ;
    my %hash ;
    my $value ;
    ok 114, my $env = new BerkeleyDB::Env ;
    ok 115, my $db = tie %hash, 'BerkeleyDB::Hash', -Filename => $Dfile,
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
    ok 116, $hash{"red"} eq "bo" ;
    ok 117, $hash{"green"} eq "ho" ;
    ok 118, $hash{"blue"}  eq "se" ;

    # do a partial get, off end of data
    $db->partial_set(3,2) ;
    ok 119, $hash{"red"} eq "t" ;
    ok 120, $hash{"green"} eq "se" ;
    ok 121, $hash{"blue"} eq "" ;

    # switch of partial mode
    $db->partial_clear() ;
    ok 122, $hash{"red"} eq "boat" ;
    ok 123, $hash{"green"} eq "house" ;
    ok 124, $hash{"blue"} eq "sea" ;

    # now partial put
    $db->partial_set(0,2) ;
    ok 125, $hash{"red"} = "" ;
    ok 126, $hash{"green"} = "AB" ;
    ok 127, $hash{"blue"} = "XYZ" ;
    ok 128, $hash{"new"} = "KLM" ;

    $db->partial_clear() ;
    ok 129, $hash{"red"} eq "at" ;
    ok 130, $hash{"green"} eq "ABuse" ;
    ok 131, $hash{"blue"} eq "XYZa" ;
    ok 132, $hash{"new"} eq "KLM" ;

    # now partial put
    $db->partial_set(3,2) ;
    ok 133, $hash{"red"} = "PPP" ;
    ok 134, $hash{"green"} = "Q" ;
    ok 135, $hash{"blue"} = "XYZ" ;
    ok 136, $hash{"new"} = "TU" ;

    $db->partial_clear() ;
    ok 137, $hash{"red"} eq "at\0PPP" ;
    ok 138, $hash{"green"} eq "ABuQ" ;
    ok 139, $hash{"blue"} eq "XYZXYZ" ;
    ok 140, $hash{"new"} eq "KLMTU" ;
}

{
    # transaction

    my $lex = new LexFile $Dfile ;
    my %hash ;
    my $value ;

    my $home = "./fred" ;
    rmtree $home if -e $home ;
    ok 141, mkdir($home, 0777) ;
    ok 142, my $env = new BerkeleyDB::Env -Home => $home,
				     -Flags => DB_CREATE|DB_INIT_TXN|
					  	DB_INIT_MPOOL|DB_INIT_LOCK ;
    ok 143, my $txn_mgr = $env->TxnMgr() ;
    ok 144, my $txn = $txn_mgr->txn_begin() ;
    ok 145, my $db1 = tie %hash, 'BerkeleyDB::Hash', -Filename => $Dfile,
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
    ok 146, $ret == 0 ;

    # should be able to see all the records

    ok 147, my $cursor = $db1->db_cursor() ;
    my ($k, $v) = ("", "") ;
    my $count = 0 ;
    # sequence forwards
    while ($cursor->c_get($k, $v, DB_NEXT) == 0) {
        ++ $count ;
    }
    ok 148, $count == 3 ;
    undef $cursor ;

    # now abort the transaction
    ok 149, $txn->txn_abort() == 0 ;

    # there shouldn't be any records in the database
    $count = 0 ;
    # sequence forwards
    ok 150, $cursor = $db1->db_cursor() ;
    while ($cursor->c_get($k, $v, DB_NEXT) == 0) {
        ++ $count ;
    }
    ok 151, $count == 0 ;

    undef $txn ;
    undef $cursor ;
    undef $db1 ;
    #undef $txn_mgr ;
    undef $env ;
    untie %hash ;
    rmtree $home ;
}


{
    # DB_DUP

    my $lex = new LexFile $Dfile ;
    my %hash ;
    ok 152, my $db = tie %hash, 'BerkeleyDB::Hash', -Filename => $Dfile,
				      -Property  => DB_DUP,
                                      -Flags    => DB_CREATE ;

    $hash{'Wall'} = 'Larry' ;
    $hash{'Wall'} = 'Stone' ;
    $hash{'Smith'} = 'John' ;
    $hash{'Wall'} = 'Brick' ;
    $hash{'Wall'} = 'Brick' ;
    $hash{'mouse'} = 'mickey' ;

    ok 153, keys %hash == 6 ;

    # create a cursor
    ok 154, my $cursor = $db->db_cursor() ;

    my $key = "Wall" ;
    my $value ;
    ok 155, $cursor->c_get($key, $value, DB_SET) == 0 ;
    ok 156, $key eq "Wall" && $value eq "Larry" ;
    ok 157, $cursor->c_get($key, $value, DB_NEXT) == 0 ;
    ok 158, $key eq "Wall" && $value eq "Stone" ;
    ok 159, $cursor->c_get($key, $value, DB_NEXT) == 0 ;
    ok 160, $key eq "Wall" && $value eq "Brick" ;
    ok 161, $cursor->c_get($key, $value, DB_NEXT) == 0 ;
    ok 162, $key eq "Wall" && $value eq "Brick" ;

    #my $ref = $db->db_stat() ; 
    #ok 143, $ref->{bt_flags} | DB_DUP ;

    undef $db ;
    undef $cursor ;
    untie %hash ;

}

{
   # sub-class test

   package Another ;

   use strict ;

   open(FILE, ">SubDB.pm") or die "Cannot open SubDB.pm: $!\n" ;
   print FILE <<'EOM' ;

   package SubDB ;

   use strict ;
   use vars qw( @ISA @EXPORT) ;

   require Exporter ;
   use BerkeleyDB;
   @ISA=qw(BerkeleyDB::Hash);
   @EXPORT = @BerkeleyDB::EXPORT ;

   sub db_put { 
	my $self = shift ;
        my $key = shift ;
        my $value = shift ;
        $self->SUPER::db_put($key, $value * 3) ;
   }

   sub db_get { 
	my $self = shift ;
        $self->SUPER::db_get($_[0], $_[1]) ;
	$_[1] -= 2 ;
   }

   sub A_new_method
   {
	my $self = shift ;
        my $key = shift ;
        my $value = $self->FETCH($key) ;
	return "[[$value]]" ;
   }

   1 ;
EOM

    close FILE ;

    BEGIN { push @INC, '.'; }    
    eval 'use SubDB ; ';
    main::ok 163, $@ eq "" ;
    my %h ;
    my $X ;
    eval '
	$X = tie(%h, "SubDB", -Filename => "dbhash.tmp", 
			-Flags => DB_CREATE,
			-Mode => 0640 );
	' ;

    main::ok 164, $@ eq "" ;

    my $ret = eval '$h{"fred"} = 3 ; return $h{"fred"} ' ;
    main::ok 165, $@ eq "" ;
    main::ok 166, $ret == 7 ;

    my $value = 0;
    $ret = eval '$X->db_put("joe", 4) ; $X->db_get("joe", $value) ; return $value' ;
    main::ok 167, $@ eq "" ;
    main::ok 168, $ret == 10 ;

    $ret = eval ' DB_NEXT eq main::DB_NEXT ' ;
    main::ok 169, $@ eq ""  ;
    main::ok 170, $ret == 1 ;

    $ret = eval '$X->A_new_method("joe") ' ;
    main::ok 171, $@ eq "" ;
    main::ok 172, $ret eq "[[10]]" ;

    unlink "SubDB.pm", "dbhash.tmp" ;

}
