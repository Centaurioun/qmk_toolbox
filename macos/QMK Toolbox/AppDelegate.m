#import "AppDelegate.h"

#import "HIDConsoleListener.h"
#import "LogTextView.h"
#import "MicrocontrollerSelector.h"
#import "QMKWindow.h"
#import "USBListener.h"

@interface AppDelegate () <HIDConsoleListenerDelegate, USBListenerDelegate>
@property (weak) IBOutlet QMKWindow *window;
@property IBOutlet LogTextView *logTextView;
@property IBOutlet NSMenuItem *clearMenuItem;
@property IBOutlet NSComboBox *filepathBox;
@property IBOutlet NSButton *openButton;
@property IBOutlet MicrocontrollerSelector *mcuBox;
@property IBOutlet NSButton *flashButton;
@property IBOutlet NSButton *resetButton;
@property IBOutlet NSButton *clearEEPROMButton;
@property IBOutlet NSComboBox *consoleListBox;

@property NSWindowController *keyTesterWindowController;

@property HIDConsoleListener *consoleListener;

@property HIDConsoleDevice *lastReportedDevice;

@property USBListener *usbListener;
@end

@implementation AppDelegate
#pragma mark App Delegate
- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    if ([[[filename pathExtension] lowercaseString] isEqualToString:@"hex"] || [[[filename pathExtension] lowercaseString] isEqualToString:@"bin"]) {
        [self setFilePath:[NSURL fileURLWithPath:filename]];
        return true;
    } else {
        return false;
    }
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification {
    NSAppleEventManager *appleEventManager = [NSAppleEventManager sharedAppleEventManager];
    [appleEventManager setEventHandler:self andSelector:@selector(handleGetURLEvent:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    [[self.logTextView menu] addItem:[NSMenuItem separatorItem]];
    [[self.logTextView menu] addItem:self.clearMenuItem];

    [self loadRecentDocuments];
    self.showAllDevices = [[NSUserDefaults standardUserDefaults] boolForKey:kShowAllDevices];

    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
    [self.logTextView logInfo:[NSString stringWithFormat:@"QMK Toolbox %@ (https://qmk.fm/toolbox)", version]];
    [self.logTextView logInfo:@"Supported bootloaders:"];
    [self.logTextView logInfo:@" - ARM DFU (APM32, Kiibohd, STM32, STM32duino) and RISC-V DFU (GD32V) via dfu-util (http://dfu-util.sourceforge.net/)"];
    [self.logTextView logInfo:@" - Atmel/LUFA/QMK DFU via dfu-programmer (http://dfu-programmer.github.io/)"];
    [self.logTextView logInfo:@" - Atmel SAM-BA (Massdrop) via Massdrop Loader (https://github.com/massdrop/mdloader)"];
    [self.logTextView logInfo:@" - BootloadHID (Atmel, PS2AVRGB) via bootloadHID (https://www.obdev.at/products/vusb/bootloadhid.html)"];
    [self.logTextView logInfo:@" - Caterina (Arduino, Pro Micro) via avrdude (http://nongnu.org/avrdude/)"];
    [self.logTextView logInfo:@" - HalfKay (Teensy, Ergodox EZ) via Teensy Loader (https://pjrc.com/teensy/loader_cli.html)"];
    [self.logTextView logInfo:@" - LUFA/QMK HID via hid_bootloader_cli (https://github.com/abcminiuser/lufa)"];
    [self.logTextView logInfo:@" - WB32 DFU via wb32-dfu-updater_cli (https://github.com/WestberryTech/wb32-dfu-updater)"];
    [self.logTextView logInfo:@" - LUFA Mass Storage"];
    [self.logTextView logInfo:@"Supported ISP flashers:"];
    [self.logTextView logInfo:@" - AVRISP (Arduino ISP)"];
    [self.logTextView logInfo:@" - USBasp (AVR ISP)"];
    [self.logTextView logInfo:@" - USBTiny (AVR Pocket)"];

    self.usbListener = [[USBListener alloc] init];
    self.usbListener.delegate = self;
    [self.usbListener start];

    self.consoleListener = [[HIDConsoleListener alloc] init];
    self.consoleListener.delegate = self;
    [self.consoleListener start];
}

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)reply {
    [self setFilePath:[NSURL URLWithString:[[event paramDescriptorForKeyword:keyDirectObject] stringValue]]];
}

- (void)loadRecentDocuments {
    NSArray<NSURL *> *recentDocuments = [[NSDocumentController sharedDocumentController] recentDocumentURLs];
    for (NSURL *document in recentDocuments) {
        [self.filepathBox addItemWithObjectValue:document.path];
    }
    if (self.filepathBox.numberOfItems > 0) {
        [self.filepathBox selectItemAtIndex:0];
    }
}

- (IBAction)clearRecentDocuments:(id)sender {
    [[NSDocumentController sharedDocumentController] clearRecentDocuments:sender];
    [self.filepathBox removeAllItems];
    [self.filepathBox setStringValue:@""];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    [self.usbListener stop];
    [self.consoleListener stop];
}

#pragma mark HID Console
- (void)consoleDeviceDidConnect:(HIDConsoleDevice *)device {
    self.lastReportedDevice = device;
    [self updateConsoleList];
    [self.logTextView logHID:[NSString stringWithFormat:@"HID console connected: %@", device]];
}

- (void)consoleDeviceDidDisconnect:(HIDConsoleDevice *)device {
    self.lastReportedDevice = nil;
    [self updateConsoleList];
    [self.logTextView logHID:[NSString stringWithFormat:@"HID console disconnected: %@", device]];
}

- (void)consoleDevice:(HIDConsoleDevice *)device didReceiveReport:(NSString *)report {
    NSInteger selectedDevice = [self.consoleListBox indexOfSelectedItem];
    if (selectedDevice == 0 || self.consoleListener.devices[selectedDevice - 1] == device) {
        if (self.lastReportedDevice != device) {
            [self.logTextView logHID:[NSString stringWithFormat:@"%@ %@:", device.manufacturerString, device.productString]];
            self.lastReportedDevice = device;
        }
        [self.logTextView logHIDOutput:report];
    }
}

- (void)updateConsoleList {
    NSInteger selected = [self.consoleListBox indexOfSelectedItem] != -1 ? [self.consoleListBox indexOfSelectedItem] : 0;
    [self.consoleListBox deselectItemAtIndex:selected];
    [self.consoleListBox removeAllItems];

    for (HIDConsoleDevice *device in self.consoleListener.devices) {
        [self.consoleListBox addItemWithObjectValue:[device description]];
    }

    if ([self.consoleListBox numberOfItems] > 0) {
        [self.consoleListBox insertItemWithObjectValue:@"(All connected devices)" atIndex:0];
        [self.consoleListBox selectItemAtIndex:([self.consoleListBox numberOfItems] > selected) ? selected : 0];
    }
}

#pragma mark USB Devices & Bootloaders
- (void)bootloaderDeviceDidConnect:(BootloaderDevice *)device {
    [self.logTextView logBootloader:[NSString stringWithFormat:@"%@ device connected: %@", device.name, device]];

    if (self.autoFlashEnabled) {
        [self flashAll];
    } else {
        [self enableUI];
    }
}

- (void)bootloaderDeviceDidDisconnect:(BootloaderDevice *)device {
    [self.logTextView logBootloader:[NSString stringWithFormat:@"%@ device disconnected: %@", device.name, device]];

    if (!self.autoFlashEnabled) {
        [self enableUI];
    }
}

-(void)bootloaderDevice:(BootloaderDevice *)device didReceiveCommandOutput:(NSString *)data messageType:(MessageType)type {
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self.logTextView log:data withType:type];
    });
}

- (void)usbDeviceDidConnect:(USBDevice *)device {
    if (self.showAllDevices) {
        [self.logTextView logUSB:[NSString stringWithFormat:@"USB device connected: %@", device]];
    }
}

- (void)usbDeviceDidDisconnect:(USBDevice *)device {
    if (self.showAllDevices) {
        [self.logTextView logUSB:[NSString stringWithFormat:@"USB device disconnected: %@", device]];
    }
}

#pragma mark UI Interaction
@synthesize autoFlashEnabled = _autoFlashEnabled;

- (BOOL)autoFlashEnabled {
    return _autoFlashEnabled;
}

- (void)setAutoFlashEnabled:(BOOL)autoFlashEnabled {
    _autoFlashEnabled = autoFlashEnabled;
    if (autoFlashEnabled) {
        [self.logTextView logInfo:@"Auto-flash enabled"];
        [self disableUI];
    } else {
        [self.logTextView logInfo:@"Auto-flash disabled"];
        [self enableUI];
    }
}

@synthesize showAllDevices = _showAllDevices;

- (BOOL)showAllDevices {
    return _showAllDevices;
}

- (void)setShowAllDevices:(BOOL)showAllDevices {
    _showAllDevices = showAllDevices;
    [[NSUserDefaults standardUserDefaults] setBool:showAllDevices forKey:kShowAllDevices];
}

- (void)flashAll {
    NSString *file = [self.filepathBox stringValue];

    if ([file length] > 0) {
        if ([self.mcuBox indexOfSelectedItem] >= 0) {
            NSString *mcu = [self.mcuBox keyForSelectedItem];

            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                dispatch_sync(dispatch_get_main_queue(), ^{
                    if (!self.autoFlashEnabled) {
                        [self disableUI];
                    }

                    [self.logTextView logBootloader:@"Attempting to flash, please don't remove device"];
                });

                for (BootloaderDevice *b in [self findBootloaders]) {
                    [b flashWithMCU:mcu file:file];
                }

                dispatch_sync(dispatch_get_main_queue(), ^{
                    [self.logTextView logBootloader:@"Flash complete"];

                    if (!self.autoFlashEnabled) {
                        [self enableUI];
                    }
                });
            });
        } else {
            [self.logTextView logError:@"Please select a microcontroller"];
        }
    } else {
        [self.logTextView logError:@"Please select a file"];
    }
}

- (void)resetAll {
    if ([self.mcuBox indexOfSelectedItem] >= 0) {
        NSString *mcu = [self.mcuBox keyForSelectedItem];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            dispatch_sync(dispatch_get_main_queue(), ^{
                if (!self.autoFlashEnabled) {
                    [self disableUI];
                }
            });

            for (BootloaderDevice *b in [self findBootloaders]) {
                if ([b resettable]) {
                    [b resetWithMCU:mcu];
                }
            }

            dispatch_sync(dispatch_get_main_queue(), ^{
                if (!self.autoFlashEnabled) {
                    [self enableUI];
                }
            });
        });
    } else {
        [self.logTextView logError:@"Please select a microcontroller"];
    }
}

- (void)clearEEPROMAll {
    if ([self.mcuBox indexOfSelectedItem] >= 0) {
        NSString *mcu = [self.mcuBox keyForSelectedItem];

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            dispatch_sync(dispatch_get_main_queue(), ^{
                if (!self.autoFlashEnabled) {
                    [self disableUI];
                }

                [self.logTextView logBootloader:@"Attempting to clear EEPROM, please don't remove device"];
            });

            for (BootloaderDevice *b in [self findBootloaders]) {
                if ([b eepromFlashable]) {
                    [b flashEEPROMWithMCU:mcu file:@"reset.eep"];
                }
            }

            dispatch_sync(dispatch_get_main_queue(), ^{
                [self.logTextView logBootloader:@"EEPROM clear complete"];

                if (!self.autoFlashEnabled) {
                    [self enableUI];
                }
            });
        });
    } else {
        [self.logTextView logError:@"Please select a microcontroller"];
    }
}

- (void)setHandednessAll:(BOOL)left {
    if ([self.mcuBox indexOfSelectedItem] >= 0) {
        NSString *mcu = [self.mcuBox keyForSelectedItem];
        NSString *file = left ? @"reset_left.eep" : @"reset_right.eep";

        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            dispatch_sync(dispatch_get_main_queue(), ^{
                if (!self.autoFlashEnabled) {
                    [self disableUI];
                }

                [self.logTextView logBootloader:@"Attempting to set handedness, please don't remove device"];
            });

            for (BootloaderDevice *b in [self findBootloaders]) {
                if ([b eepromFlashable]) {
                    [b flashEEPROMWithMCU:mcu file:file];
                }
            }

            dispatch_sync(dispatch_get_main_queue(), ^{
                [self.logTextView logBootloader:@"EEPROM write complete"];

                if (!self.autoFlashEnabled) {
                    [self enableUI];
                }
            });
        });
    } else {
        [self.logTextView logError:@"Please select a microcontroller"];
    }
}

- (IBAction)flashButtonClick:(id)sender {
    [self flashAll];
}

- (IBAction)resetButtonClick:(id)sender {
    [self resetAll];
}

- (IBAction)clearEEPROMButtonClick:(id)sender {
    [self clearEEPROMAll];
}

- (IBAction)setHandednessButtonClick:(id)sender {
    [self setHandednessAll:[sender tag] == 0];
}

-(NSMutableArray<BootloaderDevice *> *)findBootloaders {
    NSMutableArray<BootloaderDevice *> *bootloaders = [[NSMutableArray alloc] init];

    for (USBDevice *d in self.usbListener.devices) {
        if ([d isKindOfClass:[BootloaderDevice class]]) {
            [bootloaders addObject:(BootloaderDevice *)d];
        }
    }

    return bootloaders;
}

- (IBAction)openButtonClick:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:NO];
    [panel setMessage:@"Select firmware to load"];
    NSArray *types = @[@"bin", @"hex"];
    [panel setAllowedFileTypes:types];

    [panel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSModalResponseOK) {
            [self setFilePath:[[panel URLs] objectAtIndex:0]];
        }
    }];
}

- (IBAction)updateFilePath:(id)sender {
    if (![[self.filepathBox objectValue] isEqualToString:@""])
        [self setFilePath:[NSURL URLWithString:[self.filepathBox objectValue]]];
}

- (void)setFilePath:(NSURL *)path {
    if ([path.scheme isEqualToString:@"qmk"]) {
        NSURL *unwrappedUrl = [NSURL URLWithString:[path.absoluteString substringFromIndex:[path.absoluteString hasPrefix:@"qmk://"] ? 6 : 4]];
        [self downloadFile:unwrappedUrl];
    } else {
        [self loadLocalFile:path.path];
    }
}

-(void)loadLocalFile:(NSString *)path {
    if ([self.filepathBox indexOfItemWithObjectValue:path] == NSNotFound) {
        [self.filepathBox addItemWithObjectValue:path];
    }
    [self.filepathBox selectItemWithObjectValue:path];
    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[[NSURL alloc] initFileURLWithPath:path]];
}

-(void)downloadFile:(NSURL *)url {
    NSURL *downloadsUrl = [[NSFileManager defaultManager] URLForDirectory:NSDownloadsDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:NO error:nil];
    NSURL *destFileUrl = [downloadsUrl URLByAppendingPathComponent:url.lastPathComponent];
    [self.logTextView logInfo:[NSString stringWithFormat:@"Downloading the file: %@", url.absoluteString]];

    NSError *error;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&error];
    if (error) {
        [self.logTextView logError:[NSString stringWithFormat:@"Could not download file: %@", [error localizedDescription]]];
    }

    [data writeToURL:destFileUrl atomically:YES];
    [self.logTextView logInfo:[NSString stringWithFormat:@"File saved to: %@", destFileUrl.path]];
    [self loadLocalFile:destFileUrl.path];
}

- (void)enableUI {
    NSArray<BootloaderDevice *> *bootloaders = [self findBootloaders];
    self.canFlash = [bootloaders count] > 0;
    self.canReset = NO;
    self.canClearEEPROM = NO;
    for (BootloaderDevice *b in bootloaders) {
        if (b.resettable) {
            self.canReset = YES;
            break;
        }
    }
    for (BootloaderDevice *b in bootloaders) {
        if (b.eepromFlashable) {
            self.canClearEEPROM = YES;
            break;
        }
    }
}

- (void)disableUI {
    self.canFlash = NO;
    self.canReset = NO;
    self.canClearEEPROM = NO;
}

- (IBAction)keyTesterButtonClick:(id)sender {
    if (!self.keyTesterWindowController) {
        self.keyTesterWindowController = [[NSWindowController alloc] initWithWindowNibName:@"KeyTesterWindow"];
    }
    [self.keyTesterWindowController showWindow:self];
}

#pragma mark Uncategorized
- (IBAction)clearButtonClick:(id)sender {
    [self.logTextView setString:@""];
}
@end
