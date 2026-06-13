#include "mailcartcore/token.hpp"

#include <sys/stat.h>
#include <unistd.h>

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdlib>
#include <ctime>
#include <fstream>
#include <sstream>

#include "mailcartcore/subprocess.hpp"
#if defined(MAILCARTCORE_ENABLE_HTTP)
#include "mailcartcore/http_transport.hpp"
#endif

namespace mailcartcore
{
  namespace
  {
    constexpr const char *kStatusMissingRefreshToken = "missing_refresh_token";
    constexpr const char *kStatusMissing = "missing";
    constexpr const char *kStatusValid = "valid";
    constexpr const char *kStatusExpired = "expired";
    constexpr const char *kDefaultPsaItem = "OUTLOOK_GRAPH_API";
    constexpr const char *kDefaultPsaField = "token";
    constexpr const char *kDefaultPsaRefreshField = "refresh_token";
    constexpr const char *kDefaultPsaClientIdField = "application_client_id";
    constexpr const char *kRefreshScope =
        "openid profile offline_access https://graph.microsoft.com/Mail.Read "
        "https://graph.microsoft.com/Mail.ReadWrite";

    // #R005: Trim ASCII whitespace from both ends.
    std::string Strip(const std::string &value)
    { const auto begin = value.find_first_not_of(" \t\r\n\f\v");
      if (begin == std::string::npos)
      { return "";
      }
      const auto end = value.find_last_not_of(" \t\r\n\f\v");
      return value.substr(begin, end - begin + 1);
    }

    // #R052: Read a trimmed env var with a default fallback when unset/blank.
    std::string EnvOrDefault(const char *name, const std::string &fallback)
    { const char *raw = std::getenv(name);
      if (raw == nullptr)
      { return fallback;
      }
      std::string value = Strip(raw);
      return value.empty() ? fallback : value;
    }

    std::string EnvOrEmpty(const char *name)
    { const char *raw = std::getenv(name);
      return raw == nullptr ? "" : std::string(raw);
    }

    // #R030: Decode a base64url segment; returns nullopt on invalid characters.
    std::optional<std::string> Base64UrlDecode(std::string input)
    { const size_t padding = (4 - input.size() % 4) % 4;
      input.append(padding, '=');
      static constexpr const char *kAlphabet =
          "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
      std::array<int, 256> reverse{};
      reverse.fill(-1);
      for (int index = 0; index < 64; ++index)
      { reverse[static_cast<unsigned char>(kAlphabet[index])] = index;
      }
      std::string output;
      output.reserve(input.size() / 4 * 3);
      int accumulator = 0;
      int bits = 0;
      for (char symbol : input)
      { if (symbol == '=')
        { break;
        }
        const int value = reverse[static_cast<unsigned char>(symbol)];
        if (value < 0)
        { return std::nullopt;
        }
        accumulator = (accumulator << 6) | value;
        bits += 6;
        if (bits >= 8)
        { bits -= 8;
          output.push_back(static_cast<char>((accumulator >> bits) & 0xFF));
        }
      }
      return output;
    }

    long long NowEpoch()
    { return static_cast<long long>(std::time(nullptr));
    }

    // #R026: Default form poster uses the live HTTPS transport when built with HTTP.
    HttpResponse DefaultPostForm(const std::string &url,
                                 const std::vector<std::pair<std::string, std::string>> &form)
    {
#if defined(MAILCARTCORE_ENABLE_HTTP)
      return transport::PostForm(url, form);
#else
      (void)url;
      (void)form;
      HttpResponse response;
      response.transport_ok = false;
      response.transport_error = "HTTP transport disabled in this build";
      return response;
#endif
    }
  } // namespace

  // #R005: Accept tokens with or without a leading `Bearer ` prefix (also strip stray surrounding quotes).
  std::string NormalizeToken(const std::string &token)
  { std::string normalized = Strip(token);
    if (normalized.rfind("Bearer ", 0) == 0)
    { normalized = Strip(normalized.substr(7));
    }
    if (normalized.size() >= 2 && normalized.front() == '"' && normalized.back() == '"')
    { normalized = normalized.substr(1, normalized.size() - 2);
    }
    return normalized;
  }

  // #R030: Decode JWT exp claims into epoch timestamps, returning nullopt for malformed tokens.
  std::optional<long long> JwtExpiresAt(const std::string &access_token)
  { const auto first_dot = access_token.find('.');
    if (first_dot == std::string::npos)
    { return std::nullopt;
    }
    auto second_dot = access_token.find('.', first_dot + 1);
    if (second_dot == std::string::npos)
    { second_dot = access_token.size();
    }
    const std::string payload_segment = access_token.substr(first_dot + 1, second_dot - first_dot - 1);
    const auto decoded = Base64UrlDecode(payload_segment);
    if (!decoded.has_value())
    { return std::nullopt;
    }
    nlohmann::json data = nlohmann::json::parse(*decoded, nullptr, false);
    if (data.is_discarded() || !data.is_object() || !data.contains("exp"))
    { return std::nullopt;
    }
    const auto &exp = data["exp"];
    if (exp.is_number_integer())
    { return exp.get<long long>();
    }
    if (exp.is_number_float())
    { return static_cast<long long>(exp.get<double>());
    }
    if (exp.is_string())
    { try
      { return std::stoll(exp.get<std::string>());
      }
      catch (const std::exception &)
      { return std::nullopt;
      }
    }
    return std::nullopt;
  }

  // #R032: Resolve and normalize Graph credential fields from the 1psa CLI.
  std::string ReadPsaField(const std::string &item, const std::string &field)
  { const std::string psa_path = subprocess::Which("1psa");
    if (psa_path.empty())
    { throw GraphTokenError("1psa is required to resolve Outlook Graph credentials");
    }
    const auto completed = subprocess::Run({psa_path, "-f", item, field});
    if (!completed.launched || completed.exit_code != 0)
    { std::string detail = Strip(completed.stderr_text);
      if (detail.empty())
      { detail = "unknown 1psa error";
      }
      throw GraphTokenError("Unable to resolve 1psa field " + item + "/" + field + ": " + detail);
    }
    return NormalizeToken(completed.stdout_text);
  }

  // #R034: Treat sessions as valid only when access token is present beyond refresh buffer.
  bool TokenSession::IsValid(long long buffer_seconds) const
  { if (access_token.empty())
    { return false;
    }
    return expires_at > NowEpoch() + buffer_seconds;
  }

  // #R036: Serialize token session fields into cache payload objects.
  nlohmann::json TokenSession::ToJson() const
  { return nlohmann::json{
        {"access_token", access_token},
        {"refresh_token", refresh_token},
        {"expires_at", expires_at},
        {"client_id", client_id},
    };
  }

  // #R036: Deserialize token session objects with normalization/coercion.
  TokenSession TokenSession::FromJson(const nlohmann::json &payload)
  { TokenSession session;
    auto string_field = [&payload](const char *key) -> std::string
    { if (!payload.contains(key))
      { return "";
      }
      const auto &value = payload[key];
      if (value.is_string())
      { return value.get<std::string>();
      }
      if (value.is_null())
      { return "";
      }
      return value.dump();
    };
    session.access_token = NormalizeToken(string_field("access_token"));
    session.refresh_token = NormalizeToken(string_field("refresh_token"));
    session.client_id = Strip(string_field("client_id"));
    session.expires_at = 0;
    if (payload.contains("expires_at"))
    { const auto &expires = payload["expires_at"];
      if (expires.is_number_integer())
      { session.expires_at = expires.get<long long>();
      }
      else if (expires.is_number_float())
      { session.expires_at = static_cast<long long>(expires.get<double>());
      }
      else if (expires.is_string())
      { try
        { session.expires_at = std::stoll(expires.get<std::string>());
        }
        catch (const std::exception &)
        { session.expires_at = 0;
        }
      }
    }
    return session;
  }

  // #R028: Default OAuth session cache path shared with the ObjC++ bridge.
  std::filesystem::path DefaultTokenCachePath()
  { const char *home = std::getenv("HOME");
    std::filesystem::path base = home == nullptr ? std::filesystem::path(".") : std::filesystem::path(home);
    return base / ".cache" / "mailcart" / "graph_oauth.json";
  }

  GraphTokenManager::GraphTokenManager(std::filesystem::path cache_path, FormPoster form_poster, PsaReader psa_reader)
    : cache_path_(std::move(cache_path)),
      form_poster_(form_poster ? std::move(form_poster) : FormPoster(DefaultPostForm)),
      psa_reader_(psa_reader ? std::move(psa_reader) : PsaReader(ReadPsaField))
  {
  }

  // #R038: Invalidate in-memory token session state.
  void GraphTokenManager::Invalidate()
  { session_.reset();
  }

  const std::filesystem::path &GraphTokenManager::cachePath() const
  { return cache_path_;
  }

  // #R040: Report token health metadata from current cache/session state.
  std::map<std::string, std::string> GraphTokenManager::TokenStatus()
  { TokenSession session;
    try
    { session = Load();
    }
    catch (const GraphTokenError &exc)
    { std::string message = exc.what();
      std::string lowered = message;
      std::transform(lowered.begin(), lowered.end(), lowered.begin(),
                     [](unsigned char symbol) { return static_cast<char>(std::tolower(symbol)); });
      if (lowered.find("refresh") != std::string::npos)
      { return {{"token_status", kStatusMissingRefreshToken}, {"token_error", message}};
      }
      return {{"token_status", kStatusMissing}, {"token_error", message}};
    }
    if (session.IsValid())
    { return {{"token_status", kStatusValid}, {"token_expires_at", std::to_string(session.expires_at)}};
    }
    if (!session.refresh_token.empty())
    { return {{"token_status", kStatusExpired}, {"token_expires_at", std::to_string(session.expires_at)}};
    }
    return {{"token_status", kStatusMissingRefreshToken}};
  }

  // #R042: Load a valid session from memory, cache, bootstrap, or refresh fallback.
  TokenSession GraphTokenManager::Load()
  { if (session_.has_value() && session_->IsValid())
    { return *session_;
    }

    const auto cached = ReadCache();
    if (cached.has_value() && cached->IsValid())
    { session_ = cached;
      return *cached;
    }

    TokenSession bootstrapped = BootstrapSession(cached);
    if (bootstrapped.IsValid())
    { session_ = bootstrapped;
      Persist(bootstrapped);
      return bootstrapped;
    }

    if (!bootstrapped.refresh_token.empty())
    { TokenSession refreshed = Refresh(true, bootstrapped);
      session_ = refreshed;
      return refreshed;
    }

    throw GraphTokenError("OUTLOOK_GRAPH_TOKEN or refresh_token is required");
  }

  // #R044: Return a valid access token, forcing refresh when loaded session is expired.
  std::string GraphTokenManager::GetAccessToken()
  { TokenSession session = Load();
    if (session.IsValid())
    { return session.access_token;
    }
    if (!session.refresh_token.empty())
    { TokenSession refreshed = Refresh(true, session);
      return refreshed.access_token;
    }
    throw GraphTokenError("OUTLOOK_GRAPH_TOKEN is required");
  }

  // #R026: Refresh expired Graph access tokens using a stored refresh token via the Microsoft token endpoint.
  TokenSession GraphTokenManager::Refresh(bool force, const std::optional<TokenSession> &session)
  { TokenSession current;
    if (session.has_value())
    { current = *session;
    }
    else if (session_.has_value())
    { current = *session_;
    }
    else
    { const auto cached = ReadCache();
      current = cached.has_value() ? *cached : BootstrapSession(std::nullopt);
    }
    if (!force && current.IsValid())
    { session_ = current;
      return current;
    }
    if (current.refresh_token.empty())
    { throw GraphTokenError("refresh_token is required for automatic Graph token refresh");
    }
    std::string client_id = current.client_id.empty() ? ClientId() : current.client_id;
    if (client_id.empty())
    { throw GraphTokenError("OUTLOOK_GRAPH_CLIENT_ID is required for automatic Graph token refresh");
    }

    const HttpResponse response = form_poster_(
        kTokenEndpoint,
        {
            {"client_id", client_id},
            {"grant_type", "refresh_token"},
            {"refresh_token", current.refresh_token},
            {"scope", kRefreshScope},
        });
    if (!response.transport_ok)
    { throw GraphTokenError("Graph token refresh failed: " + response.transport_error);
    }
    if (response.status >= 400)
    { throw GraphTokenError("Graph token refresh failed: " + std::to_string(response.status) + " " +
                            response.body.substr(0, 200));
    }

    nlohmann::json payload = nlohmann::json::parse(response.body, nullptr, false);
    if (payload.is_discarded() || !payload.is_object())
    { throw GraphTokenError("Graph token refresh returned an invalid JSON payload");
    }
    const std::string access_token =
        NormalizeToken(payload.value("access_token", std::string()));
    if (access_token.empty())
    { throw GraphTokenError("Graph token refresh returned an empty access_token");
    }
    std::string refresh_token = NormalizeToken(payload.value("refresh_token", current.refresh_token));
    long long expires_in = 3600;
    if (payload.contains("expires_in"))
    { const auto &expires_value = payload["expires_in"];
      if (expires_value.is_number())
      { expires_in = expires_value.get<long long>();
      }
      else if (expires_value.is_string())
      { try
        { expires_in = std::stoll(expires_value.get<std::string>());
        }
        catch (const std::exception &)
        { expires_in = 3600;
        }
      }
      if (expires_in == 0)
      { expires_in = 3600;
      }
    }
    const auto jwt_expiry = JwtExpiresAt(access_token);
    const long long expires_at = jwt_expiry.has_value() ? *jwt_expiry : NowEpoch() + expires_in;

    TokenSession refreshed{access_token, refresh_token, expires_at, client_id};
    session_ = refreshed;
    Persist(refreshed);
    return refreshed;
  }

  // #R028: Persist refreshed OAuth session data atomically to the shared local cache file with 0600 permissions.
  void GraphTokenManager::Persist(const std::optional<TokenSession> &session)
  { std::optional<TokenSession> payload = session.has_value() ? session : session_;
    if (!payload.has_value())
    { return;
    }
    std::error_code ec;
    std::filesystem::create_directories(cache_path_.parent_path(), ec);
    const std::string serialized = payload->ToJson().dump(2) + "\n";
    std::string temp_template = (cache_path_.parent_path() / "graph_oauth.XXXXXX.tmp").string();
    std::vector<char> temp_buffer(temp_template.begin(), temp_template.end());
    temp_buffer.push_back('\0');
    const int fd = mkstemps(temp_buffer.data(), 4);
    if (fd < 0)
    { return;
    }
    const std::string temp_path(temp_buffer.data());
    bool wrote = true;
    size_t offset = 0;
    while (offset < serialized.size())
    { const ssize_t written = write(fd, serialized.data() + offset, serialized.size() - offset);
      if (written <= 0)
      { wrote = false;
        break;
      }
      offset += static_cast<size_t>(written);
    }
    close(fd);
    if (wrote && chmod(temp_path.c_str(), 0600) == 0 &&
        rename(temp_path.c_str(), cache_path_.c_str()) == 0)
    { return;
    }
    unlink(temp_path.c_str());
  }

  // #R032: Resolve Graph client id from env first, then 1Password fallback.
  std::string GraphTokenManager::ClientId() const
  { const std::string env_value = Strip(EnvOrEmpty("OUTLOOK_GRAPH_CLIENT_ID"));
    if (!env_value.empty())
    { return env_value;
    }
    try
    { return psa_reader_(PsaItem(), PsaClientIdField());
    }
    catch (const GraphTokenError &)
    { return "";
    }
  }

  // #R046: Read and validate cached OAuth session payloads from disk.
  std::optional<TokenSession> GraphTokenManager::ReadCache() const
  { std::error_code ec;
    if (!std::filesystem::exists(cache_path_, ec))
    { return std::nullopt;
    }
    std::ifstream stream(cache_path_);
    if (!stream.is_open())
    { return std::nullopt;
    }
    std::stringstream buffer;
    buffer << stream.rdbuf();
    nlohmann::json payload = nlohmann::json::parse(buffer.str(), nullptr, false);
    if (payload.is_discarded() || !payload.is_object())
    { return std::nullopt;
    }
    TokenSession session = TokenSession::FromJson(payload);
    if (session.access_token.empty() && session.refresh_token.empty())
    { return std::nullopt;
    }
    if (session.client_id.empty())
    { session.client_id = ClientId();
    }
    return session;
  }

  // #R048: Bootstrap token session from env, cache, and 1Password sources.
  TokenSession GraphTokenManager::BootstrapSession(const std::optional<TokenSession> &cached) const
  { const std::string env_token = NormalizeToken(EnvOrEmpty("OUTLOOK_GRAPH_TOKEN"));
    std::string access_token = env_token;
    std::string refresh_token;
    std::string client_id = ClientId();
    long long expires_at = 0;

    if (cached.has_value())
    { if (access_token.empty())
      { access_token = cached->access_token;
      }
      refresh_token = cached->refresh_token;
      if (client_id.empty())
      { client_id = cached->client_id;
      }
      expires_at = cached->expires_at;
    }

    if (refresh_token.empty())
    { refresh_token = RefreshTokenFromPsa();
    }
    if (access_token.empty())
    { access_token = AccessTokenFromPsa();
    }

    if (!access_token.empty() && expires_at == 0)
    { const auto jwt_expiry = JwtExpiresAt(access_token);
      expires_at = jwt_expiry.has_value() ? *jwt_expiry : 0;
    }

    return TokenSession{access_token, refresh_token, expires_at, client_id};
  }

  // #R052: Resolve configured 1Password item name with default fallback.
  std::string GraphTokenManager::PsaItem() const
  { return EnvOrDefault("OUTLOOK_GRAPH_TOKEN_PSA_ITEM", kDefaultPsaItem);
  }

  // #R052: Resolve configured 1Password access-token field name with default fallback.
  std::string GraphTokenManager::PsaAccessField() const
  { return EnvOrDefault("OUTLOOK_GRAPH_TOKEN_PSA_FIELD", kDefaultPsaField);
  }

  // #R052: Resolve configured 1Password refresh-token field name with default fallback.
  std::string GraphTokenManager::PsaRefreshField() const
  { return EnvOrDefault("OUTLOOK_GRAPH_TOKEN_PSA_REFRESH_FIELD", kDefaultPsaRefreshField);
  }

  // #R052: Resolve configured 1Password client-id field name with default fallback.
  std::string GraphTokenManager::PsaClientIdField() const
  { return EnvOrDefault("OUTLOOK_GRAPH_TOKEN_PSA_CLIENT_ID_FIELD", kDefaultPsaClientIdField);
  }

  // #R032: Resolve access token from 1Password, degrading safely on lookup failures.
  std::string GraphTokenManager::AccessTokenFromPsa() const
  { try
    { return psa_reader_(PsaItem(), PsaAccessField());
    }
    catch (const GraphTokenError &)
    { return "";
    }
  }

  // #R032: Resolve refresh token from 1Password, degrading safely on lookup failures.
  std::string GraphTokenManager::RefreshTokenFromPsa() const
  { try
    { return psa_reader_(PsaItem(), PsaRefreshField());
    }
    catch (const GraphTokenError &)
    { return "";
    }
  }
} // namespace mailcartcore
