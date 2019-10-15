#!/usr/bin/env perl

use strict;

BEGIN {
    use Cwd qw(abs_path);
    use File::Basename;
    use File::Spec::Functions qw(catfile);
    map { unshift(@INC, catfile(dirname(abs_path(__FILE__)), $_)) } qw(../lib);
}

use Test::More;

use Serge::Util qw(wrap);

my $tests = [
    {
        source =>
            "",
        width => 10,
        result => [
            ""
        ]
    },
    {
        source =>
            "\n",
        width => 10,
        result => [
            "\n"
        ]
    },
    {
        source =>
            "\n\n\n",
        width => 10,
        result => [
            "\n",
            "\n",
            "\n"
        ]
    },
    {
        source =>
            "A short string",
        width => 10,
        result => [
            "A short ",
            "string"
        ]
    },
    {
        source =>
            "A short string",
        width => 50,
        result => [
            "A short string"
        ]
    },
    {
        source =>
            "Another string\nwith an explicit line break",
        width => 20,
        result => [
            "Another string\n",
            "with an explicit ",
            "line break"
        ]
    },
    {
        source =>
            "Another string\nwith an explicit line break",
        width => 50,
        result => [
            "Another string\n",
            "with an explicit line break"
        ]
    },
    {
        source =>
            "A string ending with a newline\n",
        width => 20,
        result => [
            "A string ending ",
            "with a newline\n"
        ]
    },
    {
        source =>
            "A string ending with a newline\n",
        width => 50,
        result => [
            "A string ending with a newline\n"
        ]
    },
    {
        source =>
            "Some long string that should be word-wrapped at 50 characters.\n".
            "123456789012345678901234567890123456789012345678901234567890".
            "123456789012345678901234567890123456789012345678901234567890",
        width => 50,
        result => [
            "Some long string that should be word-wrapped at ",
            "50 characters.\n",
            "12345678901234567890123456789012345678901234567890",
            "12345678901234567890123456789012345678901234567890",
            "12345678901234567890"
        ]
    },
    {
        source =>
            "Some long string that should be word-wrapped at 80 characters.\n".
            "123456789012345678901234567890123456789012345678901234567890".
            "123456789012345678901234567890123456789012345678901234567890",
        width => 80,
        result => [
            "Some long string that should be word-wrapped at 80 characters.\n",
            "12345678901234567890123456789012345678901234567890123456789012345678901234567890",
            "1234567890123456789012345678901234567890"
        ]
    },
    {
        source =>
            "A string with a lot of whitespace                            ".
            "                                                             ".
            "                                                             ",
        width => 50,
        result => [
            "A string with a lot of ",
            "whitespace                                        ",
            "                                                  ",
            "                                                  ",
            "          "
        ]
    }
];

foreach my $test (@$tests) {
    subtest "Line length: $test->{width}, source: [$test->{source}]" => sub {
        my @lines = wrap($test->{source}, $test->{width});
        my $glued = join('', @lines);
        ok(scalar(@lines) == scalar(@{$test->{result}}), "number of resulting lines");

        my $n = scalar(@lines);
        for (my $i = 0; $i < $n; $i++) {
            ok($lines[$i] eq $test->{result}->[$i], "line $i");
        }

        ok($glued eq $test->{source}, "source and glued strings should match");
    }
}

done_testing();