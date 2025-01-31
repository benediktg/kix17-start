# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::PublicRepository;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

use Kernel::Language qw(Translatable);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $File = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'File' ) || '';
    $File =~ s/^\///g;
    my $AccessControlRexExp = $Kernel::OM->Get('Kernel::Config')->Get('Package::RepositoryAccessRegExp');
    my $LayoutObject        = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    if ( !$AccessControlRexExp ) {
        return $LayoutObject->ErrorScreen(
            Message => Translatable('Need config Package::RepositoryAccessRegExp'),
        );
    }
    else {
        if ( $ENV{REMOTE_ADDR} !~ /^$AccessControlRexExp$/ ) {
            return $LayoutObject->ErrorScreen(
                Message =>
                    $LayoutObject->{LanguageObject}->Translate( 'Authentication failed from %s!', $ENV{REMOTE_ADDR} ),
            );
        }
    }

    my $PackageObject = $Kernel::OM->Get('Kernel::System::Package');

    # get repository index
    if ( $File =~ /kix.xml$/ ) {

        # get repository index
        my $Index = "<?xml version=\"1.0\" encoding=\"utf-8\" ?>";
        $Index .= "<otrs_package_list version=\"1.0\">\n";
        my @List = $PackageObject->RepositoryList();
        for my $Package (@List) {
            $Index .= "<Package>\n";
            $Index .= "  <File>$Package->{Name}->{Content}-$Package->{Version}->{Content}</File>\n";
            $Index .= $PackageObject->PackageBuild( %{$Package}, Type => 'Index' );
            $Index .= "</Package>\n";
        }
        $Index .= "</otrs_package_list>\n";
        return $LayoutObject->Attachment(
            Type        => 'inline',     # inline|attachment
            Filename    => 'kix.xml',
            ContentType => 'text/xml',
            Content     => $Index,
        );
    }

    # export package
    else {
        my $Name    = '';
        my $Version = '';
        if ( $File =~ /^(.*)\-(.+?)$/ ) {
            $Name    = $1;
            $Version = $2;
        }
        my $Package = $PackageObject->RepositoryGet(
            Name    => $Name,
            Version => $Version,
        );
        return $LayoutObject->Attachment(
            Type        => 'inline',           # inline|attachment
            Filename    => "$Name-$Version",
            ContentType => 'text/xml',
            Content     => $Package,
        );
    }
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
