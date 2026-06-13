#pragma once
#include <map>
#include <optional>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "mailcartcore/graph.hpp"

// Port of the endpoint layer of scripts/matchy_mailcart_api.py: write-token
// auth, scoped search, single-message fetch, and move-to-folder, plus a
// request-level dispatcher that mirrors FastAPI routing and error envelopes
// so the HTTPS server and the oracle harness share one code path.
namespace mailcartcore
{
  inline constexpr const char *kApiHost = "127.0.0.1";
  inline constexpr int kApiPort = 8788;

  // #R620: Resolve the caller-facing write-token header name (env-overridable).
  [[nodiscard]] std::string WriteTokenHeaderName();
  // #R620: Normalize configured/caller write tokens by trimming and stripping optional Bearer prefixes.
  [[nodiscard]] std::string NormalizedWriteToken(const std::optional<std::string> &token_value);
  // #R620: Resolve the configured caller write-token from supported environment keys.
  [[nodiscard]] std::string ConfiguredWriteToken();
  // #R620: Validate caller-provided write-token using constant-time comparison.
  [[nodiscard]] bool IsValidWriteToken(const std::optional<std::string> &provided_token);

  // Carries FastAPI/pydantic-style 422 validation error payloads.
  class ApiValidationError : public std::exception
  { public:
    explicit ApiValidationError(nlohmann::json errors)
      : errors_(std::move(errors))
    {
    }

    [[nodiscard]] const nlohmann::json &errors() const
    { return errors_;
    }

    [[nodiscard]] const char *what() const noexcept override
    { return "request validation failed";
    }

    private:
    nlohmann::json errors_;
  };

  class MailcartApi
  { public:
    explicit MailcartApi(GraphClient &graph);

    // #R029: Expose token metadata only to authenticated callers on the health endpoint.
    [[nodiscard]] nlohmann::json Health(const std::optional<std::string> &provided_token);
    // #R020: Return recent messages for empty query; otherwise apply scoped filtering with caller limit.
    [[nodiscard]] nlohmann::json SearchMessages(const std::string &query, int limit);
    // #R035: Return a single message with subject, sender, recipients, body, and preview metadata.
    [[nodiscard]] nlohmann::json GetMessage(const std::string &message_id);
    // #R025: Move selected message into requested destination folder.
    [[nodiscard]] nlohmann::json MoveMessage(const std::string &message_id, const std::string &folder_name);
    // #R620: Require caller-facing write-token auth for all message API routes (throws ApiError 503/401).
    void RequireApiWriteToken(const std::optional<std::string> &provided_token,
                              const std::optional<std::string> &authorization_header) const;

    private:
    GraphClient &graph_;
  };

  struct ApiRequest
  { std::string method;
    std::string path; // URL-decoded path
    QueryParams query_params;
    std::map<std::string, std::string> headers; // lowercased header names
    std::string body;
    bool has_body = false;
  };

  struct ApiResult
  { int status = 200;
    nlohmann::json body;
    std::map<std::string, std::string> headers;
  };

  // FastAPI-equivalent request dispatch: routing, auth dependency, parameter
  // validation (422 envelopes), endpoint invocation, and error mapping.
  [[nodiscard]] ApiResult HandleApiRequest(MailcartApi &api, const ApiRequest &request);
} // namespace mailcartcore
