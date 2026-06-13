#pragma once
#include <cstdint>
#include <filesystem>
#include <functional>
#include <map>
#include <optional>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include <nlohmann/json.hpp>

// Port of scripts/graph_token.py: OAuth token lifecycle for Microsoft Graph
// access (1psa bootstrap, JWT expiry, refresh-token exchange, shared cache).
namespace mailcartcore
{
  inline constexpr const char *kTokenEndpoint = "https://login.microsoftonline.com/common/oauth2/v2.0/token";
  inline constexpr long long kRefreshBufferSeconds = 300;

  // Minimal HTTP response surface shared by the token and Graph transports.
  struct HttpResponse
  { int status = 0;
    std::string body;
    bool transport_ok = false;
    std::string transport_error;
  };

  // #R005: Raised when a valid Graph access token cannot be obtained.
  class GraphTokenError : public std::runtime_error
  { public:
    using std::runtime_error::runtime_error;
  };

  // #R005: Accept tokens with or without a leading `Bearer ` prefix (also strip stray surrounding quotes).
  [[nodiscard]] std::string NormalizeToken(const std::string &token);

  // #R030: Decode JWT exp claims into epoch timestamps, returning nullopt for malformed tokens.
  [[nodiscard]] std::optional<long long> JwtExpiresAt(const std::string &access_token);

  // #R032: Resolve and normalize Graph credential fields from the 1psa CLI; throws GraphTokenError.
  [[nodiscard]] std::string ReadPsaField(const std::string &item, const std::string &field);

  struct TokenSession
  { std::string access_token;
    std::string refresh_token;
    long long expires_at = 0;
    std::string client_id;

    // #R034: Treat sessions as valid only when access token is present beyond refresh buffer.
    [[nodiscard]] bool IsValid(long long buffer_seconds = kRefreshBufferSeconds) const;
    // #R036: Serialize token session fields into cache payload objects.
    [[nodiscard]] nlohmann::json ToJson() const;
    // #R036: Deserialize token session objects with normalization/coercion.
    [[nodiscard]] static TokenSession FromJson(const nlohmann::json &payload);
  };

  using FormPoster = std::function<HttpResponse(const std::string &url,
                                                const std::vector<std::pair<std::string, std::string>> &form)>;
  using PsaReader = std::function<std::string(const std::string &item, const std::string &field)>;

  // #R028: Default OAuth session cache path shared with the ObjC++ bridge.
  [[nodiscard]] std::filesystem::path DefaultTokenCachePath();

  class GraphTokenManager
  { public:
    // #R038: Initialize token manager with configurable cache path and injectable transports.
    explicit GraphTokenManager(std::filesystem::path cache_path = DefaultTokenCachePath(),
                               FormPoster form_poster = nullptr,
                               PsaReader psa_reader = nullptr);

    // #R038: Invalidate in-memory token session state.
    void Invalidate();
    // #R040: Report token health metadata from current cache/session state.
    [[nodiscard]] std::map<std::string, std::string> TokenStatus();
    // #R042: Load a valid session from memory, cache, bootstrap, or refresh fallback.
    [[nodiscard]] TokenSession Load();
    // #R044: Return a valid access token, forcing refresh when loaded session is expired.
    [[nodiscard]] std::string GetAccessToken();
    // #R026: Refresh expired Graph access tokens using a stored refresh token via the Microsoft token endpoint.
    TokenSession Refresh(bool force = false, const std::optional<TokenSession> &session = std::nullopt);
    // #R028: Persist refreshed OAuth session data atomically to the shared local cache file with 0600 permissions.
    void Persist(const std::optional<TokenSession> &session = std::nullopt);

    [[nodiscard]] const std::filesystem::path &cachePath() const;

    private:
    [[nodiscard]] std::string ClientId() const;
    [[nodiscard]] std::optional<TokenSession> ReadCache() const;
    [[nodiscard]] TokenSession BootstrapSession(const std::optional<TokenSession> &cached) const;
    [[nodiscard]] std::string PsaItem() const;
    [[nodiscard]] std::string PsaAccessField() const;
    [[nodiscard]] std::string PsaRefreshField() const;
    [[nodiscard]] std::string PsaClientIdField() const;
    [[nodiscard]] std::string AccessTokenFromPsa() const;
    [[nodiscard]] std::string RefreshTokenFromPsa() const;

    std::filesystem::path cache_path_;
    FormPoster form_poster_;
    PsaReader psa_reader_;
    std::optional<TokenSession> session_;
  };
} // namespace mailcartcore
