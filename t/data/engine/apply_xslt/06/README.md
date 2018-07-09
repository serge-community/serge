Test for 'apply_xslt' plugin, 'before_save_localized_file' phase for XML-unsafe chars

Uses an identity transform (copies the source data into the destination data without change), so that only xml parsing issues should be visible.