foo({
    "key1" : "foo\\nbar",
    "key2" : "foo\\\nbar",
    "key3" : "foo\\\\nbar",

    "key4a" : "foo \"bar\"",
    "key4b" : "foo \\\"bar\"",

    "key5a" : "foo \'bar\'",
    "key5b" : "foo \\\'bar\'",

    "key6" : "fooAbar", // \101 = 'A' (ASCII), octal form

    "key7" : "fooAbar", // \x41 = 'A' (ASCII), hexadecimal form

    "key8a" : "fooAbar", // \u{41} = 'A' (ASCII), hexadecimal form
    "key8b" : "fooAbar", // \u{041} = 'A' (ASCII), hexadecimal form
    "key8c" : "fooAbar", // \u{0041} = 'A' (ASCII), hexadecimal form
    "key8d" : "fooAbar", // \u{00041} = 'A' (ASCII), hexadecimal form

    "key9" : "fooĂbar", // \u0102 = 'Ă' // Unicode
    "key10" : "fooѦbar", // \u0466 = 'Ѧ' // Unicode
    "key11" : "foo😀bar", // \u{1F600} = '😀' // Unicode, emoji

    "key12a" : "foo\bbar",
    "key12b" : "foo\b\bbar",

    "key13a" : "foo\fbar",
    "key13b" : "foo\f\fbar",

    "key14a" : "foo\nbar",
    "key14b" : "foo\n\nbar",

    "key15a" : "foo\rbar",
    "key15b" : "foo\r\rbar",

    "key16a" : "foo\tbar",
    "key16b" : "foo\t\tbar",

    "key17a" : "foo\vbar",
    "key17b" : "foo\v\vbar",
});
