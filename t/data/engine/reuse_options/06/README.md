Test for the 'reuse_fuzzy' option set to NO: for two translation variants of
a certain string in the database where the first one has a fuzzy flag, the fuzzy one
will be ignored in find_best_translation(), which will allow to reuse the first
translation even with 'reuse_uncertain' option set to NO, since now there will
be only one qualifying, i.e. not fuzzy, translation.
