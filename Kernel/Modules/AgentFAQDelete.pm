# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AgentFAQDelete;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # get layout object
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # permission check
    if ( !$Self->{AccessRo} ) {
        return $LayoutObject->NoPermission(
            Message    => 'You need ro permission!',
            WithHeader => 'yes',
        );
    }

    # get params
    my %GetParam;

    # get needed Item id
    $GetParam{ItemID} = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'ItemID' );

    # check needed stuff
    if ( !$GetParam{ItemID} ) {

        # error page
        return $LayoutObject->ErrorScreen(
            Message => "No ItemID is given!",
            Comment => 'Please contact the administrator.',
        );
    }

    # get FAQ object
    my $FAQObject = $Kernel::OM->Get('Kernel::System::FAQ');

    # get FAQ item data
    my %FAQData = $FAQObject->FAQGet(
        ItemID     => $GetParam{ItemID},
        ItemFields => 0,
        UserID     => $Self->{UserID},
    );
    if ( !%FAQData ) {
        return $LayoutObject->ErrorScreen();
    }

    # check user permission
    my $Permission = $FAQObject->CheckCategoryUserPermission(
        UserID     => $Self->{UserID},
        CategoryID => $FAQData{CategoryID},
    );

    # show error message
    if ( !$Permission ) {
        return $LayoutObject->NoPermission(
            Message    => 'You have no permission for this category!',
            WithHeader => 'yes',
        );
    }

    if ( $Self->{Subaction} eq 'Delete' ) {

        # delete the FAQ article
        my $CouldDeleteItem = $FAQObject->FAQDelete(
            ItemID => $FAQData{ItemID},
            UserID => $Self->{UserID},
        );

        if ($CouldDeleteItem) {

            # redirect to explorer, when the deletion was successful
            return $LayoutObject->Redirect(
                OP => "Action=AgentFAQExplorer;CategoryID=$FAQData{CategoryID}",
            );
        }
        else {

            # show error message, when delete failed
            return $LayoutObject->ErrorScreen(
                Message => "Was not able to delete the FAQ article $FAQData{ItemID}!",
                Comment => 'Please contact the administrator.',
            );
        }
    }

    # set the dialog type. As default, the dialog will have 2 buttons: Yes and No
    my $DialogType = 'Confirmation';

    # output content
    my $Output = $LayoutObject->Output(
        TemplateFile => 'AgentFAQDelete',
        Data         => {
            %Param,
            %FAQData,
        },
    );

    # build the returned data structure
    my %Data = (
        HTML       => $Output,
        DialogType => $DialogType,
    );

    # return JSON-String because of AJAX-Mode
    my $OutputJSON = $LayoutObject->JSONEncode( Data => \%Data );

    return $LayoutObject->Attachment(
        ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
        Content     => $OutputJSON,
        Type        => 'inline',
        NoCache     => 1,
    );
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
