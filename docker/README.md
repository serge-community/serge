# Serge

**Serge** _(String Extraction and Resource Generation Engine)_ helps you
set up a seamless continuous localization process for your software
in a fully automated and scalable fashion. It allows developers to
concentrate on maintaining resource files in just one language (e.g. English),
and will take care of keeping all localized resources in sync and translated.

Serge is developed and maintained by Evernote, where it works non-stop
to help deliver various Evernote clients, websites and marketing materials
in 25 languages.

### Learn more at [serge.io &rarr;](https://serge.io/docs/) or [the GitHub repository &rarr;](https://github.com/evernote/serge)

## Installation

You need to run `docker` from the parent (root) project directory:

    $ docker build --no-cache -t serge -f docker/Dockerfile .

This will create an image called `serge`.

## Organizing your data

Serge is expected to run against configuration files, data directories and a database (typically an SQLite database). So this data needs to be exposed to Serge via a volume. The recommended solution would be to create the following folder structure on the host machine:

    /var
        /serge
            /data
                /db                      <= Serge database file will be stored here
                /vcs                     <= directory for source code checkouts
                /ts                      <= directory for generated translation interchange files
                /configs                 <= folder with Serge configuration files
                        config1.serge
                        config2.serge
                        ...

## Running Serge

Inside the Docker image, the data volume is defined as `/data`. If you have a directory structure on your host machine as suggested above, under `/var/serge/data`, Serge can be run as follows:

    $ docker run -v /var/serge/data:/data serge [parameters]

Example:

    $ docker run -v /var/serge/data:/data serge localize /data/configs/config1.serge

## Creating a wrapper

    $ sudo sh -c 'echo "#!/bin/sh\ndocker run -v /var/serge/data:/data serge \"\$@\"" >/usr/local/bin/serge'

    $ sudo chmod +x /usr/local/bin/serge

Assuming you're using a Unix-like OS, the commands above will create a helper executable script, `/usr/local/bin/serge`, which you can then simply run as `serge`, instead of having to type `docker run -v /var/serge/data:/data serge`.
