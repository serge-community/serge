foo({
    // supported are only keys and values in double quotes
    "key1" : "value1",
    "key2": "value\\2",
    "key3" :"value \"3\"",
    "key4" : "value\\\"4\"",

    // bad strings
    "bad_key1" : 'bad_value1',
    'bad_key2': "bad_value2",
    'bad_key3' :'bad_value3'
});
