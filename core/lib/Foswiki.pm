
package Foswiki;
use v5.14;    # First version to accept v-numbers.

=begin TML

---+ package Foswiki

Foswiki operates by creating a singleton object (known as the Session
object) that acts as a point of reference for all the different
modules in the system. This package is the class for this singleton,
and also contains the vast bulk of the basic constants and the per-
site configuration mechanisms.

Global variables are avoided wherever possible to avoid problems
with CGI accelerators such as mod_perl.

---++ Public Data members
   * =request=          Pointer to the Foswiki::Request
   * =response=         Pointer to the Foswiki::Response
   * =context=          Hash of context ids
   * =plugins=          Foswiki::Plugins singleton
   * =prefs=            Foswiki::Prefs singleton
   * =remoteUser=       Login ID when using ApacheLogin. Maintained for
                        compatibility only, do not use.
   * =requestedWebName= Name of web found in URL path or =web= URL parameter
   * =scriptUrlPath=    URL path to the current script. May be dynamically
                        extracted from the URL path if {GetScriptUrlFromCgi}.
                        Only required to support {GetScriptUrlFromCgi} and
                        not consistently used. Avoid.
   * =access=         Foswiki::Access singleton
   * =store=            Foswiki::Store singleton
   * =topicName=        Name of topic found in URL path or =topic= URL
                        parameter
   * =urlHost=          Host part of the URL (including the protocol)
                        determined during intialisation and defaulting to
                        {DefaultUrlHost}
   * =user=             Unique user ID of logged-in user
   * =users=            Foswiki::Users singleton
   * =webName=          Name of web found in URL path, or =web= URL parameter,
                        or {UsersWebName}

=cut

use Cwd qw( abs_path );
use Module::Load;
use File::Spec   ();
use Monitor      ();
use CGI          ();    # Always required to get html generation tags;
use Digest::MD5  ();    # For passthru and validation
use Scalar::Util ();

# Item13331 - use CGI::ENCODE_ENTITIES introduced in CGI>=4.14 to restrict encoding
# in CGI's html rendering code to only these; note that CGI's default values
# still breaks some unicode byte strings
$CGI::ENCODE_ENTITIES = q{&<>"'};

our $app;

# Site configuration constants
our %cfg;

# Other computed constants
our %regex;
our $VERSION;
our $RELEASE;
our $UNICODE = 1;  # flag that extensions can use to test if the core is unicode
our $TRUE    = 1;
our $FALSE   = 0;
our $engine;
our $TranslationToken = "\0";    # Do not deprecate - used in many plugins
our $system_message;             # Important broadcast message from the system
my $bootstrap_message = '';      # Bootstrap message.

# Note: the following marker is used in text to mark RENDERZONE
# macros that have been hoisted from the source text of a page. It is
# carefully chosen so that it is (1) not normally present in written
# text (2) does not combine with other characters to form valid
# wide-byte characters and (3) does not conflict with other markers used
# by Foswiki/Render.pm
our $RENDERZONE_MARKER = "\3";

# Used by takeOut/putBack blocks
our $BLOCKID = 0;
our $OC      = "<!--\0";
our $CC      = "\0-->";

# This variable is set if Foswiki is running in unit test mode.
# It is provided so that modules can detect unit test mode to avoid
# corrupting data spaces.
our $inUnitTestMode = 0;

use Try::Tiny;

#use Moo;
#use namespace::clean;
#extends qw( Foswiki::Object );

use Assert;
use Exporter qw(import);
our @EXPORT_OK =
  qw(%regex urlEncode urlDecode make_params load_package load_class expandStandardEscapes);

sub SINGLE_SINGLETONS       { 0 }
sub SINGLE_SINGLETONS_TRACE { 0 }

# Character encoding/decoding stubs. Done so we can ovveride
# if necessary (e.g. on OSX we may want to monkey-patch in a
# NFC/NFD module)
#
# Note, NFC normalization is being done only for network and directory
# read operations,  but NOT for topic data. Adding normalization here
# caused performance issues because some versions of Unicode::Normalize
# have removed the XS versions.  We really only need to normalize directory
# names not file contents.

=begin TML

---++ StaticMethod decode_utf8($octets) -> $unicode

Decode a binary string of octets known to be encoded using UTF-8 into
perl characters (unicode).

=cut

*decode_utf8 = \&Encode::decode_utf8;

=begin TML

---++ StaticMethod encode_utf8($unicode) -> $octets

Encode a perl character string into a binary string of octets
encoded using UTF-8.

=cut

*encode_utf8 = \&Encode::encode_utf8;

BEGIN {

    # First thing we do; make sure we print unicode errors
    binmode( STDERR, ":utf8" );

    #Monitor::MARK("Start of BEGIN block in Foswiki.pm");

    # DO NOT CHANGE THE FORMAT OF $VERSION.
    # Use $RELEASE for a descriptive version.
    use version 0.77; $VERSION = version->declare('v2.99.0');
    $RELEASE = 'Foswiki-2.99.0';

    #if ( $Foswiki::cfg{UseLocale} ) {
    #    require locale;
    #    import locale();
    #}

    # Set environment var FOSWIKI_NOTAINT to disable taint checks even
    # if Taint::Runtime is installed
    if ( DEBUG && !$ENV{FOSWIKI_NOTAINT} ) {
        eval { require Taint::Runtime; };
        if ($@) {
            print STDERR
"DEVELOPER WARNING: taint mode could not be enabled. Is Taint::Runtime installed?\n";
        }
        else {
            # Enable taint checking
            Taint::Runtime::_taint_start();
        }
    }

    # locale setup
    #
    #
    # Note that 'use locale' must be done in BEGIN block for regexes and
    # sorting to work properly, although regexes can still work without
    # this in 'non-locale regexes' mode.

   # XXX TODO Reimplement using unicode routines.
   #if ( $Foswiki::cfg{UseLocale} ) {
   #
   #    # Set environment variables for grep
   #    $ENV{LC_CTYPE} = $Foswiki::cfg{Site}{Locale};
   #
   #    # Load POSIX for I18N support.
   #    require POSIX;
   #    import POSIX qw( locale_h LC_CTYPE LC_COLLATE );
   #
   #   # SMELL: mod_perl compatibility note: If Foswiki is running under Apache,
   #   # won't this play with the Apache process's locale settings too?
   #   # What effects would this have?
   #    setlocale( &LC_CTYPE,   $Foswiki::cfg{Site}{Locale} );
   #    setlocale( &LC_COLLATE, $Foswiki::cfg{Site}{Locale} );
   #}

    #Monitor::MARK('End of BEGIN block in Foswiki.pm');
}

# Components that all requests need
#use Foswiki::Response ();
#use Foswiki::Request  ();
#use Foswiki::Logger   ();
#use Foswiki::Meta     ();
#use Foswiki::Sandbox  ();
#use Foswiki::Time     ();
#use Foswiki::Prefs    ();
#use Foswiki::Plugins  ();
#use Foswiki::Users    ();

# Tests if the $redirect is an external URL, returning false if
# AllowRedirectUrl is denied
sub _isRedirectSafe {
    my $redirect = shift;

    return 1 if ( $Foswiki::cfg{AllowRedirectUrl} );

    # relative URL - OK
    return 1 if $redirect =~ m#^/#;

    #TODO: this should really use URI
    # Compare protocol, host name and port number
    if ( $redirect =~ m!^(.*?://[^/?#]*)! ) {

        # implicit untaints OK because result not used. uc retaints
        # if use locale anyway.
        my $target = uc($1);

        $Foswiki::cfg{DefaultUrlHost} =~ m!^(.*?://[^/]*)!;
        return 1 if ( $target eq uc($1) );

        if ( $Foswiki::cfg{PermittedRedirectHostUrls} ) {
            foreach my $red (
                split( /\s*,\s*/, $Foswiki::cfg{PermittedRedirectHostUrls} ) )
            {
                $red =~ m!^(.*?://[^/]*)!;
                return 1 if ( $target eq uc($1) );
            }
        }
    }
    return 0;
}

=begin TML

---++ StaticMethod splitAnchorFromUrl( $url ) -> ( $url, $anchor )

Takes a full url (including possible query string) and splits off the anchor.
The anchor includes the # sign. Returns an empty string if not found in the url.

=cut

sub splitAnchorFromUrl {
    my ($url) = @_;

    ( $url, my $anchor ) = $url =~ m/^(.*?)(#(.*?))*$/;
    return ( $url, $anchor );
}

=begin TML

---++ ObjectMethod getCGISession() -> $cgisession

Get the CGI::Session object associated with this session, if there is
one. May return undef.

=cut

sub getCGISession {
    $_[0]->users->getCGISession();
}

=begin TML

---++ ObjectMethod getLoginManager() -> $loginManager

Get the Foswiki::LoginManager object associated with this session, if there is
one. May return undef.

=cut

sub getLoginManager {
    $_[0]->users->getLoginManager();
}

=begin TML

---++ StaticMethod isValidWikiWord( $name ) -> $boolean

Check for a valid WikiWord or WikiName

=cut

sub isValidWikiWord {
    my $name = shift || '';
    return ( $name =~ m/^$regex{wikiWordRegex}$/ );
}

=begin TML

---++ StaticMethod isValidTopicName( $name [, $nonww] ) -> $boolean

Check for a valid topic =$name=. If =$nonww=, then accept non wiki-words
(though they must still be composed of only valid, unfiltered characters)

=cut

# Note: must work on tainted names.
sub isValidTopicName {
    my ( $name, $nonww ) = @_;

    return 0 unless defined $name && $name ne '';

    # Make sure any name is supported by the Store encoding
    if (   $Foswiki::cfg{Store}{Encoding}
        && $Foswiki::cfg{Store}{Encoding} ne 'utf-8'
        && $name =~ m/[^[:ascii:]]+/ )
    {
        my $badName = 0;
        try {
            Foswiki::Store::encode( $name, 1 );
        }
        catch {
            $badName = 1;
        };
        return 0 if $badName;
    }

    return 1 if ( $name =~ m/^$regex{topicNameRegex}$/ );
    return 0 unless $nonww;
    return 0 if $name =~ m/$cfg{NameFilter}/;
    return 1;
}

=begin TML

---++ StaticMethod isValidWebName( $name, $system ) -> $boolean

STATIC Check for a valid web name. If $system is true, then
system web names are considered valid (names starting with _)
otherwise only user web names are valid

If $Foswiki::cfg{EnableHierarchicalWebs} is off, it will also return false
when a nested web name is passed to it.

=cut

# Note: must work on tainted names.
sub isValidWebName {
    my $name = shift || '';
    my $sys = shift;
    return 1 if ( $sys && $name =~ m/^$regex{defaultWebNameRegex}$/ );
    return ( $name =~ m/^$regex{webNameRegex}$/ );
}

=begin TML

---++ StaticMethod isValidEmailAddress( $name ) -> $boolean

STATIC Check for a valid email address name.

=cut

# Note: must work on tainted names.
sub isValidEmailAddress {
    my $name = shift || '';
    return $name =~ m/^$regex{emailAddrRegex}$/;
}

=begin TML

---++ StaticMethod make_params(...)
Generate a URL parameters string from parameters given. A parameter
named '#' will generate a fragment identifier.

=cut

sub make_params {
    my $url = '';
    my @ps;
    my $anchor = '';
    while ( my $p = shift @_ ) {
        if ( $p eq '#' ) {
            $anchor = '#' . urlEncode( shift(@_) );
        }
        else {
            my $v = shift(@_);
            $v = '' unless defined $v;
            push( @ps, urlEncode($p) . '=' . urlEncode($v) );
        }
    }
    if ( scalar(@ps) ) {
        @ps = sort(@ps) if (DEBUG);
        $url .= '?' . join( ';', @ps );
    }
    return $url . $anchor;
}

=begin TML

---++ StaticMethod load_package( $full_package_name [, %params ] )

Will cleanly load the package or fail. This is better than 'eval "require $package"'.

It is not perfect for Perl < 5.10. For Perl 5.8, if somewhere else 'eval "require $package"' 
was used *earlier* for a module that fails to load, then not only is the failure not detected
then. Neither will it be detected here.

The recommendation is to replace all dynamic require calls in Foswiki to be replaced with this call.

This functionality used to be done via module Class::Load, but that had painful dependencies.

See http://blog.fox.geek.nz/2010/11/searching-design-spec-for-ultimate.html for the gory details.

=cut

# _package_defined checks if package is present in the global symbol table.
sub _package_defined {
    my $fullname = shift;

    # See if package is already defined in the main symbol table.
    my ( $namePref, $nameSuff ) = ( $fullname =~ /^(.+::)?([^:]+)$/ );
    $namePref //= '::';
    no strict 'refs';
    my $pkgLoaded = defined $namePref->{"${nameSuff}::"};
    use strict 'refs';
    return $pkgLoaded;
}

# SMELL Wouldn't it be more reliable to use Module::Load? Or Class::Load? Though
# the latter requires additional CPAN module installed.
sub load_package {
    my $fullname = shift;
    my %params   = @_;

    my $defined = _package_defined($fullname);
    my $loaded  = $defined;
    if ( $defined && $params{method} ) {

        # Check if loaded package can do a method. If it can't we assume that
        # the entry in the symbol table was autovivified.
        $loaded = $fullname->can( $params{method} );
    }
    return if $loaded;

    my $filename = File::Spec->catfile( split /::/, $fullname ) . '.pm';
    #
    ## Check if the module has been already loaded before.
    #return if exists $INC{$filename};

    # Is it already loaded? If so, it might be an internal class an missing
    # from @INC, so skip it. See perldoc UNIVERSAL for what this does.
    # XXX vrurg This method is unreliable and sometimes detects a module which
    # hasn't been loaded yet. Besides it depends on module name being 1-to-1
    # mapped into file name which is not always the case. Consider macros which
    # are part of Foswiki namespace.
    #return if eval { $fullname->isa($fullname) };

    #say STDERR "Loading $fullname from $filename";

    local $SIG{__DIE__};
    require $filename;
}

sub load_class {
    load_package( @_, method => 'new', );
}

=begin TML

---++ StaticMethod entityEncode( $text [, $extras] ) -> $encodedText

Escape special characters to HTML numeric entities. This is *not* a generic
encoding, it is tuned specifically for use in Foswiki.

HTML4.0 spec:
"Certain characters in HTML are reserved for use as markup and must be
escaped to appear literally. The "&lt;" character may be represented with
an <em>entity</em>, <strong class=html>&amp;lt;</strong>. Similarly, "&gt;"
is escaped as <strong class=html>&amp;gt;</strong>, and "&amp;" is escaped
as <strong class=html>&amp;amp;</strong>. If an attribute value contains a
double quotation mark and is delimited by double quotation marks, then the
quote should be escaped as <strong class=html>&amp;quot;</strong>.

Other entities exist for special characters that cannot easily be entered
with some keyboards..."

This method encodes:
   * all non-printable 7-bit chars (< \x1f), except \n (\xa) and \r (\xd)
   * HTML special characters '>', '<', '&', ''' (single quote) and '"' (double quote).
   * TML special characters '%', '|', '[', ']', '@', '_', '*', '$' and "="

$extras is an optional param that may be used to include *additional*
characters in the set of encoded characters. It should be a string
containing the additional chars.

This internal function is available for use by expanding the =%ENCODE= macro,
or the =%URLPARAM= macro, specifying =type="entities"= or =type="entity"=.

=cut

sub entityEncode {
    my ( $text, $extra ) = @_;
    $extra = '' unless defined $extra;

    # Safe on utf8 binary strings, as none of the characters has bit 7 set
    $text =~
s/([[\x01-\x09\x0b\x0c\x0e-\x1f"%&\$'*<=>@\]_\|$extra])/'&#'.ord($1).';'/ge;
    return $text;
}

#s/([[\x01-\x09\x0b\x0c\x0e-\x1f"%&\$'*<=>@[_\|$extra])/'&#'.ord($1).';'/ge;

=begin TML

---++ StaticMethod entityDecode ( $encodedText ) -> $text

Decodes all numeric entities (e.g. &amp;#123;). _Does not_ decode
named entities such as &amp;amp; (use HTML::Entities for that)

=cut

sub entityDecode {
    my $text = shift;

    $text =~ s/&#(\d+);/chr($1)/ge;
    return $text;
}

=begin TML

---++ StaticMethod expandStandardEscapes($str) -> $unescapedStr

Expands standard escapes used in parameter values to block evaluation. See
System.FormatTokens for a full list of supported tokens.

=cut

sub expandStandardEscapes {
    my $text = shift;

    # expand '$n()' and $n! to new line
    $text =~ s/\$n\(\)/\n/gs;
    $text =~ s/\$n(?=[^[:alpha:]]|$)/\n/gs;

    # filler, useful for nested search
    $text =~ s/\$nop(\(\))?//gs;

    # $quot -> "
    $text =~ s/\$quot(\(\))?/\"/gs;

    # $comma -> ,
    $text =~ s/\$comma(\(\))?/,/gs;

    # $percent -> %
    $text =~ s/\$perce?nt(\(\))?/\%/gs;

    # $lt -> <
    $text =~ s/\$lt(\(\))?/\</gs;

    # $gt -> >
    $text =~ s/\$gt(\(\))?/\>/gs;

    # $amp -> &
    $text =~ s/\$amp(\(\))?/\&/gs;

    # $dollar -> $, done last to avoid creating the above tokens
    $text =~ s/\$dollar(\(\))?/\$/gs;

    return $text;
}

=begin TML

---++ StaticMethod urlEncode( $perlstring ) -> $bytestring

Encode by converting characters that are reserved in URLs to
their %NN equivalents. This method is used for encoding
strings that must be embedded _verbatim_ in URLs; it cannot
be applied to URLs themselves, as it escapes reserved
characters such as =, &, %, ;, # and ?.

RFC 1738, Dec. '94:
    <verbatim>
    ...Only alphanumerics [0-9a-zA-Z], the special
    characters $-_.+!*'(), and reserved characters used for their
    reserved purposes may be used unencoded within a URL.
    </verbatim>

However this function is tuned for use with Foswiki. As such, it
encodes *all* characters except 0-9a-zA-Z-_.:~!*/

This internal function is available for use by expanding the =%ENCODE= macro,
specifying =type="url"=.  It is also the default encoding used by the =%URLPARAM= macro. 

=cut

sub urlEncode {
    my $text = shift;

    $text = encode_utf8($text);
    $text =~ s{([^0-9a-zA-Z-_.:~!*/])}{sprintf('%%%02x',ord($1))}ge;

    return $text;
}

=begin TML

---++ StaticMethod urlDecode( $bytestring ) -> $perlstring

Reverses the encoding done in urlEncode.

=cut

sub urlDecode {
    my $text = shift;

    $text =~ s/%([\da-fA-F]{2})/chr(hex($1))/ge;
    $text = decode_utf8($text);

    return $text;
}

=begin TML

---++ StaticMethod isTrue( $value, $default ) -> $boolean

Returns 1 if =$value= is true, and 0 otherwise. "true" means set to
something with a Perl true value, with the special cases that "off",
"false" and "no" (case insensitive) are forced to false. Leading and
trailing spaces in =$value= are ignored.

If the value is undef, then =$default= is returned. If =$default= is
not specified it is taken as 0.

=cut

sub isTrue {
    my ( $value, $default ) = @_;

    $default ||= 0;

    return $default unless defined($value);

    $value =~ s/^\s*(.*?)\s*$/$1/g;
    $value =~ s/off//gi;
    $value =~ s/no//gi;
    $value =~ s/false//gi;
    return ($value) ? 1 : 0;
}

=begin TML

---++ StaticMethod spaceOutWikiWord( $word, $sep ) -> $string

Spaces out a wiki word by inserting a string (default: one space) between each word component.
With parameter $sep any string may be used as separator between the word components; if $sep is undefined it defaults to a space.

=cut

sub spaceOutWikiWord {
    my ( $word, $sep ) = @_;

    # Both could have the value 0 so we cannot use simple = || ''
    $word = defined($word) ? $word : '';
    $sep  = defined($sep)  ? $sep  : ' ';
    my $mark = "\001";
    $word =~ s/([[:upper:]])([[:digit:]])/$1$mark$2/g;
    $word =~ s/([[:digit:]])([[:upper:]])/$1$mark$2/g;
    $word =~ s/([[:lower:]])([[:upper:][:digit:]]+)/$1$mark$2/g;
    $word =~ s/([[:upper:]])([[:upper:]])(?=[[:lower:]])/$1$mark$2/g;
    $word =~ s/$mark/$sep/g;
    return $word;
}

=begin TML

---++ StaticMethod takeOutBlocks( \$text, $tag, \%map ) -> $text
   * =$text= - Text to process
   * =$tag= - XML-style tag.
   * =\%map= - Reference to a hash to contain the removed blocks

Return value: $text with blocks removed

Searches through $text and extracts blocks delimited by an XML-style tag,
storing the extracted block, and replacing with a token string which is
not affected by TML rendering.  The text after these substitutions is
returned.

=cut

sub takeOutBlocks {
    my ( $intext, $tag, $map ) = @_;

    # Case insensitive regexes are very slow,  Change to character class match
    # link is transformed to [lL][iI][nN][kK]
    my $re = join( '', map { '[' . lc($_) . uc($_) . ']' } split( '', $tag ) );

    return $intext unless ( $intext =~ m/<$re\b/ );

    my $out   = '';
    my $depth = 0;
    my $scoop;
    my $tagParams;

    foreach my $token ( split( /(<\/?$re[^>]*>)/, $intext ) ) {
        if ( $token =~ m/<$re\b([^>]*)?>/ ) {
            $depth++;
            if ( $depth eq 1 ) {
                $tagParams = $1;
                next;
            }
        }
        elsif ( $token =~ m/<\/$re>/ ) {
            if ( $depth > 0 ) {
                $depth--;
                if ( $depth eq 0 ) {
                    my $placeholder = "$tag$BLOCKID";
                    $BLOCKID++;
                    $map->{$placeholder}{text}   = $scoop;
                    $map->{$placeholder}{params} = $tagParams;
                    $out .= "$OC$placeholder$CC";
                    $scoop = '';
                    next;
                }
            }
        }
        if ( $depth > 0 ) {
            $scoop .= $token;
        }
        else {
            $out .= $token;
        }
    }

    # unmatched tags
    if ( defined($scoop) && ( $scoop ne '' ) ) {
        my $placeholder = "$tag$BLOCKID";
        $BLOCKID++;
        $map->{$placeholder}{text}   = $scoop;
        $map->{$placeholder}{params} = $tagParams;
        $out .= "$OC$placeholder$CC";
    }

    return $out;
}

=begin TML

---++ StaticMethod putBackBlocks( \$text, \%map, $tag, $newtag, $callBack ) -> $text

Return value: $text with blocks added back
   * =\$text= - reference to text to process
   * =\%map= - map placeholders to blocks removed by takeOutBlocks
   * =$tag= - Tag name processed by takeOutBlocks
   * =$newtag= - Tag name to use in output, in place of $tag.
     If undefined, uses $tag.
   * =$callback= - Reference to function to call on each block
     being inserted (optional)

Reverses the actions of takeOutBlocks.

Each replaced block is processed by the callback (if there is one) before
re-insertion.

Parameters to the outermost cut block are replaced into the open tag,
even if that tag is changed. This allows things like =&lt;verbatim class=''>=
to be changed to =&lt;pre class=''>=

If you set $newtag to '', replaces the taken-out block with the contents
of the block, not including the open/close. This is used for &lt;literal>,
for example.

=cut

sub putBackBlocks {
    my ( $text, $map, $tag, $newtag, $callback ) = @_;

    $newtag = $tag if ( !defined($newtag) );

    my $otext = $$text;
    my $pos   = 0;
    my $ntext = '';

    while ( ( $pos = index( $otext, ${OC} . $tag, $pos ) ) >= 0 ) {

        # Grab the text ahead of the marker
        $ntext .= substr( $otext, 0, $pos );

        # Length of the marker prefix
        my $pfxlen = length( ${OC} . $tag );

        # Ending marker position
        my $epos = index( $otext, ${CC}, $pos );

        # Tag instance
        my $placeholder =
          $tag . substr( $otext, $pos + $pfxlen, $epos - $pos - $pfxlen );

  # Not all calls to putBack use a common map, so skip over any missing entries.
        unless ( exists $map->{$placeholder} ) {
            $ntext .= substr( $otext, $pos, $epos - $pos + 4 );
            $otext = substr( $otext, $epos + 4 );
            $pos = 0;
            next;
        }

        # Any params saved with the tag
        my $params = $map->{$placeholder}{params} || '';

        # Get replacement value
        my $val = $map->{$placeholder}{text};
        $val = &$callback($val) if ( defined($callback) );

        # Append the new data and remove leading text + marker from original
        if ( defined($val) ) {
            $ntext .=
              ( $newtag eq '' ) ? $val : "<$newtag$params>$val</$newtag>";
        }
        $otext = substr( $otext, $epos + 4 );

        # Reset position for next pass
        $pos = 0;

        delete( $map->{$placeholder} );
    }

    $ntext .= $otext;    # Append any remaining text.
    $$text = $ntext;     # Replace the entire text

}

1;
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2016 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

Additional copyrights apply to some or all of the code in this
file as follows:

Copyright (C) 1999-2007 Peter Thoeny, peter@thoeny.org
and TWiki Contributors. All Rights Reserved. TWiki Contributors
are listed in the AUTHORS file in the root of this distribution.
Based on parts of Ward Cunninghams original Wiki and JosWiki.
Copyright (C) 1998 Markus Peter - SPiN GmbH (warpi@spin.de)
Some changes by Dave Harris (drh@bhresearch.co.uk) incorporated

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
