// Catch2 port of tests/python/test_graph_token.py.
#include <catch2/catch_test_macros.hpp>
#include <catch2/matchers/catch_matchers_string.hpp>

#include <sys/stat.h>
#include <unistd.h>

#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <vector>

#include "mailcartcore/token.hpp"

using mailcartcore::GraphTokenError;
using mailcartcore::GraphTokenManager;
using mailcartcore::HttpResponse;
using mailcartcore::JwtExpiresAt;
using mailcartcore::NormalizeToken;
using mailcartcore::TokenSession;

namespace
{
  std::string Base64UrlEncode(const std::string &input)
  { static constexpr const char *kAlphabet =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    std::string output;
    int accumulator = 0;
    int bits = 0;
    for (unsigned char symbol : input)
    { accumulator = (accumulator << 8) | symbol;
      bits += 8;
      while (bits >= 6)
      { bits -= 6;
        output.push_back(kAlphabet[(accumulator >> bits) & 0x3F]);
      }
    }
    if (bits > 0)
    { output.push_back(kAlphabet[(accumulator << (6 - bits)) & 0x3F]);
    }
    return output;
  }

  // #R026: Build a JWT fixture with an exp claim for token-lifecycle tests.
  std::string MakeJwt(long long exp)
  { const std::string header = Base64UrlEncode(R"({"alg":"none","typ":"JWT"})");
    const std::string payload = Base64UrlEncode("{\"exp\":" + std::to_string(exp) + "}");
    return header + "." + payload + ".signature";
  }

  std::filesystem::path MakeTempDir()
  { std::string templ = (std::filesystem::temp_directory_path() / "mailcart-token-test-XXXXXX").string();
    std::vector<char> buffer(templ.begin(), templ.end());
    buffer.push_back('\0');
    REQUIRE(mkdtemp(buffer.data()) != nullptr);
    return std::filesystem::path(buffer.data());
  }

  void ClearTokenEnv()
  { unsetenv("OUTLOOK_GRAPH_TOKEN");
    unsetenv("OUTLOOK_GRAPH_CLIENT_ID");
    unsetenv("OUTLOOK_GRAPH_TOKEN_PSA_ITEM");
    unsetenv("OUTLOOK_GRAPH_TOKEN_PSA_FIELD");
    unsetenv("OUTLOOK_GRAPH_TOKEN_PSA_REFRESH_FIELD");
    unsetenv("OUTLOOK_GRAPH_TOKEN_PSA_CLIENT_ID_FIELD");
  }

  mailcartcore::PsaReader FailingPsa()
  { return [](const std::string &, const std::string &) -> std::string
    { throw GraphTokenError("1psa is required to resolve Outlook Graph credentials");
    };
  }

  std::string ReadFileText(const std::filesystem::path &path)
  { std::ifstream stream(path);
    std::stringstream buffer;
    buffer << stream.rdbuf();
    return buffer.str();
  }
} // namespace

// #R005-T01: token normalization strips Bearer prefix and surrounding quotes.
TEST_CASE("NormalizeToken strips Bearer and quotes", "[token]")
{ CHECK(NormalizeToken("Bearer \"abc\"") == "abc");
  CHECK(NormalizeToken("  Bearer abc  ") == "abc");
}

// #R026: jwt_expires_at reads the exp claim used for refresh decisions.
TEST_CASE("JwtExpiresAt reads exp claim", "[token]")
{ const long long exp = static_cast<long long>(std::time(nullptr)) + 3600;
  CHECK(JwtExpiresAt(MakeJwt(exp)) == exp);
}

// #R030-T01: malformed JWTs return nullopt instead of raising.
TEST_CASE("JwtExpiresAt handles malformed tokens", "[token]")
{ CHECK_FALSE(JwtExpiresAt("no-dots").has_value());
  CHECK_FALSE(JwtExpiresAt("a.b.c").has_value());
}

// #R026: TokenSession.IsValid applies the pre-expiry refresh buffer.
TEST_CASE("TokenSession validity uses refresh buffer", "[token]")
{ TokenSession session{"token", "refresh", static_cast<long long>(std::time(nullptr)) + 120, "client"};
  CHECK_FALSE(session.IsValid());
  session.expires_at = static_cast<long long>(std::time(nullptr)) + 600;
  CHECK(session.IsValid());
}

// #R028: GetAccessToken returns a valid token from the persisted cache.
TEST_CASE("GetAccessToken uses valid cache", "[token]")
{ ClearTokenEnv();
  const auto tmp_dir = MakeTempDir();
  const auto cache_path = tmp_dir / "graph_oauth.json";
  const long long exp = static_cast<long long>(std::time(nullptr)) + 7200;
  { std::ofstream stream(cache_path);
    stream << nlohmann::json{{"access_token", "cached-access"},
                             {"refresh_token", "cached-refresh"},
                             {"expires_at", exp},
                             {"client_id", "client-id"}}
                  .dump();
  }
  GraphTokenManager manager(cache_path, nullptr, FailingPsa());
  CHECK(manager.GetAccessToken() == "cached-access");
}

// #R028: refresh persists rotated tokens to the 0600 cache.
TEST_CASE("Refresh persists rotated tokens", "[token]")
{ ClearTokenEnv();
  setenv("OUTLOOK_GRAPH_CLIENT_ID", "client-id", 1);
  const auto tmp_dir = MakeTempDir();
  const auto cache_path = tmp_dir / "graph_oauth.json";
  auto poster = [](const std::string &url, const std::vector<std::pair<std::string, std::string>> &form)
  { CHECK(url == std::string(mailcartcore::kTokenEndpoint));
    bool has_grant_type = false;
    for (const auto &[key, value] : form)
    { if (key == "grant_type" && value == "refresh_token")
      { has_grant_type = true;
      }
    }
    CHECK(has_grant_type);
    HttpResponse response;
    response.transport_ok = true;
    response.status = 200;
    response.body = nlohmann::json{{"access_token", "new-access"},
                                   {"refresh_token", "new-refresh"},
                                   {"expires_in", 3600}}
                        .dump();
    return response;
  };
  GraphTokenManager manager(cache_path, poster, FailingPsa());
  TokenSession session{"old-access", "old-refresh", static_cast<long long>(std::time(nullptr)) - 10, "client-id"};
  const TokenSession refreshed = manager.Refresh(true, session);
  CHECK(refreshed.access_token == "new-access");
  CHECK(refreshed.refresh_token == "new-refresh");
  const nlohmann::json persisted = nlohmann::json::parse(ReadFileText(cache_path));
  CHECK(persisted["access_token"] == "new-access");
  CHECK(persisted["refresh_token"] == "new-refresh");
  struct stat status_buffer{};
  REQUIRE(stat(cache_path.c_str(), &status_buffer) == 0);
  CHECK((status_buffer.st_mode & 0777) == 0600);
  unsetenv("OUTLOOK_GRAPH_CLIENT_ID");
}

// #R026: refresh fails clearly when no client id can be resolved.
TEST_CASE("Refresh requires client id", "[token]")
{ ClearTokenEnv();
  const auto tmp_dir = MakeTempDir();
  GraphTokenManager manager(tmp_dir / "graph_oauth.json", nullptr, FailingPsa());
  TokenSession session{"", "refresh", 0, ""};
  CHECK_THROWS_AS(manager.Refresh(true, session), GraphTokenError);
}

// #R026: GetAccessToken raises a clear error when all credentials are absent.
TEST_CASE("Missing credentials raise clear error", "[token]")
{ ClearTokenEnv();
  const auto tmp_dir = MakeTempDir();
  GraphTokenManager manager(tmp_dir / "missing.json", nullptr, FailingPsa());
  CHECK_THROWS_WITH(manager.GetAccessToken(),
                    Catch::Matchers::ContainsSubstring("OUTLOOK_GRAPH_TOKEN or refresh_token is required"));
}

// #R040-T01: token_status maps error and expiry states correctly.
TEST_CASE("TokenStatus maps load errors and states", "[token]")
{ ClearTokenEnv();
  const auto tmp_dir = MakeTempDir();
  // No cache + no credentials -> load fails with "refresh" in message -> missing_refresh_token.
  GraphTokenManager manager(tmp_dir / "graph_oauth.json", nullptr, FailingPsa());
  CHECK(manager.TokenStatus().at("token_status") == "missing_refresh_token");

  // Expired session with refresh token -> expired.
  const auto cache_path = tmp_dir / "expired.json";
  { std::ofstream stream(cache_path);
    stream << nlohmann::json{{"access_token", "x"},
                             {"refresh_token", "r"},
                             {"expires_at", static_cast<long long>(std::time(nullptr)) - 10},
                             {"client_id", "c"}}
                  .dump();
  }
  auto failing_poster = [](const std::string &, const std::vector<std::pair<std::string, std::string>> &)
  { HttpResponse response;
    response.transport_ok = true;
    response.status = 400;
    response.body = "invalid_grant";
    return response;
  };
  GraphTokenManager expired_manager(cache_path, failing_poster, FailingPsa());
  const auto status = expired_manager.TokenStatus();
  // Load attempts a refresh which fails; the error message contains "refresh"
  // so it classifies as missing_refresh_token (Python parity).
  CHECK(status.at("token_status") == "missing_refresh_token");
  CHECK(status.count("token_error") == 1);
}

// #R026-T01: non-forced refresh on valid session returns unchanged session.
TEST_CASE("Refresh short-circuits when valid and not forced", "[token]")
{ ClearTokenEnv();
  const auto tmp_dir = MakeTempDir();
  bool poster_called = false;
  auto poster = [&poster_called](const std::string &, const std::vector<std::pair<std::string, std::string>> &)
  { poster_called = true;
    HttpResponse response;
    response.transport_ok = true;
    response.status = 200;
    return response;
  };
  GraphTokenManager manager(tmp_dir / "graph_oauth.json", poster, FailingPsa());
  TokenSession valid{"cached-access", "cached-refresh", static_cast<long long>(std::time(nullptr)) + 7200,
                     "client-id"};
  const TokenSession result = manager.Refresh(false, valid);
  CHECK(result.access_token == "cached-access");
  CHECK_FALSE(poster_called);
}

// #R026-T01: refresh rejects token endpoint HTTP failures and empty access_token payloads.
TEST_CASE("Refresh raises on HTTP failure or empty access token", "[token]")
{ ClearTokenEnv();
  const auto tmp_dir = MakeTempDir();
  TokenSession base_session{"old", "refresh", static_cast<long long>(std::time(nullptr)) - 10, "client-id"};

  auto bad_http = [](const std::string &, const std::vector<std::pair<std::string, std::string>> &)
  { HttpResponse response;
    response.transport_ok = true;
    response.status = 400;
    response.body = "invalid_grant";
    return response;
  };
  GraphTokenManager manager_http(tmp_dir / "a.json", bad_http, FailingPsa());
  CHECK_THROWS_WITH(manager_http.Refresh(true, base_session),
                    Catch::Matchers::ContainsSubstring("Graph token refresh failed"));

  auto empty_access = [](const std::string &, const std::vector<std::pair<std::string, std::string>> &)
  { HttpResponse response;
    response.transport_ok = true;
    response.status = 200;
    response.body = nlohmann::json{{"access_token", "  "}}.dump();
    return response;
  };
  GraphTokenManager manager_empty(tmp_dir / "b.json", empty_access, FailingPsa());
  CHECK_THROWS_WITH(manager_empty.Refresh(true, base_session),
                    Catch::Matchers::ContainsSubstring("empty access_token"));
}

// #R046-T01: cache reader tolerates invalid JSON/non-dict payloads (falls through to bootstrap error).
TEST_CASE("Corrupt cache payloads are ignored", "[token]")
{ ClearTokenEnv();
  const auto tmp_dir = MakeTempDir();
  const auto cache_path = tmp_dir / "graph_oauth.json";
  for (const std::string content : {"{not json", "[]", R"({"access_token":"","refresh_token":""})"})
  { { std::ofstream stream(cache_path);
      stream << content;
    }
    GraphTokenManager manager(cache_path, nullptr, FailingPsa());
    CHECK_THROWS_AS(manager.GetAccessToken(), GraphTokenError);
  }
}

// #R048: env token bootstrap derives expiry from the JWT exp claim.
TEST_CASE("Bootstrap uses env token with JWT expiry", "[token]")
{ ClearTokenEnv();
  const auto tmp_dir = MakeTempDir();
  const long long exp = static_cast<long long>(std::time(nullptr)) + 7200;
  const std::string jwt = MakeJwt(exp);
  setenv("OUTLOOK_GRAPH_TOKEN", jwt.c_str(), 1);
  GraphTokenManager manager(tmp_dir / "graph_oauth.json", nullptr, FailingPsa());
  CHECK(manager.GetAccessToken() == jwt);
  // The bootstrapped session is persisted to the cache for the bridge to share.
  const nlohmann::json persisted = nlohmann::json::parse(ReadFileText(tmp_dir / "graph_oauth.json"));
  CHECK(persisted["access_token"] == jwt);
  CHECK(persisted["expires_at"] == exp);
  unsetenv("OUTLOOK_GRAPH_TOKEN");
}
