//
//  UITests.m
//  UITests
//
//  Created by Theodore Dubois on 11/13/20.
//

#import <XCTest/XCTest.h>

@interface UITests : XCTestCase
@end

@implementation UITests

- (void)setUp {
    self.continueAfterFailure = NO;
}

- (void)testCodexPadDemoWorkspaceAndTerminalRecovery {
    XCUIApplication *app = [[XCUIApplication alloc] init];
    app.launchArguments = @[@"--codexpad-demo"];
    [app launch];

    XCUIElement *workspace = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.workspace"];
    XCTAssertTrue([workspace waitForExistenceWithTimeout:15]);
    XCTAssertTrue([app.staticTexts[@"Make the repository update-safe"] exists]);
    XCTAssertTrue([app.buttons[@"codexpad.new-thread"] exists]);
    XCTAssertTrue([app.buttons[@"codexpad.terminal"] exists]);

    XCUIElement *composer = [app descendantsMatchingType:XCUIElementTypeAny][@"codexpad.composer"];
    XCTAssertTrue([composer exists]);
    XCTAssertTrue([composer isHittable]);

    [app.buttons[@"codexpad.terminal"] tap];
    XCUIElement *returnButton = app.buttons[@"codexpad.return-to-workspace"];
    XCTAssertTrue([returnButton waitForExistenceWithTimeout:5]);
    [returnButton tap];
    XCTAssertTrue([workspace waitForExistenceWithTimeout:5]);

    XCTAttachment *screenshot = [XCTAttachment attachmentWithScreenshot:XCUIScreen.mainScreen.screenshot];
    screenshot.name = @"CodexPad demo workspace";
    screenshot.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:screenshot];
}

@end
