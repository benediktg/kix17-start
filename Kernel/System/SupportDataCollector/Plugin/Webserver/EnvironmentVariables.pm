# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::SupportDataCollector::Plugin::Webserver::EnvironmentVariables;

use strict;
use warnings;

use base qw(Kernel::System::SupportDataCollector::PluginBase);

use Kernel::Language qw(Translatable);

our @ObjectDependencies = ();

sub GetDisplayPath {
    return Translatable('Webserver') . '/' . Translatable('Environment Variables');
}

sub Run {
    my $Self = shift;

    my %Environment = %ENV;

    # Skip the plugin, if the support data collection isn't running in a web request.
    return $Self->GetResults() if !$ENV{GATEWAY_INTERFACE};

    for my $NotNeededString (
        qw(
        HTTP_REFERER HTTP_CACHE_CONTROL HTTP_COOKIE HTTP_USER_AGENT
        HTTP_ACCEPT_LANGUAGE HTTP_ACCEPT_ENCODING HTTP_ACCEPT
        QUERY_STRING REQUEST_METHOD REQUEST_URI SCRIPT_NAME
        ALLUSERSPROFILE      APPDATA              LOCALAPPDATA   COMMONPROGRAMFILES
        PROGRAMDATA          PROGRAMFILES         PSMODULEPATH   PUBLIC
        SYSTEMDRIVE          SYSTEMROOT           TEMP           WINDIR
        USERPROFILE          REMOTE_PORT
        )
    ) {
        delete $Environment{$NotNeededString};
    }

    for my $Variable ( sort { $a cmp $b } keys %Environment ) {
        $Self->AddResultInformation(
            Identifier => $Variable,
            Label      => $Variable,
            Value      => $Environment{$Variable},
        );
    }

    return $Self->GetResults();
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the KIX project
(L<https://www.kixdesk.com/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see the enclosed file
LICENSE for license information (AGPL). If you did not receive this file, see

<https://www.gnu.org/licenses/agpl.txt>.

=cut
