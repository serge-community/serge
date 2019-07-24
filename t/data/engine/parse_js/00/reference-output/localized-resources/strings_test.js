foo({
    // supported are only keys and values in double quotes
    "key1" : "\u1e7d\u00e1\u013c\u0169\u01131",
    "key2": "\u1e7d\u00e1\u013c\u0169\u0113\\2",
    "key3" :"\u1e7d\u00e1\u013c\u0169\u0113 \"3\"",
    "key4" : "\u1e7d\u00e1\u013c\u0169\u0113\\\"4\"",

    // keys identical to values are not extracted
    // as hints
    "value1" : "\u1e7d\u00e1\u013c\u0169\u01131",

    // line comments are extracted as hints as well
    "key5" : "\u1e7d\u00e1\u013c\u0169\u01131", // this is a comment "with quotes" and forward slashes: // test

    // bad strings
    "bad_key1" : 'bad_value1',
    'bad_key2': "bad_value2",
    'bad_key3' :'bad_value3'
});
