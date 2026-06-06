#import <Foundation/Foundation.h>
#include <string>

namespace mailcart_bridge
{
  // #R015: Resolve Graph token from shared cache or runtime environment for live fetches.
  NSString *ResolveGraphToken();

  // #R015: Refresh cached Graph credentials when a live request reports HTTP 401.
  BOOL AttemptRefreshGraphToken();

  // Shared synchronous transport primitives reused by GET and POST Graph flows.
  NSString *TruncatedResponseBodyText(NSData *response_data);
  NSData *PerformRequestSynchronously(NSURLRequest *request, NSHTTPURLResponse **http_response, NSError **request_error);

  // Authenticated Graph GET helpers (binary or JSON accept) with single 401 refresh+retry.
  NSData *FetchGraphGetData(NSURL *url, NSString *token, BOOL binary_accept, NSString **error_text);
  NSString *FetchGraphGet(NSString *url_text);

  // Normalize a Graph attachment file name into a safe single path component.
  NSString *NormalizedAttachmentFileName(NSString *name);

  // #R020: Apply case-insensitive subject/preview search matching.
  // #R025: Enforce non-negative and capped search limits.
  // #R030: Return summary-only payload fields in search responses.
  std::string BuildGraphSearchPayload(const std::string &query, int limit);

  // Build a single Graph message payload (with attachments) for the read path.
  std::string BuildGraphMessagePayload(const std::string &message_id);
} // namespace mailcart_bridge
