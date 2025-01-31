# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Ticket::Event::DynamicFieldFromCustomerUser;

use strict;
use warnings;

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::CustomerUser',
    'Kernel::System::DynamicField',
    'Kernel::System::DynamicField::Backend',
    'Kernel::System::Log',
    'Kernel::System::Ticket',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Needed (qw(Data UserID)) {
        if ( !$Param{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!",
            );
            return;
        }
    }
    for my $Needed (qw(TicketID)) {
        if ( !$Param{Data}->{$Needed} ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed! in Data",
            );
            return;
        }
    }

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # get mapping config,
    my %Mapping = %{ $ConfigObject->Get('DynamicFieldFromCustomerUser::Mapping') || {} };

    # no mapping is OK
    return 1 if !%Mapping;

    # get customer user data, so that values can be stored in dynamic fields
    my %Ticket = $Kernel::OM->Get('Kernel::System::Ticket')->TicketGet(
        TicketID      => $Param{Data}->{TicketID},
        DynamicFields => 0,
        Silent        => 1,
        UserID        => 1,
    );
    return if ( !%Ticket );

    # get dynamic field objects
    my $DynamicFieldObject        = $Kernel::OM->Get('Kernel::System::DynamicField');
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');

    # get dynamic fields list
    my $DynamicFields = $DynamicFieldObject->DynamicFieldList(
        Valid      => 1,
        ObjectType => 'Ticket',
        ResultType => 'HASH',
    );

    my $DynamicFieldsReverse = { reverse %{$DynamicFields} };

    my %CustomerUserData = $Kernel::OM->Get('Kernel::System::CustomerUser')->CustomerUserDataGet(
        User          => $Ticket{CustomerUserID},
        DynamicFields => 1,
    );

    # also continue if there was no CustomerUser data found - erase values
    # loop over the configured mapping of customer data variables to dynamic fields
    CUSTOMERUSERVARIABLENAME:
    for my $CustomerUserVariableName ( sort keys %Mapping ) {

        # check config for the particular mapping
        if ( !defined $DynamicFieldsReverse->{ $Mapping{$CustomerUserVariableName} } ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message =>
                    "DynamicField $Mapping{$CustomerUserVariableName} in DynamicFieldFromCustomerUser::Mapping must be set in system and valid.",
            );
            next CUSTOMERUSERVARIABLENAME;
        }

        my $DynamicFieldConfig = $DynamicFieldObject->DynamicFieldGet(
            Name => $Mapping{$CustomerUserVariableName},
        );

        # update dynamic field value for ticket
        $DynamicFieldBackendObject->ValueSet(
            DynamicFieldConfig => $DynamicFieldConfig,
            ObjectID           => $Param{Data}->{TicketID},
            Value              => $CustomerUserData{$CustomerUserVariableName} || '',
            UserID             => $Param{UserID},
        );
    }

    return 1;
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
