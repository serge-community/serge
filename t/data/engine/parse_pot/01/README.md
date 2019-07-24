Test for .mo file compilation.

Generated binary .mo files should be identical to the ones produced
by running the following command:

    msgfmt infile.po -o outfile.mo -f --endianness=big --no-hash

Also, to examine the generated .mo files, one can decompile them
back into .po as follows:

    msgunfmt generated.mo -o decompiled.po

`msgfmt` and `msgunfmt` are a part of GNU gettext utilities:
https://www.gnu.org/software/gettext/manual/html_node/index.html
