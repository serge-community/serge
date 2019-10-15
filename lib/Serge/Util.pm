package Serge::Util;

use strict;

no warnings qw(uninitialized);

our @ISA = qw(Exporter);

our @EXPORT = qw(
    combine_and
    combine_or
    abspath
    normalize_path
    get_flag_pos
    is_flag_set
    set_flag
    remove_flag
    generate_key
    generate_hash
    locale_from_lang
    subst_macros
    normalize_strref
    escape_strref
    unescape_strref
    encode
    po_is_msgid_plural
    po_serialize_msgid
    po_serialize_msgstr
    glue_plural_string
    split_plural_string
    po_wrap
    read_and_normalize_file
    file_mtime
    remove_blank_entries
);

our @EXPORT_OK = qw(
    culture_from_lang
    full_locale_from_lang
    langname
    locale_android
    locale_iphone
    langname_iphone
    subst_env_var
    subst_macros_strref
    xml_escape_strref
    xml_unescape_strref
    wrap
    set_flags
    remove_flags
);

use Digest::MD5 qw(md5_hex);
use Encode qw(encode_utf8);
use Encode::Guess;
use File::Spec::Functions qw(rel2abs);

use Serge::Util::LangID;

our $PO_LINE_LENGTH = 76; # used to wrap long lines in .po files, value is the same as in Pootle

our $UNIT_SEPARATOR = "\x1f"; # ASCII "Unit Separator" character, used to delimit plural forms in a string

# A hash of legacy locale names used in Mac/iPhone resource folder naming.
# For other languages, a locale code will be used (e.g. 'fi' or 'pt_BR')

my $APPLE_LEGACY_LOCALE_NAMES = {
    'en' => 'English',
    'fr' => 'French',
    'de' => 'German',
    'it' => 'Italian',
    'ja' => 'Japanese',
    'pl' => 'Polish',
    'ru' => 'Russian',
    'es' => 'Spanish',
    'sv' => 'Swedish',
};

# A hash of locale name that need to be changed specifically for iPhone

my $APPLE_IPHONE_LOCALE_REWRITE = {
    'pt' => 'pt_PT',
    'pt_BR' => 'pt',
};

# return 1 if all items in the provided array evaluate to true; otherwise return 0
sub combine_and {
    my $result = scalar(@_) > 0;
    map { $result &&= $_ } @_;
    return $result ? 1 : 0;
}

# return 1 if any item in the provided array evaluates to true; otherwise return 0
sub combine_or {
    my $result = 0;
    map { $result ||= $_ } @_;
    return $result ? 1 : 0;
}

sub abspath {
    my ($root, $path) = @_;
    $path = rel2abs($path, $root);
    $path =~ s/\\/\//sg; # always use forward slash
    return $path;
}

sub normalize_path {
    my ($path) = @_;
    $path =~ s/\\/\//g; # use forward slashes
    $path =~ s/\/\//\//g; # remove double slashes
    $path =~ s/\/+$//g; # remove slashes at the end of the path
    return $path;
}

sub get_flag_pos {
    my ($flagsref, $name) = @_;

    my $i = -1;
    foreach my $flag (@$flagsref) {
        $i++;
        return $i if ($flag eq $name);
    }

    return -1;
}

sub is_flag_set {
    return (get_flag_pos(@_) >= 0);
}

sub set_flag {
    my ($flagsref, $name) = @_;
    push @$flagsref, $name unless is_flag_set($flagsref, $name);
}

sub set_flags {
    my ($flagsref, @list) = @_;
    map { set_flag($flagsref, $_) } @list;
}

sub remove_flag {
    my ($flagsref, $name) = @_;
    my $i = get_flag_pos($flagsref, $name);
    return if $i == -1;
    splice @$flagsref, $i, 1;
}

sub remove_flags {
    my ($flagsref, @list) = @_;
    map { remove_flag($flagsref, $_) } @list;
}

sub generate_key {
    my ($str, $context) = @_;

    return md5_hex(encode_utf8($str."\001".$context));
}

sub generate_hash {
    return md5_hex(encode_utf8(join("\001", @_)));
}

sub locale_from_lang {
    my $locale = shift;
    $locale =~ s/(-.+?)(-.+)?$/uc($1).$2/e; # convert e.g. 'pt-br-Whatever' to 'pt-BR-Whatever'
    $locale =~ s/-/_/g;
    return $locale;
}

sub culture_from_lang {
    my $culture = shift;
    $culture =~ s/(-.+?)(-.+)?$/uc($1).$2/e; # convert e.g. 'pt-br-Whatever' to 'pt-BR-Whatever'
    if ($culture =~ m/^\w+$/) { # just language
        my $suffix = $culture;
        $suffix = 'US' if ($suffix eq 'en'); # en-US
        $suffix = 'JP' if ($suffix eq 'ja'); # ja-JP
        $suffix = 'SE' if ($suffix eq 'sv'); # sv-SE
        $suffix = 'CN' if ($suffix eq 'zh'); # zh-CN // Simplified Chinese
        $suffix = 'KR' if ($suffix eq 'ko'); # ko-KR
        $suffix = 'DK' if ($suffix eq 'da'); # da-DK
        $suffix = 'RS' if ($suffix eq 'sr'); # sr-RS // Serbian (Cyrillic)
        $suffix = 'RS' if ($suffix eq 'sh'); # sh-RS // Serbian (Latin)
        $suffix = 'GR' if ($suffix eq 'el'); # el-GR
        $suffix = 'CZ' if ($suffix eq 'cs'); # cs-CZ
        $suffix = 'NO' if ($suffix eq 'nb'); # nb-NO // Norwegian Bokmal
        $suffix = 'NO' if ($suffix eq 'nn'); # nn-NO // Norwegian Nynorsk
        $suffix = 'ES' if ($suffix eq 'ca'); # ca-ES
        $suffix = 'EE' if ($suffix eq 'et'); # et-EE // Estonian
        $suffix = 'GE' if ($suffix eq 'ka'); # ka-GE // Georgian
        $suffix = 'IN' if ($suffix eq 'te'); # te-IN // Telugu
        $suffix = 'IL' if ($suffix eq 'he'); # he-IL // Hebrew
        $suffix = 'AE' if ($suffix eq 'ar'); # ar-AE // Arabic (U.A.E.)
        $suffix = 'ES' if ($suffix eq 'gl'); # gl-ES // Galician
        $suffix = 'UA' if ($suffix eq 'uk'); # uk-UA // Ukrainian
        $suffix = 'VN' if ($suffix eq 'vi'); # vi-VN // Vietnamese
        $suffix = 'MY' if ($suffix eq 'ms'); # ms-MY // Malay
        $culture .= '-'.uc($suffix); # convert e.g. 'ru' to 'ru-RU'
    }
    return $culture;
}

sub full_locale_from_lang {
    my $culture = culture_from_lang(shift);
    $culture =~ s/-/_/g;
    return $culture;
}

sub langname {
    my $lang = shift;

    return exists $APPLE_LEGACY_LOCALE_NAMES->{$lang} ?
        $APPLE_LEGACY_LOCALE_NAMES->{$lang} : locale_from_lang($lang);
}

sub locale_android {
    my $locale = shift;
    $locale =~ s/-(.+?)(-.+)?$/'-r'.uc($1).$2/e; # convert e.g. 'pt-br' to 'pt-rBR'
    return $locale;
}

sub locale_iphone {
    my $locale = locale_from_lang(shift);
    return exists $APPLE_IPHONE_LOCALE_REWRITE->{$locale} ?
        $APPLE_IPHONE_LOCALE_REWRITE->{$locale} : $locale;
}

sub langname_iphone {
    my $langname = langname(shift);
    return exists $APPLE_IPHONE_LOCALE_REWRITE->{$langname} ?
        $APPLE_IPHONE_LOCALE_REWRITE->{$langname} : $langname;
}

sub subst_env_var {
    my $name = shift;
    die "'$name' environment variable not defined\n" unless exists $ENV{$name};
    return $ENV{$name};
}

sub subst_macros_strref {
    my ($strref, $file, $lang, $source_lang) = @_;

    $$strref =~ s/%ENV:(\w+)%/subst_env_var($1)/ge;

    if ($file) {
        my $path = '';
        my $fname = $file;
        if ($fname =~ m/^(.+[\\\/])(.+?)$/) {
            $path = $1;
            $fname = $2;
        }

        # splitting the filename using the leftmost dot

        my $lname = $fname;
        my $lext;
        if ($lname =~ m/^(.+?)\.(.+)$/) {
            $lname = $1;
            $lext = $2;
        }

        # splitting the filename using the rightmost dot

        my $name = $fname;
        my $ext;
        if ($name =~ m/^(.+)\.(.+?)$/) {
            $name = $1;
            $ext = $2;
        }

        $$strref =~ s/%FILE%/$file/ge;   # full file name with path
        $$strref =~ s/%PATH%/$path/ge;   # just directory with trailing delimiter
        $$strref =~ s/%NAME%/$name/ge;   # file name with no path and no extension
        $$strref =~ s/%EXT%/$ext/ge;     # extension
        $$strref =~ s/%LNAME%/$lname/ge;
        $$strref =~ s/%LEXT%/$lext/ge;

        # stripping the locale/culture-specific suffix from %NAME% and %LNAME%
        # e.g. myfile_en => myfile (if the source language is 'en')

        if ($source_lang) {
            my $source_locale = locale_from_lang($source_lang);
            my $source_culture = culture_from_lang($source_lang);

            my $name_nolocale = $name;
            $name_nolocale =~ s/_(\Q$source_locale\E|\Q$source_culture\E)$//i;
            $$strref =~ s/%NAME:NOLOCALE%/$name_nolocale/ge;

            my $lname_nolocale = $lname;
            $lname_nolocale =~ s/_(\Q$source_locale\E|\Q$source_culture\E)$//i;
            $$strref =~ s/%LNAME:NOLOCALE%/$lname_nolocale/ge;
        }

        # now split the name further into name and extension parts
        # (to be able to address files with double extensions like `file.ext1.ext2')

        $lname = $name;
        $lext = '';
        if ($lname =~ m/^(.+?)\.(.+)$/) {
            $lname = $1;
            $lext = $2;
        }

        $ext = '';
        if ($name =~ m/^(.+)\.(.+?)$/) {
            $name = $1;
            $ext = $2;
        }

        $$strref =~ s/%NAME:NAME%/$name/ge;
        $$strref =~ s/%NAME:EXT%/$ext/ge;
        $$strref =~ s/%NAME:LNAME%/$lname/ge;
        $$strref =~ s/%NAME:LEXT%/$lext/ge;
    }

    if ($lang) {
        my $locale = locale_from_lang($lang);
        my $full_locale = full_locale_from_lang($lang);
        my $culture = culture_from_lang($lang);
        my $langname = langname($lang);

        $$strref =~ s/%LANG%/$lang/ge;
        $$strref =~ s/%LOCALE%/$locale/ge;
        $$strref =~ s/%LOCALE:ANDROID%/locale_android($lang)/ge;
        $$strref =~ s/%LOCALE:IPHONE%/locale_iphone($lang)/ge;
        $$strref =~ s/%LOCALE:LC%/lc($locale)/ge;
        $$strref =~ s/%LOCALE:UC%/uc($locale)/ge;
        $$strref =~ s/%LOCALE:FULL%/$full_locale/ge;
        $$strref =~ s/%LOCALE:FULL:LC%/lc($full_locale)/ge;
        $$strref =~ s/%LOCALE:FULL:UC%/uc($full_locale)/ge;
        $$strref =~ s/%CULTURE%/$culture/ge;
        $$strref =~ s/%LANGNAME%/$langname/g;
        $$strref =~ s/%LANGNAME:IPHONE%/langname_iphone($lang)/g;

        my $alias = $Serge::Util::LangID::alias{$lang};
        $lang = $alias if $alias;
        my $h = $Serge::Util::LangID::map{$lang} || $Serge::Util::LangID::map{''};
        if ($h) {
            my $langid_dec = $h->{code};
            my $langid = sprintf('%04x', $langid_dec) if ($langid_dec > 0);
            my $codepage = $h->{cp};
            $codepage = $Serge::Util::LangID::default_codepage unless $codepage;

            $$strref =~ s/%LANGID:DEC%/$langid_dec/ge;
            $$strref =~ s/%LANGID%/$langid/ge;
            $$strref =~ s/%LANGCONST%/$h->{lang}/ge;
            $$strref =~ s/%SUBLANGCONST%/$h->{sublang}/ge;
            $$strref =~ s/%AFXTARGCONST%/$h->{afx}/ge;
            $$strref =~ s/%CODEPAGE%/$codepage/ge;
        }
    }
}

sub subst_macros {
    my ($str, $file, $lang, $source_lang) = @_;
    subst_macros_strref(\$str, $file, $lang, $source_lang);
    return $str;
}

sub normalize_strref {
    my $ref = shift;
    $$ref =~ s/\s/ /sg; # normalize all whitespace to regular space characters
    $$ref =~ s/[ ]{2,}/ /g; # normalize whitespace
    $$ref =~ s/^[ ]//g; # remove leading whitespace
    $$ref =~ s/[ ]$//g; # remove trailing whitespace
}

# .PO-specific string escaping
# see gettext po parser for a list of control sequences
# https://github.com/autotools-mirror/gettext/blob/master/gettext-tools/src/po-lex.c#L749-L856
sub escape_strref {
    my $ref = shift;
    $$ref =~ s/\\/\x1/g; # convert backslashes to a temporary symbol
    $$ref =~ s/\"/\\"/g;
    $$ref =~ s/\n/\\n/sg; # newline
    $$ref =~ s/\t/\\t/g;  # horizontal tab
    $$ref =~ s/\x8/\\b/g; # 0x08 (bs) backspace
    $$ref =~ s/\r/\\r/sg; # carriage return
    $$ref =~ s/\xC/\\f/g; # 0x0C (np) formfeed
    $$ref =~ s/\xB/\\v/g; # 0x0B (vt) vertical tab
    $$ref =~ s/\x7/\\a/g; # 0x07 (bel) bel character
    $$ref =~ s/\x1/\\\\/g; # restore backslashes (and escape them)
}

# .PO-specific string unescaping
sub unescape_strref {
    my $ref = shift;
    $$ref =~ s/\\\\/\x1/g;
    $$ref =~ s/\\"/\"/g;
    $$ref =~ s/\\n/\n/sg;
    $$ref =~ s/\\t/\t/g;
    $$ref =~ s/\\b/\x8/g;
    $$ref =~ s/\\r/\r/sg;
    $$ref =~ s/\\f/\xC/g;
    $$ref =~ s/\\v/\xB/g;
    $$ref =~ s/\\a/\x7/g;
    $$ref =~ s/\x1/\\/g;
}

sub xml_escape_strref { # escape XML-unsafe chars
  my ($strref, $noquotes, $apos) = @_;
  $$strref =~ s/\&/&amp;/g;
  $$strref =~ s/\'/&apos;/g if $apos;
  $$strref =~ s/\"/&quot;/g unless $noquotes;
  $$strref =~ s/\</&lt;/g;
  $$strref =~ s/\>/&gt;/g;
}

sub xml_unescape_strref { # unescape XML-unsafe chars
  my ($strref, $noquotes, $apos) = @_;
  $$strref =~ s/&gt;/\>/g;
  $$strref =~ s/&lt;/\</g;
  $$strref =~ s/&quot;/\"/g unless $noquotes;
  $$strref =~ s/&apos;/'/g if $apos;
  $$strref =~ s/\&amp;/&/g;
}

sub encode {
    my ($encoding, $str) = @_;

    if (uc($encoding) eq 'JAVA') {
        $str =~ s/([^\000-\177])/sprintf "\\u%04x", ord($1)/ge;
        return $str;
    } else {
        return Encode::encode($encoding, $str);
    }
}

sub po_is_msgid_plural {
    my ($s) = @_;
    return !!($s =~ m/$UNIT_SEPARATOR/);
}

sub po_serialize_msgid {
    my ($s) = @_;
    my @out;
    my @plurals = split_plural_string($s);
    die "More than two plural forms not supported for msgid" if @plurals > 2;
    push @out, "msgid ".po_wrap($plurals[0]);
    if (@plurals > 1) {
        push @out, "msgid_plural ".po_wrap($plurals[1]);
    }
    return @out;
}

sub po_serialize_msgstr {
    my ($s, $n_plurals) = @_;
    my @out;
    my @plurals = split_plural_string($s);
    if ($n_plurals || @plurals > 1) {
        for (my $i = 0; $i < @plurals || $i < $n_plurals; $i++) {
            $s = $plurals[$i];
            push @out, "msgstr[$i] ".po_wrap($s);
        }
    } else {
        push @out, "msgstr ".po_wrap($s);
    }
    return @out;
}

sub glue_plural_string {
    my @variants = @_;
    my $s = join($Serge::Util::UNIT_SEPARATOR, @variants);
    # trim unit separators at the end of the resulting string
    $s =~ s/[$UNIT_SEPARATOR]+$//sg;
    return $s;
}

sub split_plural_string {
    return split(/$UNIT_SEPARATOR/, shift);
}

sub po_wrap {
    my ($s) = @_;

    my @lines = wrap($s, $PO_LINE_LENGTH);

    # Add empty string as the first line to indicate multi-line entry in .po

    unshift(@lines, '') if scalar(@lines) > 1;

    map { escape_strref(\$_) } @lines;

    return '"'.join(qq|"\n"|, @lines).'"';
}

sub wrap {
    my ($s, $length) = @_;
    die "length should be a positive integer" unless $length > 0;

    return ('') if $s eq '';

    # Wrap by '\n' explicitly
    if ($s =~ m{^(.*?(?:\\n|\n))(.+)$}s) {
        my $a = $1; # if $1 and $2 are used directly, this won't work
        my $b = $2;
        return wrap($a, $length), wrap($b, $length);
    }

    # The following regexp was taken from the Translate Toolkit, file textwrap.py
    my @a = split(/(\s+|[^\s\w]*\w+[a-zA-Z]-(?=\w+[a-zA-Z])|(?<=[\w\!\"\'\&\.\,\?])-{2,}(?=\w))/, $s);

    my @lines;
    my $accum = '';
    while (scalar(@a) > 0) {

        # Take the next chunk and append the
        # following whitespace chunk to it, if any
        my $chunk = shift @a;
        if (@a > 0 && $a[0] =~ m/^\s*$/) {
            $chunk .= shift @a;
        }

        if (length($accum) + length($chunk) > $length) {
            push @lines, $accum if $accum ne '';

            while (length($chunk) >= $length) {
                push @lines, substr($chunk, 0, $length, '');
            }

            $accum = $chunk;
        } else {
            $accum .= $chunk;
        }
    }
    push @lines, $accum if $accum ne '';

    return @lines;
}

sub read_and_normalize_file {
    my ($fname) = @_;

    # Reading the entire file

    open(SRC, $fname) || die "Can't read [$fname]: $!";
    binmode(SRC);
    my $data = join('', <SRC>);
    close(SRC);

    my $decoder = Encode::Guess->guess($data);
    if (ref($decoder)) {
        my $enc = uc($decoder->name);

        # remove BOM
        # (not sure why this was done, as BOM is apparently needed for at least UTF-16 decoding;
        # so I disabled BOM removal for UTF-16 for now)
        $data =~ s/^\xFF\xFE//s         if  ($enc eq 'UTF-16LE');
        #$data =~ s/^\xFE\xFF//s         if (($enc eq 'UTF-16BE') || ($enc eq 'UTF-16'));
        $data =~ s/^\xFF\xFE\x00\x00//s if  ($enc eq 'UTF-32LE');
        $data =~ s/^\x00\x00\xFE\xFF//s if (($enc eq 'UTF-32BE') || ($enc eq 'UTF-32'));
        $data =~ s/^\xEF\xBB\xBF//s     if (($enc eq 'UTF-8')    || ($enc eq 'UTF8'));

        $data = $decoder->decode($data);
    } else {
        if ($data =~ m/^<\?xml\s+(.+?)\?>/i) {
            my $attrs = $1;
            if ($attrs =~ m/encoding=['"](.+?)['"]/i) {
                my $enc = uc($1);
                #print "\t\tEncoding (from XML header): $enc\n";

                # remove BOM
                $data =~ s/^\xEF\xBB\xBF//s if (($enc eq 'UTF-8') || ($enc eq 'UTF8'));

                $data = decode($enc, $data);
            }
        } else {
            #print "\t\tEncoding (default): ASCII\n"; # $decoder holds the error string
        }
    }

    $data =~ s/\r\n/\n/sg; # normalize line-feeds

    return $data;
}

sub file_mtime {
    my ($fname) = @_;

    my ($dev, $ino, $mode, $nlink, $uid, $gid, $rdev, $size,
       $atime, $mtime, $ctime, $blksize, $blocks) = stat($fname);

    return $mtime;
}

sub remove_blank_entries {
    my ($aref, $reason) = @_;

    my @out;
    foreach my $s (@$aref) {
        if ($s eq '') {
            print "$reason\n" if $reason ne '';
        } else {
            push @out, $s;
        }
    }

    return \@out;
}

1;
