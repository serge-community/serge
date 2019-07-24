# Here we define a job template (common parameters) that will be reused
# across all jobs in the generated configuration file.
# Certain job parameters (like job ID and paths) will be overridden
# in each feature branch job.
job-template
{
    name                          JSON file processing ('master' branch)
    id                            myproject.json.master # master job id
    db_namespace                  myproject

    destination_languages         es pt-br ru

    source_dir                    ./data/myproject/master/res/en
    output_file_path              ./data/myproject/master/res/%LANG%/%FILE%

    source_match                  \.json$

    parser
    {
        plugin                    parse_json_keyvalue
    }

    ts_file_path                  ./po/myproject/%LOCALE%/%FILE%.po

    callback_plugins
    {
        :feature_branch
        {
            plugin                feature_branch

            data
            {
                master_job        myproject.json.master  # this must match your master job id
            }
        }
    }
}

# This block will be included conditionally
# for all branches except the `release/` ones (see myproject.cfg).
# This allows one to skip saving localized files in non-release branches
# (but still gather from them strings for translation).
skip-saving-localized-files
{
    callback_plugins
    {
        :skip-saving-localized-files
        {
            plugin                  process_if
            phase                   can_generate_localized_file

            data
            {
                if
                {
                    lang_matches    .

                    then
                    {
                        return      NO
                    }
                }
            }
        }
    }
}
