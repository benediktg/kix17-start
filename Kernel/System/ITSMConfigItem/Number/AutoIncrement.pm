# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::ITSMConfigItem::Number::AutoIncrement;

use strict;
use warnings;

our $ObjectManagerDisabled = 1;

## no critic qw(Subroutines::ProhibitUnusedPrivateSubroutines)

=head1 NAME

Kernel::System::ITSMConfigItem::Number::AutoIncrement - config item number backend module

=head1 SYNOPSIS

All auto increment config item number functions

=over 4

=cut

=item _ConfigItemNumberCreate()

create a new config item number

    my $Number = $BackendObject->_ConfigItemNumberCreate(
        ClassID => 123,
    );

=cut

sub _ConfigItemNumberCreate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{ClassID} ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Need ClassID!',
        );
        return;
    }

    # get system id
    my $SystemID = $Kernel::OM->Get('Kernel::Config')->Get('SystemID');

    # get current counter
    my $CurrentCounter = $Self->CurrentCounterGet(
        ClassID => $Param{ClassID},
        Type    => 'AutoIncrement',
    ) || 0;

    CIPHER:
    for my $Cipher ( 1 .. 1_000_000_000 ) {

        # create new number
        my $Number = $SystemID . $Param{ClassID} . sprintf( "%06d", ( $CurrentCounter + $Cipher ) );

        # find existing number
        my $Duplicate = $Self->ConfigItemNumberLookup(
            ConfigItemNumber => $Number,
        );

        next CIPHER if $Duplicate;

        # set counter
        $Self->CurrentCounterSet(
            ClassID => $Param{ClassID},
            Type    => 'AutoIncrement',
            Counter => ( $CurrentCounter + $Cipher ),
        );

        return $Number;
    }

    return;
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
