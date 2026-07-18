//
//  UITests.m
//  UITests
//
//  Created by Theodore Dubois on 11/13/20.
//

#import <XCTest/XCTest.h>

@interface UITests : XCTestCase
- (void)exerciseCodexPadExpandedWorkspace:(BOOL)expandedWorkspace;
- (XCUIElement *)hittableButtonWithIdentifier:(NSString *)identifier
                                inApplication:(XCUIApplication *)app;
- (XCUIElement *)hittableButtonWithLabelContaining:(NSString *)fragment
                                      inApplication:(XCUIApplication *)app;
@end

@implementation UITests

- (void)setUp {
    self.continueAfterFailure = NO;
}

- (void)testCodexPadStandardWorkspaceAndTerminalRecovery {
    [self exerciseCodexPadExpandedWorkspace:YES];
}

- (void)testCodexPadAccessibilityWorkspaceAndTerminalRecovery {
    [self exerciseCodexPadExpandedWorkspace:NO];
}

- (void)testCodexPadDesktopModeCompleteSurfaceAndFocus {
    XCUIApplication *app = [[XCUIApplication alloc] init];
    app.launchArguments = @[@"--codexpad-demo", @"--codexpad-desktop-mode"];
    [app launch];

    XCUIElement *workspace = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.workspace"];
    XCTAssertTrue([workspace waitForExistenceWithTimeout:15]);
    XCTAssertTrue([app.keyboards.firstMatch waitForNonExistenceWithTimeout:5]);
    XCTAssertTrue([app.buttons[@"codexpad.model-picker"] exists]);
    XCTAssertTrue([app.buttons[@"codexpad.reasoning-picker"] exists]);
    XCTAssertTrue([app.buttons[@"codexpad.collaboration-picker"] exists]);

    XCUIElement *composer = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.composer"];
    XCTAssertTrue(composer.isHittable);
    [composer tap];
    [composer typeText:@"Keep desktop focus"];
    XCTAssertTrue(composer.hasFocus);

    XCUIElement *send = app.buttons[@"codexpad.send"];
    XCTAssertTrue(send.isHittable);
    [send tap];
    NSPredicate *focused = [NSPredicate predicateWithFormat:@"hasFocus == YES"];
    [self expectationForPredicate:focused evaluatedWithObject:composer handler:nil];
    [self waitForExpectationsWithTimeout:5 handler:nil];

    XCUIElement *features = [self hittableButtonWithIdentifier:@"codexpad.features"
                                                 inApplication:app];
    XCTAssertNotNil(features);
    [features tap];
    XCUIElement *featureCenter = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.feature-center"];
    XCTAssertTrue([featureCenter waitForExistenceWithTimeout:5]);
    XCUIElement *featureSummary = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.feature-summary"];
    XCTAssertTrue([featureSummary waitForExistenceWithTimeout:5]);
    XCTAssertTrue([featureSummary.label containsString:@"125 compatible operations"]);
    XCTAssertTrue([featureSummary.label containsString:@"3 explicit platform exceptions"]);
    XCUIElement *featureDone = [self hittableButtonWithLabelContaining:@"Done"
                                                          inApplication:app];
    XCTAssertNotNil(featureDone);
    [featureDone tap];
    XCTAssertTrue([featureCenter waitForNonExistenceWithTimeout:5]);
    [self expectationForPredicate:focused evaluatedWithObject:composer handler:nil];
    [self waitForExpectationsWithTimeout:5 handler:nil];

    XCUIElement *terminal = [self hittableButtonWithIdentifier:@"codexpad.terminal"
                                                 inApplication:app];
    XCTAssertNotNil(terminal);
    [terminal tap];
    XCUIElement *returnButton = app.buttons[@"codexpad.return-to-workspace"];
    XCTAssertTrue([returnButton waitForExistenceWithTimeout:5]);
    [returnButton tap];
    XCTAssertTrue([workspace waitForExistenceWithTimeout:5]);
    [self expectationForPredicate:focused evaluatedWithObject:composer handler:nil];
    [self waitForExpectationsWithTimeout:5 handler:nil];

    XCTAttachment *screenshot = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
    screenshot.name = @"CodexPad 13-inch desktop mode";
    screenshot.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:screenshot];
}

- (void)exerciseCodexPadExpandedWorkspace:(BOOL)expandedWorkspace {
    XCUIApplication *app = [[XCUIApplication alloc] init];
    app.launchArguments = @[@"--codexpad-demo"];
    [app launch];

    XCUIElement *workspace = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.workspace"];
    XCTAssertTrue([workspace waitForExistenceWithTimeout:15]);
    XCTAssertTrue([app.keyboards.firstMatch waitForNonExistenceWithTimeout:5]);

    XCUIElement *workbench = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.workbench"];
    if (expandedWorkspace) {
        // Touch mode starts with the optional inspector hidden in portrait,
        // but the complete workbench remains one tap away.
        XCTAssertTrue([workbench waitForNonExistenceWithTimeout:5]);
        XCUIElement *workbenchToggle = app.buttons[@"codexpad.toggle-workbench"];
        XCTAssertTrue(workbenchToggle.isHittable);
        [workbenchToggle tap];
        XCTAssertTrue([workbench waitForExistenceWithTimeout:5]);
        [workbenchToggle tap];
        XCTAssertTrue([workbench waitForNonExistenceWithTimeout:5]);
    } else {
        XCTAssertTrue([workbench waitForNonExistenceWithTimeout:5]);
    }

    XCUIElement *sidebar = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.sidebar"];
    if (!expandedWorkspace) {
        XCTAssertTrue([sidebar waitForNonExistenceWithTimeout:5]);
    }

    XCTAssertTrue([app.staticTexts[@"Make the repository update-safe"] exists]);
    XCTAssertTrue([app.buttons[@"codexpad.new-thread"] exists]);
    XCTAssertTrue([app.buttons[@"codexpad.terminal"] exists]);
    XCTAssertTrue([app.buttons[@"codexpad.model-picker"] exists]);
    XCTAssertFalse([app.buttons[@"codexpad.features"] exists]);

    XCUIElement *composer = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.composer"];
    XCTAssertTrue([composer exists]);
    XCTAssertTrue([composer isHittable]);

    if (expandedWorkspace) {
        XCUIElement *settings = [self hittableButtonWithIdentifier:@"codexpad.settings"
                                                     inApplication:app];
        BOOL openedSettingsFromSidebar = NO;
        if (settings == nil) {
            // At 11-inch portrait widths, NavigationSplitView correctly
            // collapses its sidebar. Exercise the visible system sidebar
            // control before opening the bottom-pinned account settings. SwiftUI
            // does not publish that row as a stable XCUIElement in this compact
            // presentation, so let the system overlay animation settle, tap
            // the row's verified compact-screen position, and assert the
            // resulting Settings destination instead.
            XCUIElement *sidebarToggle = [self hittableButtonWithLabelContaining:@"sidebar"
                                                                    inApplication:app];
            XCTAssertNotNil(sidebarToggle);
            [sidebarToggle tap];
            [NSThread sleepForTimeInterval:0.8];
            [[app coordinateWithNormalizedOffset:CGVectorMake(0.20, 0.96)] tap];
            openedSettingsFromSidebar = YES;
        } else {
            [settings tap];
        }
        XCTAssertTrue(openedSettingsFromSidebar || settings != nil);
        XCTAssertTrue([app.navigationBars[@"Settings"] waitForExistenceWithTimeout:5]);

        XCUIElement *showAll = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.touch-show-all"];
        XCTAssertTrue(showAll.isHittable);
        // SwiftUI exposes the full Form row as the switch's accessibility
        // frame. A center tap lands on the explanatory row rather than the
        // trailing switch on iPad, so exercise the visible control itself.
        [[showAll coordinateWithNormalizedOffset:CGVectorMake(0.94, 0.5)] tap];
        NSPredicate *switchIsOn = [NSPredicate predicateWithFormat:@"value == '1'"];
        [self expectationForPredicate:switchIsOn evaluatedWithObject:showAll handler:nil];
        [self waitForExpectationsWithTimeout:5 handler:nil];

        XCUIElement *folderButton = app.buttons[@"Choose folder in Files"];
        XCUIElement *settingsScroller = app.collectionViews.firstMatch.exists
            ? app.collectionViews.firstMatch
            : app.tables.firstMatch;
        for (NSUInteger attempt = 0; attempt < 5 && !folderButton.isHittable; attempt++) {
            [settingsScroller swipeUp];
        }
        XCTAssertTrue(folderButton.isHittable);
        [folderButton tap];
        XCTAssertTrue([app.buttons[@"Unlink Files folder"] waitForExistenceWithTimeout:5]);

        XCUIElement *openFeatureCenter = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.open-feature-center"];
        for (NSUInteger attempt = 0; attempt < 5 && !openFeatureCenter.isHittable; attempt++) {
            [settingsScroller swipeUp];
        }
        XCTAssertTrue(openFeatureCenter.isHittable);
        [openFeatureCenter tap];
        XCUIElement *featureCenter = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.feature-center"];
        XCTAssertTrue([featureCenter waitForExistenceWithTimeout:5]);
        XCUIElement *featureSummary = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.feature-summary"];
        XCTAssertTrue([featureSummary waitForExistenceWithTimeout:5]);
        XCTAssertTrue([featureSummary.label containsString:@"125 compatible operations"]);

        XCUIElement *startFeature = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.feature.thread/start"];
        XCTAssertTrue([startFeature waitForExistenceWithTimeout:5]);
        XCTAssertTrue(startFeature.isHittable);
        [startFeature tap];
        XCUIElement *featureRun = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.feature-run"];
        XCTAssertTrue([featureRun waitForExistenceWithTimeout:5]);
        XCUIElement *featureScroller = app.scrollViews.firstMatch;
        for (NSUInteger attempt = 0; attempt < 4 && !featureRun.isHittable; attempt++) {
            [featureScroller swipeUp];
        }
        XCTAssertTrue(featureRun.isHittable);

        XCUIElement *featureDone = [self hittableButtonWithLabelContaining:@"Done"
                                                              inApplication:app];
        XCTAssertNotNil(featureDone);
        [featureDone tap];
        XCTAssertTrue([featureCenter waitForNonExistenceWithTimeout:5]);
    }

    XCUIElement *terminalButton;
    if (expandedWorkspace) {
        terminalButton = [self hittableButtonWithIdentifier:@"codexpad.terminal"
                                              inApplication:app];
        if (terminalButton == nil) {
            // The 11-inch compact presentation keeps the system sidebar open
            // after its Settings sheet closes. Dismiss that visible column
            // before exercising the conversation toolbar.
            XCUIElement *sidebarToggle = [self hittableButtonWithLabelContaining:@"sidebar"
                                                                    inApplication:app];
            XCTAssertNotNil(sidebarToggle);
            [sidebarToggle tap];
            terminalButton = [self hittableButtonWithIdentifier:@"codexpad.terminal"
                                                    inApplication:app];
        }
        XCTAssertNotNil(terminalButton);
    } else {
        // The single-column hierarchy has exactly one stable toolbar element;
        // querying it directly avoids XCTest's slow multi-match snapshot path.
        terminalButton = app.buttons[@"codexpad.terminal"];
        XCTAssertTrue(terminalButton.isHittable);
    }
    [terminalButton tap];
    XCUIElement *returnButton = app.buttons[@"codexpad.return-to-workspace"];
    if (![returnButton waitForExistenceWithTimeout:3]) {
        // Simulator accessibility services can occasionally acknowledge a
        // synthesized toolbar tap without delivering its action. Re-resolve
        // the still-visible control and require the real terminal transition.
        terminalButton = [self hittableButtonWithIdentifier:@"codexpad.terminal"
                                               inApplication:app];
        XCTAssertNotNil(terminalButton);
        [terminalButton tap];
    }
    XCTAssertTrue([returnButton waitForExistenceWithTimeout:5]);
    [returnButton tap];
    XCTAssertTrue([workspace waitForExistenceWithTimeout:5]);
    XCTAssertTrue([app.keyboards.firstMatch waitForNonExistenceWithTimeout:5]);
    XCTAssertTrue([workbench waitForNonExistenceWithTimeout:5]);
    if (!expandedWorkspace) {
        XCTAssertTrue([sidebar waitForNonExistenceWithTimeout:5]);
    }

    XCTAttachment *screenshot = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
    screenshot.name = expandedWorkspace ? @"CodexPad standard workspace" : @"CodexPad accessibility workspace";
    screenshot.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:screenshot];
}

- (XCUIElement *)hittableButtonWithIdentifier:(NSString *)identifier
                                inApplication:(XCUIApplication *)app {
    // SwiftUI can retain an offscreen copy of a detail toolbar item while an
    // inspector is presented. XCTest's keyed subscript selects that ghost
    // element first, even though the visible toolbar control is actionable.
    // Walk every match and exercise the same control a user can actually tap.
    XCUIElementQuery *matches = [app.buttons matchingIdentifier:identifier];
    for (NSUInteger index = 0; index < matches.count; index++) {
        XCUIElement *candidate = [matches elementBoundByIndex:index];
        if (candidate.isHittable) {
            return candidate;
        }
    }
    return nil;
}

- (XCUIElement *)hittableButtonWithLabelContaining:(NSString *)fragment
                                      inApplication:(XCUIApplication *)app {
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"label CONTAINS[c] %@", fragment];
    XCUIElementQuery *matches = [app.buttons matchingPredicate:predicate];
    for (NSUInteger index = 0; index < matches.count; index++) {
        XCUIElement *candidate = [matches elementBoundByIndex:index];
        if (candidate.isHittable) {
            return candidate;
        }
    }
    return nil;
}

@end
