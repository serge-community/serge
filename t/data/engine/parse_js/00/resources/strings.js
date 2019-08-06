foo({
    // test keys and values surrounded by double quotes
    "key1" : "value1",
    "key2": "value\\2",
    "key3" :"value \"3\"",
    "key4" : "value\\\"4\"",

    // keys identical to values are not extracted
    // as hints
    "value1" : "value1",

    // line comments are extracted as hints as well
    "key5" : "value5", // this is a comment "with quotes" and forward slashes: // test
    "key6" : "value6",//        comment 6
    "key7" : "value7",//comment 7
    "key8" : "value8",          //comment 8
});
