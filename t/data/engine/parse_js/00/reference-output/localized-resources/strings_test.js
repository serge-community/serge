foo({
    // test keys and values surrounded by double quotes
    "key1" : "\u1e7d\u00e1\u013c\u0169\u01131",
    "key2": "\u1e7d\u00e1\u013c\u0169\u0113\\2",
    "key3" :"\u1e7d\u00e1\u013c\u0169\u0113 \"3\"",
    "key4" : "\u1e7d\u00e1\u013c\u0169\u0113\\\"4\"",

    // keys identical to values are not extracted
    // as hints
    "value1" : "\u1e7d\u00e1\u013c\u0169\u01131",

    // line comments are extracted as hints as well
    "key5" : "\u1e7d\u00e1\u013c\u0169\u01135", // this is a comment "with quotes" and forward slashes: // test
    "key6" : "\u1e7d\u00e1\u013c\u0169\u01136",//        comment 6
    "key7" : "\u1e7d\u00e1\u013c\u0169\u01137",//comment 7
    "key8" : "\u1e7d\u00e1\u013c\u0169\u01138",          //comment 8
});
