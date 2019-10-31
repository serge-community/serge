Test for bare `true` and `false` in keys and values.

YAML parser allows such bare strings both in keys and values,
but it itself has some issues parsing YAML files with aliases.

YAML::XS, the parser used in Serge, allows bare booleans
only as values, but not as key names.

A hacky solution would be to rename keys before parsing,
and restore them afterwards.
