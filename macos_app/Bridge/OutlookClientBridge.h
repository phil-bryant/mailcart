#import <Foundation/Foundation.h>
#import "OutlookBridgeModels.h"

NS_ASSUME_NONNULL_BEGIN

// #R001: Expose Objective-C bridge operations for search and read.
// #R015: Bind client operations to gateway/parser-backed bridge behavior.
// #R040: Own and expose bridge lifecycle around C++ client dependencies.
@interface OutlookClientBridge : NSObject

// #R020: Support case-insensitive query behavior through search entrypoint.
// #R025: Accept bounded/non-negative limit semantics for search.
// #R030: Return summary-field-oriented search payloads.
// #R045: Return Objective-C DTO summaries for Swift UI consumption.
- (OutlookSearchResultDTO *)searchMailcartsWithQuery:(NSString *)query
                                            limit:(NSInteger)limit
                                           cursor:(NSString *)cursor;

// #R005: Return immutable DTO model instances.
// #R010: Normalize Foundation/C++ string bridging on read path.
// #R035: Resolve message reads by id with unknown-id fallback behavior.
- (OutlookMailcartDTO *)readMailcartWithMessageId:(NSString *)messageId;

- (BOOL)openAttachmentWithMessageId:(NSString *)messageId
                        attachmentId:(NSString *)attachmentId
                          fileName:(NSString *)fileName;

- (BOOL)moveMessageToFolderWithMessageId:(NSString *)messageId
                              folderName:(NSString *)folderName;

@end

NS_ASSUME_NONNULL_END
