# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AdminGroup;

use strict;
use warnings;

use Kernel::System::Valid;
use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    $Self->{Config} = $Kernel::OM->Get('Kernel::Config')->{'Admin::Frontend::AdminGroup'};

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $GroupObject  = $Kernel::OM->Get('Kernel::System::Group');
    my $LogObject    = $Kernel::OM->Get('Kernel::System::Log');
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # ------------------------------------------------------------ #
    # change
    # ------------------------------------------------------------ #
    if ( $Self->{Subaction} eq 'Change' ) {
        my $ID = $ParamObject->GetParam( Param => 'ID' )
            || $ParamObject->GetParam( Param => 'GroupID' )
            || '';
        my %Data   = $GroupObject->GroupGet( ID => $ID );
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Self->_Edit(
            Action => 'Change',
            %Data,
        );
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminGroup',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # ------------------------------------------------------------ #
    # change action
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'ChangeAction' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my $Note = '';
        my ( %GetParam, %Errors );
        for my $Parameter (qw(ID Name Comment ValidID)) {
            $GetParam{$Parameter} = $ParamObject->GetParam( Param => $Parameter ) || '';
        }

        # check for needed data
        if ( !$GetParam{Name} ) {
            $Errors{GroupNameInvalid} = 'ServerError';
        }

        # if no errors occurred
        if ( !%Errors ) {

            # update group
            my $GroupUpdate = $GroupObject->GroupUpdate(
                %GetParam,
                UserID => $Self->{UserID}
            );

            if ($GroupUpdate) {
                $Self->_Overview();
                my $Output = $LayoutObject->Header();
                $Output .= $LayoutObject->NavigationBar();
                $Output .= $LayoutObject->Notify( Info => Translatable('Group updated!') );
                $Output .= $LayoutObject->Output(
                    TemplateFile => 'AdminGroup',
                    Data         => \%Param,
                );
                $Output .= $LayoutObject->Footer();
                return $Output;
            }
            else {
                $Note = $LogObject->GetLogEntry(
                    Type => 'Error',
                    What => 'Message',
                );
            }
        }

        # something went wrong
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $Note
            ? $LayoutObject->Notify(
            Priority => 'Error',
            Info     => $Note,
            )
            : '';
        $Self->_Edit(
            Action => 'Change',
            %GetParam,
            %Errors,
        );
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminGroup',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # ------------------------------------------------------------ #
    # add
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'Add' ) {
        my %GetParam = ();

        $GetParam{Name} = $ParamObject->GetParam( Param => 'Name' );

        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Self->_Edit(
            Action => 'Add',
            %GetParam,
        );
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminGroup',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # ------------------------------------------------------------ #
    # add action
    # ------------------------------------------------------------ #
    elsif ( $Self->{Subaction} eq 'AddAction' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my $Note = '';
        my $GroupID;
        my ( %GetParam, %Errors );
        for my $Parameter (qw(ID Name Comment ValidID)) {
            $GetParam{$Parameter} = $ParamObject->GetParam( Param => $Parameter ) || '';
        }

        # check for needed data
        if ( !$GetParam{Name} ) {
            $Errors{GroupNameInvalid} = 'ServerError';
        }

        # if no errors occurred
        if ( !%Errors ) {

            # add group
            $GroupID = $GroupObject->GroupAdd(
                %GetParam,
                UserID => $Self->{UserID}
            );

            if ($GroupID) {

                # redirect
                if (
                    !$ConfigObject->Get('Frontend::Module')->{AdminUserGroup}
                    && $ConfigObject->Get('Frontend::Module')->{AdminRoleGroup}
                ) {
                    return $LayoutObject->Redirect(
                        OP => "Action=AdminRoleGroup;Subaction=Group;ID=$GroupID",
                    );
                }
                if ( $ConfigObject->Get('Frontend::Module')->{AdminUserGroup} ) {
                    return $LayoutObject->Redirect(
                        OP => "Action=AdminUserGroup;Subaction=Group;ID=$GroupID",
                    );
                }
                return $LayoutObject->Redirect(
                    OP => 'Action=AdminGroup',
                );
            }
            else {
                $Note = $LogObject->GetLogEntry(
                    Type => 'Error',
                    What => 'Message',
                );
            }
        }

        # something went wrong
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $Note ? $LayoutObject->Notify(
            Priority => 'Error',
            Info     => $Note,
        ) : '';
        $Self->_Edit(
            Action => 'Add',
            %GetParam,
            %Errors,
        );
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminGroup',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;

    }

    # ------------------------------------------------------------
    # overview
    # ------------------------------------------------------------
    else {
        $Self->_Overview();
        my $Output = $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();
        $Output .= $LayoutObject->Output(
            TemplateFile => 'AdminGroup',
            Data         => \%Param,
        );
        $Output .= $LayoutObject->Footer();
        return $Output;
    }

}

sub _Edit {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $ValidObject  = $Kernel::OM->Get('Kernel::System::Valid');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');

    # get validiy filter
    $Param{ValidityFilter} = $ParamObject->GetParam( Param => 'ValidityFilter' ) // $Self->{Config}->{ValidityFilter};

    $LayoutObject->Block(
        Name => 'Overview',
        Data => \%Param,
    );

    $LayoutObject->Block( Name => 'ActionList' );
    $LayoutObject->Block(
        Name => 'ActionOverview',
        Data => {
            ValidityFilter => $Param{ValidityFilter}
        }
    );

    # get valid list
    my %ValidList        = $ValidObject->ValidList();
    my %ValidListReverse = reverse %ValidList;

    $Param{ValidOption} = $LayoutObject->BuildSelection(
        Data       => \%ValidList,
        Name       => 'ValidID',
        Class      => 'Modernize',
        SelectedID => $Param{ValidID} || $ValidListReverse{valid},
    );

    $LayoutObject->Block(
        Name => 'OverviewUpdate',
        Data => \%Param,
    );

    # shows header
    if ( $Param{Action} eq 'Change' ) {
        $LayoutObject->Block( Name => 'HeaderEdit' );
    }
    else {
        $LayoutObject->Block( Name => 'HeaderAdd' );
    }

    return 1;
}

sub _Overview {
    my ( $Self, %Param ) = @_;

    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $GroupObject  = $Kernel::OM->Get('Kernel::System::Group');
    my $ValidObject  = $Kernel::OM->Get('Kernel::System::Valid');
    my $ParamObject  = $Kernel::OM->Get('Kernel::System::Web::Request');

    # get valid list
    my %ValidList          = $ValidObject->ValidList();
    $Param{ValidityFilter} = $ParamObject->GetParam( Param => 'ValidityFilter' ) // $Self->{Config}->{ValidityFilter};

    $Param{ValidOption} = $LayoutObject->BuildSelection(
        Data       => {
            %ValidList,
            0 => 'all'
        },
        Name       => 'ValidityFilter',
        SelectedID => $Param{ValidityFilter},
        Class      => 'Modernize Fullsize',
    );

    $LayoutObject->Block(
        Name => 'Overview',
        Data => \%Param,
    );

    $LayoutObject->Block( Name => 'ActionList' );
    $LayoutObject->Block( Name => 'ActionAdd' );
    $LayoutObject->Block(
        Name => 'ActionFilter',
        Data => {
            %Param
        }
    );

    my %List = $GroupObject->GroupList(
        Valid => $Param{ValidityFilter},
    );

    my $ListSize = keys %List;
    $Param{AllItemsCount} = $ListSize;

    $LayoutObject->Block(
        Name => 'OverviewResult',
        Data => \%Param,
    );

    for my $ListKey ( sort { $List{$a} cmp $List{$b} } keys %List ) {

        my %Data = $GroupObject->GroupGet(
            ID => $ListKey,
        );
        $LayoutObject->Block(
            Name => 'OverviewResultRow',
            Data => {
                Valid          => $ValidList{ $Data{ValidID} },
                ValidityFilter => $Param{ValidityFilter},
                %Data,
            },
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
