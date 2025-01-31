# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::AgentTicketEmail;

use strict;
use warnings;

use Mail::Address;

use Kernel::System::VariableCheck qw(:all);
use Kernel::Language qw(Translatable);

our $ObjectManagerDisabled = 1;

use base qw(Kernel::Modules::BaseTicketTemplateHandler);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    my $Config = $Kernel::OM->Get('Kernel::Config')->Get("Ticket::Frontend::$Self->{Action}");

    # get the dynamic fields for this screen
    $Self->{DynamicField} = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldListGet(
        Valid       => 1,
        ObjectType  => [ 'Ticket', 'Article' ],
        FieldFilter => $Config->{DynamicField} || {},
    );

    # get form id
    $Self->{FormID} = $Kernel::OM->Get('Kernel::System::Web::Request')->GetParam( Param => 'FormID' );

    # create form id
    if ( !$Self->{FormID} ) {
        $Self->{FormID} = $Kernel::OM->Get('Kernel::System::Web::UploadCache')->FormIDCreate();
    }

    # handle for quick ticket templates
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');
    $Self->{DefaultSet}            = $ParamObject->GetParam( Param => 'DefaultSet' ) || 0;
    $Self->{DefaultSetTypeChanged} = $ParamObject->GetParam( Param => 'DefaultSetTypeChanged' ) || 0;
    $Self->{ActionReal}            = $Self->{Action};

    return $Self;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $Output;

    # store last queue screen
    if ( $Self->{LastScreenOverview} && $Self->{LastScreenOverview} !~ /Action=AgentTicketEmail/ ) {
        $Kernel::OM->Get('Kernel::System::AuthSession')->UpdateSessionID(
            SessionID => $Self->{SessionID},
            Key       => 'LastScreenOverview',
            Value     => $Self->{RequestedURL},
        );
    }

    # get needed objects
    my $ParamObject       = $Kernel::OM->Get('Kernel::System::Web::Request');
    my $UploadCacheObject = $Kernel::OM->Get('Kernel::System::Web::UploadCache');
    my $TicketObject      = $Kernel::OM->Get('Kernel::System::Ticket');
    my $QueueObject       = $Kernel::OM->Get('Kernel::System::Queue');
    my $MainObject        = $Kernel::OM->Get('Kernel::System::Main');
    my $ConfigObject      = $Kernel::OM->Get('Kernel::Config');
    my $LinkObject        = $Kernel::OM->Get('Kernel::System::LinkObject');

    my $Debug = $Param{Debug} || 0;
    my $Config = $ConfigObject->Get("Ticket::Frontend::$Self->{Action}");

    # get params
    my %GetParam;
    for my $Key (
        qw(Year Month Day Hour Minute To Cc Bcc TimeUnits PriorityID Subject Body
        TypeID ServiceID SLAID OwnerAll ResponsibleAll NewResponsibleID NewUserID
        NextStateID StandardTemplateID
        Dest DefaultSetTypeChanged SelectedConfigItemIDs CustomerID
        )
    ) {
        $GetParam{$Key} = $ParamObject->GetParam( Param => $Key );
    }

    my @SelectedCIIDs;
    if ( defined $GetParam{SelectedConfigItemIDs} && $GetParam{SelectedConfigItemIDs} ) {
        my $ConfigItemIDStrg = $GetParam{SelectedConfigItemIDs};
        $ConfigItemIDStrg =~ s/^,//g;
        @SelectedCIIDs = split( ',', $ConfigItemIDStrg );
    }
    $GetParam{DefaultSet} = $Self->{DefaultSet} || 0;
    $GetParam{LinkTicketID} = $ParamObject->GetParam( Param => 'LinkTicketID' ) || '';

    # ACL compatibility translation
    my %ACLCompatGetParam;
    $ACLCompatGetParam{OwnerID} = $GetParam{NewUserID};

    # If is an action about attachments
    my $IsUpload = ( $ParamObject->GetParam( Param => 'AttachmentUpload' ) ? 1 : 0 );

    # hash for check duplicated entries
    my %AddressesList;

    # MultipleCustomer To-field
    my @MultipleCustomer;
    my $CustomersNumber = $ParamObject->GetParam( Param => 'CustomerTicketCounterToCustomer' ) || 0;
    my $Selected = $ParamObject->GetParam( Param => 'CustomerSelected' ) || '';

    # get check item object
    my $CheckItemObject = $Kernel::OM->Get('Kernel::System::CheckItem');

    if ($CustomersNumber) {
        my $CustomerCounter = 1;
        for my $Count ( 1 ... $CustomersNumber ) {
            my $CustomerElement = $ParamObject->GetParam( Param => 'CustomerTicketText_' . $Count );
            my $CustomerSelected = ( $Selected eq $Count ? 'checked="checked"' : '' );
            my $CustomerKey = $ParamObject->GetParam( Param => 'CustomerKey_' . $Count )
                || '';

            if ($CustomerElement) {

                if ( $GetParam{To} ) {
                    $GetParam{To} .= ', ' . $CustomerElement;
                }
                else {
                    $GetParam{To} = $CustomerElement;
                }

                my $CustomerErrorMsg = 'CustomerGenericServerErrorMsg';
                my $CustomerError    = '';
                my $CustomerDisabled = '';
                my $CountAux         = $CustomerCounter++;

                if ( !$IsUpload ) {

                    # check email address
                    for my $Email ( Mail::Address->parse($CustomerElement) ) {
                    if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                            $CustomerErrorMsg = $CheckItemObject->CheckErrorType()
                                . 'ServerErrorMsg';
                            $CustomerError = 'ServerError';
                        }
                    }

                    # check for duplicated entries
                    if ( defined $AddressesList{$CustomerElement} && $CustomerError eq '' ) {
                        $CustomerErrorMsg = 'IsDuplicatedServerErrorMsg';
                        $CustomerError    = 'ServerError';
                    }

                    if ( $CustomerError ne '' ) {
                        $CustomerDisabled = 'disabled="disabled"';
                        $CountAux         = $Count . 'Error';
                    }
                }

                push @MultipleCustomer, {
                    Count            => $CountAux,
                    CustomerElement  => $CustomerElement,
                    CustomerSelected => $CustomerSelected,
                    CustomerKey      => $CustomerKey,
                    CustomerError    => $CustomerError,
                    CustomerErrorMsg => $CustomerErrorMsg,
                    CustomerDisabled => $CustomerDisabled,
                };
                $AddressesList{$CustomerElement} = 1;
            }
        }
    }

    # MultipleCustomer Cc-field
    my @MultipleCustomerCc;
    my $CustomersNumberCc = $ParamObject->GetParam( Param => 'CustomerTicketCounterCcCustomer' ) || 0;

    if ($CustomersNumberCc) {
        my $CustomerCounterCc = 1;
        for my $Count ( 1 ... $CustomersNumberCc ) {
            my $CustomerElementCc = $ParamObject->GetParam( Param => 'CcCustomerTicketText_' . $Count );
            my $CustomerKeyCc     = $ParamObject->GetParam( Param => 'CcCustomerKey_' . $Count )
                || '';

            if ($CustomerElementCc) {
                my $CustomerErrorMsgCc = 'CustomerGenericServerErrorMsg';
                my $CustomerErrorCc    = '';
                my $CustomerDisabledCc = '';
                my $CountAuxCc         = $CustomerCounterCc++;

                if ( !$IsUpload ) {

                    if ( $GetParam{Cc} ) {
                        $GetParam{Cc} .= ', ' . $CustomerElementCc;
                    }
                    else {
                        $GetParam{Cc} = $CustomerElementCc;
                    }

                    # check email address
                    for my $Email ( Mail::Address->parse($CustomerElementCc) ) {
                        if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                            $CustomerErrorMsgCc = $CheckItemObject->CheckErrorType()
                                . 'ServerErrorMsg';
                            $CustomerErrorCc = 'ServerError';
                        }
                    }

                    # check for duplicated entries
                    if ( defined $AddressesList{$CustomerElementCc} && $CustomerErrorCc eq '' ) {
                        $CustomerErrorMsgCc = 'IsDuplicatedServerErrorMsg';
                        $CustomerErrorCc    = 'ServerError';
                    }

                    if ( $CustomerErrorCc ne '' ) {
                        $CustomerDisabledCc = 'disabled="disabled"';
                        $CountAuxCc         = $Count . 'Error';
                    }
                }

                push @MultipleCustomerCc, {
                    Count            => $CountAuxCc,
                    CustomerElement  => $CustomerElementCc,
                    CustomerKey      => $CustomerKeyCc,
                    CustomerError    => $CustomerErrorCc,
                    CustomerErrorMsg => $CustomerErrorMsgCc,
                    CustomerDisabled => $CustomerDisabledCc,
                };
                $AddressesList{$CustomerElementCc} = 1;
            }
        }
    }

    # MultipleCustomer Bcc-field
    my @MultipleCustomerBcc;
    my $CustomersNumberBcc = $ParamObject->GetParam( Param => 'CustomerTicketCounterBccCustomer' ) || 0;

    if ($CustomersNumberBcc) {
        my $CustomerCounterBcc = 1;
        for my $Count ( 1 ... $CustomersNumberBcc ) {
            my $CustomerElementBcc = $ParamObject->GetParam( Param => 'BccCustomerTicketText_' . $Count );
            my $CustomerKeyBcc     = $ParamObject->GetParam( Param => 'BccCustomerKey_' . $Count )
                || '';

            if ($CustomerElementBcc) {

                my $CustomerDisabledBcc = '';
                my $CountAuxBcc         = $CustomerCounterBcc++;
                my $CustomerErrorMsgBcc = 'CustomerGenericServerErrorMsg';
                my $CustomerErrorBcc    = '';
                if ( !$IsUpload ) {

                    if ( $GetParam{Bcc} ) {
                        $GetParam{Bcc} .= ', ' . $CustomerElementBcc;
                    }
                    else {
                        $GetParam{Bcc} = $CustomerElementBcc;
                    }

                    # check email address
                    for my $Email ( Mail::Address->parse($CustomerElementBcc) ) {
                        if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                            $CustomerErrorMsgBcc = $CheckItemObject->CheckErrorType()
                                . 'ServerErrorMsg';
                            $CustomerErrorBcc = 'ServerError';
                        }
                    }

                    # check for duplicated entries
                    if ( defined $AddressesList{$CustomerElementBcc} && $CustomerErrorBcc eq '' ) {
                        $CustomerErrorMsgBcc = 'IsDuplicatedServerErrorMsg';
                        $CustomerErrorBcc    = 'ServerError';
                    }

                    if ( $CustomerErrorBcc ne '' ) {
                        $CustomerDisabledBcc = 'disabled="disabled"';
                        $CountAuxBcc         = $Count . 'Error';
                    }
                }

                push @MultipleCustomerBcc, {
                    Count            => $CountAuxBcc,
                    CustomerElement  => $CustomerElementBcc,
                    CustomerKey      => $CustomerKeyBcc,
                    CustomerError    => $CustomerErrorBcc,
                    CustomerErrorMsg => $CustomerErrorMsgBcc,
                    CustomerDisabled => $CustomerDisabledBcc,
                };
                $AddressesList{$CustomerElementBcc} = 1;
            }
        }
    }

    # set an empty value if not defined
    $GetParam{Cc}  = '' if !defined $GetParam{Cc};
    $GetParam{Bcc} = '' if !defined $GetParam{Bcc};

    # get Dynamic fields form ParamObject
    my %DynamicFieldValues;
# ---
# ITSMIncidentProblemManagement
# ---
    # to store the reference to the dynamic field for the impact
    my $ImpactDynamicFieldConfig;
# ---

    # get needed objects
    my $DynamicFieldBackendObject = $Kernel::OM->Get('Kernel::System::DynamicField::Backend');
    my $LayoutObject              = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # get needed objects
    my $DynamicFieldObject = $Kernel::OM->Get('Kernel::System::DynamicField');

    # handle email quick ticket configuration
    if ( $Self->{Action} eq 'AgentTicketEmailQuick' ) {
        $Self->{Action} = 'AgentTicketEmail';
        $Config = $ConfigObject->Get("Ticket::Frontend::$Self->{Action}");
        my $QuickConfig = $ConfigObject->Get('Ticket::Frontend::AgentTicketEmailQuick')
            || '';
        if ( $QuickConfig && ref($QuickConfig) eq 'HASH' ) {
            for my $Key ( keys %{$QuickConfig} ) {
                $Config->{$Key} = $QuickConfig->{$Key};
            }
        }
    }

    # get all dynamic fields
    $Self->{NotShownDynamicFields} = $DynamicFieldObject->DynamicFieldList(
        Valid      => 1,
        ObjectType => [ 'Ticket', 'Article' ],
        ResultType => 'HASH',
    );

    # create a lookup list
    %{ $Self->{NotShownDynamicFields} } = reverse %{ $Self->{NotShownDynamicFields} };

    for my $DynamicField ( sort keys %{ $Config->{DynamicField} } ) {

        # check if each field is active
        if ( $Config->{DynamicField}->{$DynamicField} ) {

            # remove all the fields that are actived for this screen
            delete $Self->{NotShownDynamicFields}->{$DynamicField};
        }
    }

    # prevent comparison errors by filling the non existent dynamic fields in the screen
    # configuration
    for my $DynamicField ( sort keys %{ $Self->{NotShownDynamicFields} } ) {
        if ( !defined $Config->{DynamicField}->{$DynamicField} ) {
            $Config->{DynamicField}->{$DynamicField} = 0;
        }
    }

    # Core.AJAX.js does not admit an empty string, then is necessary to define a string that
    # will set to empty right before is assigned to the HTML element (non select).
    $Self->{EmptyString} = '_DynamicTicketTemplate_EmptyString_Dont_Use_It_Please';

    # cycle through the activated Dynamic Fields for this screen
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

        # extract the dynamic field value form the web request
        $DynamicFieldValues{ $DynamicFieldConfig->{Name} } = $DynamicFieldBackendObject->EditFieldValueGet(
            DynamicFieldConfig => $DynamicFieldConfig,
            ParamObject        => $ParamObject,
            LayoutObject       => $LayoutObject,
        );
# ---
# ITSMIncidentProblemManagement
# ---
        # impact field was found
        if ( $DynamicFieldConfig->{Name} eq 'ITSMImpact' ) {

            # store the reference to the impact field
            $ImpactDynamicFieldConfig = $DynamicFieldConfig;
        }
# ---
    }
# ---
# ITSMIncidentProblemManagement
# ---
    # get needed stuff
    $GetParam{DynamicField_ITSMImpact} = $ParamObject->GetParam(Param => 'DynamicField_ITSMImpact');
    $GetParam{PriorityRC}              = $ParamObject->GetParam(Param => 'PriorityRC');
    $GetParam{ElementChanged}          = $ParamObject->GetParam(Param => 'ElementChanged') || '';

    # check if priority needs to be recalculated
    if ( $GetParam{ElementChanged} eq 'ServiceID' || $GetParam{ElementChanged} eq 'DynamicField_ITSMImpact' ) {
        $GetParam{PriorityRC} = 1;
    }

    my %Service;
    if ( $GetParam{ServiceID} ) {

        # get service
        %Service = $Kernel::OM->Get('Kernel::System::Service')->ServiceGet(
            ServiceID     => $GetParam{ServiceID},
            IncidentState => $Config->{ShowIncidentState} || 0,
            UserID        => $Self->{UserID},
        );

        # recalculate impact if impact is not set until now
        if ( !$GetParam{DynamicField_ITSMImpact} && $GetParam{ElementChanged} ne 'DynamicField_ITSMImpact' ) {

            # get default selection
            my $DefaultSelection = $ImpactDynamicFieldConfig->{Config}->{DefaultValue};

            if ($DefaultSelection) {

                # get default impact
                $GetParam{DynamicField_ITSMImpact} = $DefaultSelection;
                $GetParam{PriorityRC} = 1;
            }
        }

        # recalculate priority
        if ( $GetParam{PriorityRC} && $GetParam{DynamicField_ITSMImpact} ) {

            # get priority
            $GetParam{PriorityIDFromImpact} = $Kernel::OM->Get('Kernel::System::ITSMCIPAllocate')->PriorityAllocationGet(
                Criticality => $Service{Criticality},
                Impact      => $GetParam{DynamicField_ITSMImpact},
            );
        }
        if ( $GetParam{PriorityIDFromImpact} ) {
            $GetParam{PriorityID} = $GetParam{PriorityIDFromImpact};
        }
    }

    # no service was selected
    else {

        # do not show the default selection
        $ImpactDynamicFieldConfig->{Config}->{DefaultValue} = '';

        # show only the empty selection
        $ImpactDynamicFieldConfig->{Config}->{PossibleValues} = {};
        $GetParam{DynamicField_ITSMImpact} = '';
    }

    # set the selected impact
    $DynamicFieldValues{ITSMImpact} = $GetParam{DynamicField_ITSMImpact};
# ---

    # transform pending time, time stamp based on user time zone
    if (
        defined $GetParam{Year}
        && defined $GetParam{Month}
        && defined $GetParam{Day}
        && defined $GetParam{Hour}
        && defined $GetParam{Minute}
    ) {
        %GetParam = $LayoutObject->TransformDateSelection(
            %GetParam,
        );
    }

    # moved from below
    # get user preferences
    my %UserPreferences = $Kernel::OM->Get('Kernel::System::User')->GetUserData(
        UserID => $Self->{UserID},
    );

    if ( $Self->{DefaultSet}
        && ( !$Self->{Subaction}
        || $Self->{Subaction} eq 'Created' )
    ) {

        my %TemplateData = $Self->TicketTemplateReplace(
            IsUpload         => $IsUpload,
            Data             => \%GetParam,
            DefaultSet       => $Self->{DefaultSet},
            MultipleCustomer => \@MultipleCustomer,
            MultipleCustomerCc => \@MultipleCustomerCc,
            MultipleCustomerBcc => \@MultipleCustomerBcc,
        );

        for my $Key ( keys %TemplateData ) {
            next if $Key =~ m/^MultipleCustomer(Bc|C)?c?$/;
            $GetParam{$Key} = $TemplateData{$Key};

            if( $Key eq 'QuickTicketBody' ) {
                my %FormIDSeen;
                my @FormIDs  = $GetParam{$Key} =~ m/FormID=(\d+.\d+.\d+)/g;
                if( scalar @FormIDs ) {
                    $UploadCacheObject->FormIDRemove(
                        FormID => $Self->{FormID},
                    );

                    my @UFormIDs = grep { ! $FormIDSeen{$_} ++ } @FormIDs;
                    for my $ID ( @UFormIDs ) {
                        my @TemplateAttachment = $UploadCacheObject->FormIDGetAllFilesData(
                            FormID => $ID,
                        );
                        for my $TAttachment ( @TemplateAttachment ) {
                            $UploadCacheObject->FormIDAddFile(
                                %{$TAttachment},
                                FormID => $Self->{FormID},
                            );
                        }
                        $GetParam{$Key} =~ s/(FormID=)($ID)/$1$Self->{FormID}/g;
                    }
                }
            }

            elsif ( $TemplateData{$Key}
                    && $Key =~ /^QuickTicket/
                    && $Key ne 'QuickTicketDynamicFieldHash'
            ) {
                my $Attribute = $Key;
                $Attribute =~ s/^QuickTicket(.*)$/$1/gm;
                $ACLCompatGetParam{$Attribute} = $TemplateData{$Key};
            }

            elsif (
                $Key eq 'QuickTicketDynamicFieldHash'
                && IsHashRefWithData( $TemplateData{$Key} )
            ) {
                for my $DynamicField ( keys %{ $TemplateData{$Key} } ) {
                    my $DynamicFieldName = $DynamicField;
                    $DynamicFieldName   =~ s/^DynamicField_//;

                    $GetParam{$DynamicField}                 = $TemplateData{$Key}->{$DynamicField};
                    $DynamicFieldValues{ $DynamicFieldName } = $TemplateData{$Key}->{$DynamicField};
                }
            }
        }

        if (
            defined $TemplateData{MultipleCustomer}
            && ref $TemplateData{MultipleCustomer} eq 'ARRAY'
        ) {
            @MultipleCustomer = @{ $TemplateData{MultipleCustomer} };
        }
        if (
            defined $TemplateData{MultipleCustomerCc}
            && ref $TemplateData{MultipleCustomerCc} eq 'ARRAY'
        ) {
            @MultipleCustomerCc = @{ $TemplateData{MultipleCustomerCc} };
        }
        if (
            defined $TemplateData{MultipleCustomerBcc}
            && ref $TemplateData{MultipleCustomerBcc} eq 'ARRAY'
        ) {
            @MultipleCustomerBcc = @{ $TemplateData{MultipleCustomerBcc} };
        }
    }

    # convert dynamic field values into a structure for ACLs
    my %DynamicFieldACLParameters;
    DYNAMICFIELD:
    for my $DynamicField ( sort keys %DynamicFieldValues ) {
        next DYNAMICFIELD if !$DynamicField;
        next DYNAMICFIELD if !$DynamicFieldValues{$DynamicField};

        $DynamicFieldACLParameters{ 'DynamicField_' . $DynamicField } = $DynamicFieldValues{$DynamicField};
    }
    $GetParam{DynamicField} = \%DynamicFieldACLParameters;

    if ( !$Self->{Subaction} || $Self->{Subaction} eq 'Created' ) {

        # header
        $Output .= $LayoutObject->Header();
        $Output .= $LayoutObject->NavigationBar();

        # ticket split based on given ticket ID and without given article ID
        $GetParam{ArticleID} = $ParamObject->GetParam( Param => 'ArticleID' ) || '';
        $GetParam{LinkTicketID} = $ParamObject->GetParam( Param => 'LinkTicketID' )
            || '';
        if (
            $GetParam{ArticleID}
            && $GetParam{ArticleID} eq 'Split'
            && $GetParam{LinkTicketID}
        ) {
            my %Article = $TicketObject->ArticleFirstArticle(
                TicketID => $GetParam{LinkTicketID},
            );
            $GetParam{ArticleID} = $Article{ArticleID} || '';
        }

        # get split article if given
        my %Article;
        my %CustomerData;
        if ( $GetParam{ArticleID} && $GetParam{ArticleID} ne 'Split' ) {
            %Article = $TicketObject->ArticleGet( ArticleID => $GetParam{ArticleID} );
            $GetParam{QuickTicketSubject} ||= $TicketObject->TicketSubjectClean(
                TicketNumber => $Article{TicketNumber},
                Subject => $Article{Subject} || '',
            );

            # body preparation for plain text processing
            $GetParam{QuickTicketBody} ||= $LayoutObject->ArticleQuote(
                TicketID           => $Article{TicketID},
                ArticleID          => $GetParam{ArticleID},
                FormID             => $Self->{FormID},
                UploadCacheObject  => $UploadCacheObject,
                AttachmentsInclude => 1,
            );

            # show customer info
            if ( $Article{CustomerUserID} ) {
                $GetParam{QuickTicketCustomer} = $Article{CustomerUserID};
            }

            # for initial service and SLA search
            $GetParam{QuickTicketServiceID} = $Article{ServiceID} || '';
            $GetParam{QuickTicketSLAID}     = $Article{SLAID}     || '';
        }

        # if there is no ticket id!
        if ( !$Self->{TicketID} || ( $Self->{TicketID} && $Self->{Subaction} eq 'Created' ) ) {

            # notify info
            if ( $Self->{TicketID} ) {
                my %Ticket = $TicketObject->TicketGet( TicketID => $Self->{TicketID} );
                $Output .= $LayoutObject->Notify(
                    Info => $LayoutObject->{LanguageObject}->Translate(
                        'Ticket "%s" created!',
                        $Ticket{TicketNumber},
                    ),
                    Link => $LayoutObject->{Baselink}
                        . 'Action=AgentTicketZoom;TicketID='
                        . $Ticket{TicketID},
                );
            }

            # get needed objects
            my $TypeObject         = $Kernel::OM->Get('Kernel::System::Type');
            my $StateObject        = $Kernel::OM->Get('Kernel::System::State');
            my $ServiceObject      = $Kernel::OM->Get('Kernel::System::Service');
            my $SLAObject          = $Kernel::OM->Get('Kernel::System::SLA');
            my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');

            # get customer from quick ticket
            if ( $GetParam{QuickTicketCustomer} ) {
                %CustomerData = $CustomerUserObject->CustomerUserDataGet(
                    User => $GetParam{QuickTicketCustomer},
                );
                if (
                    $CustomerData{UserCustomerID}
                    && $CustomerData{UserID}
                    && $CustomerData{UserEmail}
                ) {
                    my $CustomerName = $CustomerUserObject->CustomerName( UserLogin => $CustomerData{UserID} );
                    $GetParam{To} = '"' . $CustomerName . '" '
                                  . '<' . $CustomerData{UserEmail} . '>';
                    $GetParam{CustomerID}            = $CustomerData{UserCustomerID};
                    $GetParam{CustomerUserID}        = $CustomerData{UserID};
                    $CustomerData{CustomerUserLogin} = $CustomerData{UserID};
                }
                else {
                    $GetParam{To} = $GetParam{QuickTicketCustomer};
                }
            }
            elsif ( $Self->{DefaultSet} ) {
                my $CustomerUser = $ParamObject->GetParam( Param => 'SelectedCustomerUser' );
                if ( $CustomerUser ) {
                    %CustomerData = $CustomerUserObject->CustomerUserDataGet(
                        User => $CustomerUser,
                    );
                    $CustomerData{CustomerUserLogin} = $CustomerData{UserID};
                }
            }

            # get default queue and build selected string
            $GetParam{DefaultQueue}
                = $ConfigObject->Get('Ticket::CreateOptions::DefaultQueue')
                || '';
            if ( $Self->{QueueID} ) {
                my $QueueName = $QueueObject->QueueLookup(
                    QueueID => $Self->{QueueID}
                );
                $GetParam{DefaultQueueSelected} = $Self->{QueueID} . "||" . $QueueName;
            }
            elsif ( $GetParam{DefaultQueue} ) {
                my $QueueID = $QueueObject->QueueLookup(
                    Queue => $GetParam{DefaultQueue}
                );
                $Self->{QueueID} = $QueueID;
                $GetParam{DefaultQueueSelected}
                    = $Self->{QueueID} . "||" . $GetParam{DefaultQueue};
                $GetParam{DefaultQueueSet} = 1;
            }

            # get default ticket type and lookup type ID
            $GetParam{DefaultTicketType} =
                $ConfigObject->Get('Ticket::CreateOptions::DefaultTicketType') || '';

            if ( !$GetParam{DefaultTypeID} && $GetParam{DefaultTicketType} ) {

                # Blanks remove
                $GetParam{DefaultTicketType} =~ s/^\s+|\s+$//g;

                # select TypeID from Name
                my $DefaultTypeID = '';
                my $TypeList      = $Self->_GetTypes(
                    QueueID => $Self->{QueueID} || 1,
                    DefaultSet => $Self->{DefaultSet}
                );
                for my $ID ( keys %{$TypeList} ) {
                    my $Name = $TypeList->{$ID};
                    if ( $Name eq $GetParam{DefaultTicketType} ) {
                        $DefaultTypeID = $ID;
                        last;
                    }
                }
                $GetParam{DefaultTypeID} = $DefaultTypeID;
            }

            # check for default ticketstate for this tickettype
            my $DefaultStateRef =
                $ConfigObject->Get('TicketStateWorkflow::DefaultTicketState');
            my $DefaultStateExtendedRef
                = $ConfigObject->Get('TicketStateWorkflowExtension::DefaultTicketState');
            if ( defined $DefaultStateExtendedRef && ref $DefaultStateExtendedRef eq 'HASH' ) {
                for my $Extension ( sort keys %{$DefaultStateExtendedRef} ) {
                    for my $Type ( keys %{ $DefaultStateExtendedRef->{$Extension} } ) {
                        $DefaultStateRef->{$Type} = $DefaultStateExtendedRef->{$Extension}->{$Type};
                    }
                }
            }
            my $DefaultStateName = '';
            my $DefaultStateID   = '';
            if ( $GetParam{DefaultTypeID} ) {
                my %Type = $TypeObject->TypeGet(
                    ID => $GetParam{DefaultTypeID},
                );
                if ( $DefaultStateRef->{ $Type{Name} } ) {
                    $DefaultStateName = $DefaultStateRef->{ $Type{Name} };
                }
                elsif ( $DefaultStateRef->{''} ) {
                    $DefaultStateName = $DefaultStateRef->{''};
                }
            }
            elsif ( $DefaultStateRef->{''} ) {
                $DefaultStateName = $DefaultStateRef->{''};
            }
            if ( $DefaultStateName && !$GetParam{DefaultNextState} ) {
                my %DefaultState = $StateObject->StateGet(
                    Name => $DefaultStateName,
                );
                if ( $DefaultState{ID} ) {
                    $GetParam{DefaultNextStateID} = $DefaultState{ID};
                    $GetParam{DefaultNextState}   = $DefaultStateName;
                }
            }

            # check for default queue for this tickettype...
            my $DefaultQueueRef =
                $ConfigObject->Get('TicketStateWorkflow::DefaultTicketQueue');
            my $DefaultQueueExtendedRef
                = $ConfigObject->Get('TicketStateWorkflowExtension::DefaultTicketQueue');
            if ( defined $DefaultQueueExtendedRef && ref $DefaultQueueExtendedRef eq 'HASH' ) {
                for my $Extension ( sort keys %{$DefaultQueueExtendedRef} ) {
                    for my $Type ( keys %{ $DefaultQueueExtendedRef->{$Extension} } ) {
                        $DefaultQueueRef->{$Type} = $DefaultQueueExtendedRef->{$Extension}->{$Type};
                    }
                }
            }
            my $DefaultQueueName = "";
            my $DefaultQueueID   = "";
            if ( $GetParam{DefaultTypeID} ) {
                my %Type = $TypeObject->TypeGet(
                    ID => $GetParam{DefaultTypeID},
                );
                if ( $DefaultQueueRef->{ $Type{Name} } ) {
                    $DefaultQueueName = $DefaultQueueRef->{ $Type{Name} };
                }
                elsif ( $DefaultQueueRef->{''} ) {
                    $DefaultQueueName = $DefaultQueueRef->{''};
                }
            }
            elsif ( $DefaultQueueRef->{''} ) {
                $DefaultQueueName = $DefaultQueueRef->{''};
            }
            if (
                $DefaultQueueName
                &&
                (
                    !$Self->{QueueID} || (
                        $Self->{QueueID} && $GetParam{DefaultQueueSet}
                    )
                )
            ) {
                my $QueueID = $QueueObject->QueueLookup(
                    Queue => $DefaultQueueName,
                );
                $Self->{QueueID} = $QueueID;
                $GetParam{DefaultQueueSelected} = $Self->{QueueID} . "||" . $DefaultQueueName;
            }
            if ( !defined $GetParam{DynamicField} ) {
                # store the dynamic fields default values or used specific default values to be used as
                # ACLs info for all fields
                my %DynamicFieldDefaults;

                # cycle through the activated Dynamic Fields for this screen
                DYNAMICFIELD:
                for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {
                    next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);
                    next DYNAMICFIELD if !IsHashRefWithData( $DynamicFieldConfig->{Config} );
                    next DYNAMICFIELD if !$DynamicFieldConfig->{Name};

                    # get default value from dynamic field config (if any)
                    my $DefaultValue = $DynamicFieldConfig->{Config}->{DefaultValue} || '';

                    # override the value from user preferences if is set
                    if ( $UserPreferences{ 'UserDynamicField_' . $DynamicFieldConfig->{Name} } ) {
                        $DefaultValue = $UserPreferences{ 'UserDynamicField_' . $DynamicFieldConfig->{Name} };
                    }

                    next DYNAMICFIELD if $DefaultValue eq '';
                    next DYNAMICFIELD
                        if ref $DefaultValue eq 'ARRAY' && !IsArrayRefWithData($DefaultValue);

                    $DynamicFieldDefaults{ 'DynamicField_' . $DynamicFieldConfig->{Name} } = $DefaultValue;
                }
                $GetParam{DynamicField} = \%DynamicFieldDefaults;
            }

            # get split article if given
            # create html strings for all dynamic fields
            my %DynamicFieldHTML;

            # get queue id for use with acl
            my $QueueID        = $GetParam{QueueID} || $Self->{QueueID};
            if ( !defined $GetParam{QueueID}
              && !$Self->{QueueID}
              && defined $GetParam{Dest}
              && $GetParam{Dest} =~ /^(\d{1,100})\|\|.+?$/ ) {
                $QueueID = $1;
            }

            # cycle through the activated Dynamic Fields for this screen
            DYNAMICFIELD:
            for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {
                next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

                my $IsACLReducible = $DynamicFieldBackendObject->HasBehavior(
                    DynamicFieldConfig => $DynamicFieldConfig,
                    Behavior           => 'IsACLReducible',
                );

                if ($IsACLReducible) {

                    # get PossibleValues
                    my $PossibleValues = $DynamicFieldBackendObject->PossibleValuesGet(
                        DynamicFieldConfig => $DynamicFieldConfig,
                    );

                    # check if field has PossibleValues property in its configuration
                    if ( IsHashRefWithData($PossibleValues) ) {

                        # convert possible values key => value to key => key for ACLs using a Hash slice
                        my %AclData = %{$PossibleValues};
                        @AclData{ keys %AclData } = keys %AclData;

                        # set possible values filter from ACLs
                        my $ACL = $TicketObject->TicketAcl(
                            %GetParam,
                            %ACLCompatGetParam,
                            QueueID       => $QueueID,
                            Action        => $Self->{Action},
                            ReturnType    => 'Ticket',
                            ReturnSubType => 'DynamicField_' . $DynamicFieldConfig->{Name},
                            Data          => \%AclData,
                            UserID        => $Self->{UserID},
                        );
                        if ($ACL) {
                            my %Filter = $TicketObject->TicketAclData();

                            # convert Filer key => key back to key => value using map
                            %{$DynamicFieldConfig->{ShownPossibleValues}} = map { $_ => $PossibleValues->{$_} }
                                keys %Filter;
                        }
                    }
                }

                # to store dynamic field value from database (or undefined)
                my $Value;

                # override the value from user preferences if is set
                if ( $UserPreferences{ 'UserDynamicField_' . $DynamicFieldConfig->{Name} } ) {
                    $Value = $UserPreferences{ 'UserDynamicField_' . $DynamicFieldConfig->{Name} };
                }

                elsif ( $GetParam{ 'QuickTicketDynamicFieldHash' }->{ 'DynamicField_' . $DynamicFieldConfig->{Name} } ) {
                    $Value = $GetParam{ 'QuickTicketDynamicFieldHash' }->{ 'DynamicField_' . $DynamicFieldConfig->{Name} };
                }

                # get field html
                $DynamicFieldHTML{ $DynamicFieldConfig->{Name} } = $DynamicFieldBackendObject->EditFieldRender(
                    DynamicFieldConfig   => $DynamicFieldConfig,
                    PossibleValuesFilter => $DynamicFieldConfig->{ShownPossibleValues},
                    Value                => $Value,
                    Mandatory            => $Config->{DynamicField}->{ $DynamicFieldConfig->{Name} } == 2,
                    LayoutObject         => $LayoutObject,
                    ParamObject          => $ParamObject,
                    AJAXUpdate           => 1,
                    UpdatableFields      => $Self->_GetFieldsToUpdate(),
                    Template             => $GetParam{QuickTicketDynamicFieldHash},
                );
            }

            # run compose modules
            if (
                ref $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') eq
                'HASH'
            ) {
                my %Jobs = %{ $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') };
                for my $Job ( sort keys %Jobs ) {

                    # load module
                    if ( !$MainObject->Require( $Jobs{$Job}->{Module} ) ) {
                        return $LayoutObject->FatalError();
                    }

                    my $Object = $Jobs{$Job}->{Module}->new(
                        %{$Self},
                        Debug => $Debug,
                    );

                    # get params
                    for my $Parameter ( $Object->Option( %GetParam, Config => $Jobs{$Job} ) ) {
                        $GetParam{$Parameter} = $ParamObject->GetParam( Param => $Parameter );
                    }

                    # run module
                    $Object->Run( %GetParam, Config => $Jobs{$Job} );
                }
            }

            if ( $GetParam{QuickTicketSubject} ) {
                $Config->{Subject} = $GetParam{QuickTicketSubject};
            }
            if ( $GetParam{QuickTicketBody} ) {
                $Config->{Body} = $GetParam{QuickTicketBody};
            }

            # get and format default subject and body
            my $Subject = $LayoutObject->Output(
                Template => $Config->{Subject} || '',
            );

            my $Body = $LayoutObject->Output(
                Template => $Config->{Body} || '',
            );

            # make sure body is rich text
            if ( $LayoutObject->{BrowserRichText} && !$GetParam{QuickTicketBody} ) {
                $Body = $LayoutObject->Ascii2RichText(
                    String => $Body,
                );
            }

            # html output
            my $Services = $Self->_GetServices(
                QueueID => $Self->{QueueID} || 1,
                %GetParam,
                CustomerUserID => $CustomerData{CustomerUserLogin} ||'',
                TypeID         => $GetParam{TypeID}                || $GetParam{DefaultTypeID},
            );
            my $SLAs = $Self->_GetSLAs(
                QueueID => $Self->{QueueID} || 1,
                Services => $Services,
                %GetParam,
                %ACLCompatGetParam,
                ServiceID => $GetParam{ServiceID} || $GetParam{QuickTicketServiceID},
                TypeID    => $GetParam{TypeID}    || $GetParam{DefaultTypeID},
            );

            my $Signature = '';
            if ( $Self->{QueueID} ) {
                $Signature = $Self->_GetSignature( QueueID => $Self->{QueueID} ) || '';
            }
            if ( $LayoutObject->{BrowserRichText} ) {
                $Signature = $Kernel::OM->Get('Kernel::System::HTMLUtils')->ToAscii( String => $Signature, );
            }

            $Output .= $Self->_MaskEmailNew(
                %GetParam,
                QueueID    => $Self->{QueueID},
                NextStates => $Self->_GetNextStates(
                    %GetParam,
                    %ACLCompatGetParam,
                    CustomerUserID => $CustomerData{CustomerUserLogin} || '',
                    QueueID        => $Self->{QueueID}    || 1,
                    TypeID         => $GetParam{TypeID}   || $GetParam{DefaultTypeID},
                    DefaultSet     => $Self->{DefaultSet} || '',
                ),
                Priorities => $Self->_GetPriorities(
                    %GetParam,
                    %ACLCompatGetParam,
                    QueueID     => $Self->{QueueID} || 1,
                    DefaultSet  => $Self->{DefaultSet} || '',
                ),
                Types => $Self->_GetTypes(
                    %GetParam,
                    %ACLCompatGetParam,
                    QueueID     => $Self->{QueueID} || 1,
                    DefaultSet  => $Self->{DefaultSet} || '',
                ),
                NextState               => $GetParam{DefaultNextState}             || '',
                DefaultDiffTime         => $GetParam{DefaultPendingOffset}         || '',
                DefaultTypeID           => $GetParam{DefaultTypeID}                || '',
                TypeID                  => $GetParam{TypeID}                       || '',
                DefaultQueueSelected    => $GetParam{DefaultQueueSelected}         || '',
                PriorityID              => $GetParam{QuickTicketPriorityID}        || '',
                UserSelected            => $GetParam{QuickTicketOwnerID}           || '',
                ResponsibleUserSelected => $GetParam{QuickTicketResponsibleUserID} || '',
                TimeUnits               => $GetParam{QuickTicketTimeUnits}         || '',
                ServiceID               => $GetParam{QuickTicketServiceID},
                SLAID                   => $GetParam{QuickTicketSLAID},
                Signature               => $Signature,
                LinkTicketID            => $GetParam{LinkTicketID}                 || '',
                Services                => $Services,
                SLAs                    => $SLAs,
                StandardTemplates       => $Self->_GetStandardTemplates(
                    %GetParam,
                    %ACLCompatGetParam,
                    QueueID => $Self->{QueueID} || '',
                ),
                Users => $Self->_GetOwners(
                    %GetParam,
                    %ACLCompatGetParam,
                    QueueID => $Self->{QueueID}
                ),
                ResponsibleUsers => $Self->_GetResponsibles(
                    %GetParam,
                    %ACLCompatGetParam,
                    QueueID => $Self->{QueueID}
                ),
                FromList => $Self->_GetTos(
                    %GetParam,
                    %ACLCompatGetParam,
                    QueueID        => $Self->{QueueID},
                    CustomerUserID => $CustomerData{CustomerUserLogin} || '',
                    TypeID         => $GetParam{TypeID}                || $Param{DefaultTypeID},
                ),
                To                => '',
                Subject           => $Subject,
                Body              => $Body,
                CustomerUser => $GetParam{QuickTicketCustomer} || $Article{CustomerUserID},
                CustomerID   => $GetParam{CustomerID},
                CustomerUser => $GetParam{CustomerUserID}
                    || $ParamObject->GetParam( Param => 'SelectedCustomerUser' ),
                CustomerData => \%CustomerData,

                TimeUnitsRequired => (
                    $ConfigObject->Get('Ticket::Frontend::NeedAccountedTime')
                    ? 'Validate_Required'
                    : ''
                ),
                DynamicFieldHTML      => \%DynamicFieldHTML,
                MultipleCustomer      => \@MultipleCustomer,
                MultipleCustomerCc    => \@MultipleCustomerCc,
                MultipleCustomerBcc   => \@MultipleCustomerBcc,
                SelectedConfigItemIDs => $GetParam{SelectedConfigItemIDs},
            );
        }

        $Output .= $LayoutObject->Footer();
        return $Output;
    }

    # deliver signature
    elsif ( $Self->{Subaction} eq 'Signature' ) {
        my $CustomerUser = $ParamObject->GetParam( Param => 'SelectedCustomerUser' ) || '';
        my $QueueID      = $ParamObject->GetParam( Param => 'QueueID' );
        if ( !$QueueID ) {
            my $Dest = $ParamObject->GetParam( Param => 'Dest' ) || '';
            ($QueueID) = split( /\|\|/, $Dest );
        }

        # start with empty signature (no queue selected) - if we have a queue, get the sig.
        my $Signature = '';
        if ($QueueID) {
            $Signature = $Self->_GetSignature(
                CustomerUserID => $CustomerUser,
                QueueID        => $QueueID,
            );
        }
        my $MimeType = 'text/plain';
        if ( $LayoutObject->{BrowserRichText} ) {
            $MimeType  = 'text/html';
            $Signature = $LayoutObject->RichTextDocumentComplete(
                String => $Signature,
            );
        }

        return $LayoutObject->Attachment(
            ContentType => $MimeType . '; charset=' . $LayoutObject->{Charset},
            Content     => $Signature,
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # create new ticket and article
    elsif ( $Self->{Subaction} eq 'StoreNew' ) {

        my %Error;
        my $NextStateID = $ParamObject->GetParam( Param => 'NextStateID' ) || '';
        my %StateData;
        if ($NextStateID) {
            %StateData = $Kernel::OM->Get('Kernel::System::State')->StateGet(
                ID => $NextStateID,
            );
        }
        my $NextState        = $StateData{Name};
        my $NewResponsibleID = $ParamObject->GetParam( Param => 'NewResponsibleID' ) || '';
        my $NewUserID        = $ParamObject->GetParam( Param => 'NewUserID' ) || '';
        my $Dest             = $ParamObject->GetParam( Param => 'Dest' ) || '';

        # see if only a name has been passed
        if ( $Dest && $Dest !~ m{ \A (?:\d+)? \| \| .+ \z }xms ) {

            # see if we can get an ID for this queue name
            my $DestID = $QueueObject->QueueLookup(
                Queue => $Dest,
            );

            if ($DestID) {
                $Dest = $DestID . '||' . $Dest;
            }
            else {
                $Dest = '';
            }
        }

        my ( $NewQueueID, $From ) = split( /\|\|/, $Dest );
        if ( !$NewQueueID ) {
            $GetParam{OwnerAll} = 1;
        }
        else {
            my %Queue = $QueueObject->GetSystemAddress( QueueID => $NewQueueID );
            $GetParam{From} = $Queue{Email};
        }

        # get sender queue from
        my $Signature = $ParamObject->GetParam( Param => 'Signature' ) || '';

        if ($NewQueueID) {
            $Signature = $Self->_GetSignature( QueueID => $NewQueueID );
        }
        my $CustomerUser = $ParamObject->GetParam( Param => 'CustomerUser' )
            || $ParamObject->GetParam( Param => 'PreSelectedCustomerUser' )
            || $ParamObject->GetParam( Param => 'SelectedCustomerUser' )
            || '';
        my $CustomerID = $ParamObject->GetParam( Param => 'CustomerID' ) || '';
        my $SelectedCustomerUser = $ParamObject->GetParam( Param => 'SelectedCustomerUser' )
            || '';
        my $ExpandCustomerName = $ParamObject->GetParam( Param => 'ExpandCustomerName' )
            || 0;
        my %FromExternalCustomer;
        $FromExternalCustomer{Customer} = $ParamObject->GetParam( Param => 'PreSelectedCustomerUser' )
            || $ParamObject->GetParam( Param => 'CustomerUser' )
            || '';
        $GetParam{QueueID}            = $NewQueueID;
        $GetParam{ExpandCustomerName} = $ExpandCustomerName;

        if ( $ParamObject->GetParam( Param => 'OwnerAllRefresh' ) ) {
            $GetParam{OwnerAll} = 1;
            $ExpandCustomerName = 3;
        }
        if ( $ParamObject->GetParam( Param => 'ResponsibleAllRefresh' ) ) {
            $GetParam{ResponsibleAll} = 1;
            $ExpandCustomerName = 3;
        }
        if ( $ParamObject->GetParam( Param => 'ClearTo' ) ) {
            $GetParam{To} = '';
            $ExpandCustomerName = 3;
        }
        for my $Number ( 1 .. 2 ) {
            my $Item = $ParamObject->GetParam( Param => "ExpandCustomerName$Number" ) || 0;
            if ( $Number == 1 && $Item ) {
                $ExpandCustomerName = 1;
            }
            elsif ( $Number == 2 && $Item ) {
                $ExpandCustomerName = 2;
            }
        }

        # attachment delete
        my @AttachmentIDs = ();
        for my $Name ( $ParamObject->GetParamNames() ) {
            if ( $Name =~ m{ \A AttachmentDelete (\d+) \z }xms ) {
                push (@AttachmentIDs, $1);
            };
        }

        COUNT:
        for my $Count ( reverse sort @AttachmentIDs ) {
            my $Delete = $ParamObject->GetParam( Param => "AttachmentDelete$Count" );
            next COUNT if !$Delete;
            $Error{AttachmentDelete} = 1;
            $UploadCacheObject->FormIDRemoveFile(
                FormID => $Self->{FormID},
                FileID => $Count,
            );
            $IsUpload = 1;
        }

        # attachment upload
        if ( $ParamObject->GetParam( Param => 'AttachmentUpload' ) ) {
            $IsUpload                = 1;
            %Error                   = ();
            $Error{AttachmentUpload} = 1;
            my %UploadStuff = $ParamObject->GetUploadAll(
                Param => 'FileUpload',
            );
            $UploadCacheObject->FormIDAddFile(
                FormID      => $Self->{FormID},
                Disposition => 'attachment',
                %UploadStuff,
            );
        }

        # create html strings for all dynamic fields
        my %DynamicFieldHTML;

        # cycle through the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

            my $IsACLReducible = $DynamicFieldBackendObject->HasBehavior(
                DynamicFieldConfig => $DynamicFieldConfig,
                Behavior           => 'IsACLReducible',
            );

            if ($IsACLReducible) {

                # get PossibleValues
                my $PossibleValues = $DynamicFieldBackendObject->PossibleValuesGet(
                    DynamicFieldConfig => $DynamicFieldConfig,
                );

                # check if field has PossibleValues property in its configuration
                if ( IsHashRefWithData($PossibleValues) ) {

                    # convert possible values key => value to key => key for ACLs using a Hash slice
                    my %AclData = %{$PossibleValues};
                    @AclData{ keys %AclData } = keys %AclData;

                    # set possible values filter from ACLs
                    my $ACL = $TicketObject->TicketAcl(
                        %GetParam,
                        %ACLCompatGetParam,
                        CustomerUserID => $CustomerUser || '',
                        QueueID        => $NewQueueID || 0,
                        Action         => $Self->{Action},
                        ReturnType     => 'Ticket',
                        ReturnSubType  => 'DynamicField_' . $DynamicFieldConfig->{Name},
                        Data           => \%AclData,
                        UserID         => $Self->{UserID},
                    );
                    if ($ACL) {
                        my %Filter = $TicketObject->TicketAclData();

                        # convert Filer key => key back to key => value using map
                        %{$DynamicFieldConfig->{ShownPossibleValues}} = map { $_ => $PossibleValues->{$_} }
                            keys %Filter;
                    }
                }
            }
        }

        # run acl to prepare TicketAclFormData
        my $ShownDFACL = $Kernel::OM->Get('Kernel::System::Ticket')->TicketAcl(
            %GetParam,
            %ACLCompatGetParam,
            CustomerUserID => $CustomerUser || '',
            QueueID        => $NewQueueID || 0,
            Action         => $Self->{Action},
            ReturnType     => 'Ticket',
            ReturnSubType  => '-',
            Data           => {},
            UserID         => $Self->{UserID},
        );

        # update 'Shown' for $Self->{DynamicField}
        $Self->_GetShownDynamicFields();

        # cycle trough the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

            my $ValidationResult;

            # do not validate on attachment upload or if field is disabled
            if (
                !$IsUpload
                && !$ExpandCustomerName
                && $DynamicFieldConfig->{Shown}
            ) {

                $ValidationResult = $DynamicFieldBackendObject->EditFieldValueValidate(
                    DynamicFieldConfig   => $DynamicFieldConfig,
                    PossibleValuesFilter => $DynamicFieldConfig->{ShownPossibleValues},
                    ParamObject          => $ParamObject,
                    Mandatory =>
                        $Config->{DynamicField}->{ $DynamicFieldConfig->{Name} } == 2,
                );

                if ( !IsHashRefWithData($ValidationResult) ) {
                    return $LayoutObject->ErrorScreen(
                        Message =>
                            $LayoutObject->{LanguageObject}
                            ->Translate( 'Could not perform validation on field %s!', $DynamicFieldConfig->{Label} ),
                        Comment => Translatable('Please contact the administrator.'),
                    );
                }

                # propagate validation error to the Error variable to be detected by the frontend
                if ( $ValidationResult->{ServerError} ) {
                    $Error{ $DynamicFieldConfig->{Name} } = ' ServerError';
                }
            }

            # get field html
            $DynamicFieldHTML{ $DynamicFieldConfig->{Name} } = $DynamicFieldBackendObject->EditFieldRender(
                DynamicFieldConfig   => $DynamicFieldConfig,
                PossibleValuesFilter => $DynamicFieldConfig->{ShownPossibleValues},
                Mandatory =>
                    $Config->{DynamicField}->{ $DynamicFieldConfig->{Name} } == 2,
                ServerError  => $ValidationResult->{ServerError}  || '',
                ErrorMessage => $ValidationResult->{ErrorMessage} || '',
                LayoutObject => $LayoutObject,
                ParamObject  => $ParamObject,
                AJAXUpdate   => 1,
                UpdatableFields => $Self->_GetFieldsToUpdate(),
            );
        }

        # get all attachments meta data
        my @Attachments = $UploadCacheObject->FormIDGetAllFilesMeta(
            FormID => $Self->{FormID},
        );

        # get customer user object
        my $CustomerUserObject = $Kernel::OM->Get('Kernel::System::CustomerUser');

        # Expand Customer Name
        my %CustomerUserData;
        if ( $ExpandCustomerName == 1 ) {

            # search customer
            my %CustomerUserList;
            %CustomerUserList = $CustomerUserObject->CustomerSearch(
                Search => $GetParam{To},
            );

            # check if just one customer user exists
            # if just one, fillup CustomerUserID and CustomerID
            $Param{CustomerUserListCount} = 0;
            for my $CustomerUserKey ( sort keys %CustomerUserList ) {
                $Param{CustomerUserListCount}++;
                $Param{CustomerUserListLast}     = $CustomerUserList{$CustomerUserKey};
                $Param{CustomerUserListLastUser} = $CustomerUserKey;
            }
            if ( $Param{CustomerUserListCount} == 1 ) {
                $GetParam{To}              = $Param{CustomerUserListLast};
                $Error{ExpandCustomerName} = 1;
                %CustomerUserData = $CustomerUserObject->CustomerUserDataGet(
                    User => $Param{CustomerUserListLastUser},
                );
                if ( $CustomerUserData{UserCustomerID} ) {
                    $CustomerID = $CustomerUserData{UserCustomerID};
                }
                if ( $CustomerUserData{UserLogin} ) {
                    $CustomerUser = $CustomerUserData{UserLogin};
                }
            }

            # if more the one customer user exists, show list
            # and clean CustomerUserID and CustomerID
            else {

                # don't check email syntax on multi customer select
                $ConfigObject->Set(
                    Key   => 'CheckEmailAddresses',
                    Value => 0
                );
                $CustomerID = '';

                $Param{ToOptions} = \%CustomerUserList;

                # clear to if there is no customer found
                if ( !%CustomerUserList ) {
                    $GetParam{To} = '';
                }
                $Error{ExpandCustomerName} = 1;
            }
        }

        # get from and customer id if customer user is given
        elsif ( $ExpandCustomerName == 2 ) {
            %CustomerUserData = $CustomerUserObject->CustomerUserDataGet(
                User => $CustomerUser,
            );
            my %CustomerUserList = $CustomerUserObject->CustomerSearch(
                UserLogin => $CustomerUser,
            );
            for my $CustomerUserKey ( sort keys %CustomerUserList ) {
                $GetParam{To} = $CustomerUserList{$CustomerUserKey};
            }
            if ( $CustomerUserData{UserCustomerID} ) {
                $CustomerID = $CustomerUserData{UserCustomerID};
            }
            if ( $CustomerUserData{UserLogin} ) {
                $CustomerUser = $CustomerUserData{UserLogin};
            }
            if ( $FromExternalCustomer{Customer} ) {
                my %ExternalCustomerUserData = $CustomerUserObject->CustomerUserDataGet(
                    User => $FromExternalCustomer{Customer},
                );
                $FromExternalCustomer{Email} = $ExternalCustomerUserData{UserEmail};
            }
            $Error{ExpandCustomerName} = 1;
        }

        # if a new destination queue is selected
        elsif ( $ExpandCustomerName == 3 ) {
            $Error{NoSubmit} = 1;
            $CustomerUser = $SelectedCustomerUser;
        }

        # get To if customer user is given,
        # BUT get customer id only if given customer id is wrong or empty
        elsif ( $ExpandCustomerName == 5 ) {
            if ($CustomerUser) {
                %CustomerUserData = $CustomerUserObject->CustomerUserDataGet(
                    User => $CustomerUser,
                );
                my %CustomerUserList = $CustomerUserObject->CustomerSearch(
                    UserLogin => $CustomerUser,
                );
                for my $KeyCustomerUser ( keys %CustomerUserList ) {
                    $GetParam{To} = $CustomerUserList{$KeyCustomerUser};
                }
                if (
                    ( !$CustomerID && $CustomerUserData{UserCustomerID} ) ||
                    (
                        $CustomerID &&
                        (
                            $CustomerID ne $CustomerUserData{UserCustomerID} &&
                            $CustomerUserData{UserCustomerIDs} !~ /(?:^|,\s*)$CustomerID(?:,\s*|$)/
                        )
                    )
                ) {
                    $CustomerID = $CustomerUserData{UserCustomerID};
                }
                if ( $CustomerUserData{UserLogin} ) {
                    $CustomerUser = $CustomerUserData{UserLogin};
                }
            }
            $Error{ExpandCustomerName} = 1;
            $IsUpload = 1;
        }

        # show customer info
        my %CustomerData;
        if ( $ConfigObject->Get('Ticket::Frontend::CustomerInfoCompose') ) {
            if ( $CustomerUser || $SelectedCustomerUser ) {
                %CustomerData = $CustomerUserObject->CustomerUserDataGet(
                    User => $CustomerUser || $SelectedCustomerUser,
                );
            }
        }

        # check email address
        PARAMETER:
        for my $Parameter (qw(To Cc Bcc)) {
            next PARAMETER if !$GetParam{$Parameter};
            for my $Email ( Mail::Address->parse( $GetParam{$Parameter} ) ) {
                if ( !$CheckItemObject->CheckEmail( Address => $Email->address() ) ) {
                    $Error{ $Parameter . 'ErrorType' }
                        = $Parameter . $CheckItemObject->CheckErrorType() . 'ServerErrorMsg';
                    $Error{ $Parameter . 'Invalid' } = 'ServerError';
                }

                if ($ConfigObject->Get('CheckEmailInternalAddress')) {
                    my $IsLocal = $Kernel::OM->Get('Kernel::System::SystemAddress')->SystemAddressIsLocalAddress(
                        Address => $Email->address()
                    );
                    if ($IsLocal) {
                        $Error{ $Parameter . 'IsLocalAddress' } = 'ServerError';
                    }
                }
            }
        }

        # if it is not a subaction about attachments, check for server errors
        if ( !$IsUpload && !$ExpandCustomerName ) {
            if ( !$GetParam{To} ) {
                $Error{'ToInvalid'} = 'ServerError';
            }
            if ( !$GetParam{Subject} ) {
                $Error{'SubjectInvalid'} = 'ServerError';
            }
            if ( !$NewQueueID ) {
                $Error{'DestinationInvalid'} = 'ServerError';
            }
            if ( !$GetParam{Body} ) {
                $Error{'BodyInvalid'} = 'ServerError';
            }

            # check if date is valid
            if (
                !$ExpandCustomerName
                && $StateData{TypeName}
                && $StateData{TypeName} =~ /^pending/i
            ) {

                # get time object
                my $TimeObject = $Kernel::OM->Get('Kernel::System::Time');

                if ( !$TimeObject->Date2SystemTime( %GetParam, Second => 0 ) ) {
                    $Error{'DateInvalid'} = 'ServerError';
                }
                if (
                    $TimeObject->Date2SystemTime( %GetParam, Second => 0 )
                    < $TimeObject->SystemTime()
                ) {
                    $Error{'DateInvalid'} = 'ServerError';
                }
            }

            if (
                $ConfigObject->Get('Ticket::Service')
                && $GetParam{SLAID}
                && !$GetParam{ServiceID}
            ) {
                $Error{'ServiceInvalid'} = 'ServerError';
            }

            # check mandatory service
            if (
                $ConfigObject->Get('Ticket::Service')
                && $Config->{ServiceMandatory}
                && !$GetParam{ServiceID}
            ) {
                $Error{'ServiceInvalid'} = ' ServerError';
            }

            # check mandatory sla
            if (
                $ConfigObject->Get('Ticket::Service')
                && $Config->{SLAMandatory}
                && !$GetParam{SLAID}
            ) {
                $Error{'SLAInvalid'} = ' ServerError';
            }

            if ( !$GetParam{NextStateID} ) {
                $Error{'NextStateInvalid'} = 'ServerError';
            }
            if ( !$GetParam{PriorityID} ) {
                $Error{'PriorityInvalid'} = 'ServerError';
            }
            if ( $ConfigObject->Get('Ticket::Type') && !$GetParam{TypeID} ) {
                $Error{'TypeInvalid'} = 'ServerError';
            }
            if (
                $ConfigObject->Get('Ticket::Frontend::AccountTime')
                && $ConfigObject->Get('Ticket::Frontend::NeedAccountedTime')
                && $GetParam{TimeUnits} eq ''
            ) {
                $Error{'TimeUnitsInvalid'} = 'ServerError';
            }

            # check owner
            if (
                $ConfigObject->Get('Ticket::Frontend::NewOwnerSelection')
                && $NewUserID
            ) {
                my $PossibleOwners = $Self->_GetOwners(
                    %GetParam,
                    %ACLCompatGetParam,
                    QueueID  => $NewQueueID,
                    AllUsers => $GetParam{OwnerAll},
                );
                if ( !$PossibleOwners->{ $NewUserID } ) {
                    $Error{'NewUserInvalid'} = 'ServerError';
                }
            }

            # check responsible
            if (
                $ConfigObject->Get('Ticket::Responsible')
                && $ConfigObject->Get('Ticket::Frontend::NewResponsibleSelection')
                && $NewResponsibleID
            ) {
                my $PossibleResponsibles = $Self->_GetResponsibles(
                    %GetParam,
                    %ACLCompatGetParam,
                    QueueID  => $NewQueueID,
                    AllUsers => $GetParam{ResponsibleAll},
                );
                if ( !$PossibleResponsibles->{ $NewResponsibleID } ) {
                    $Error{'NewResponsibleInvalid'} = 'ServerError';
                }
            }
        }

        # run compose modules
        my %ArticleParam;
        if ( ref $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') eq 'HASH' ) {
            my %Jobs = %{ $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') };
            for my $Job ( sort keys %Jobs ) {

                # load module
                if ( !$MainObject->Require( $Jobs{$Job}->{Module} ) ) {
                    return $LayoutObject->FatalError();
                }

                my $Object = $Jobs{$Job}->{Module}->new(
                    %{$Self},
                    Debug => $Debug,
                );

                # get params
                for my $Parameter ( $Object->Option( %GetParam, Config => $Jobs{$Job} ) ) {
                    $GetParam{$Parameter} = $ParamObject->GetParam( Param => $Parameter );
                }

                # run module
                $Object->Run( %GetParam, Config => $Jobs{$Job} );

                # ticket params
                %ArticleParam = (
                    %ArticleParam,
                    $Object->ArticleOption( %GetParam, Config => $Jobs{$Job} ),
                );

                # get errors
                %Error = (
                    %Error,
                    $Object->Error( %GetParam, Config => $Jobs{$Job} ),
                );
            }
        }

        if (%Error) {

            if ( $Error{ToIsLocalAddress} ) {
                $LayoutObject->Block(
                    Name => 'ToIsLocalAddressServerErrorMsg',
                    Data => \%GetParam,
                );
            }

            if ( $Error{CcIsLocalAddress} ) {
                $LayoutObject->Block(
                    Name => 'CcIsLocalAddressServerErrorMsg',
                    Data => \%GetParam,
                );
            }

            if ( $Error{BccIsLocalAddress} ) {
                $LayoutObject->Block(
                    Name => 'BccIsLocalAddressServerErrorMsg',
                    Data => \%GetParam,
                );
            }

            # get and format default subject and body
            my $Subject = $LayoutObject->Output(
                Template => $Config->{Subject} || '',
            );

            my $Body = $LayoutObject->Output(
                Template => $Config->{Body} || '',
            );

            # make sure body is rich text
            if ( $LayoutObject->{BrowserRichText} ) {
                $Body = $LayoutObject->Ascii2RichText(
                    String => $Body,
                );
            }

            #set Body and Subject parameters for Output
            if ( !$GetParam{Subject} ) {
                $GetParam{Subject} = $Subject;
            }

            if ( !$GetParam{Body} ) {
                $GetParam{Body} = $Body;
            }

            # get services
            my $Services = $Self->_GetServices(
                %GetParam,
                %ACLCompatGetParam,
                CustomerUserID => $CustomerUser || '',
                QueueID        => $NewQueueID   || 1,
            );

            # reset previous ServiceID to reset SLA-List if no service is selected
            if (
                ( !$GetParam{ServiceID} || !$Services->{ $GetParam{ServiceID} } )
                && (
                    !$GetParam{QuickTicketServiceID}
                    || !$Services->{ $GetParam{QuickTicketServiceID} }
                )
            ) {
                $GetParam{ServiceID} = '';
            }
            elsif (
                ( !$GetParam{ServiceID} || !$Services->{ $GetParam{ServiceID} } )
                && $GetParam{QuickTicketServiceID} && $Services->{ $GetParam{QuickTicketServiceID} }
            ) {
                $GetParam{ServiceID} = $GetParam{QuickTicketServiceID};
            }

            my $SLAs = $Self->_GetSLAs(
                %GetParam,
                %ACLCompatGetParam,
                QueueID => $NewQueueID || 1,
                Services => $Services,
            );

            # header
            $Output .= $LayoutObject->Header();
            $Output .= $LayoutObject->NavigationBar();

            # html output
            $Output .= $Self->_MaskEmailNew(
                QueueID => $Self->{QueueID},
                Users   => $Self->_GetOwners(
                    %GetParam,
                    %ACLCompatGetParam,
                    QueueID  => $NewQueueID || $Self->{QueueID} || 1,
                    AllUsers => $GetParam{OwnerAll},
                ),
                UserSelected     => $GetParam{NewUserID} || $GetParam{QuickTicketOwnerID},
                ResponsibleUsers => $Self->_GetResponsibles(
                    %GetParam,
                    %ACLCompatGetParam,
                    QueueID  => $NewQueueID || $Self->{QueueID} || 1,
                    AllUsers => $GetParam{ResponsibleAll}
                ),
                ResponsibleUserSelected => $GetParam{NewResponsibleID}
                    || $GetParam{QuickTicketResponsibleUserID},
                NextStates => $Self->_GetNextStates(
                    %GetParam,
                    %ACLCompatGetParam,
                    CustomerUserID => $CustomerUser || '',
                    QueueID        => $NewQueueID || $Self->{QueueID} || 1,
                    TypeID         => $GetParam{TypeID},
                ),
                NextState  => $NextState,
                Priorities => $Self->_GetPriorities(
                    %GetParam,
                    %ACLCompatGetParam,
                    CustomerUserID => $CustomerUser || '',
                    QueueID        => $NewQueueID || $Self->{QueueID} || 1,
                ),
                Types => $Self->_GetTypes(
                    %GetParam,
                    %ACLCompatGetParam,
                    CustomerUserID => $CustomerUser || '',
                    QueueID        => $NewQueueID || $Self->{QueueID} || 1,
                ),
                Services          => $Services,
                SLAs              => $SLAs,
                StandardTemplates => $Self->_GetStandardTemplates(
                    %GetParam,
                    %ACLCompatGetParam,
                    QueueID => $NewQueueID || '',
                ),
                CustomerID        => $LayoutObject->Ascii2Html( Text => $CustomerID ),
                CustomerUser      => $CustomerUser,
                CustomerData      => \%CustomerData,
                TimeUnitsRequired => (
                    $ConfigObject->Get('Ticket::Frontend::NeedAccountedTime')
                    ? 'Validate_Required'
                    : ''
                ),
                FromList => $Self->_GetTos(
                    # QueueID => $NewQueueID
                    QueueID => $NewQueueID || $Self->{QueueID} || 1,
                    TypeID => $GetParam{TypeID},
                ),
                LinkTicketID => $GetParam{LinkTicketID} || '',
                To  => $GetParam{To}  || '',
                Cc  => $GetParam{Cc}  || '',
                Bcc => $GetParam{Bcc} || '',
                FromSelected => $Dest,
                ToOptions    => $Param{ToOptions},
                Subject      => $LayoutObject->Ascii2Html( Text => $GetParam{Subject} ),
                Body         => $LayoutObject->Ascii2Html( Text => $GetParam{Body} ),
                Errors       => \%Error,
                Attachments  => \@Attachments,
                Signature    => $Signature,
                %GetParam,
                DynamicFieldHTML     => \%DynamicFieldHTML,
                MultipleCustomer     => \@MultipleCustomer,
                MultipleCustomerCc   => \@MultipleCustomerCc,
                MultipleCustomerBcc  => \@MultipleCustomerBcc,
                FromExternalCustomer => \%FromExternalCustomer,
                SelectedConfigItemIDs => $GetParam{SelectedConfigItemIDs},
                PriorityID            => $GetParam{PriorityID} || $GetParam{QuickTicketPriorityID},
                Priority              => $GetParam{Priority} || $GetParam{QuickTicketPriority},
                ServiceID             => $GetParam{ServiceID} || $GetParam{QuickTicketServiceID},
                SLAID                 => $GetParam{SLAID} || $GetParam{QuickTicketSLAID},
                Subject               => $GetParam{Subject} || $GetParam{QuickTicketSubject},
                Body                  => $GetParam{Body} || $GetParam{QuickTicketBody},
                TimeUnits             => $GetParam{TimeUnits} || $GetParam{QuickTicketTimeUnits},
            );

            $Output .= $LayoutObject->Footer();
            return $Output;
        }

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        # create new ticket, do db insert
        my $TicketID = $TicketObject->TicketCreate(
            Title        => $GetParam{Subject},
            QueueID      => $NewQueueID,
            Subject      => $GetParam{Subject},
            Lock         => 'unlock',
            TypeID       => $GetParam{TypeID},
            ServiceID    => $GetParam{ServiceID},
            SLAID        => $GetParam{SLAID},
            StateID      => $NextStateID,
            PriorityID   => $GetParam{PriorityID},
            OwnerID      => 1,
            CustomerID   => $CustomerID,
            CustomerUser => $SelectedCustomerUser,
            UserID       => $Self->{UserID},
        );

        # set ticket dynamic fields
        # cycle through the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);
            next DYNAMICFIELD if !$DynamicFieldConfig->{Shown};
            next DYNAMICFIELD if $DynamicFieldConfig->{ObjectType} ne 'Ticket';

            # set the value
            my $Success = $DynamicFieldBackendObject->ValueSet(
                DynamicFieldConfig => $DynamicFieldConfig,
                ObjectID           => $TicketID,
                Value              => $DynamicFieldValues{ $DynamicFieldConfig->{Name} },
                UserID             => $Self->{UserID},
            );
        }
# ---
# ITSMIncidentProblemManagement
# ---
        if ( $GetParam{ServiceID} && $Service{Criticality} ) {

            # get config for criticality dynamic field
            my $CriticalityDynamicFieldConfig = $Kernel::OM->Get('Kernel::System::DynamicField')->DynamicFieldGet(
                Name => 'ITSMCriticality',
            );

            # get possible values for criticality
            my $CriticalityPossibleValues = $DynamicFieldBackendObject->PossibleValuesGet(
                DynamicFieldConfig => $CriticalityDynamicFieldConfig,
            );

            # reverse the list to find out the key
            my %ReverseCriticalityPossibleValues = reverse %{ $CriticalityPossibleValues };

            # set the criticality
            $DynamicFieldBackendObject->ValueSet(
                DynamicFieldConfig => $CriticalityDynamicFieldConfig,
                ObjectID           => $TicketID,
                Value              => $ReverseCriticalityPossibleValues{ $Service{Criticality} },
                UserID             => $Self->{UserID},
            );
        }
# ---

        # get pre loaded attachment
        @Attachments = $UploadCacheObject->FormIDGetAllFilesData(
            FormID => $Self->{FormID},
        );

        # get submit attachment
        my %UploadStuff = $ParamObject->GetUploadAll(
            Param => 'FileUpload',
        );
        if (%UploadStuff) {
            push @Attachments, \%UploadStuff;
        }

        # prepare subject
        my $Tn = $TicketObject->TicketNumberLookup( TicketID => $TicketID );
        $GetParam{Subject} = $TicketObject->TicketSubjectBuild(
            TicketNumber => $Tn,
            Subject      => $GetParam{Subject} || '',
            Type         => 'New',
        );

        # get signature an replace ticket data placeholder
        $Signature = $Self->_GetSignature(
            QueueID  => $NewQueueID,
            TicketID => $TicketID,
        );

        # check if new owner is given (then send no agent notify)
        my $NoAgentNotify = 0;
        if ($NewUserID) {
            $NoAgentNotify = 1;
        }

        my $MimeType = 'text/plain';
        if ( $LayoutObject->{BrowserRichText} ) {
            $MimeType = 'text/html';
            $GetParam{Body} .= '<br/><br/>' . $Signature;

            # remove unused inline images
            my @NewAttachmentData;
            ATTACHMENT:
            for my $Attachment (@Attachments) {
                my $ContentID = $Attachment->{ContentID};
                if (
                    $ContentID
                    && ( $Attachment->{ContentType} =~ /image/i )
                    && ( $Attachment->{Disposition} eq 'inline' )
                ) {
                    my $ContentIDHTMLQuote = $LayoutObject->Ascii2Html(
                        Text => $ContentID,
                    );

                    # workaround for link encode of rich text editor, see bug#5053
                    my $ContentIDLinkEncode = $LayoutObject->LinkEncode($ContentID);
                    $GetParam{Body} =~ s/(ContentID=)$ContentIDLinkEncode/$1$ContentID/g;

                    # ignore attachment if not linked in body
                    next ATTACHMENT
                        if $GetParam{Body} !~ /(?:\Q$ContentIDHTMLQuote\E|\Q$ContentID\E)/i;
                }

                # remember inline images and normal attachments
                push @NewAttachmentData, \%{$Attachment};
            }
            @Attachments = @NewAttachmentData;

            # verify html document
            $GetParam{Body} = $LayoutObject->RichTextDocumentComplete(
                String => $GetParam{Body},
            );
        }
        else {
            $GetParam{Body} .= "\n\n" . $Signature;
        }

        # lookup sender
        my $TemplateGenerator = $Kernel::OM->Get('Kernel::System::TemplateGenerator');
        my $Sender            = $TemplateGenerator->Sender(
            QueueID => $NewQueueID,
            UserID  => $Self->{UserID},
        );

        # send email
        my $ArticleID = $TicketObject->ArticleSend(
            NoAgentNotify  => $NoAgentNotify,
            Attachment     => \@Attachments,
            TicketID       => $TicketID,
            ArticleType    => $Config->{ArticleType},
            SenderType     => $Config->{SenderType},
            From           => $Sender,
            To             => $GetParam{To},
            Cc             => $GetParam{Cc},
            Bcc            => $GetParam{Bcc},
            Subject        => $GetParam{Subject},
            Body           => $GetParam{Body},
            Charset        => $LayoutObject->{UserCharset},
            MimeType       => $MimeType,
            UserID         => $Self->{UserID},
            HistoryType    => $Config->{HistoryType},
            HistoryComment => $Config->{HistoryComment}
                || "\%\%$GetParam{To}, $GetParam{Cc}, $GetParam{Bcc}",
            %ArticleParam,
        );
        if ( !$ArticleID ) {
            return $LayoutObject->ErrorScreen();
        }

        # set article dynamic fields
        # cycle through the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);
            next DYNAMICFIELD if !$DynamicFieldConfig->{Shown};
            next DYNAMICFIELD if $DynamicFieldConfig->{ObjectType} ne 'Article';

            # set the value
            my $Success = $DynamicFieldBackendObject->ValueSet(
                DynamicFieldConfig => $DynamicFieldConfig,
                ObjectID           => $ArticleID,
                Value              => $DynamicFieldValues{ $DynamicFieldConfig->{Name} },
                UserID             => $Self->{UserID},
            );
        }

        # remove pre-submitted attachments
        $UploadCacheObject->FormIDRemove( FormID => $Self->{FormID} );

        # set owner (if new user id is given)
        if (
            $ConfigObject->Get('Ticket::Frontend::NewOwnerSelection')
            && $NewUserID
        ) {
            $TicketObject->TicketOwnerSet(
                TicketID  => $TicketID,
                NewUserID => $NewUserID,
                UserID    => $Self->{UserID},
            );

            # set lock
            $TicketObject->TicketLockSet(
                TicketID => $TicketID,
                Lock     => 'lock',
                UserID   => $Self->{UserID},
            );
        }

        # else set owner to current agent but do not lock it
        else {
            $TicketObject->TicketOwnerSet(
                TicketID           => $TicketID,
                NewUserID          => $Self->{UserID},
                SendNoNotification => 1,
                UserID             => $Self->{UserID},
            );
        }

        # set responsible (if new user id is given)
        if (
            $ConfigObject->Get('Ticket::Responsible')
            && $ConfigObject->Get('Ticket::Frontend::NewResponsibleSelection')
            && $NewResponsibleID
        ) {
            $TicketObject->TicketResponsibleSet(
                TicketID  => $TicketID,
                NewUserID => $NewResponsibleID,
                UserID    => $Self->{UserID},
            );
        }

        # time accounting
        if ( $GetParam{TimeUnits} ) {
            $TicketObject->TicketAccountTime(
                TicketID  => $TicketID,
                ArticleID => $ArticleID,
                TimeUnit  => $GetParam{TimeUnits},
                UserID    => $Self->{UserID},
            );
        }

        # should i set an unlock?
        if ( $StateData{TypeName} =~ /^close/i ) {

            # set lock
            $TicketObject->TicketLockSet(
                TicketID => $TicketID,
                Lock     => 'unlock',
                UserID   => $Self->{UserID},
            );
        }

        # set pending time
        elsif ( $StateData{TypeName} =~ /^pending/i ) {

            # set pending time
            $TicketObject->TicketPendingTimeSet(
                UserID   => $Self->{UserID},
                TicketID => $TicketID,
                %GetParam,
            );
        }
# ---
# ITSMIncidentProblemManagement
# ---
            # get the temporarily links
            my $TempLinkList = $LinkObject->LinkList(
                Object => 'Ticket',
                Key    => $Self->{FormID},
                State  => 'Temporary',
                UserID => $Self->{UserID},
            );

            if ( $TempLinkList && ref $TempLinkList eq 'HASH' && %{$TempLinkList} ) {

                for my $TargetObjectOrg ( sort keys %{$TempLinkList} ) {

                    # extract typelist
                    my $TypeList = $TempLinkList->{$TargetObjectOrg};

                    for my $Type ( sort keys %{$TypeList} ) {

                        # extract direction list
                        my $DirectionList = $TypeList->{$Type};

                        for my $Direction ( sort keys %{$DirectionList} ) {

                            for my $TargetKeyOrg ( sort keys %{ $DirectionList->{$Direction} } ) {

                                # delete the temp link
                                $LinkObject->LinkDelete(
                                    Object1 => 'Ticket',
                                    Key1    => $Self->{FormID},
                                    Object2 => $TargetObjectOrg,
                                    Key2    => $TargetKeyOrg,
                                    Type    => $Type,
                                    UserID  => $Self->{UserID},
                                );

                                if ($TargetObjectOrg eq 'Person') {
                                     $Kernel::OM->Get('Kernel::System::AsynchronousExecutor::LinkedTicketPersonExecutor')->AsyncCall(
                                         TicketID      => $TicketID,
                                         PersonID      => $TargetKeyOrg,
                                         PersonHistory => $TargetKeyOrg,
                                         LinkType      => $Type,
                                         UserID        => $Self->{UserID},
                                     );
                                }
                                else {
                                    if ($Direction eq 'Source') {
                                        $LinkObject->LinkAdd(
                                            SourceObject => $TargetObjectOrg,
                                            SourceKey    => $TargetKeyOrg,
                                            TargetObject => 'Ticket',
                                            TargetKey    => $TicketID,
                                            Type         => $Type,
                                            State        => 'Valid',
                                            UserID       => $Self->{UserID},
                                        );
                                    } else {
                                        $LinkObject->LinkAdd(
                                            SourceObject => 'Ticket',
                                            SourceKey    => $TicketID,
                                            TargetObject => $TargetObjectOrg,
                                            TargetKey    => $TargetKeyOrg,
                                            Type         => $Type,
                                            State        => 'Valid',
                                            UserID       => $Self->{UserID},
                                        );
                                    }
                                }
                            }
                        }
                    }
                }
            }
# ---
        # link split ticket
        if (
            $GetParam{LinkTicketID}
            && $Config->{SplitLinkType}
            && $Config->{SplitLinkType}->{LinkType}
            && $Config->{SplitLinkType}->{Direction}
        ) {

            my $SourceKey = $GetParam{LinkTicketID};
            my $TargetKey = $TicketID;

            if ( $Config->{SplitLinkType}->{Direction} eq 'Source' ) {
                $SourceKey = $TicketID;
                $TargetKey = $GetParam{LinkTicketID};
            }

            # link the tickets
            $LinkObject->LinkAdd(
                SourceObject => 'Ticket',
                SourceKey    => $SourceKey,
                TargetObject => 'Ticket',
                TargetKey    => $TargetKey,
                Type         => $Config->{SplitLinkType}->{LinkType} || 'Normal',
                State        => 'Valid',
                UserID       => $Self->{UserID},
            );
        }

        my $LinkType = $ConfigObject->Get('KIXSidebarConfigItemLink::LinkType')
            || 'Normal';
        for my $CurrKey (@SelectedCIIDs) {
            $LinkObject->LinkAdd(
                SourceObject => 'ITSMConfigItem',
                SourceKey    => $CurrKey,
                TargetObject => 'Ticket',
                TargetKey    => $TicketID,
                Type         => $LinkType,
                State        => 'Valid',
                UserID       => $Self->{UserID},
            );
        }

        # get redirect screen
        my $NextScreen = $Self->{UserCreateNextMask} || 'AgentTicketEmail';

        # redirect
        return $LayoutObject->Redirect(
            OP => "Action=$NextScreen;Subaction=Created;TicketID=$TicketID",
        );
    }
# ---
# ITSMIncidentProblemManagement
# ---
    elsif ( $Self->{Subaction} eq 'GetServiceIncidentState' ) {

        # get the selected service id
        my $ServiceID = $ParamObject->GetParam( Param => 'ServiceID' ) || '';

        # build empty response hash
        my %Response = (
            CurInciSignal => '',
            CurInciState  => '&nbsp',
        );

        # only if service id is selected
        if ( $ServiceID && $Config->{ShowIncidentState} ) {

            # set incident signal
            my %InciSignals = (
                operational => 'greenled',
                warning     => 'yellowled',
                incident    => 'redled',
            );

            # build the response
            %Response = (
                CurInciSignal => $InciSignals{ $Service{CurInciStateType} },
                CurInciState  => $LayoutObject->{LanguageObject}->Translate($Service{CurInciState}),
            );
        }

        # encode response to JSON
        my $JSON = $LayoutObject->JSONEncode(
            Data => \%Response,
        );

        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
            Content     => $JSON,
            Type        => 'inline',
            NoCache     => 1,
        );
    }
# ---
    elsif ( $Self->{Subaction} eq 'AJAXUpdate' ) {
        my $Dest           = $ParamObject->GetParam( Param => 'Dest' ) || '';
        my $CustomerUser   = $ParamObject->GetParam( Param => 'SelectedCustomerUser' );
        my $ElementChanged = $ParamObject->GetParam( Param => 'ElementChanged' ) || '';

        # get From based on selected queue
        my $QueueID = '';
        if ( $Dest =~ /^(\d{1,100})\|\|.+?$/ ) {
            $QueueID = $1;
            my %Queue = $QueueObject->GetSystemAddress( QueueID => $QueueID );
            $GetParam{From} = $Queue{Email};
        }

        if ( $ConfigObject->Get('Frontend::Agent::CreateOptions::ViewAllOwner') ) {
            $GetParam{OwnerAll}       = 1;
            $GetParam{ResponsibleAll} = 1;
        }
        $ElementChanged = $GetParam{ElementChanged} || $ElementChanged;
        my $ServiceID =
            $GetParam{ServiceID}
            || $ParamObject->GetParam( Param => 'ServiceID' )
            || '';

        if ( $ElementChanged eq 'ServiceID' && $ServiceID ) {

            # retrieve service data...
            my %ServiceData = $Kernel::OM->Get('Kernel::System::Service')->ServiceGet(
                ServiceID => $ServiceID,
                UserID    => 1,
            );

            my $DefaultSetQueueID = "";
            if ( $Self->{DefaultSet} ) {
                my %TicketTemplate = $TicketObject->TicketTemplateGet(
                    ID => $Self->{DefaultSet},
                );
                $DefaultSetQueueID = $TicketTemplate{QueueID};
            }

            if ( !$DefaultSetQueueID && %ServiceData && $ServiceData{AssignedQueueID} ) {
                $QueueID = $ServiceData{AssignedQueueID};
                $Dest    = 'SetByQueueID';
            }

        }

        # get list type
        my $TreeView = 0;
        if ( $ConfigObject->Get('Ticket::Frontend::ListType') eq 'tree' ) {
            $TreeView = 1;
        }

        my $Tos = $Self->_GetTos(
            %GetParam,
            %ACLCompatGetParam,
            CustomerUserID => $CustomerUser || '',
            QueueID => $QueueID,
        );

        my $NewTos;

        if ($Tos) {
            TOs:
            for my $KeyTo ( sort keys %{$Tos} ) {
                next TOs if ( $Tos->{$KeyTo} eq '-' );
                $NewTos->{"$KeyTo||$Tos->{$KeyTo}"} = $Tos->{$KeyTo};
            }
        }
        my $Signature = '';
        if ($QueueID) {
            $Signature = $Self->_GetSignature( QueueID => $QueueID );
        }
        my $Users = $Self->_GetOwners(
            %GetParam,
            %ACLCompatGetParam,
            QueueID  => $QueueID,
            AllUsers => $GetParam{OwnerAll},
        );
        my $ResponsibleUsers = $Self->_GetResponsibles(
            %GetParam,
            %ACLCompatGetParam,
            QueueID  => $QueueID,
            AllUsers => $GetParam{ResponsibleAll},
        );

        my %NewTo = ();
        for my $QueueKey ( keys( %{$Tos} ) ) {
            $NewTo{ $QueueKey . "||" . $Tos->{$QueueKey} } = $Tos->{$QueueKey};
        }
        if ( $QueueID && $Dest eq 'SetByQueueID' ) {
            $Dest = $QueueID . "||" . $Tos->{$QueueID};
        }

        my $NextStates = $Self->_GetNextStates(
            %GetParam,
            %ACLCompatGetParam,
            CustomerUserID => $CustomerUser || '',
            QueueID        => $QueueID      || 1,
            TypeID         => $GetParam{TypeID},
            DefaultSet     => $GetParam{DefaultSet},
        );
        my $Priorities = $Self->_GetPriorities(
            %GetParam,
            %ACLCompatGetParam,
            CustomerUserID => $CustomerUser || '',
            QueueID        => $QueueID      || 1,
        );
        my $Services = $Self->_GetServices(
            %GetParam,
            %ACLCompatGetParam,
            CustomerUserID => $CustomerUser || '',
            QueueID        => $QueueID      || 1,
        );
        my $SLAs = $Self->_GetSLAs(
            %GetParam,
            %ACLCompatGetParam,
            CustomerUserID => $CustomerUser || '',
            QueueID        => $QueueID      || 1,
            Services       => $Services,
        );
        my $StandardTemplates = $Self->_GetStandardTemplates(
            %GetParam,
            %ACLCompatGetParam,
            QueueID => $QueueID || '',
        );
        my $Types = $Self->_GetTypes(
            %GetParam,
            %ACLCompatGetParam,
            CustomerUserID => $CustomerUser || '',
            QueueID        => $QueueID      || 1,
        );

        # update Dynamic Fields Possible Values via AJAX
        my @DynamicFieldAJAX;
        my %DynamicFieldHTML;

        # cycle through the activated Dynamic Fields for this screen
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {
            next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

            my $IsACLReducible = $DynamicFieldBackendObject->HasBehavior(
                DynamicFieldConfig => $DynamicFieldConfig,
                Behavior           => 'IsACLReducible',
            );

            if ( !$IsACLReducible ) {
                $DynamicFieldHTML{ $DynamicFieldConfig->{Name} } =
                    $DynamicFieldBackendObject->EditFieldRender(
                        DynamicFieldConfig => $DynamicFieldConfig,
                        Mandatory =>
                            $Config->{DynamicField}->{ $DynamicFieldConfig->{Name} } == 2,
                        LayoutObject    => $LayoutObject,
                        ParamObject     => $ParamObject,
                        AJAXUpdate      => 0,
                        UpdatableFields => $Self->_GetFieldsToUpdate(),
                        UseDefaultValue => 1,
                    );
                next DYNAMICFIELD;
            }

            my $PossibleValues = $DynamicFieldBackendObject->PossibleValuesGet(
                DynamicFieldConfig => $DynamicFieldConfig,
            );

            # convert possible values key => value to key => key for ACLs using a Hash slice
            my %AclData = %{$PossibleValues};
            @AclData{ keys %AclData } = keys %AclData;

            # set possible values filter from ACLs
            my $ACL = $TicketObject->TicketAcl(
                %GetParam,
                %ACLCompatGetParam,
                CustomerUserID => $CustomerUser || '',
                Action         => $Self->{Action},
                QueueID        => $QueueID      || 0,
                ReturnType     => 'Ticket',
                ReturnSubType  => 'DynamicField_' . $DynamicFieldConfig->{Name},
                Data           => \%AclData,
                UserID         => $Self->{UserID},
            );
            if ($ACL) {
                my %Filter = $TicketObject->TicketAclData();

                # convert Filer key => key back to key => value using map
                %{$PossibleValues} = map { $_ => $PossibleValues->{$_} } keys %Filter;
            }

            my $DataValues = $DynamicFieldBackendObject->BuildSelectionDataGet(
                DynamicFieldConfig => $DynamicFieldConfig,
                PossibleValues     => $PossibleValues,
                Value              => $DynamicFieldValues{ $DynamicFieldConfig->{Name} },
            ) || $PossibleValues;

            $DynamicFieldHTML{ $DynamicFieldConfig->{Name} } =
                $DynamicFieldBackendObject->EditFieldRender(
                    DynamicFieldConfig   => $DynamicFieldConfig,
                    PossibleValuesFilter => $DynamicFieldConfig->{ShownPossibleValues},
                    Mandatory =>
                        $Config->{DynamicField}->{ $DynamicFieldConfig->{Name} } == 2,
                    LayoutObject    => $LayoutObject,
                    ParamObject     => $ParamObject,
                    AJAXUpdate      => 1,
                    UpdatableFields => $Self->_GetFieldsToUpdate(),
                    UseDefaultValue => 1,
                );

            # add dynamic field to the list of fields to update
            push(
                @DynamicFieldAJAX,
                {
                    Name        => 'DynamicField_' . $DynamicFieldConfig->{Name},
                    Data        => $DataValues,
                    SelectedID  => $DynamicFieldValues{ $DynamicFieldConfig->{Name} } // $DynamicFieldConfig->{Config}->{DefaultValue},
                    Translation => $DynamicFieldConfig->{Config}->{TranslatableValues} || 0,
                    Max         => 100,
                }
            );
        }

        # run acl to prepare TicketAclFormData
        my $ShownDFACL = $Kernel::OM->Get('Kernel::System::Ticket')->TicketAcl(
            %GetParam,
            %ACLCompatGetParam,
            CustomerUserID => $CustomerUser || '',
            QueueID        => $QueueID || 0,
            Action         => $Self->{Action},
            ReturnType     => 'Ticket',
            ReturnSubType  => '-',
            Data           => {},
            UserID         => $Self->{UserID},
        );

        # update 'Shown' for $Self->{DynamicField}
        $Self->_GetShownDynamicFields();

        my %Output;
        DYNAMICFIELD:
        for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {

            if ( $DynamicFieldConfig->{Shown} == 1 ) {

                $Output{ ( "DynamicField_" . $DynamicFieldConfig->{Name} ) } = (
                    $DynamicFieldHTML{ $DynamicFieldConfig->{Name} }->{Label}
                        . qq~\n<div class="Field">~
                        . $DynamicFieldHTML{ $DynamicFieldConfig->{Name} }->{Field}
                        . qq~\n</div>\n<div class="Clear"></div>\n~
                );
            }
            else {
                $Output{ ( "DynamicField_" . $DynamicFieldConfig->{Name} ) } = "";
            }
        }

        my @FormDisplayOutput;
        if ( IsHashRefWithData( \%Output ) ) {
            push @FormDisplayOutput, {
                Name => 'FormDisplay',
                Data => \%Output,
                Max  => 10000,
            };
        }

        my @TemplateAJAX;

        # update ticket body and attachements if needed.
        if ( $ElementChanged eq 'StandardTemplateID' ) {
            my @TicketAttachments;
            my $TemplateText;

            # remove all attachments from the Upload cache
            my $RemoveSuccess = $UploadCacheObject->FormIDRemove(
                FormID => $Self->{FormID},
            );
            if ( !$RemoveSuccess ) {
                $Kernel::OM->Get('Kernel::System::Log')->Log(
                    Priority => 'error',
                    Message  => "Form attachments could not be deleted!",
                );
            }

            # get the template text and set new attachments if a template is selected
            if ( IsPositiveInteger( $GetParam{StandardTemplateID} ) ) {
                my $TemplateGenerator = $Kernel::OM->Get('Kernel::System::TemplateGenerator');

                # set template text, replace smart tags (limited as ticket is not created)
                $TemplateText = $TemplateGenerator->Template(
                    TemplateID => $GetParam{StandardTemplateID},
                    UserID     => $Self->{UserID},
                );

                # create StdAttachmentObject
                my $StdAttachmentObject = $Kernel::OM->Get('Kernel::System::StdAttachment');

                # add std. attachments to ticket
                my %AllStdAttachments = $StdAttachmentObject->StdAttachmentStandardTemplateMemberList(
                    StandardTemplateID => $GetParam{StandardTemplateID},
                );
                for ( sort keys %AllStdAttachments ) {
                    my %AttachmentsData = $StdAttachmentObject->StdAttachmentGet( ID => $_ );
                    $UploadCacheObject->FormIDAddFile(
                        FormID      => $Self->{FormID},
                        Disposition => 'attachment',
                        %AttachmentsData,
                    );
                }

                # send a list of attachments in the upload cache back to the clientside JavaScript
                # which renders then the list of currently uploaded attachments
                @TicketAttachments = $UploadCacheObject->FormIDGetAllFilesMeta(
                    FormID => $Self->{FormID},
                );
            }

            @TemplateAJAX = (
                {
                    Name => 'UseTemplateCreate',
                    Data => '0',
                },
                {
                    Name => 'RichText',
                    Data => $TemplateText || '',
                },
                {
                    Name     => 'TicketAttachments',
                    Data     => \@TicketAttachments,
                    KeepData => 1,
                },
            );
        }

        my @ExtendedData;

        # run compose modules
        if ( ref $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') eq 'HASH' ) {

            # use QueueID from web request in compose modules
            $GetParam{QueueID} = $QueueID;

            my %Jobs = %{ $ConfigObject->Get('Ticket::Frontend::ArticleComposeModule') };
            JOB:
            for my $Job ( sort keys %Jobs ) {

                # load module
                next JOB if !$MainObject->Require( $Jobs{$Job}->{Module} );

                my $Object = $Jobs{$Job}->{Module}->new(
                    %{$Self},
                    Debug => $Debug,
                );

                # get params
                for my $Parameter ( $Object->Option( %GetParam, Config => $Jobs{$Job} ) ) {
                    $GetParam{$Parameter} = $ParamObject->GetParam( Param => $Parameter );
                }

                # run module
                my %Data = $Object->Data( %GetParam, Config => $Jobs{$Job} );

                # get AJAX param values
                if ( $Object->can('GetParamAJAX') ) {
                    %GetParam = ( %GetParam, $Object->GetParamAJAX(%GetParam) )
                }

                my $Key = $Object->Option( %GetParam, Config => $Jobs{$Job} );
                if ($Key) {
                    push(
                        @ExtendedData,
                        {
                            Name        => $Key,
                            Data        => \%Data,
                            SelectedID  => $GetParam{$Key},
                            Translation => 1,
                            Max         => 100,
                        }
                    );
                }
            }
        }

        # convert Signature to ASCII, if RichText is on
        if ( $LayoutObject->{BrowserRichText} ) {

            #            $Signature = $Kernel::OM->Get('Kernel::System::HTMLUtils')->ToAscii( String => $Signature, );
        }

        # create hash with DisabledOptions
        my $ListOptionJson = $LayoutObject->AgentListOptionJSON(
            [
                {
                    Name => 'Dest',
                    Data => \%NewTo,
                },
                {
                    Name => 'Services',
                    Data => $Services,
                },
            ],
        );

        my $JSON = $LayoutObject->BuildSelectionJSON(
            [
                {
                    Name            => 'Dest',
                    Data            => $ListOptionJson->{Dest}->{Data},
                    SelectedID      => $Dest,
                    Translation     => 0,
                    PossibleNone    => 0,
                    TreeView        => $TreeView,
                    Max             => 100,
                    DisabledOptions => $ListOptionJson->{Dest}->{DisabledOptions} || 0,
                },
                {
                    Name         => 'Signature',
                    Data         => $Signature,
                    Translation  => 1,
                    PossibleNone => 1,
                    Max          => 100,
                },
                {
                    Name         => 'NewUserID',
                    Data         => $Users,
                    SelectedID   => $GetParam{NewUserID},
                    Translation  => 0,
                    PossibleNone => 1,
                    Max          => 100,
                },
                {
                    Name         => 'NewResponsibleID',
                    Data         => $ResponsibleUsers,
                    SelectedID   => $GetParam{NewResponsibleID},
                    Translation  => 0,
                    PossibleNone => 1,
                    Max          => 100,
                },
                {
                    Name        => 'NextStateID',
                    Data        => $NextStates,
                    SelectedID  => $GetParam{NextStateID},
                    Translation => 1,
                    Max         => 100,
                },
                {
                    Name        => 'PriorityID',
                    Data        => $Priorities,
                    SelectedID  => $GetParam{PriorityID},
                    Translation => 1,
                    Max         => 100,
                },
                {
                    Name            => 'ServiceID',
                    Data            => $ListOptionJson->{Services}->{Data},
                    SelectedID      => $GetParam{ServiceID},
                    PossibleNone    => 1,
                    Translation     => $ConfigObject->Get('Ticket::ServiceTranslation') || 0,
                    TreeView        => $TreeView,
                    DisabledOptions => $ListOptionJson->{Services}->{DisabledOptions} || 0,
                    Max             => 100,
                },
                {
                    Name         => 'SLAID',
                    Data         => $SLAs,
                    SelectedID   => $GetParam{SLAID},
                    PossibleNone => 1,
                    Translation  => $ConfigObject->Get('Ticket::SLATranslation') || 0,
                    Max          => 100,
                },
                {
                    Name         => 'StandardTemplateID',
                    Data         => $StandardTemplates,
                    SelectedID   => $GetParam{StandardTemplateID},
                    PossibleNone => 1,
                    Translation  => 1,
                    Max          => 100,
                },
                {
                    Name         => 'TypeID',
                    Data         => $Types,
                    SelectedID   => $GetParam{TypeID},
                    PossibleNone => 1,
                    Translation  => 0,
                    Max          => 100,
                },
                @FormDisplayOutput,
                @DynamicFieldAJAX,
                @TemplateAJAX,
                @ExtendedData,
            ],
        );
        return $LayoutObject->Attachment(
            ContentType => 'application/json; charset=' . $LayoutObject->{Charset},
            Content     => $JSON,
            Type        => 'inline',
            NoCache     => 1,
        );
    }

    # update position
    elsif ( $Self->{Subaction} eq 'UpdatePosition' ) {

        # challenge token check for write action
        $LayoutObject->ChallengeTokenCheck();

        my @Backends = $ParamObject->GetArray( Param => 'Backend' );

        # get new order
        my $Key  = $Self->{Action} . 'Position';
        my $Data = '';
        for my $Backend (@Backends) {
            $Data .= $Backend . ';';
        }

        # update ssession
        $Kernel::OM->Get('Kernel::System::AuthSession')->UpdateSessionID(
            SessionID => $Self->{SessionID},
            Key       => $Key,
            Value     => $Data,
        );

        # update preferences
        if ( !$ConfigObject->Get('DemoSystem') ) {
            $Kernel::OM->Get('Kernel::System::User')->SetPreferences(
                UserID => $Self->{UserID},
                Key    => $Key,
                Value  => $Data,
            );
        }

        # redirect
        return $LayoutObject->Attachment(
            ContentType => 'text/html',
            Charset     => $LayoutObject->{UserCharset},
            Content     => '',
        );
    }

    else {
        return $LayoutObject->ErrorScreen(
            Message => Translatable('No Subaction!'),
            Comment => Translatable('Please contact the administrator.'),
        );
    }
}

sub _GetNextStates {
    my ( $Self, %Param ) = @_;

    my %NextStates;
    if ( $Param{QueueID} || $Param{TicketID} ) {
        %NextStates = $Kernel::OM->Get('Kernel::System::Ticket')->TicketStateList(
            %Param,
            Action => $Self->{Action},
            UserID => $Self->{UserID},
        );
    }
    return \%NextStates;
}

sub _GetOwners {
    my ( $Self, %Param ) = @_;

    # get needed objects
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $GroupObject  = $Kernel::OM->Get('Kernel::System::Group');
    my $QueueObject  = $Kernel::OM->Get('Kernel::System::Queue');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $UserObject   = $Kernel::OM->Get('Kernel::System::User');

    # get available permissions and set permission group type accordingly.
    my $ConfigPermissions   = $ConfigObject->Get('System::Permission');
    my $PermissionGroupType = ( grep { $_ eq 'owner' } @{$ConfigPermissions} ) ? 'owner' : 'rw';

    # get login list of users
    my %UserLoginList = $UserObject->UserList(
        Type  => 'Short',
        Valid => 1,
    );

    # just show only users with selected custom queue
    if (
        $Param{QueueID}
        && !$Param{AllUsers}
    ) {
        my @UserIDs = $TicketObject->GetSubscribedUserIDsByQueueID( %Param );
        for my $GroupMemberKey ( keys( %UserLoginList ) ) {
            my $Hit = 0;
            USERID:
            for my $UID (@UserIDs) {
                if ( $UID eq $GroupMemberKey ) {
                    $Hit = 1;

                    last USERID;
                }
            }
            if ( !$Hit ) {
                delete( $UserLoginList{ $GroupMemberKey } );
            }
        }
    }

    # prepare acl data
    my %ACLUsers;

    # show all system users
    if ( $ConfigObject->Get('Ticket::ChangeOwnerToEveryone') ) {
        %ACLUsers = %UserLoginList;
    }

    # show all subscribed users who have the appropriate permission in the queue group
    elsif ( $Param{QueueID} ) {
        my $GID = $QueueObject->GetQueueGroupID(
            QueueID => $Param{QueueID}
        );

        my %MemberList = $GroupObject->PermissionGroupGet(
            GroupID => $GID,
            Type    => $PermissionGroupType,
        );

        for my $MemberKey ( keys( %MemberList ) ) {
            if ( $UserLoginList{ $MemberKey } ) {
                $ACLUsers{ $MemberKey } = $UserLoginList{ $MemberKey };
            }
        }
    }

    # apply acl
    my $ACL = $TicketObject->TicketAcl(
        %Param,
        Action        => $Self->{Action},
        ReturnType    => 'Ticket',
        ReturnSubType => 'Owner',
        Data          => \%ACLUsers,
        UserID        => $Self->{UserID},
    );
    if ( $ACL ) {
        %ACLUsers = $TicketObject->TicketAclData();
    }

    # prepare display data
    my %UserNameList = $UserObject->UserList(
        Type  => 'Long',
        Valid => 1,
    );
    my %ShownUsers = map( { $_ => $UserNameList{$_} } keys( %ACLUsers ) );

    return \%ShownUsers;
}

sub _GetResponsibles {
    my ( $Self, %Param ) = @_;

    # get needed objects
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $GroupObject  = $Kernel::OM->Get('Kernel::System::Group');
    my $QueueObject  = $Kernel::OM->Get('Kernel::System::Queue');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');
    my $UserObject   = $Kernel::OM->Get('Kernel::System::User');

    # get available permissions and set permission group type accordingly.
    my $ConfigPermissions   = $ConfigObject->Get('System::Permission');
    my $PermissionGroupType = ( grep { $_ eq 'responsible' } @{$ConfigPermissions} ) ? 'responsible' : 'rw';

    # get login list of users
    my %UserLoginList = $UserObject->UserList(
        Type  => 'Short',
        Valid => 1,
    );

    # just show only users with selected custom queue
    if (
        $Param{QueueID}
        && !$Param{AllUsers}
    ) {
        my @UserIDs = $TicketObject->GetSubscribedUserIDsByQueueID( %Param );
        for my $GroupMemberKey ( keys( %UserLoginList ) ) {
            my $Hit = 0;
            USERID:
            for my $UID (@UserIDs) {
                if ( $UID eq $GroupMemberKey ) {
                    $Hit = 1;

                    last USERID;
                }
            }
            if ( !$Hit ) {
                delete( $UserLoginList{ $GroupMemberKey } );
            }
        }
    }

    # prepare acl data
    my %ACLUsers;

    # show all system users
    if ( $ConfigObject->Get('Ticket::ChangeOwnerToEveryone') ) {
        %ACLUsers = %UserLoginList;
    }

    # show all subscribed users who have the appropriate permission in the queue group
    elsif ( $Param{QueueID} ) {
        my $GID = $QueueObject->GetQueueGroupID(
            QueueID => $Param{QueueID}
        );

        my %MemberList = $GroupObject->PermissionGroupGet(
            GroupID => $GID,
            Type    => $PermissionGroupType,
        );

        for my $MemberKey ( keys( %MemberList ) ) {
            if ( $UserLoginList{ $MemberKey } ) {
                $ACLUsers{ $MemberKey } = $UserLoginList{ $MemberKey };
            }
        }
    }

    # apply acl
    my $ACL = $TicketObject->TicketAcl(
        %Param,
        Action        => $Self->{Action},
        ReturnType    => 'Ticket',
        ReturnSubType => 'Responsible',
        Data          => \%ACLUsers,
        UserID        => $Self->{UserID},
    );
    if ( $ACL ) {
        %ACLUsers = $TicketObject->TicketAclData();
    }

    # prepare display data
    my %UserNameList = $UserObject->UserList(
        Type  => 'Long',
        Valid => 1,
    );
    my %ShownUsers = map( { $_ => $UserNameList{$_} } keys( %ACLUsers ) );

    return \%ShownUsers;
}

sub _GetPriorities {
    my ( $Self, %Param ) = @_;

    # get priority
    my %Priorities;
    if ( $Param{QueueID} || $Param{TicketID} ) {
        %Priorities = $Kernel::OM->Get('Kernel::System::Ticket')->TicketPriorityList(
            %Param,
            Action => $Self->{Action},
            UserID => $Self->{UserID},
        );
    }
    return \%Priorities;
}

sub _GetTypes {
    my ( $Self, %Param ) = @_;

    # get type
    my %Type;
    if ( $Param{QueueID} || $Param{TicketID} ) {
        %Type = $Kernel::OM->Get('Kernel::System::Ticket')->TicketTypeList(
            %Param,
            Action => $Self->{Action},
            UserID => $Self->{UserID},
        );
    }
    return \%Type;
}

sub _GetServices {
    my ( $Self, %Param ) = @_;

    # get service
    my %Service;

    # get options for default services for unknown customers
    my $DefaultServiceUnknownCustomer = $Kernel::OM->Get('Kernel::Config')->Get('Ticket::Service::Default::UnknownCustomer');

    # check if no CustomerUserID is selected
    # if $DefaultServiceUnknownCustomer = 0 leave CustomerUserID empty, it will not get any services
    # if $DefaultServiceUnknownCustomer = 1 set CustomerUserID to get default services
    if (
        !$Param{CustomerUserID}
        && $DefaultServiceUnknownCustomer
    ) {
        $Param{CustomerUserID} = '<DEFAULT>';
    }

    # get service list
    if ( $Param{CustomerUserID} ) {
        %Service = $Kernel::OM->Get('Kernel::System::Ticket')->TicketServiceList(
            %Param,
            Action => $Self->{Action},
            UserID => $Self->{UserID},
        );
    }
    return \%Service;
}

sub _GetSLAs {
    my ( $Self, %Param ) = @_;

    # get sla
    my %SLA;
    if ( $Param{ServiceID} && $Param{Services} && %{ $Param{Services} } ) {
        if ( $Param{Services}->{ $Param{ServiceID} } ) {
            %SLA = $Kernel::OM->Get('Kernel::System::Ticket')->TicketSLAList(
                %Param,
                Action => $Self->{Action},
                UserID => $Self->{UserID},
            );
        }
    }
    return \%SLA;
}

sub _GetTos {
    my ( $Self, %Param ) = @_;

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # check own selection
    my %NewTos;
    if ( $ConfigObject->Get('Ticket::Frontend::NewQueueOwnSelection') ) {
        %NewTos = %{ $ConfigObject->Get('Ticket::Frontend::NewQueueOwnSelection') };
    }
    else {

        # SelectionType Queue or SystemAddress?
        my %Tos;
        if ( $ConfigObject->Get('Ticket::Frontend::NewQueueSelectionType') eq 'Queue' ) {
            %Tos = $Kernel::OM->Get('Kernel::System::Ticket')->TicketMoveList(
                %Param,
                Type    => 'create',
                Action  => $Self->{Action},
                UserID  => $Self->{UserID},
                QueueID => $Param{QueueID},
                TypeID  => $Param{TypeID},
            );
        }
        else {
            %Tos = $Kernel::OM->Get('Kernel::System::DB')->GetTableData(
                Table => 'system_address',
                What  => 'queue_id, id',
                Valid => 1,
                Clamp => 1,
            );
        }

        # get create permission queues
        my %UserGroups = $Kernel::OM->Get('Kernel::System::Group')->PermissionUserGet(
            UserID => $Self->{UserID},
            Type   => 'create',
        );

        # build selection string
        QUEUEID:
        for my $QueueID ( sort keys %Tos ) {
            my %QueueData = $Kernel::OM->Get('Kernel::System::Queue')->QueueGet( ID => $QueueID );

            # permission check, can we create new tickets in queue
            next QUEUEID if !$UserGroups{ $QueueData{GroupID} };

            my $String = $ConfigObject->Get('Ticket::Frontend::NewQueueSelectionString')
                || '<Realname> <<Email>> - Queue: <Queue>';
            $String =~ s/<Queue>/$QueueData{Name}/g;
            $String =~ s/<QueueComment>/$QueueData{Comment}/g;
            if ( $ConfigObject->Get('Ticket::Frontend::NewQueueSelectionType') ne 'Queue' ) {
                my %SystemAddressData = $Kernel::OM->Get('Kernel::System::SystemAddress')->SystemAddressGet(
                    ID => $Tos{$QueueID},
                );
                $String =~ s/<Realname>/$SystemAddressData{Realname}/g;
                $String =~ s/<Email>/$SystemAddressData{Name}/g;
            }
            $NewTos{$QueueID} = $String;
        }
    }

    # add empty selection
    $NewTos{''} = '-';
    return \%NewTos;
}

sub _GetSignature {
    my ( $Self, %Param ) = @_;

    # prepare signature
    my $TemplateGenerator = $Kernel::OM->Get('Kernel::System::TemplateGenerator');
    my $Signature         = $TemplateGenerator->Signature(
        QueueID  => $Param{QueueID},
        Data     => \%Param,
        UserID   => $Self->{UserID},
        TicketID => $Param{TicketID},
    );

    return $Signature;
}

sub _GetStandardTemplates {
    my ( $Self, %Param ) = @_;

    # get create templates
    my %Templates;

    # check needed
    return \%Templates if !$Param{QueueID} && !$Param{TicketID};

    my $QueueID = $Param{QueueID} || '';
    if ( !$Param{QueueID} && $Param{TicketID} ) {

        # get QueueID from the ticket
        my %Ticket = $Kernel::OM->Get('Kernel::System::Ticket')->TicketGet(
            TicketID      => $Param{TicketID},
            DynamicFields => 0,
            UserID        => $Self->{UserID},
        );
        $QueueID = $Ticket{QueueID} || '';
    }

    # fetch all std. templates
    my %StandardTemplates = $Kernel::OM->Get('Kernel::System::Queue')->QueueStandardTemplateMemberList(
        QueueID       => $QueueID,
        TemplateTypes => 1,
    );

    # return empty hash if there are no templates for this screen
    return \%Templates if !IsHashRefWithData( $StandardTemplates{Create} );

    # return just the templates for this screen
    return $StandardTemplates{Create};
}

sub _MaskEmailNew {
    my ( $Self, %Param ) = @_;

    $Param{FormID} = $Self->{FormID};

    # get config object
    my $ConfigObject = $Kernel::OM->Get('Kernel::Config');

    # get layout object - moved from below
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    my @Templates = $TicketObject->TicketTemplateList(
        Result   => 'ID',
        Frontend => 'Agent',
        UserID => $Self->{UserID},
    );

    if ( scalar @Templates ) {

        my %TemplateHash;
        for my $TemplateKeys (@Templates) {
            $TemplateHash{$TemplateKeys} = $TicketObject->TicketTemplateLookup(
                ID => $TemplateKeys
            );
        }

        my $DefaultSetSelection = $LayoutObject->BuildSelection(
            Data         => \%TemplateHash,
            SelectedID   => $Self->{DefaultSet} || 0,
            Translation  => 0,
            Name         => 'DefaultSetSelection',
            PossibleNone => 1,
            Class        => 'Modernize'
        );
        $LayoutObject->Block(
            Name => 'DefaultSetSelection',
            Data => {
                DefaultSetSelStr => $DefaultSetSelection,
            },
        );
    }

    # get list type
    my $TreeView = 0;
    if ( $ConfigObject->Get('Ticket::Frontend::ListType') eq 'tree' ) {
        $TreeView = 1;
    }

    # build customer search autocomplete field
    $LayoutObject->Block(
        Name => 'CustomerSearchAutoComplete',
    );

    # build string
    $Param{Users}->{''} = '-';
    $Param{OptionStrg} = $LayoutObject->BuildSelection(
        Data       => $Param{Users},
        SelectedID => $Param{UserSelected},
        Name       => 'NewUserID',
        Class      => 'Modernize ' . ( $Param{Errors}->{NewUserInvalid} || '' ),
    );

    my $Config = $Kernel::OM->Get('Kernel::Config')->Get("Ticket::Frontend::$Self->{Action}");

    # build next states string
    $Param{NextStatesStrg} = $LayoutObject->BuildSelection(
        Data          => $Param{NextStates},
        Name          => 'NextStateID',
        Class         => 'Validate_Required Modernize ' . ( $Param{Errors}->{NextStateInvalid} || ' ' ),
        Translation   => 1,
        SelectedValue => $Param{NextState} || $Config->{StateDefault},
    );

    # build Destination string
    my %NewTo;
    if ( $Param{FromList} ) {
        for my $FromKey ( sort keys %{ $Param{FromList} } ) {
            $NewTo{"$FromKey||$Param{FromList}->{$FromKey}"} = $Param{FromList}->{$FromKey};
        }
    }

    if ( $ConfigObject->Get('Ticket::Frontend::NewQueueSelectionType') eq 'Queue' ) {
        $Param{FromStrg} = $LayoutObject->AgentQueueListOption(
            Data           => \%NewTo,
            Multiple       => 0,
            Size           => 0,
            Class          => 'Validate_Required Modernize ' . ( $Param{Errors}->{DestinationInvalid} || ' ' ),
            Name           => 'Dest',
            TreeView       => $TreeView,
            SelectedID     => $Param{FromSelected} || $Param{DefaultQueueSelected} || '',
            Translation    => 0,
            OnChangeSubmit => 0,
        );
    }
    else {
        $Param{FromStrg} = $LayoutObject->BuildSelection(
            Data       => \%NewTo,
            Class      => 'Validate_Required Modernize ' . ( $Param{Errors}->{DestinationInvalid} || ' ' ),
            Name       => 'Dest',
            TreeView   => $TreeView,
            SelectedID => $Param{FromSelected},
        );
    }

    # load KIXSidebar
    $Param{KIXSidebarContent} = $LayoutObject->AgentKIXSidebar(
        %Param,
        TypeID => $Param{TypeID} || $Param{DefaultTypeID} || ''
    );

    # prepare errors!
    if ( $Param{Errors} ) {
        for my $ErrorKey ( sort keys %{ $Param{Errors} } ) {
            $Param{$ErrorKey} = $LayoutObject->Ascii2Html( Text => $Param{Errors}->{$ErrorKey} );
        }
    }

    # From external
    my $ShowErrors = 1;
    if (
        defined $Param{FromExternalCustomer}
        &&
        defined $Param{FromExternalCustomer}->{Email} &&
        defined $Param{FromExternalCustomer}->{Customer}
    ) {
        $ShowErrors = 0;
        $LayoutObject->Block(
            Name => 'FromExternalCustomer',
            Data => $Param{FromExternalCustomer},
        );
    }

    # Cc
    my $CustomerCounterCc = 0;
    if ( $Param{MultipleCustomerCc} ) {
        for my $Item ( @{ $Param{MultipleCustomerCc} } ) {
            if ( !$ShowErrors ) {

                # set empty values for errors
                $Item->{CustomerError}    = '';
                $Item->{CustomerDisabled} = '';
                $Item->{CustomerErrorMsg} = 'CustomerGenericServerErrorMsg';
            }
            $LayoutObject->Block(
                Name => 'CcMultipleCustomer',
                Data => $Item,
            );
            $LayoutObject->Block(
                Name => 'Cc' . $Item->{CustomerErrorMsg},
                Data => $Item,
            );
            if ( $Item->{CustomerError} ) {
                $LayoutObject->Block(
                    Name => 'CcCustomerErrorExplantion',
                );
            }
            $CustomerCounterCc++;
        }
    }

    if ( !$CustomerCounterCc ) {
        $Param{CcCustomerHiddenContainer} = 'Hidden';
    }

    # set customer counter
    $LayoutObject->Block(
        Name => 'CcMultipleCustomerCounter',
        Data => {
            CustomerCounter => $CustomerCounterCc++,
        },
    );

    # Bcc
    my $CustomerCounterBcc = 0;
    if ( $Param{MultipleCustomerBcc} ) {
        for my $Item ( @{ $Param{MultipleCustomerBcc} } ) {
            if ( !$ShowErrors ) {

                # set empty values for errors
                $Item->{CustomerError}    = '';
                $Item->{CustomerDisabled} = '';
                $Item->{CustomerErrorMsg} = 'CustomerGenericServerErrorMsg';
            }
            $LayoutObject->Block(
                Name => 'BccMultipleCustomer',
                Data => $Item,
            );
            $LayoutObject->Block(
                Name => 'Bcc' . $Item->{CustomerErrorMsg},
                Data => $Item,
            );
            if ( $Item->{CustomerError} ) {
                $LayoutObject->Block(
                    Name => 'BccCustomerErrorExplantion',
                );
            }
            $CustomerCounterBcc++;
        }
    }

    if ( !$CustomerCounterBcc ) {
        $Param{BccCustomerHiddenContainer} = 'Hidden';
    }

    # set customer counter
    $LayoutObject->Block(
        Name => 'BccMultipleCustomerCounter',
        Data => {
            CustomerCounter => $CustomerCounterBcc++,
        },
    );

    # To
    my $CustomerCounter = 0;
    if ( $Param{MultipleCustomer} ) {
        for my $Item ( @{ $Param{MultipleCustomer} } ) {
            if ( !$ShowErrors ) {

                # set empty values for errors
                $Item->{CustomerError}    = '';
                $Item->{CustomerDisabled} = '';
                $Item->{CustomerErrorMsg} = 'CustomerGenericServerErrorMsg';
            }
            $LayoutObject->Block(
                Name => 'MultipleCustomer',
                Data => $Item,
            );
            $LayoutObject->Block(
                Name => $Item->{CustomerErrorMsg},
                Data => $Item,
            );
            if ( $Item->{CustomerError} ) {
                $LayoutObject->Block(
                    Name => 'CustomerErrorExplantion',
                );
            }
            $CustomerCounter++;
        }
    }

    if ( !$CustomerCounter ) {
        $Param{CustomerHiddenContainer} = 'Hidden';
    }

    # set customer counter
    $LayoutObject->Block(
        Name => 'MultipleCustomerCounter',
        Data => {
            CustomerCounter => $CustomerCounter++,
        },
    );

    if ( $Param{ToInvalid} && $Param{Errors} && !$Param{Errors}->{ToErrorType} ) {
        $LayoutObject->Block(
            Name => 'ToServerErrorMsg',
        );
    }
    if ( $Param{Errors}->{ToErrorType} || !$ShowErrors ) {
        $Param{ToInvalid} = '';
    }

    if ( $Param{CcInvalid} && $Param{Errors} && !$Param{Errors}->{CcErrorType} ) {
        $LayoutObject->Block(
            Name => 'CcServerErrorMsg',
        );
    }
    if ( $Param{Errors}->{CcErrorType} || !$ShowErrors ) {
        $Param{CcInvalid} = '';
    }

    if ( $Param{BccInvalid} && $Param{Errors} && !$Param{Errors}->{BccErrorType} ) {
        $LayoutObject->Block(
            Name => 'BccServerErrorMsg',
        );
    }
    if ( $Param{Errors}->{BccErrorType} || !$ShowErrors ) {
        $Param{BccInvalid} = '';
    }

    my $DynamicFieldNames = $Self->_GetFieldsToUpdate(
        OnlyDynamicFields => 1
    );

    # create a string with the quoted dynamic field names separated by commas
    if ( !$Param{DynamicFieldNamesStrg} ) {
        $Param{DynamicFieldNamesStrg} = '';
    }

    if ( IsArrayRefWithData($DynamicFieldNames) ) {
        for my $Field ( @{$DynamicFieldNames} ) {
            $Param{DynamicFieldNamesStrg} .= ", '" . $Field . "'";
        }
    }

    # build type string
    if ( $ConfigObject->Get('Ticket::Type') ) {
        $Param{TypeStrg} = $LayoutObject->BuildSelection(
            Data         => $Param{Types},
            Name         => 'TypeID',
            Class        => 'Validate_Required Modernize ' . ( $Param{Errors}->{TypeInvalid} || ' ' ),
            SelectedID   => $Param{TypeID} || $Param{DefaultTypeID},
            PossibleNone => 1,
            Sort         => 'AlphanumericValue',
            Translation  => 0,
        );
        $LayoutObject->Block(
            Name => 'TicketType',
            Data => {%Param},
        );
    }

    # build service string
    if ( $ConfigObject->Get('Ticket::Service') ) {

        my $ListOptionJson = $LayoutObject->AgentListOptionJSON(
            [
                {
                    Name => 'Services',
                    Data => $Param{Services},
                },
            ],
        );

        if ( $Config->{ServiceMandatory} ) {
            $Param{ServiceStrg} = $LayoutObject->BuildSelection(
                Data            => $ListOptionJson->{Services}->{Data},
                Name            => 'ServiceID',
                Class           => 'Validate_Required Modernize ' . ( $Param{Errors}->{ServiceInvalid} || ' ' ),
                SelectedID      => $Param{ServiceID},
                PossibleNone    => 1,
                TreeView        => $TreeView,
                Sort            => 'TreeView',
                DisabledOptions => $ListOptionJson->{Services}->{DisabledOptions} || 0,
                Translation     => $ConfigObject->Get('Ticket::ServiceTranslation') || 0,
                Max             => 200,
            );
            $LayoutObject->Block(
                Name => 'TicketServiceMandatory',
                Data => {%Param},
            );
        }
        else {
            $Param{ServiceStrg} = $LayoutObject->BuildSelection(
                Data            => $ListOptionJson->{Services}->{Data},
                Name            => 'ServiceID',
                Class           => 'Modernize ' . ( $Param{Errors}->{ServiceInvalid} || ' ' ),
                SelectedID      => $Param{ServiceID},
                PossibleNone    => 1,
                TreeView        => $TreeView,
                Sort            => 'TreeView',
                DisabledOptions => $ListOptionJson->{Services}->{DisabledOptions} || 0,
                Translation     => $ConfigObject->Get('Ticket::ServiceTranslation') || 0,
                Max             => 200,
            );
            $LayoutObject->Block(
                Name => 'TicketService',
                Data => {%Param},
            );
        }

        if ( $Config->{SLAMandatory} ) {
            $Param{SLAStrg} = $LayoutObject->BuildSelection(
                Data         => $Param{SLAs},
                Name         => 'SLAID',
                SelectedID   => $Param{SLAID},
                Class        => 'Validate_Required Modernize ' . ( $Param{Errors}->{SLAInvalid} || ' ' ),
                PossibleNone => 1,
                Sort         => 'AlphanumericValue',
                Translation  => $ConfigObject->Get('Ticket::SLATranslation') || 0,
                Max          => 200,
            );
            $LayoutObject->Block(
                Name => 'TicketSLAMandatory',
                Data => {%Param},
            );
        }
        else {
            $Param{SLAStrg} = $LayoutObject->BuildSelection(
                Data         => $Param{SLAs},
                Name         => 'SLAID',
                SelectedID   => $Param{SLAID},
                Class        => 'Modernize',
                PossibleNone => 1,
                Sort         => 'AlphanumericValue',
                Translation  => $ConfigObject->Get('Ticket::SLATranslation') || 0,
                Max          => 200,
            );
            $LayoutObject->Block(
                Name => 'TicketSLA',
                Data => {%Param},
            );
        }
    }
# ---
# ITSMIncidentProblemManagement
# ---
    if ( $Param{PriorityIDFromImpact} ) {
        $Param{PriorityID} = $Param{PriorityIDFromImpact};
    }
# ---

    # check if exists create templates regardless the queue
    my %StandardTemplates = $Kernel::OM->Get('Kernel::System::StandardTemplate')->StandardTemplateList(
        Valid => 1,
        Type  => 'Create',
    );

    # build text template string
    if ( IsHashRefWithData( \%StandardTemplates ) ) {
        $Param{StandardTemplateStrg} = $LayoutObject->BuildSelection(
            Data       => $Param{StandardTemplates}  || {},
            Name       => 'StandardTemplateID',
            SelectedID => $Param{StandardTemplateID} || '',
            Class      => 'Modernize',
            PossibleNone => 1,
            Sort         => 'AlphanumericValue',
            Translation  => 1,
            Max          => 200,
        );
        $LayoutObject->Block(
            Name => 'StandardTemplate',
            Data => {%Param},
        );
    }

    # build priority string
    if ( !$Param{PriorityID} ) {
        $Param{Priority} = $Config->{Priority};
    }
    $Param{PriorityStrg} = $LayoutObject->BuildSelection(
        Data          => $Param{Priorities},
        Name          => 'PriorityID',
        SelectedID    => $Param{PriorityID},
        Class         => 'Validate_Required Modernize ' . ( $Param{Errors}->{PriorityInvalid} || ' ' ),
        SelectedValue => $Param{Priority},
        Translation   => 1,
    );

    # pending data string
    $Param{PendingDateString} = $LayoutObject->BuildDateSelection(
        %Param,
        Format               => 'DateInputFormatLong',
        YearPeriodPast       => 0,
        YearPeriodFuture     => 5,
        DiffTime             => $Param{DefaultDiffTime}
            || $ConfigObject->Get('Ticket::Frontend::PendingDiffTime')
            || 0,
        Class                => $Param{Errors}->{DateInvalid} || ' ',
        Validate             => 1,
        ValidateDateInFuture => 1,
    );

    # show owner selection
    if ( $ConfigObject->Get('Ticket::Frontend::NewOwnerSelection') ) {
        $LayoutObject->Block(
            Name => 'OwnerSelection',
            Data => \%Param,
        );
    }

    # show responsible selection
    if (
        $ConfigObject->Get('Ticket::Responsible')
        && $ConfigObject->Get('Ticket::Frontend::NewResponsibleSelection')
    ) {
        $Param{ResponsibleUsers}->{''} = '-';
        $Param{ResponsibleOptionStrg} = $LayoutObject->BuildSelection(
            Data       => $Param{ResponsibleUsers},
            SelectedID => $Param{ResponsibleUserSelected},
            Name       => 'NewResponsibleID',
            Class      => 'Modernize ' . ( $Param{Errors}->{NewResponsibleInvalid} || '' ),
        );
        $LayoutObject->Block(
            Name => 'ResponsibleSelection',
            Data => \%Param,
        );
    }

    # run acl to prepare TicketAclFormData
    my $ShownDFACL = $Kernel::OM->Get('Kernel::System::Ticket')->TicketAcl(
        %Param,
        CustomerUserID => $Param{CustomerUser},
        TypeID         => $Param{TypeID} || $Param{DefaultTypeID} || '',
        Action         => $Self->{Action},
        ReturnType     => 'Ticket',
        ReturnSubType  => '-',
        Data           => {},
        UserID         => $Self->{UserID},
    );

    # update 'Shown' for $Self->{DynamicField}
    $Self->_GetShownDynamicFields();

# ---
# ITSMIncidentProblemManagement
# ---
    my @IndividualDynamicFields;
# ---

    # Dynamic fields
    # cycle through the activated Dynamic Fields for this screen
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

        # skip fields that HTML could not be retrieved
        next DYNAMICFIELD if !IsHashRefWithData(
            $Param{DynamicFieldHTML}->{ $DynamicFieldConfig->{Name} }
        );

        # get the html strings form $Param
        my $DynamicFieldHTML = $Param{DynamicFieldHTML}->{ $DynamicFieldConfig->{Name} };

# ---
# ITSMIncidentProblemManagement
# ---
        # remember dynamic fields that should be displayed individually
        if ( $DynamicFieldConfig->{Name} eq 'ITSMImpact' ) {
            push @IndividualDynamicFields, $DynamicFieldConfig;
            next DYNAMICFIELD;
        }
# ---

        if ( !$DynamicFieldConfig->{Shown} ) {
            my $DynamicFieldName = $DynamicFieldConfig->{Name};

            $LayoutObject->AddJSOnDocumentComplete( Code => <<"END");
Core.Form.Validate.DisableValidation(\$('.Row_DynamicField_$DynamicFieldName'));
\$('.Row_DynamicField_$DynamicFieldName').addClass('Hidden');
END
        }

        $LayoutObject->Block(
            Name => 'DynamicField',
            Data => {
                Name  => $DynamicFieldConfig->{Name},
                Label => $DynamicFieldHTML->{Label},
                Field => $DynamicFieldHTML->{Field},
            },
        );

        # example of dynamic fields order customization
        $LayoutObject->Block(
            Name => 'DynamicField_' . $DynamicFieldConfig->{Name},
            Data => {
                Name  => $DynamicFieldConfig->{Name},
                Label => $DynamicFieldHTML->{Label},
                Field => $DynamicFieldHTML->{Field},
            },
        );
    }
# ---
# ITSMIncidentProblemManagement
# ---
    # cycle trough dynamic fields that should be displayed individually
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @IndividualDynamicFields ) {

        # get the html strings form $Param
        my $DynamicFieldHTML = $Param{DynamicFieldHTML}->{ $DynamicFieldConfig->{Name} };

        # example of dynamic fields order customization
        $LayoutObject->Block(
            Name => 'DynamicField_' . $DynamicFieldConfig->{Name},
            Data => {
                Name  => $DynamicFieldConfig->{Name},
                Label => $DynamicFieldHTML->{Label},
                Field => $DynamicFieldHTML->{Field},
            },
        );
    }
# ---

    # show time accounting box
    if ( $ConfigObject->Get('Ticket::Frontend::AccountTime') ) {
        if ( $ConfigObject->Get('Ticket::Frontend::NeedAccountedTime') ) {
            $LayoutObject->Block(
                Name => 'TimeUnitsLabelMandatory',
                Data => \%Param,
            );
        }
        else {
            $LayoutObject->Block(
                Name => 'TimeUnitsLabel',
                Data => \%Param,
            );
        }
        $LayoutObject->Block(
            Name => 'TimeUnits',
            Data => \%Param,
        );
    }

    my $ShownOptionsBlock;
    # show address book if the module is registered and java script support is available
    if (
        $ConfigObject->Get('Frontend::Module')->{AgentBook}
        && $LayoutObject->{BrowserJavaScriptSupport}
    ) {

        # check if need to call Options block
        if ( !$ShownOptionsBlock ) {
            $LayoutObject->Block(
                Name => 'TicketOptions',
                Data => {
                    %Param,
                },
            );

            # set flag to "true" in order to prevent calling the Options block again
            $ShownOptionsBlock = 1;
        }

        $LayoutObject->Block(
            Name => 'AddressBook',
            Data => {
                %Param,
            },
        );
    }

    # show customer edit link
    my $OptionCustomer = $LayoutObject->Permission(
        Action => 'AdminCustomerUser',
        Type   => 'rw',
    );
    if ($OptionCustomer) {

        # check if need to call Options block
        if ( !$ShownOptionsBlock ) {
            $LayoutObject->Block(
                Name => 'TicketOptions',
                Data => {
                    %Param,
                },
            );

            # set flag to "true" in order to prevent calling the Options block again
            $ShownOptionsBlock = 1;
        }

        $LayoutObject->Block(
            Name => 'OptionCustomer',
            Data => {
                %Param,
            },
        );
    }
# ---
# ITSMIncidentProblemManagement
# ---
    # make sure to show the options block so that the "Link Ticket" option is shown
    # even if address book and OptionCustomer is turned off
    if ( !$ShownOptionsBlock ) {
        $LayoutObject->Block(
            Name => 'TicketOptions',
            Data => {
                %Param,
            },
        );

        # set flag to "true" in order to prevent calling the Options block again
        $ShownOptionsBlock = 1;
    }
# ---

    # show attachments
    ATTACHMENT:
    for my $Attachment ( @{ $Param{Attachments} } ) {
        if (
            $Attachment->{ContentID}
            && $LayoutObject->{BrowserRichText}
            && ( $Attachment->{ContentType} =~ /image/i )
            && ( $Attachment->{Disposition} eq 'inline' )
        ) {
            next ATTACHMENT;
        }
        $LayoutObject->Block(
            Name => 'Attachment',
            Data => $Attachment,
        );
    }

    # add rich text editor
    if ( $LayoutObject->{BrowserRichText} ) {

        # use height/width defined for this screen
        $Param{RichTextHeight} = $Config->{RichTextHeight} || 0;
        $Param{RichTextWidth}  = $Config->{RichTextWidth}  || 0;

        $LayoutObject->Block(
            Name => 'RichText',
            Data => \%Param,
        );
    }

    # show right header
    my $HeaderTitle = $ConfigObject->Get('Frontend::Module')->{ $Self->{ActionReal} }->{Description};
    $LayoutObject->Block(
        Name => 'MaskHeader',
        Data => {
            Text => $HeaderTitle,
        },
    );

    # get output back
    return $LayoutObject->Output(
        TemplateFile => 'AgentTicketEmail',
        Data         => {
            %Param,
            DefaultSet => $Self->{DefaultSet} || '',
        },
    );
}

sub _GetFieldsToUpdate {
    my ( $Self, %Param ) = @_;

    my @UpdatableFields;

    # set the fields that can be updateable via AJAXUpdate
    if ( !$Param{OnlyDynamicFields} ) {
        @UpdatableFields = qw(
            TypeID Dest NextStateID PriorityID ServiceID SLAID SignKeyID CryptKeyID To Cc Bcc
            StandardTemplateID
        );
    }

    # cycle through the activated Dynamic Fields for this screen
    DYNAMICFIELD:
    for my $DynamicFieldConfig ( @{ $Self->{DynamicField} } ) {
        next DYNAMICFIELD if !IsHashRefWithData($DynamicFieldConfig);

        my $IsACLReducible = $Kernel::OM->Get('Kernel::System::DynamicField::Backend')->HasBehavior(
            DynamicFieldConfig => $DynamicFieldConfig,
            Behavior           => 'IsACLReducible',
        );
        next DYNAMICFIELD if !$IsACLReducible;

        push @UpdatableFields, 'DynamicField_' . $DynamicFieldConfig->{Name};
    }

    return \@UpdatableFields;
}

sub _GetShownDynamicFields {
    my ( $Self, %Param ) = @_;

    # get ticket object
    my $TicketObject = $Kernel::OM->Get('Kernel::System::Ticket');

    # use only dynamic fields which passed the acl
    my %TicketAclFormData = $TicketObject->TicketAclFormData();

    # cycle through dynamic fields to get shown or hidden fields
    for my $DynamicField ( @{ $Self->{DynamicField} } ) {

        # if field was not configured initially set it as not visible
        if ( $Self->{NotShownDynamicFields}->{ $DynamicField->{Name} } ) {
            $DynamicField->{Shown} = 0;
        }
        else {

            # hide DynamicFields only if we have ACL's
            if (
                IsHashRefWithData( \%TicketAclFormData )
                && defined $TicketAclFormData{ $DynamicField->{Name} }
            ) {
                if ( $TicketAclFormData{ $DynamicField->{Name} } >= 1 ) {
                    $DynamicField->{Shown} = 1;
                }
                else {
                    $DynamicField->{Shown} = 0;
                }
            }

            # else show them by default
            else {
                $DynamicField->{Shown} = 1;
            }
        }
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
