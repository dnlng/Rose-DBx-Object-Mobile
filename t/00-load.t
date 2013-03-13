#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Rose::DBx::Object::Mobile' ) || print "Bail out!\n";
}

diag( "Testing Rose::DBx::Object::Mobile $Rose::DBx::Object::Mobile::VERSION, Perl $], $^X" );
