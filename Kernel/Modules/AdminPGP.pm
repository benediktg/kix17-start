# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AdminPGP;

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

    # get layout objects
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # ------------------------------------------------------------ #
    # check if feature is active
    # ------------------------------------------------------------ #
    if ( !$Kernel::OM->Get('Kernel::Config')->Get('PGP') ) {

        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();

        $LayoutObject->Block( Name => 'Overview' );
        $LayoutObject->Block( Name => 'Notice' );
        $LayoutObject->Block( Name => 'Disabled' );
        $LayoutObject->Block( Name => 'OverviewResult' );
        $LayoutObject->Block(
            Name => 'NoDataFoundMsg',
            Data => {},
        );

        $Output .= $LayoutObject->Output( TemplateFile => 'AdminPGP' );
        $Output .= $LayoutObject->Footer();

        return $Output;
    }

    # get PGP object
    my $PGPObject = $Kernel::OM->Get('Kernel::System::Crypt::PGP');

    if ( !$PGPObject ) {

        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();

        $Output .= $LayoutObject->Notify(
            Priority => 'Error',
            Data     => Translatable("PGP environment is not working. Please check log for more info!"),
            Link     => $LayoutObject->{Baselink} . 'Action=AdminLog',
        );

        $LayoutObject->Block( Name => 'Overview' );
        $LayoutObject->Block( Name => 'Notice' );
        $LayoutObject->Block( Name => 'NotWorking' );
        $LayoutObject->Block( Name => 'OverviewResult' );
        $LayoutObject->Block(
            Name => 'NoDataFoundMsg',
            Data => {},
        );

        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminPGP',
        );

        $Output .= $LayoutObject->Footer();

        return $Output;
    }

    # get param object
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');

    $Param{Search} = $ParamObject->GetParam( Param => 'Search' );
    if ( !defined( $Param{Search} ) ) {
        $Param{Search} = $Self->{PGPSearch} || '';
    }
    if ( $Self->{Subaction} eq '' ) {
        $Param{Search} = '';
    }

    # get session object
    my $SessionObject = $Kernel::OM->Get('Kernel::System::AuthSession');

    $SessionObject->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key       => 'PGPSearch',
        Value     => $Param{Search},
    );

    # ------------------------------------------------------------ #
    # delete key
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'Delete' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        $LayoutObject->Block( Name => 'Overview' );
        $LayoutObject->Block( Name => 'ActionList' );
        $LayoutObject->Block( Name => 'ActionSearch' );
        $LayoutObject->Block( Name => 'ActionAdd' );
        $LayoutObject->Block( Name => 'Hint' );
        $LayoutObject->Block( Name => 'OverviewResult' );

        my $Key  = $ParamObject->GetParam( Param => 'Key' )  || '';
        my $Type = $ParamObject->GetParam( Param => 'Type' ) || '';
        if ( !$Key ) {
            return $LayoutObject->ErrorScreen(
                Message => Translatable('Need param Key to delete!'),
            );
        }
        my $Success = '';
        if ( $Type eq 'sec' ) {
            $Success = $PGPObject->SecretKeyDelete( Key => $Key );
        }
        else {
            $Success = $PGPObject->PublicKeyDelete( Key => $Key );
        }
        my @List = $PGPObject->KeySearch( Search => $Param{Search} );
        if (@List) {
            for my $Key (@List) {
                $LayoutObject->Block(
                    Name => 'Row',
                    Data => { %{$Key} },
                );
            }
        }
        else {
            $LayoutObject->Block(
                Name => 'NoDataFoundMsg',
                Data => {},
            );
        }
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        my $Message = '';
        if ($Success) {
            $Message = $LayoutObject->{LanguageObject}->Translate( 'Key %s deleted!', $Key );
        }
        else {
            $Message = $Kernel::OM->Get('Kernel::System::Log')->GetLogEntry(
                Type => 'Error',
                What => 'Message',
            );
        }
        $Output .= $LayoutObject->Notify( Info => $Message );

        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminPGP',
            Data         => \%Param
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # ------------------------------------------------------------ #
    # add key (form)
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'Add' ) {
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();

        $LayoutObject->Block( Name => 'Overview' );
        $LayoutObject->Block( Name => 'ActionList' );
        $LayoutObject->Block( Name => 'ActionOverview' );
        $LayoutObject->Block( Name => 'AddKey' );

        $Output .= $LayoutObject->Output( TemplateFile => 'AdminPGP' );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # ------------------------------------------------------------ #
    # add key
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'AddKey' ) {

        my %Errors;

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        $SessionObject->UpdateSessionID(
            SessionID => $Self->{SessionID},
            Key       => 'PGPSearch',
            Value     => '',
        );
        my %UploadStuff = $ParamObject->GetUploadAll(
            Param => 'FileUpload',
        );
        if ( !%UploadStuff ) {
            $Errors{FileUploadInvalid} = 'ServerError';
        }

        # if no errors occurred
        if ( !%Errors ) {

            # add pgp key
            my $KeyAdd = $PGPObject->KeyAdd( Key => $UploadStuff{Content} );

            if ($KeyAdd) {
                $LayoutObject->Block( Name => 'Overview' );
                $LayoutObject->Block( Name => 'ActionList' );
                $LayoutObject->Block( Name => 'ActionSearch' );
                $LayoutObject->Block( Name => 'ActionAdd' );
                $LayoutObject->Block( Name => 'OverviewResult' );

                my @List = $PGPObject->KeySearch( Search => '' );
                if (@List) {
                    for my $Key (@List) {
                        $LayoutObject->Block(
                            Name => 'Row',
                            Data => { %{$Key} },
                        );
                    }
                }
                else {
                    $LayoutObject->Block(
                        Name => 'NoDataFoundMsg',
                        Data => {},
                    );
                }

                my $Output = $LayoutObject->Header();
                $Output .= $LayoutObject->NavigationBar();
                $Output .= $LayoutObject->Notify( Info => $KeyAdd );

                $Output .= $LayoutObject->Output( TemplateFile => 'AdminPGP' );
                $Output .= $LayoutObject->Footer();
                return $Output;
            }
        }

        # something went wrong
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $LayoutObject->Notify( Priority => 'Error' );
        $LayoutObject->Block( Name => 'Overview' );
        $LayoutObject->Block( Name => 'ActionList' );
        $LayoutObject->Block( Name => 'ActionOverview' );
        $LayoutObject->Block(
            Name => 'AddKey',
            Data => \%Errors,
        );
        $Output .= $LayoutObject->Output( TemplateFile => 'AdminPGP' );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # ------------------------------------------------------------ #
    # download key
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'Download' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my $Key  = $ParamObject->GetParam( Param => 'Key' )  || '';
        my $Type = $ParamObject->GetParam( Param => 'Type' ) || '';
        if ( !$Key ) {
            return $LayoutObject->ErrorScreen(
                Message => Translatable('Need param Key to download!'),
            );
        }
        my $KeyString = '';
        my $Prefix    = '';
        if ( $Type eq 'sec' ) {
            $KeyString = $PGPObject->SecretKeyGet( Key => $Key );
            $Prefix    = 'Secret';
        }
        else {
            $KeyString = $PGPObject->PublicKeyGet( Key => $Key );
            $Prefix    = 'Public';
        }
        return $LayoutObject->Attachment(
            ContentType => 'text/plain',
            Content     => $KeyString,
            Filename    => $Prefix . '-' . $Key . '.asc',
            Type        => 'attachment',
        );
    }

    # ------------------------------------------------------------ #
    # download fingerprint
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'DownloadFingerprint' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my $Key  = $ParamObject->GetParam( Param => 'Key' )  || '';
        my $Type = $ParamObject->GetParam( Param => 'Type' ) || '';
        if ( !$Key ) {
            return $LayoutObject->ErrorScreen(
                Message => Translatable('Need param Key to download!'),
            );
        }
        my $Download = '';
        my $Prefix   = '';
        if ( $Type eq 'sec' ) {
            my @Result = $PGPObject->PrivateKeySearch( Search => $Key );
            if ( $Result[0] ) {
                $Download = $Result[0]->{Fingerprint};
                $Prefix   = 'Private';
            }
        }
        else {
            my @Result = $PGPObject->PublicKeySearch( Search => $Key );
            if ( $Result[0] ) {
                $Download = $Result[0]->{Fingerprint};
                $Prefix   = 'Public';
            }
        }
        return $LayoutObject->Attachment(
            ContentType => 'text/plain',
            Content     => $Download,
            Filename    => $Prefix . '-' . $Key . '.txt',
            Type        => 'attachment',
        );
    }

    # ------------------------------------------------------------ #
    # search key
    # ------------------------------------------------------------ #
    else {

        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();

        $LayoutObject->Block( Name => 'Overview' );
        $LayoutObject->Block( Name => 'ActionList' );
        $LayoutObject->Block( Name => 'ActionSearch' );
        $LayoutObject->Block( Name => 'ActionAdd' );
        $LayoutObject->Block( Name => 'Hint' );
        $LayoutObject->Block( Name => 'OverviewResult' );

        my @List = ();
        if ($PGPObject) {
            @List = $PGPObject->KeySearch( Search => $Param{Search} );
        }
        if (@List) {
            for my $Key (@List) {
                $LayoutObject->Block(
                    Name => 'Row',
                    Data => { %{$Key} },
                );
            }
        }
        else {
            $LayoutObject->Block(
                Name => 'NoDataFoundMsg',
                Data => {},
            );
        }

        if ( $PGPObject && $PGPObject->Check() ) {
            $Output .= $LayoutObject->Notify(
                Priority => 'Error',
                Data     => $LayoutObject->{LanguageObject}->Translate( $PGPObject->Check() ),
            );
        }
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminPGP',
            Data         => \%Param
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
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
