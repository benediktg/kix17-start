# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AdminSelectBox;

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

    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    $Param{ResultFormatStrg} = $LayoutObject->BuildSelection(
        Name  => 'ResultFormat',
        Data  => [ 'HTML', 'CSV', 'Excel' ],
        Class => 'Modernize',
    );

    if ( !$ConfigObject->Get('AdminSelectBox::AllowDatabaseModification') ) {
        $LayoutObject->Block(
            Name => 'ExplanationOnlySelect',
        );
    }
    else {
        $LayoutObject->Block(
            Name => 'ExplanationAllSqlQueries',
        );
    }

    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');

    # ------------------------------------------------------------ #
    # do select
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'Select' ) {
        my %Errors;

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        # get params
        for my $Parameter (qw(SQL Max ResultFormat)) {
            $Param{$Parameter} = $ParamObject->GetParam( Param => $Parameter ) || '';
        }

        # check needed data
        if ( !$Param{SQL} ) {
            $Errors{SQLInvalid} = 'ServerError';
            $Errors{ErrorType}  = 'FieldRequired';
        }

        # check if enabled all SQL queries
        if ( !$ConfigObject->Get('AdminSelectBox::AllowDatabaseModification') ) {

            # check if SQL query is "SELECT" one
            if ( uc( $Param{SQL} ) !~ m{ \A \s* (?:SELECT|SHOW|DESC) }smx ) {
                $Errors{SQLInvalid} = 'ServerError';
                $Errors{ErrorType}  = 'SQLIsNotSelect';
            }
        }

        # if no errors occurred
        if ( !%Errors ) {

            my $DBObject = $Kernel::OM->Get('Kernel::System::DB');

            # fetch database and add row blocks
            if (
                $DBObject->Prepare(
                    SQL   => $Param{SQL},
                    Limit => $Param{Max}
                )
            ) {

                my @Data;
                my $MatchesFound;

                # add result block
                $LayoutObject->Block(
                    Name => 'Result',
                    Data => \%Param,
                );

                my @Head = $DBObject->GetColumnNames();
                for my $Column (@Head) {
                    $LayoutObject->Block(
                        Name => 'ColumnHead',
                        Data => {
                            ColumnName => $Column,
                        },
                    );
                }

                # if there are any matching rows, they are shown
                ROW:
                while ( my @Row = $DBObject->FetchrowArray( RowNames => 1 ) ) {

                    $MatchesFound = 1;

                    # get csv data
                    if (
                        $Param{ResultFormat} eq 'CSV'
                        || $Param{ResultFormat} eq 'Excel'
                    ) {
                        push @Data, \@Row;
                        next ROW;
                    }

                    $LayoutObject->Block(
                        Name => 'Row',
                    );

                    # get html data
                    my $Row = '';
                    for my $Item (@Row) {
                        if ( !defined $Item ) {
                            $Item = 'NULL';
                        }

                        $LayoutObject->Block(
                            Name => 'Cell',
                            Data => {
                                Content => $Item,
                            },
                        );
                    }
                }

                # otherwise a no matches found msg is displayed
                if ( !$MatchesFound ) {
                    if ( uc( $Param{SQL} ) !~ m{ \A \s* (?:SELECT|SHOW|DESC) }smx ) {
                        $LayoutObject->Block(
                            Name => 'NoSelectResult',
                            Data => {
                                Colspan => scalar @Head,
                            },
                        );
                    }
                    else {
                        $LayoutObject->Block(
                            Name => 'NoMatches',
                            Data => {
                                Colspan => scalar @Head,
                            },
                        );
                    }
                }

                # get Separator from language file
                my $UserCSVSeparator = $LayoutObject->{LanguageObject}->{Separator};

                if ( $ConfigObject->Get('PreferencesGroups')->{CSVSeparator}->{Active} ) {
                    my %UserData = $Kernel::OM->Get('Kernel::System::User')->GetUserData( UserID => $Self->{UserID} );
                    $UserCSVSeparator = $UserData{UserCSVSeparator} if $UserData{UserCSVSeparator};
                }

                my $TimeStamp = $Kernel::OM->Get('Kernel::System::Time')->CurrentTimestamp();
                $TimeStamp =~ s/[:-]//g;
                $TimeStamp =~ s/ /-/;
                my $FileName  = 'admin-select-' . $TimeStamp;
                my $CSVObject = $Kernel::OM->Get('Kernel::System::CSV');

                # generate csv output
                if ( $Param{ResultFormat} eq 'CSV' ) {
                    my $CSV = $CSVObject->Array2CSV(
                        Head      => \@Head,
                        Data      => \@Data,
                        Separator => $UserCSVSeparator,
                    );
                    return $LayoutObject->Attachment(
                        Filename    => "$FileName" . ".csv",
                        ContentType => 'text/csv',
                        Content     => $CSV,
                        Type        => 'attachment'
                    );
                }

                # generate Excel output
                elsif ( $Param{ResultFormat} eq 'Excel' ) {
                    my $Excel = $CSVObject->Array2CSV(
                        Head   => \@Head,
                        Data   => \@Data,
                        Format => 'Excel',
                    );
                    return $LayoutObject->Attachment(
                        Filename => "$FileName" . ".xlsx",
                        ContentType =>
                            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                        Content => $Excel,
                        Type    => 'attachment'
                    );
                }

                # generate html output
                my $Output = $LayoutObject->Header();
                $Output .= $LayoutObject->NavigationBar();
                $Output .= $LayoutObject->Output(
                    TemplateFile => 'AdminSelectBox',
                    Data         => \%Param,
                );
                $Output .= $LayoutObject->Footer();
                return $Output;
            }
            else {
                $Errors{ErrorMessage} = $Kernel::OM->Get('Kernel::System::Log')->GetLogEntry(
                    Type => 'Error',
                    What => 'Message',
                );
                $Errors{ErrorType} = ( $Errors{ErrorMessage} =~ /bind/i ) ? 'BindParam' : 'SQLSyntax';
                $Errors{SQLInvalid} = 'ServerError';
            }
        }

        # add server error message block
        $LayoutObject->Block( Name => $Errors{ErrorType} . 'ServerError' );

        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $LayoutObject->Notify(
            Info     => $Errors{ErrorMessage},
            Priority => 'Error'
        );
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminSelectBox',
            Data         => {
                %Param,
                %Errors,
            },
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # ------------------------------------------------------------ #
    # print form
    # ------------------------------------------------------------ #
    else {

        # get params
        $Param{SQL} = $ParamObject->GetParam( Param => 'SQL' ) || 'SELECT * FROM ';
        $Param{Max} = $ParamObject->GetParam( Param => 'Max' ) || 40;

        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminSelectBox',
            Data         => \%Param,
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
