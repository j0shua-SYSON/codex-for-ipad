//
//  UITests.m
//  UITests
//
//  Created by Theodore Dubois on 11/13/20.
//

#import <XCTest/XCTest.h>

@interface UITests : XCTestCase
- (void)exerciseCodexPadExpectingWorkbench:(BOOL)expectsWorkbench;
@end

@implementation UITests

- (void)setUp {
    self.continueAfterFailure = NO;
}

- (void)testCodexPadStandardWorkspaceAndTerminalRecovery {
    [self exerciseCodexPadExpectingWorkbench:YES];
}

- (void)testCodexPadAccessibilityWorkspaceAndTerminalRecovery {
    [self exerciseCodexPadExpectingWorkbench:NO];
}

- (void)exerciseCodexPadExpectingWorkbench:(BOOL)expectsWorkbench {
    XCUIApplication *app = [[XCUIApplication alloc] init];
    app.launchArguments = @[@"--codexpad-demo"];
    [app launch];

    XCUIElement *workspace = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.workspace"];
    XCTAssertTrue([workspace waitForExistenceWithTimeout:15]);
    XCTAssertTrue([app.keyboards.firstMatch waitForNonExistenceWithTimeout:5]);

    XCUIElement *workbench = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.workbench"];
    if (expectsWorkbench) {
        XCTAssertTrue([workbench waitForExistenceWithTimeout:5]);
    } else {
        XCTAssertTrue([workbench waitForNonExistenceWithTimeout:5]);
    }

    XCUIElement *sidebar = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.sidebar"];
    if (!expectsWorkbench) {
        XCTAssertTrue([sidebar waitForNonExistenceWithTimeout:5]);
    }

    XCTAssertTrue([app.staticTexts[@"Make the repository update-safe"] exists]);
    XCTAssertTrue([app.buttons[@"codexpad.new-thread"] exists]);
    XCTAssertTrue([app.buttons[@"codexpad.terminal"] exists]);

    XCUIElement *composer = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.composer"];
    XCTAssertTrue([composer exists]);
    XCTAssertTrue([composer isHittable]);

    XCUIElement *terminalButton = app.buttons[@"codexpad.terminal"];
    XCTAssertTrue([terminalButton isHittable]);
    [terminalButton tap];
    XCUIElement *returnButton = app.buttons[@"codexpad.return-to-workspace"];
    XCTAssertTrue([returnButton waitForExistenceWithTimeout:5]);
    [returnButton tap];
    XCTAssertTrue([workspace waitForExistenceWithTimeout:5]);
    XCTAssertTrue([app.keyboards.firstMatch waitForNonExistenceWithTimeout:5]);
    if (expectsWorkbench) {
        XCTAssertTrue([workbench waitForExistenceWithTimeout:5]);
    } else {
        XCTAssertTrue([workbench waitForNonExistenceWithTimeout:5]);
    }
    if (!expectsWorkbench) {
        XCTAssertTrue([sidebar waitForNonExistenceWithTimeout:5]);
    }

    XCTAttachment *screenshot = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
    screenshot.name = expectsWorkbench ? @"CodexPad standard workspace" : @"CodexPad accessibility workspace";
    screenshot.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:screenshot];
}

@end
