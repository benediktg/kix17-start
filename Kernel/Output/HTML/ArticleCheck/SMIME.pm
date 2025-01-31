# --
# Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
# based on the original work of:
# Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file LICENSE for license information (AGPL). If you
# did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Output::HTML::ArticleCheck::SMIME;

use strict;
use warnings;

use MIME::Parser;
use Kernel::System::EmailParser;
use Kernel::Language qw(Translatable);

our @ObjectDependencies = (
    'Kernel::Config',
    'Kernel::System::Crypt::SMIME',
    'Kernel::System::Log',
    'Kernel::System::Ticket',
);

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get needed params
    for my $Needed (qw(UserID ArticleID)) {
        if ( $Param{$Needed} ) {
            $Self->{$Needed} = $Param{$Needed};
        }
        else {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Priority => 'error',
                Message  => "Need $Needed!"
            );
        }
    }

    return $Self;
}

sub Check {
    my ( $Self, %Param ) = @_;

    my %SignCheck;
    my @Return;

    # get config object
    my $ConfigObject = $Param{ConfigObject} || $Kernel::OM->Get('Kernel::Config');

    # check if smime is enabled
    return if !$ConfigObject->Get('SMIME');

    # check if article is an email
    return if $Param{Article}->{ArticleType} !~ /email/i;

    # get configuration
    my $StoreDecryptedData   = $ConfigObject->Get('SMIME::StoreDecryptedData');
    my $ProcessUntrustedData = $ConfigObject->Get('SMIME::ProcessUntrustedData');

    # get needed objects
    my $SMIMEObject  = $Kernel::OM->Get('Kernel::System::Crypt::SMIME');
    my $TicketObject = $Param{TicketObject} || $Kernel::OM->Get('Kernel::System::Ticket');

    # check inline smime
    if ( $Param{Article}->{Body} =~ /^-----BEGIN PKCS7-----/ ) {
        %SignCheck = $SMIMEObject->Verify( Message => $Param{Article}->{Body} );
        if (%SignCheck) {

            # remember to result
            $Self->{Result} = \%SignCheck;
        }
        else {

            # return with error
            push(
                @Return,
                {
                    Key   => Translatable('Signed'),
                    Value => Translatable('"S/MIME SIGNED MESSAGE" header found, but invalid!'),
                }
            );
        }
    }

    # check smime
    else {

        # get email from fs
        my $Message = $TicketObject->ArticlePlain(
            ArticleID => $Self->{ArticleID},
            UserID    => $Self->{UserID},
        );
        return if !$Message;

        my @Email = ();
        my @Lines = split( /\n/, $Message );
        for my $Line (@Lines) {
            push( @Email, $Line . "\n" );
        }

        my $ParserObject = Kernel::System::EmailParser->new(
            Email => \@Email,
        );

        my $Parser = MIME::Parser->new();
        $Parser->decode_headers(0);
        $Parser->extract_nested_messages(0);
        $Parser->output_to_core("ALL");
        my $Entity = $Parser->parse_data($Message);
        my $Head   = $Entity->head();
        $Head->unfold();
        $Head->combine('Content-Type');
        my $ContentType = $Head->get('Content-Type');

        if (
            $ContentType
            && $ContentType =~ /application\/(x-pkcs7|pkcs7)-mime/i
            && $ContentType !~ /signed/i
        ) {

            # check if article is already decrypted
            if ( $Param{Article}->{Body} ne '- no text message => see attachment -' ) {
                push(
                    @Return,
                    {
                        Key        => Translatable('Crypted'),
                        Value      => Translatable('Ticket decrypted before'),
                        Successful => 1,
                    }
                );
            }

            # check sender (don't decrypt sent emails)
            if ( $Param{Article}->{SenderType} =~ /(agent|system)/i ) {

                # return info
                return (
                    {
                        Key        => Translatable('Crypted'),
                        Value      => Translatable('Sent message crypted to recipient!'),
                        Successful => 1,
                    }
                );
            }

            # get all email addresses on article
            my %EmailsToSearch;
            for my $Email (qw(Resent-To Envelope-To To Cc Delivered-To X-Original-To)) {

                my @EmailAddressOnField = $ParserObject->SplitAddressLine(
                    Line => $ParserObject->GetParam( WHAT => $Email ),
                );

                # filter email addresses avoiding repeated and save on hash to search
                for my $EmailAddress (@EmailAddressOnField) {
                    my $CleanEmailAddress = $ParserObject->GetEmailAddress(
                        Email => $EmailAddress,
                    );
                    $EmailsToSearch{$CleanEmailAddress} = '1';
                }
            }

            # look for private keys for every email address
            # extract every resulting cert and put it into an hash of hashes avoiding repeated
            my %PrivateKeys;
            for my $EmailAddress ( sort keys %EmailsToSearch ) {
                my @PrivateKeysResult = $SMIMEObject->PrivateSearch(
                    Search => $EmailAddress,
                );
                for my $Cert (@PrivateKeysResult) {
                    $PrivateKeys{ $Cert->{Filename} } = $Cert;
                }
            }

            # search private cert to decrypt email
            if ( !%PrivateKeys ) {
                push(
                    @Return,
                    {
                        Key   => Translatable('Crypted'),
                        Value => Translatable('Impossible to decrypt: private key for email was not found!'),
                    }
                );
                return @Return;
            }

            my %Decrypt;
            PRIVATESEARCH:
            for my $CertResult ( values %PrivateKeys ) {

                # decrypt
                %Decrypt = $SMIMEObject->Decrypt(
                    Message            => $Message,
                    SearchingNeededKey => 1,
                    %{$CertResult},
                );
                last PRIVATESEARCH if ( $Decrypt{Successful} );
            }

            # ok, decryption went fine
            if ( $Decrypt{Successful} ) {

                push(
                    @Return,
                    {
                        Key   => Translatable('Crypted'),
                        Value => $Decrypt{Message} || Translatable('Successful decryption'),
                        %Decrypt,
                    }
                );

                # store decrypted data
                my $EmailContent = $Decrypt{Data};

                # now check if the data contains a signature too
                %SignCheck = $SMIMEObject->Verify(
                    Message => $Decrypt{Data},
                );

                if ( $SignCheck{SignatureFound} ) {

                    # If the signature was verified well, use the stripped content to store the email.
                    #   Now it contains only the email without other SMIME generated data.
                    if ( $SignCheck{Successful} && $SignCheck{Content} ) {
                        $EmailContent = $SignCheck{Content};
                    }
                    # check if email without other SMIME generated data should be stored
                    elsif ( $ProcessUntrustedData ) {
                        # check message again without verify
                        my %NoVerifySignCheck = $SMIMEObject->Verify(
                            Message  => $Decrypt{Data},
                            NoVerify => 1
                        );

                        # If the signature was verified well, use the stripped content to store the email
                        if ( $NoVerifySignCheck{Successful} && $NoVerifySignCheck{Content} ) {
                            $EmailContent = $NoVerifySignCheck{Content};
                        }
                    }
                }

                # parse the decrypted email body
                my $CryptParserObject = Kernel::System::EmailParser->new(
                    Email => $EmailContent
                );
                my $Body = $CryptParserObject->GetMessageBody();

                # from RFC 3850
                # 3.  Using Distinguished Names for Internet Mail
                #
                #   End-entity certificates MAY contain ...
                #
                #    ...
                #
                #   Sending agents SHOULD make the address in the From or Sender header
                #   in a mail message match an Internet mail address in the signer's
                #   certificate.  Receiving agents MUST check that the address in the
                #   From or Sender header of a mail message matches an Internet mail
                #   address, if present, in the signer's certificate, if mail addresses
                #   are present in the certificate.  A receiving agent SHOULD provide
                #   some explicit alternate processing of the message if this comparison
                #   fails, which may be to display a message that shows the recipient the
                #   addresses in the certificate or other certificate details.

                # as described in bug#5098 and RFC 3850 an alternate mail handling should be
                # made if sender and signer addresses does not match

                # get original sender from email
                my @OrigEmail = map {"$_\n"} split( /\n/, $Message );
                my $ParserObjectOrig = Kernel::System::EmailParser->new(
                    Email => \@OrigEmail,
                );

                if ( $SignCheck{SignatureFound} ) {
                    my $OrigFrom   = $ParserObjectOrig->GetParam( WHAT => 'From' ) || '';
                    my $OrigSender = $ParserObjectOrig->GetEmailAddress( Email => $OrigFrom ) || '';

                    # compare sender email to signer email
                    my $SignerSenderMatch = 0;
                    SIGNER:
                    for my $Signer ( @{ $SignCheck{Signers} } ) {
                        if ( $OrigSender =~ m{\A \Q$Signer\E \z}xmsi ) {
                            $SignerSenderMatch = 1;
                            last SIGNER;
                        }
                    }

                    # sender email does not match signing certificate!
                    if ( !$SignerSenderMatch ) {
                        $SignCheck{Successful} = 0;
                        $SignCheck{Message} =~ s/successful/failed!/;
                        $SignCheck{Message} .= " (signed by "
                            . join( ' | ', @{ $SignCheck{Signers} } )
                            . ")"
                            . ", but sender address $OrigSender: does not match certificate address!";
                    }
                }

                if ($StoreDecryptedData) {

                    # updated article body
                    $TicketObject->ArticleUpdate(
                        TicketID  => $Param{Article}->{TicketID},
                        ArticleID => $Self->{ArticleID},
                        Key       => 'Body',
                        Value     => $Body,
                        UserID    => $Self->{UserID},
                    );

                    # delete crypted attachments
                    $TicketObject->ArticleDeleteAttachment(
                        ArticleID => $Self->{ArticleID},
                        UserID    => $Self->{UserID},
                    );

                    # write attachments to the storage
                    for my $Attachment ( $CryptParserObject->GetAttachments() ) {
                        $TicketObject->ArticleWriteAttachment(
                            %{$Attachment},
                            ArticleID => $Self->{ArticleID},
                            UserID    => $Self->{UserID},
                        );
                    }
                }
            }
            else {
                push(
                    @Return,
                    {
                        Key   => Translatable('Crypted'),
                        Value => "$Decrypt{Message}",
                        %Decrypt,
                    }
                );
            }
        }

        elsif (
            $ContentType
            && $ContentType =~ /application\/(x-pkcs7|pkcs7)/i
            && $ContentType =~ /signed/i
        ) {

            # init mail content
            my $EmailContent = $Message;

            # check sign and get clear content
            %SignCheck = $SMIMEObject->Verify(
                Message => $Message,
            );

            # check for signature
            if ( %SignCheck ) {

                # If the signature was verified well, use the stripped content to store the email.
                #   Now it contains only the email without other SMIME generated data.
                if ( $SignCheck{Successful} && $SignCheck{Content} ) {
                    $EmailContent = $SignCheck{Content};
                }
                # check if email without other SMIME generated data should be stored
                elsif ( $ProcessUntrustedData ) {
                    # check message again without verify
                    my %NoVerifySignCheck = $SMIMEObject->Verify(
                        Message  => $Message,
                        NoVerify => 1
                    );

                    # If the signature was verified well, use the stripped content to store the email
                    if ( $NoVerifySignCheck{Successful} && $NoVerifySignCheck{Content} ) {
                        $EmailContent = $NoVerifySignCheck{Content};
                    }
                }

                my @SignEmail = ();
                my @SignLines = split( /\n/, $EmailContent );
                for (@SignLines) {
                    push( @SignEmail, $_ . "\n" );
                }
                my $SignParserObject = Kernel::System::EmailParser->new(
                    Email => \@SignEmail,
                );
                my $Body = $SignParserObject->GetMessageBody();

                # from RFC 3850
                # 3.  Using Distinguished Names for Internet Mail
                #
                #   End-entity certi$SignParserObjectficates MAY contain ...
                #
                #    ...
                #
                #   Sending agents SHOULD make the address in the From or Sender header
                #   in a mail message match an Internet mail address in the signer's
                #   certificate.  Receiving agents MUST check that the address in the
                #   From or Sender header of a mail message matches an Internet mail
                #   address, if present, in the signer's certificate, if mail addresses
                #   are present in the certificate.  A receiving agent SHOULD provide
                #   some explicit alternate processing of the message if this comparison
                #   fails, which may be to display a message that shows the recipient the
                #   addresses in the certificate or other certificate details.

                # as described in bug#5098 and RFC 3850 an alternate mail handling should be
                # made if sender and signer addresses does not match

                # get original sender from email
                my @OrigEmail = map {"$_\n"} split( /\n/, $Message );
                my $ParserObjectOrig = Kernel::System::EmailParser->new(
                    Email => \@OrigEmail,
                );

                if ( $SignCheck{SignatureFound} ) {
                    my $OrigFrom   = $ParserObjectOrig->GetParam( WHAT => 'From' ) || '';
                    my $OrigSender = $ParserObjectOrig->GetEmailAddress( Email => $OrigFrom ) || '';

                    # compare sender email to signer email
                    my $SignerSenderMatch = 0;
                    SIGNER:
                    for my $Signer ( @{ $SignCheck{Signers} } ) {
                        if ( $OrigSender =~ m{\A \Q$Signer\E \z}xmsi ) {
                            $SignerSenderMatch = 1;
                            last SIGNER;
                        }
                    }

                    # sender email does not match signing certificate!
                    if ( !$SignerSenderMatch ) {
                        $SignCheck{Successful} = 0;
                        $SignCheck{Message} =~ s/successful/failed!/;
                        $SignCheck{Message} .= " (signed by "
                            . join( ' | ', @{ $SignCheck{Signers} } )
                            . ")"
                            . ", but sender address $OrigSender: does not match certificate address!";
                    }
                }

                if ($StoreDecryptedData) {

                    # updated article body
                    $TicketObject->ArticleUpdate(
                        TicketID  => $Param{Article}->{TicketID},
                        ArticleID => $Self->{ArticleID},
                        Key       => 'Body',
                        Value     => $Body,
                        UserID    => $Self->{UserID},
                    );

                    # delete crypted attachments
                    $TicketObject->ArticleDeleteAttachment(
                        ArticleID => $Self->{ArticleID},
                        UserID    => $Self->{UserID},
                    );

                    # write attachments to the storage
                    for my $Attachment ( $SignParserObject->GetAttachments() ) {
                        $TicketObject->ArticleWriteAttachment(
                            %{$Attachment},
                            ArticleID => $Self->{ArticleID},
                            UserID    => $Self->{UserID},
                        );
                    }
                }
            }
        }
    }

    if ( %SignCheck ) {
        push(
            @Return,
            {
                Key   => Translatable('Signed'),
                Value => $SignCheck{Message},
                %SignCheck,
            }
        );
    }

    return @Return;
}

sub Filter {
    my ( $Self, %Param ) = @_;

    # remove signature if one is found
    if ( $Self->{Result}->{SignatureFound} ) {

        # remove SMIME begin signed message
        $Param{Article}->{Body} =~ s/^-----BEGIN\sPKCS7-----.+?Hash:\s.+?$//sm;

        # remove SMIME inline sign
        $Param{Article}->{Body} =~ s/^-----END\sPKCS7-----//sm;
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
