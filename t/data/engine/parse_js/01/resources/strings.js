foo({
    "key1" : "foo\\nbar",
    "key2" : "foo\\\nbar",
    "key3" : "foo\\\\nbar",

    "key4a" : "foo \"bar\"",
    "key4b" : "foo \\\"bar\"",

    "key5a" : "foo \'bar\'",
    "key5b" : "foo \\\'bar\'",

    "key6" : "foo\101bar", // \101 = 'A' (ASCII), octal form

    "key7" : "foo\x41bar", // \x41 = 'A' (ASCII), hexadecimal form

    "key8a" : "foo\u{41}bar", // \u{41} = 'A' (ASCII), hexadecimal form
    "key8b" : "foo\u{041}bar", // \u{041} = 'A' (ASCII), hexadecimal form
    "key8c" : "foo\u{0041}bar", // \u{0041} = 'A' (ASCII), hexadecimal form
    "key8d" : "foo\u{00041}bar", // \u{00041} = 'A' (ASCII), hexadecimal form

    "key9" : "foo\u0102bar", // \u0102 = 'Ă' // Unicode
    "key10" : "foo\u0466bar", // \u0466 = 'Ѧ' // Unicode
    "key11" : "foo\u{1F600}bar", // \u{1F600} = '😀' // Unicode, emoji

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
