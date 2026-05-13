#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// #R050: Keep Bridge DTO declarations aligned with blocking clang-tidy policy ownership in OutlookClientBridge helpers.
// #R005: Define immutable Objective-C DTO model contracts.
// #R030: Provide summary-only DTO shape for search results.
@interface OutlookMailcartSummaryDTO : NSObject

@property(nonatomic, copy, readonly) NSString *messageId;
@property(nonatomic, copy, readonly) NSString *subject;
@property(nonatomic, copy, readonly) NSString *preview;
@property(nonatomic, copy, readonly) NSString *receivedAt;

// #R045: Support bridge-to-UI DTO conversion through designated initializer.
- (instancetype)initWithMessageId:(NSString *)messageId
                          subject:(NSString *)subject
                          preview:(NSString *)preview
                       receivedAt:(NSString *)receivedAt NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface OutlookSearchResultDTO : NSObject

@property(nonatomic, copy, readonly) NSArray<OutlookMailcartSummaryDTO *> *summaries;
@property(nonatomic, copy, readonly) NSString *nextCursor;
@property(nonatomic, copy, readonly) NSString *errorMessage;

- (instancetype)initWithSummaries:(NSArray<OutlookMailcartSummaryDTO *> *)summaries
                       nextCursor:(NSString *)nextCursor
                     errorMessage:(NSString *)errorMessage NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

@interface OutlookAttachmentDTO : NSObject

@property(nonatomic, copy, readonly) NSString *attachmentId;
@property(nonatomic, copy, readonly) NSString *fileName;
@property(nonatomic, copy, readonly) NSString *contentType;
@property(nonatomic, assign, readonly) NSInteger sizeInBytes;

- (instancetype)initWithAttachmentId:(NSString *)attachmentId
                            fileName:(NSString *)fileName
                         contentType:(NSString *)contentType
                         sizeInBytes:(NSInteger)sizeInBytes NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

// #R001: Define bridge-visible full-mailcart DTO contract.
// #R035: Include read-by-id fields required for unknown-id fallback payloads.
@interface OutlookMailcartDTO : NSObject

@property(nonatomic, copy, readonly) NSString *messageId;
@property(nonatomic, copy, readonly) NSString *sender;
@property(nonatomic, copy, readonly) NSString *recipient;
@property(nonatomic, copy, readonly) NSString *subject;
@property(nonatomic, copy, readonly) NSString *receivedAt;
@property(nonatomic, copy, readonly) NSString *body;
@property(nonatomic, copy, readonly) NSString *bodyText;
@property(nonatomic, copy, readonly) NSString *bodyHtml;
@property(nonatomic, copy, readonly) NSArray<OutlookAttachmentDTO *> *attachments;

// #R010: Preserve normalized string transport between bridge layers.
// #R015: Keep deterministic fixture field surface for parser-backed payloads.
// #R020: Carry case-insensitive search-matched fields into UI layer.
// #R025: Carry limit-trimmed payload records into DTOs.
// #R040: Align with bridge-owned client lifecycle object model.
- (instancetype)initWithMessageId:(NSString *)messageId
                           sender:(NSString *)sender
                        recipient:(NSString *)recipient
                          subject:(NSString *)subject
                       receivedAt:(NSString *)receivedAt
                             body:(NSString *)body
                         bodyText:(NSString *)bodyText
                         bodyHtml:(NSString *)bodyHtml
                      attachments:(NSArray<OutlookAttachmentDTO *> *)attachments NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
