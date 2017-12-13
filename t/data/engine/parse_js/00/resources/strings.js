foo({
    // supported are only keys and values in double quotes
    "key1" : "value1",
    "key2": "value\\2",
    "key3" :"value \"3\"",
    "key4" : "value\\\"4\"",

    // keys identical to values are not extracted
    // as hints
    "value1" : "value1",

    // line comments are extracted as hints as well
    "key5" : "value1", // this is a comment "with quotes" and forward slashes: // test

    // bad strings
    "bad_key1" : 'bad_value1',
    'bad_key2': "bad_value2",
    'bad_key3' :'bad_value3'
});
