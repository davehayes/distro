# See bottom of file for license and copyright information
package Foswiki::Configure::Checkers::Site::Locale;

use strict;
use warnings;

use Foswiki::Configure::Checker ();
our @ISA = ('Foswiki::Configure::Checker');

my @required = (

);

sub check_current_value {
    my ( $this, $reporter ) = @_;

    if ( $Foswiki::cfg{UseLocale} ) {
        eval("use locale;use POSIX");
        if ($@) {
            return $this->WARN( 'Locales cannot be used. Error was: '
                  . Foswiki::Configure::Reporter::stripStacktrace($@) );
        }
        my $locale = $Foswiki::cfg{Site}{Locale};
        POSIX::setlocale( &POSIX::LC_CTYPE, $locale );
        my $currentLocale = POSIX::setlocale(&POSIX::LC_CTYPE);
        if ( $currentLocale ne $locale ) {
            $reporter->WARN(<<HERE);
Unable to set locale to '$locale'. The actual locale is '$currentLocale'
- please test your locale settings. This warning can be ignored if you are
not planning to use locales (e.g. your site uses English only) - or you can
set  {Site}{Locale} to 'C', which should always work.
HERE
        }
        if ( $locale !~ /[a-z]/i && $Foswiki::cfg{UseLocale} ) {
            $reporter->WARN(<<HERE);
UseLocale set but {Site}{Locale} '$locale' has no alphabetic characters
HERE
        }
    }

    # Set the default site charset
    unless ( defined( $Foswiki::cfg{Site}{CharSet} ) ) {
        $Foswiki::cfg{Site}{CharSet} = 'iso-8859-1';
    }

    # Check for unusable multi-byte encodings as site character set
    # - anything that enables a single ASCII character such as '[' to be
    # matched within a multi-byte character cannot be used for Foswiki.
    # Refuse to work with character sets that allow Foswiki syntax
    # to be recognised within multi-byte characters.
    # FIXME: match other problematic multi-byte character sets
    if (   $Foswiki::cfg{UseLocale}
        && $Foswiki::cfg{Site}{CharSet} =~
m/^(?:iso-?2022-?|hz-?|gb2312|gbk|gb18030|.*big5|.*shift_?jis|ms.kanji|johab|uhc)/i
      )
    {

        $reporter->ERROR(
            <<HERE
Cannot use this multi-byte encoding ('$Foswiki::cfg{Site}{CharSet}') as site character
encoding. Please set a different character encoding in the {Site}{Locale}
setting.
HERE
        );
    }
}

1;
__END__
Foswiki - The Free and Open Source Wiki, http://foswiki.org/

Copyright (C) 2008-2010 Foswiki Contributors. Foswiki Contributors
are listed in the AUTHORS file in the root of this distribution.
NOTE: Please extend that file, not this notice.

Additional copyrights apply to some or all of the code in this
file as follows:

Copyright (C) 2000-2006 TWiki Contributors. All Rights Reserved.
TWiki Contributors are listed in the AUTHORS file in the root
of this distribution.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version. For
more details read LICENSE in the root of this distribution.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

As per the GPL, removal of this notice is prohibited.
