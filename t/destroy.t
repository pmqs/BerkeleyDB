#!./perl -w

use strict ;

use lib 't' ;
use BerkeleyDB;
use util ;
use Test::More;

plan tests => 15;

my $Dfile = "dbhash.tmp";
my $home = "./fred" ;

umask(0);

{
    # let object destruction kill everything

    my $lex = new LexFile $Dfile ;
    my %hash ;
    my $value ;

    ok my $lexD = new LexDir($home) ;
    ok my $env = new BerkeleyDB::Env -Home => $home,  @StdErrFile,
				     -Flags => DB_CREATE|DB_INIT_TXN|
					  	DB_INIT_MPOOL|DB_INIT_LOCK ;
    ok my $txn = $env->txn_begin() ;
    ok my $db1 = tie %hash, 'BerkeleyDB::Hash', -Filename => $Dfile,
                                      	       	-Flags     => DB_CREATE ,
					       	-Env 	   => $env,
					    	-Txn	   => $txn  ;

    ok $txn->txn_commit() == 0 ;
    ok $txn = $env->txn_begin() ;
    $db1->Txn($txn);

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
    ok $ret == 0 ;

    # should be able to see all the records

    ok my $cursor = $db1->db_cursor() ;
    my ($k, $v) = ("", "") ;
    my $count = 0 ;
    # sequence forwards
    while ($cursor->c_get($k, $v, DB_NEXT) == 0) {
        ++ $count ;
    }
    is $count, 3 ;
    undef $cursor ;

    # now abort the transaction
    ok $txn->txn_abort() == 0 ;

    # there shouldn't be any records in the database
    $count = 0 ;
    # sequence forwards
    ok $cursor = $db1->db_cursor() ;
    while ($cursor->c_get($k, $v, DB_NEXT) == 0) {
        ++ $count ;
    }
    is $count, 0 ;

    #undef $txn ;
    #undef $cursor ;
    #undef $db1 ;
    #undef $env ;
    #untie %hash ;

}

{
    my $lex = new LexFile $Dfile ;
    my %hash ;
    my $cursor ;
    my ($k, $v) = ("", "") ;
    ok my $db1 = tie %hash, 'BerkeleyDB::Hash',
		-Filename	=> $Dfile,
               	-Flags		=> DB_CREATE ;
    my $count = 0 ;
    # sequence forwards
    ok $cursor = $db1->db_cursor() ;
    while ($cursor->c_get($k, $v, DB_NEXT) == 0) {
        ++ $count ;
    }
    is $count, 0 ;
}
