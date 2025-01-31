# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::ReferenceData;

use strict;
use warnings;

use Locale::Country qw(all_country_names country2code);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Log',
);

=head1 NAME

Kernel::System::ReferenceData - ReferenceData lib

=head1 SYNOPSIS

Contains reference data. For now, this is limited to just a list of ISO country
codes.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object. Do not use it directly, instead use:

    use Kernel::System::ObjectManager;
    local $Kernel::OM = Kernel::System::ObjectManager->new();
    my $ReferenceDataObject = $Kernel::OM->Get('Kernel::System::ReferenceData');

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    return $Self;
}

=item CountryList()

DEPRECATED: This function will be removed in further versions of KIX

return a list of countries as a hash reference. The countries are based on ISO
3166-2 and are provided by the Perl module Locale::Code::Country, or optionally
from the SysConfig setting ReferenceData::OwnCountryList.

    my $CountryList = $ReferenceDataObject->CountryList(
       Result => 'CODE', # optional: returns CODE => Country pairs conform ISO 3166-2.
    );

=cut

sub CountryList {
    my ( $Self, %Param ) = @_;

    if ( !defined $Param{Result} || $Param{Result} ne 'CODE' ) {
        $Param{Result} = undef;
    }

    my $Countries = $Kernel::OM->Get('Kernel::Config')->Get('ReferenceData::OwnCountryList');

    if ( $Param{Result} && $Countries ) {

        # return Code => Country pairs from SysConfig
        return $Countries;
    }
    elsif ($Countries) {

        # return Country => Country pairs from SysConfig
        my %CountryJustNames = map { $_ => $_ } values %$Countries;
        return \%CountryJustNames;
    }

    my @CountryNames = all_country_names();

    if ( !@CountryNames ) {
        $Kernel::OM->Get('Kernel::System::Log')->Log(
            Priority => 'error',
            Message  => 'Country name list is empty!',
        );
    }

    if ( $Param{Result} ) {

        # return Code => Country pairs from ISO list
        my %Countries;
        for my $Country (@CountryNames) {
            $Countries{$Country} = country2code( $Country, 1 );
        }
        return \%Countries;
    }

    # return Country => Country pairs from ISO list
    my %CountryNames = map { $_ => $_ } @CountryNames;

    return \%CountryNames;
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
