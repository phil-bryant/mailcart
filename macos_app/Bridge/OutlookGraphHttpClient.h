#import <Foundation/Foundation.h>
#include <string>

namespace mailcart_bridge
{
  using GraphSynchronousTransport =
      NSData *(*)(NSURLRequest *request, NSHTTPURLResponse **http_response, NSError **request_error);
  using GraphRefreshHook = BOOL (*)();
  using GraphTokenResolverHook = NSString *(*)();

  // #R055: Install deterministic replay hooks for Graph transport/auth flows in integration tests.
  void InstallGraphTransportHook(GraphSynchronousTransport hook);
  void InstallGraphRefreshHook(GraphRefreshHook hook);
  void InstallGraphTokenResolverHook(GraphTokenResolverHook hook);
  void ResetGraphTestHooks();

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

  // #R035: Parse "__cursor__"-prefixed query markers into continuation cursors.
  // #R040: Normalize a Graph attachment file name into a safe single path component.
  NSString *NormalizedAttachmentFileName(NSString *name);

  // #R020: Apply case-insensitive subject/preview search matching.
  // #R025: Enforce non-negative and capped search limits.
  // #R030: Return summary-only payload fields in search responses.
  std::string BuildGraphSearchPayload(const std::string &query, int limit);

  // #R045: Build normalized attachment payload rows merged into message read results.
  // #R050: Build a deterministic single Graph message payload for read operations.
  std::string BuildGraphMessagePayload(const std::string &message_id);
} // namespace mailcart_bridge
