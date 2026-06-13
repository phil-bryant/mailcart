#pragma once
#include <functional>
#include <optional>
#include <string>
#include <utility>
#include <vector>

#include <nlohmann/json.hpp>

#include "mailcartcore/token.hpp"

// Port of the Graph request pipeline from scripts/matchy_mailcart_api.py:
// authenticated request/retry, pagination trust checks, and id encoding.
namespace mailcartcore
{
  inline constexpr const char *kGraphBase = "https://graph.microsoft.com/v1.0";

  using QueryParams = std::vector<std::pair<std::string, std::string>>;

  // One Graph call expressed before URL encoding so test/oracle transports can
  // match on structured paths and params instead of serialized URLs.
  struct GraphRequestArgs
  { std::string method;
    std::string path; // relative to kGraphBase, e.g. "/me/messages"
    QueryParams params;
    std::optional<nlohmann::json> payload;
  };

  using GraphTransport =
      std::function<HttpResponse(const GraphRequestArgs &args,
                                 const std::vector<std::pair<std::string, std::string>> &headers)>;

  // #R600: Classify Graph responses as auth failures (HTTP 401 or known invalid-token bodies) to gate retry/refresh.
  [[nodiscard]] bool IsAuthFailure(int status_code, const std::string &body);

  // #R035: Normalize message ids and encode them as safe single Graph path segments.
  [[nodiscard]] std::string GraphMessagePath(const std::string &message_id);

  // #R035: Validate message ids before Graph calls to fail closed on malformed inputs (throws ApiError 404).
  [[nodiscard]] std::string ValidatedGraphMessageId(const std::string &message_id);

  // Percent-decode (urllib.parse.unquote): leaves '+' untouched.
  [[nodiscard]] std::string UrlUnquote(const std::string &value);

  // Percent-encode one path segment (urllib.parse.quote with safe="").
  [[nodiscard]] std::string QuotePathSegment(const std::string &value);

  // parse_qsl(query, keep_blank_values=True) equivalent.
  [[nodiscard]] QueryParams ParseQueryString(const std::string &query);

  class GraphClient
  { public:
    // #R027: Wire the shared token manager and an injectable transport (live HTTPS by default).
    explicit GraphClient(GraphTokenManager &token_manager, GraphTransport transport = nullptr);

    // #R027: Retry the Graph request once after a 401 by invalidating + force-refreshing the cached token.
    [[nodiscard]] nlohmann::json Request(const std::string &method, const std::string &path,
                                         const QueryParams &params = {},
                                         const std::optional<nlohmann::json> &payload = std::nullopt);
    // #R027: Issue Graph GET requests through the shared authenticated request/retry pipeline.
    [[nodiscard]] nlohmann::json Get(const std::string &path, const QueryParams &params = {});
    // #R605: Issue authenticated Graph POST requests via the shared retry-aware pipeline.
    [[nodiscard]] nlohmann::json Post(const std::string &path, const nlohmann::json &payload);
    // #R020: Follow Graph @odata.nextLink pagination only when host and base path are trusted.
    [[nodiscard]] nlohmann::json GetNextLink(const std::string &next_link);
    // #R025: Resolve destination mail folder by name, creating it when absent.
    [[nodiscard]] std::string GetOrCreateFolderId(const std::string &folder_name);

    [[nodiscard]] GraphTokenManager &tokenManager();

    private:
    // #R010: Build Graph request headers with auth and JSON content negotiation (throws ApiError 500 when token missing).
    [[nodiscard]] std::vector<std::pair<std::string, std::string>> Headers();

    GraphTokenManager &token_manager_;
    GraphTransport transport_;
  };
} // namespace mailcartcore
