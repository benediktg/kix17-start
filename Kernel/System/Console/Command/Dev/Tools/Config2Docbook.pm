# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::System::Console::Command::Dev::Tools::Config2Docbook;

use strict;
use warnings;
use utf8;

use base qw(Kernel::System::Console::BaseCommand);

our @ObjectDependencies = (
    'Kernel::Language',
    'Kernel::System::SysConfig',
);

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Generate a config options reference chapter (docbook) for the administration manual.');
    $Self->AddOption(
        Name        => 'language',
        Description => "Which language to use.",
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );

    return;
}

sub Run {
    my ( $Self, %Param ) = @_;

    my $UserLanguage = $Self->GetOption('language');
    $Kernel::OM->ObjectParamAdd(
        'Kernel::Language' => {
            UserLanguage => $UserLanguage,
        },
    );
    my $LanguageObject = $Kernel::OM->Get('Kernel::Language');

    print <<'EOF';
<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE appendix PUBLIC "-//OASIS//DTD DocBook XML V4.4//EN"
    "http://www.oasis-open.org/docbook/xml/4.4/docbookx.dtd">

<!-- Note: this file is autogenerated by xml2docbook.pl -->

EOF

    my $AppendixTitle = $LanguageObject->Translate('Configuration Options Reference');
    print "<appendix id=\"ConfigReference\"><title>$AppendixTitle</title>\n";

    my $SysConfigObject = $Kernel::OM->Get('Kernel::System::SysConfig');
    my %List            = $SysConfigObject->ConfigGroupList();

    for my $Group ( sort { $a cmp $b } keys %List ) {
        my %SubList = $SysConfigObject->ConfigSubGroupList( Name => $Group );
        print "<section id=\"ConfigReference_$Group\"><title>$Group</title>\n";
        for my $SubGroup ( sort keys %SubList ) {
            print <<"EOF";
<variablelist id="ConfigReference_$Group:$SubGroup">
    <title>$Group → $SubGroup</title>
EOF
            my @List = $SysConfigObject->ConfigSubGroupConfigItemList(
                Group    => $Group,
                SubGroup => $SubGroup
            );
            for my $Name (@List) {
                my %Item = $SysConfigObject->ConfigItemGet( Name => $Name );
                my $Link = $Name;
                $Link =~ s/###/_/g;
                $Link =~ s/[ ]/_/g;
                $Link =~ s/\///g;

                print <<"EOF";
<varlistentry id="ConfigReference_$Group:$SubGroup:$Link">
    <term>$Name</term>
    <listitem>
EOF

                #Description
                my %HashLang;
                for my $Index ( 1 ... $#{ $Item{Description} } ) {
                    $Item{Description}[$Index]{Lang} ||= 'en';
                    $HashLang{ $Item{Description}[$Index]{Lang} } = $Item{Description}[$Index]{Content};
                }
                my $Description;

                # Description in User Language
                $Description = $HashLang{$UserLanguage} // $HashLang{'en'};

                $Description =~ s/&/&amp;/g;
                $Description =~ s/</&lt;/g;
                $Description =~ s/>/&gt;/g;
                print "<para>$Description</para>\n";
                my %ConfigItemDefault = $SysConfigObject->ConfigItemGet(
                    Name    => $Name,
                    Default => 1,
                );
                my $ReadOnly = defined $ConfigItemDefault{ReadOnly} ? $ConfigItemDefault{ReadOnly} : 0;
                my $Valid    = defined $ConfigItemDefault{Valid}    ? $ConfigItemDefault{Valid}    : 1;
                my $Required = defined $ConfigItemDefault{Required} ? $ConfigItemDefault{Required} : 0;
                my $Key      = $Name;
                $Key =~ s/\\/\\\\/g;
                $Key =~ s/'/\'/g;
                $Key =~ s/###/'}->{'/g;
                my $Config = " \$Self->{'$Key'} = "
                    . $SysConfigObject->_XML2Perl( Data => \%ConfigItemDefault );

                if ($ReadOnly) {
                    my $ReadOnlyText = $LanguageObject->Translate('This setting can not be changed.');
                    print "<para>$ReadOnlyText</para>\n";
                }
                elsif ( !$Valid ) {
                    my $InvalidText = $LanguageObject->Translate('This setting is not active by default.');
                    print "<para>$InvalidText</para>\n";
                }
                elsif ($Required) {
                    my $RequiredText = $LanguageObject->Translate('This setting can not be deactivated.');
                    print "<para>$RequiredText</para>\n";
                }

                my $DefaultValueText = $LanguageObject->Translate('Default value');
                print "<para>$DefaultValueText:<programlisting><![CDATA[$Config]]></programlisting></para>\n";
                print "</listitem></varlistentry>\n";
            }
            print "</variablelist>\n";
        }
        print "</section>\n";
    }
    print "</appendix>\n";

    return $Self->ExitCodeOk();
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
