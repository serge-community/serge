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

## Running Serge

    $ docker run serge [parameters]

## Creating a wrapper

    $ sudo echo -e "#!/bin/sh\ndocker run serge \"\$@\"" >/usr/local/bin/serge

    $ sudo chmod +x /usr/local/bin/serge

Assuming you're using a Unix-like OS, the commands above will create a helper executable script, `/usr/local/bin/serge`, which you can then simply run as `serge` from any directory, instead of having to type `docker run serge`.
