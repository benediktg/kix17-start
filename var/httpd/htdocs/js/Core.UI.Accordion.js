// --
// Modified version of the work: Copyright (C) 2006-2022 c.a.p.e. IT GmbH, https://www.cape-it.de
// based on the original work of:
// Copyright (C) 2001-2022 OTRS AG, https://otrs.com/
// --
// This software comes with ABSOLUTELY NO WARRANTY. For details, see
// the enclosed file LICENSE for license information (AGPL). If you
// did not receive this file, see https://www.gnu.org/licenses/agpl.txt.
// --

"use strict";

var Core = Core || {};
Core.UI = Core.UI || {};

/**
 * @namespace Core.UI.Accordion
 * @memberof Core.UI
 * @author OTRS AG
 * @description
 *      This namespace contains the Accordion code.
 */
Core.UI.Accordion = (function (TargetNS) {
    /**
     * @private
     * @name AccordionAnimationRunning
     * @memberof Core.UI.Accordion
     * @member {Boolean}
     * @description
     *      Indicates if an accordion animation is still running.
     */
    var AccordionAnimationRunning = false;

    /**
     * @name AnimationIsRunning
     * @memberof Core.UI.Accordion
     * @function
     * @returns {Boolean} True, if animation is still running, false otherwise.
     * @description
     *      This function checks, if an accordion animation is currently running.
     */
    TargetNS.AnimationIsRunning = function () {
        return AccordionAnimationRunning;
    };

    /**
     * @name StartAnimation
     * @memberof Core.UI.Accordion
     * @function
     * @description
     *      This function indicates that an accordion animation is now running.
     */
    TargetNS.StartAnimation = function () {
        AccordionAnimationRunning = true;
    };

    /**
     * @name StopAnimation
     * @memberof Core.UI.Accordion
     * @function
     * @description
     *      This function indicates that all accordion animations have stopped now.
     */
    TargetNS.StopAnimation = function () {
        AccordionAnimationRunning = false;
    };

    /**
     * @name ContentSelector
     * @memberof Core.UI.Accordion
     * @member {String}
     * @description
     *      The selector for the content, which is shown or hidden.
     */
    TargetNS.ContentSelector = undefined;

    /**
     * @name Init
     * @memberof Core.UI.Accordion
     * @function
     * @returns {Boolean} Returns false on error.
     * @param {jQueryObject} $Element - The parent list element (ul) for the accordion.
     * @param {String} LinkSelector - The selector for the link, on which an element is opened/closed.
     * @param {String} ContentSelector - The selector for the content, which is shown or hidden.
     * @description
     *      This function initializes the accordion effect on the specified list.
     */
    // KIX4OTRS-capeIT
    //TargetNS.Init = function ($Element, LinkSelector, ContentSelector) {
    TargetNS.Init = function ($Element, LinkSelector, ContentSelector, ToggleSpeed) {
    // EO KIX4OTRS-capeIT

        var $LinkSelectors = $Element.find(LinkSelector);

        // If no accordion element is found, stop
        if (!isJQueryObject($Element) || $Element.length === 0) {
            return false;
        }

        // KIX4OTRS-capeIT
        if (ToggleSpeed == null) ToggleSpeed = "slow";
        // EO KIX4OTRS-capeIT

        // Stop, if no link selector is found
        if ($LinkSelectors.length === 0) {
            return false;
        }

        TargetNS.ContentSelector = ContentSelector;

        // Bind click function to link selector elements
        $LinkSelectors.click(function () {
            var $ListElement = $(this).closest('li');

            TargetNS.OpenElement($ListElement, true);

            // always return false, because otherwise the url in the clicked link would be loaded
            return false;
        });
    };

    /**
     * @name OpenElement
     * @memberof Core.UI.Accordion
     * @function
     * @returns {Boolean} Returns false on error.
     * @param {jQueryObject} $ListElement
     * @param {Boolean} WithAnimation
     * @description
     *      Open a single accordion element.
     */
    TargetNS.OpenElement = function ($ListElement, WithAnimation) {
        var $AllListElements,
            $ActiveListElement;

        // if clicked element is already active, do nothing
        if ($ListElement.hasClass('Active')) {
            return false;
        }

        // if another accordion animation is currently running, do nothing
        if (TargetNS.AnimationIsRunning()) {
            return false;
        }

        $AllListElements = $ListElement.parent('ul').find('li');
        $ActiveListElement = $AllListElements.filter('.Active');

        if (WithAnimation) {
            TargetNS.StartAnimation();

            $AllListElements.find('div.Content div').css('overflow', 'hidden');

            $AllListElements.find('div.Content div').each(function () {
                $(this).data('overflow', $(this).css('overflow'));
                $(this).css('overflow', 'hidden');
            });

            $ActiveListElement.find(TargetNS.ContentSelector).add($ListElement.find(TargetNS.ContentSelector)).slideToggle("slow", function () {
                $AllListElements.find('div.Content div').each(function () {
                    $(this).css('overflow', $(this).data('overflow'));
                });
                $ListElement.addClass('Active');
                $ActiveListElement.removeClass('Active');
                TargetNS.StopAnimation();
            });
        }
        else {
            $ActiveListElement.find(TargetNS.ContentSelector).add($ListElement.find(TargetNS.ContentSelector)).toggle();
            $ListElement.addClass('Active');
            $ActiveListElement.removeClass('Active');
        }
    };

    return TargetNS;
}(Core.UI.Accordion || {}));
