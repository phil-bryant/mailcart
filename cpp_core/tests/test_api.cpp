// Catch2 port of the endpoint-level subset of tests/python/test_matchy_mailcart_api.py.
#include <catch2/catch_test_macros.hpp>
#include <catch2/matchers/catch_matchers_string.hpp>

#include <unistd.h>

#include <cstdlib>
#include <deque>
#include <filesystem>
#include <fstream>

#include "mailcartcore/api.hpp"
#include "mailcartcore/api_error.hpp"

using mailcartcore::ApiRequest;
using mailcartcore::ApiResult;
using mailcartcore::GraphClient;
using mailcartcore::GraphRequestArgs;
using mailcartcore::GraphTokenManager;
using mailcartcore::HandleApiRequest;
using mailcartcore::HttpResponse;
using mailcartcore::MailcartApi;

namespace
{
  // Non-expiring unsigned JWT (exp 2100-01-01).
  constexpr const char *kTestJwt =
      "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJleHAiOjQxMDI0NDQ4MDB9.signature";

  struct StubResponse
  { int status = 200;
    nlohmann::json body = nlohmann::json::object();
  };

  std::filesystem::path MakeTempCachePath()
  { std::string templ =
        (std::filesystem::temp_directory_path() / "mailcart-api-test-XXXXXX").string();
    std::vector<char> buffer(templ.begin(), templ.end());
    buffer.push_back('\0');
    const int fd = mkstemp(buffer.data());
    if (fd >= 0)
    { close(fd);
    }
    std::filesystem::path path(buffer.data());
    std::filesystem::remove(path); // managers expect a missing cache initially
    return path;
  }

  struct ApiHarness
  { explicit ApiHarness(std::deque<StubResponse> responses = {})
      : responses_(std::move(responses)),
        cache_path_(MakeTempCachePath()),
        token_manager_(cache_path_, nullptr,
                       [](const std::string &, const std::string &) -> std::string
                       { throw mailcartcore::GraphTokenError("no 1psa in tests");
                       }),
        graph_(token_manager_,
               [this](const GraphRequestArgs &args, const std::vector<std::pair<std::string, std::string>> &)
               { requests_.push_back(args);
                 HttpResponse response;
                 response.transport_ok = true;
                 if (responses_.empty())
                 { response.status = 200;
                   response.body = "{}";
                   return response;
                 }
                 const StubResponse next = responses_.front();
                 responses_.pop_front();
                 response.status = next.status;
                 response.body = next.body.is_string() ? next.body.get<std::string>() : next.body.dump();
                 return response;
               }),
        api_(graph_)
    { setenv("OUTLOOK_GRAPH_TOKEN", kTestJwt, 1);
      unsetenv("OUTLOOK_GRAPH_CLIENT_ID");
      unsetenv("MAILCART_API_WRITE_TOKEN_HEADER");
      setenv("MAILCART_API_WRITE_TOKEN", "test-token", 1);
      unsetenv("TELLER_CLASSIFIER_WRITE_TOKEN");
      unsetenv("CLASSY_WRITE_TOKEN");
    }

    ~ApiHarness()
    { std::error_code ec;
      std::filesystem::remove(cache_path_, ec);
    }

    ApiResult Call(const std::string &method, const std::string &path,
                   const mailcartcore::QueryParams &query = {}, bool authed = true,
                   const std::optional<std::string> &body = std::nullopt)
    { ApiRequest request;
      request.method = method;
      request.path = path;
      request.query_params = query;
      if (authed)
      { request.headers["x-teller-write-token"] = "test-token";
      }
      if (body.has_value())
      { request.has_body = true;
        request.body = *body;
      }
      return HandleApiRequest(api_, request);
    }

    std::deque<StubResponse> responses_;
    std::vector<GraphRequestArgs> requests_;
    std::filesystem::path cache_path_;
    GraphTokenManager token_manager_;
    GraphClient graph_;
    MailcartApi api_;
  };

  nlohmann::json MakeRow(const std::string &message_id, const std::string &subject,
                         const std::string &sender, const std::string &body_content,
                         const std::string &received_at = "2026-04-15T12:00:00Z")
  { return nlohmann::json{
        {"id", message_id},
        {"subject", subject},
        {"bodyPreview", ""},
        {"body", {{"contentType", "text"}, {"content", body_content}}},
        {"from", {{"emailAddress", {{"address", sender}}}}},
        {"receivedDateTime", received_at},
    };
  }

  std::vector<std::string> MessageIds(const nlohmann::json &body)
  { std::vector<std::string> ids;
    for (const auto &row : body["messages"])
    { ids.push_back(row["message_id"].get<std::string>());
    }
    return ids;
  }
} // namespace

// #R020-T01: field-scoped tokens filter subject/sender/body independently.
TEST_CASE("Search filters subject sender body independently", "[api]")
{ const nlohmann::json rows = nlohmann::json::array({
      MakeRow("msg1", "DoorDash receipt", "merchant@example.com", "hello"),
      MakeRow("msg2", "Hello", "doordash@merchant.com", "hello"),
      MakeRow("msg3", "Hello", "merchant@example.com", "DOORDASH order details"),
  });
  for (const auto &[query, expected] :
       std::vector<std::pair<std::string, std::string>>{{"subject:doordash", "msg1"},
                                                        {"sender:doordash", "msg2"},
                                                        {"body:doordash", "msg3"}})
  { ApiHarness harness({{200, nlohmann::json{{"value", rows}}}});
    const ApiResult result = harness.Call("GET", "/v1/messages/search", {{"query", query}});
    REQUIRE(result.status == 200);
    CHECK(MessageIds(result.body) == std::vector<std::string>{expected});
  }
}

// #R020: empty query returns recent mail without a Graph date filter.
TEST_CASE("Empty query returns recent mail", "[api]")
{ const nlohmann::json rows = nlohmann::json::array({
      MakeRow("newest", "Newest", "a@example.com", "", "2026-06-02T12:00:00Z"),
      MakeRow("middle", "Middle", "a@example.com", "", "2026-06-01T12:00:00Z"),
      MakeRow("older", "Older", "a@example.com", "", "2026-05-31T12:00:00Z"),
  });
  ApiHarness harness({{200, nlohmann::json{{"value", rows}}}});
  const ApiResult result = harness.Call("GET", "/v1/messages/search",
                                        {{"query", "   "}, {"limit", "2"}});
  REQUIRE(result.status == 200);
  CHECK(MessageIds(result.body) == std::vector<std::string>{"newest", "middle"});
  REQUIRE(harness.requests_.size() == 1);
  bool has_filter = false;
  std::string top_value;
  for (const auto &[key, value] : harness.requests_[0].params)
  { if (key == "$filter")
    { has_filter = true;
    }
    if (key == "$top")
    { top_value = value;
    }
  }
  CHECK_FALSE(has_filter);
  CHECK(top_value == "50");
}

// #R020-T01: date queries push a server-side receivedDateTime filter.
TEST_CASE("Date queries include server-side filter", "[api]")
{ ApiHarness harness({{200, nlohmann::json{{"value", nlohmann::json::array()}}}});
  const ApiResult result = harness.Call("GET", "/v1/messages/search",
                                        {{"query", "from:2026-04-01 to:2026-04-30"}, {"limit", "25"}});
  REQUIRE(result.status == 200);
  REQUIRE(harness.requests_.size() == 1);
  std::string filter_value;
  for (const auto &[key, value] : harness.requests_[0].params)
  { if (key == "$filter")
    { filter_value = value;
    }
  }
  CHECK_THAT(filter_value, Catch::Matchers::ContainsSubstring("receivedDateTime ge 2026-04-01T00:00:00Z"));
  CHECK_THAT(filter_value, Catch::Matchers::ContainsSubstring("receivedDateTime le 2026-04-30T23:59:59Z"));
}

// #R020-T01: search follows @odata.nextLink for older date windows.
TEST_CASE("Search paginates for older date windows", "[api]")
{ const nlohmann::json page_one{
      {"value", nlohmann::json::array({MakeRow("newer", "", "", "", "2026-05-27T10:00:00Z")})},
      {"@odata.nextLink", "https://graph.microsoft.com/v1.0/me/messages?$skiptoken=abc123"},
  };
  const nlohmann::json page_two{
      {"value", nlohmann::json::array({MakeRow("older", "", "", "", "2026-05-22T10:00:00Z")})},
  };
  ApiHarness harness({{200, page_one}, {200, page_two}});
  const ApiResult result = harness.Call("GET", "/v1/messages/search",
                                        {{"query", "from:2026-05-20 to:2026-05-23"}, {"limit", "10"}});
  REQUIRE(result.status == 200);
  CHECK(MessageIds(result.body) == std::vector<std::string>{"older"});
  REQUIRE(harness.requests_.size() == 2);
  bool skiptoken_forwarded = false;
  for (const auto &[key, value] : harness.requests_[1].params)
  { if (key == "$skiptoken" && value == "abc123")
    { skiptoken_forwarded = true;
    }
  }
  CHECK(skiptoken_forwarded);
}

// #R020-T01: invalid or unscoped tokens fail closed to empty results.
TEST_CASE("Invalid queries fail closed to empty results", "[api]")
{ for (const std::string query : {"doordash", "foo:bar"})
  { ApiHarness harness;
    const ApiResult result = harness.Call("GET", "/v1/messages/search", {{"query", query}});
    REQUIRE(result.status == 200);
    CHECK(result.body == nlohmann::json{{"messages", nlohmann::json::array()}});
    CHECK(harness.requests_.empty());
  }
}

// #R620-T01: route auth dependency fails closed when write token is unconfigured.
TEST_CASE("Auth returns 503 when server token missing", "[api]")
{ ApiHarness harness;
  unsetenv("MAILCART_API_WRITE_TOKEN");
  const ApiResult result = harness.Call("GET", "/v1/messages/search", {}, false);
  CHECK(result.status == 503);
}

// #R620-T01: route auth dependency rejects invalid caller tokens.
TEST_CASE("Auth returns 401 on invalid token", "[api]")
{ ApiHarness harness;
  ApiRequest request;
  request.method = "GET";
  request.path = "/v1/messages/search";
  request.headers["x-teller-write-token"] = "wrong-token";
  const ApiResult result = HandleApiRequest(harness.api_, request);
  CHECK(result.status == 401);
  CHECK(result.headers.at("WWW-Authenticate") == "X-Teller-Write-Token");
}

// #R029-T01: /health exposes token metadata only to authenticated callers.
TEST_CASE("Health redacts token metadata without valid write token", "[api]")
{ ApiHarness harness;
  const ApiResult unauth = harness.Call("GET", "/health", {}, false);
  REQUIRE(unauth.status == 200);
  CHECK(unauth.body == nlohmann::json{{"status", "ok"}});
  const ApiResult authed = harness.Call("GET", "/health");
  REQUIRE(authed.status == 200);
  CHECK(authed.body["status"] == "ok");
  CHECK(authed.body.contains("token_status"));
}

// #R027-T01: Graph request retries once after a 401, then succeeds.
TEST_CASE("Graph request retries once on 401 then succeeds", "[api]")
{ ApiHarness harness({{401, "InvalidAuthenticationToken"},
                      {200, nlohmann::json{{"id", "msg_00000001"},
                                           {"subject", "ok"},
                                           {"bodyPreview", ""},
                                           {"body", {{"contentType", "text"}, {"content", "hello"}}},
                                           {"from", {{"emailAddress", {{"address", "a@example.com"}}}}},
                                           {"toRecipients", nlohmann::json::array()},
                                           {"receivedDateTime", "2026-05-17T12:00:00Z"}}}});
  // Seed the token cache with a refreshable session so the 401 retry path can
  // force-refresh through the injected form poster.
  { std::ofstream stream(harness.cache_path_);
    stream << nlohmann::json{{"access_token", kTestJwt},
                             {"refresh_token", "refresh-token"},
                             {"expires_at", 4102444800LL},
                             {"client_id", "client-id"}}
                  .dump();
  }
  GraphTokenManager refreshing_manager(
      harness.cache_path_,
      [](const std::string &, const std::vector<std::pair<std::string, std::string>> &)
      { HttpResponse response;
        response.transport_ok = true;
        response.status = 200;
        response.body = nlohmann::json{{"access_token", kTestJwt}, {"expires_in", 3600}}.dump();
        return response;
      },
      [](const std::string &, const std::string &) -> std::string
      { throw mailcartcore::GraphTokenError("no 1psa in tests");
      });
  GraphClient graph(refreshing_manager,
                    [&harness](const GraphRequestArgs &args,
                               const std::vector<std::pair<std::string, std::string>> &)
                    { harness.requests_.push_back(args);
                      HttpResponse response;
                      response.transport_ok = true;
                      const StubResponse next = harness.responses_.front();
                      harness.responses_.pop_front();
                      response.status = next.status;
                      response.body = next.body.is_string() ? next.body.get<std::string>() : next.body.dump();
                      return response;
                    });
  MailcartApi api(graph);
  ApiRequest request;
  request.method = "GET";
  request.path = "/v1/messages/msg_00000001";
  request.headers["x-teller-write-token"] = "test-token";
  const ApiResult result = HandleApiRequest(api, request);
  REQUIRE(result.status == 200);
  CHECK(result.body["subject"] == "ok");
  CHECK(harness.requests_.size() == 2);
}

// #R027-T01: 401 with failed refresh surfaces HTTP 502.
TEST_CASE("Graph 401 with failed refresh surfaces 502", "[api]")
{ ApiHarness harness({{401, "InvalidAuthenticationToken"}});
  const ApiResult result = harness.Call("GET", "/v1/messages/msg_00000002");
  CHECK(result.status == 502);
  CHECK_THAT(result.body["detail"].get<std::string>(),
             Catch::Matchers::ContainsSubstring("token refresh failed"));
}

// #R030-T01: Graph ItemNotFound/ResourceNotFound errors are mapped to HTTP 404.
TEST_CASE("Graph not-found variants map to 404", "[api]")
{ for (const auto &[status, body] : std::vector<std::pair<int, std::string>>{
         {404, "ItemNotFound"}, {400, "ResourceNotFound"}})
  { ApiHarness harness({{status, body}});
    const ApiResult result = harness.Call("GET", "/v1/messages/msg_00000005");
    CHECK(result.status == 404);
  }
}

// #R035-T01: single-message fetch returns html_body and recipients.
TEST_CASE("GetMessage maps html body and recipients", "[api]")
{ const nlohmann::json payload{
      {"id", "msg_000042"},
      {"subject", "Receipt"},
      {"bodyPreview", "Thanks for your order"},
      {"body", {{"contentType", "html"}, {"content", "<p>Thanks!</p>"}}},
      {"from", {{"emailAddress", {{"address", "store@example.com"}}}}},
      {"toRecipients",
       nlohmann::json::array({{{"emailAddress", {{"address", "me@example.com"}}}},
                              {{"emailAddress", {{"address", "cc@example.com"}}}}})},
      {"receivedDateTime", "2026-05-17T12:00:00Z"},
  };
  ApiHarness harness({{200, payload}});
  const ApiResult result = harness.Call("GET", "/v1/messages/msg_000042");
  REQUIRE(result.status == 200);
  CHECK(result.body["message_id"] == "msg_000042");
  CHECK(result.body["subject"] == "Receipt");
  CHECK(result.body["preview"] == "Thanks for your order");
  CHECK(result.body["sender"] == "store@example.com");
  CHECK(result.body["recipients"] == "me@example.com,cc@example.com");
  CHECK(result.body["html_body"] == "<p>Thanks!</p>");
  CHECK(result.body["text_body"] == "");
  CHECK(result.body["body_text"] == "<p>Thanks!</p>");
  REQUIRE(harness.requests_.size() == 1);
  CHECK(harness.requests_[0].path == "/me/messages/msg_000042");
}

// #R035-T02: single-message fetch rejects blank ids with HTTP 404.
TEST_CASE("GetMessage rejects blank and short ids", "[api]")
{ ApiHarness harness;
  CHECK(harness.Call("GET", "/v1/messages/%20%20%20").status == 404);
  // (path arrives URL-decoded at the dispatcher, mirror that)
  ApiRequest request;
  request.method = "GET";
  request.path = "/v1/messages/   ";
  request.headers["x-teller-write-token"] = "test-token";
  CHECK(HandleApiRequest(harness.api_, request).status == 404);
  CHECK(harness.Call("GET", "/v1/messages/short").status == 404);
  CHECK(harness.requests_.empty());
}

// #R035-T01: get_message percent-encodes reserved id characters.
TEST_CASE("GetMessage URL-encodes reserved characters", "[api]")
{ const nlohmann::json payload{{"id", "abc123=="},
                               {"subject", ""},
                               {"bodyPreview", ""},
                               {"body", {{"contentType", "text"}, {"content", ""}}},
                               {"from", {{"emailAddress", {{"address", ""}}}}},
                               {"toRecipients", nlohmann::json::array()},
                               {"receivedDateTime", ""}};
  ApiHarness harness({{200, payload}});
  const ApiResult result = harness.Call("GET", "/v1/messages/abc123==");
  REQUIRE(result.status == 200);
  REQUIRE(harness.requests_.size() == 1);
  CHECK(harness.requests_[0].path == "/me/messages/abc123%3D%3D");
}

// #R035-T01: get_message rejects already percent-encoded ids.
TEST_CASE("GetMessage rejects already-encoded ids", "[api]")
{ ApiHarness harness;
  const ApiResult result = harness.Call("GET", "/v1/messages/abc123%3D%3D");
  CHECK(result.status == 404);
  CHECK(harness.requests_.empty());
}

// #R025-T01: move_message percent-encodes ids and reports folder/result ids.
TEST_CASE("MoveMessage resolves folder and moves", "[api]")
{ const nlohmann::json folders{{"value", nlohmann::json::array({
                                   {{"id", "folder-1"}, {"displayName", "Matchy"}},
                               })}};
  ApiHarness harness({{200, folders}, {200, nlohmann::json{{"id", "moved-1"}}}});
  const ApiResult result = harness.Call("POST", "/v1/messages/abc123==/move", {}, true,
                                        std::optional<std::string>(R"({"folder_name":"matchy"})"));
  REQUIRE(result.status == 200);
  CHECK(result.body["moved"] == true);
  CHECK(result.body["folder_id"] == "folder-1");
  CHECK(result.body["result_id"] == "moved-1");
  REQUIRE(harness.requests_.size() == 2);
  CHECK(harness.requests_[1].path == "/me/messages/abc123%3D%3D/move");
  CHECK(harness.requests_[1].method == "POST");
}

// #R025: move creates the destination folder when absent.
TEST_CASE("MoveMessage creates folder when absent", "[api]")
{ const nlohmann::json folders{{"value", nlohmann::json::array()}};
  ApiHarness harness({{200, folders},
                      {200, nlohmann::json{{"id", "created-folder"}}},
                      {200, nlohmann::json{{"id", "moved-2"}}}});
  const ApiResult result = harness.Call("POST", "/v1/messages/abc12345/move", {}, true,
                                        std::optional<std::string>(R"({"folder_name":"matchy"})"));
  REQUIRE(result.status == 200);
  CHECK(result.body["folder_id"] == "created-folder");
  REQUIRE(harness.requests_.size() == 3);
  CHECK(harness.requests_[1].method == "POST");
  CHECK(harness.requests_[1].path == "/me/mailFolders");
}

// FastAPI-style 422 envelopes for invalid query params and bodies.
TEST_CASE("Validation errors use 422 envelopes", "[api]")
{ ApiHarness harness;
  const ApiResult limit_result = harness.Call("GET", "/v1/messages/search",
                                              {{"query", ""}, {"limit", "200"}});
  REQUIRE(limit_result.status == 422);
  CHECK(limit_result.body["detail"][0]["type"] == "less_than_equal");

  const ApiResult missing_body = harness.Call("POST", "/v1/messages/abc12345/move");
  REQUIRE(missing_body.status == 422);
  CHECK(missing_body.body["detail"][0]["type"] == "missing");

  const ApiResult short_name = harness.Call("POST", "/v1/messages/abc12345/move", {}, true,
                                            std::optional<std::string>(R"({"folder_name":""})"));
  REQUIRE(short_name.status == 422);
  CHECK(short_name.body["detail"][0]["type"] == "string_too_short");
}

// Unknown routes and methods mirror FastAPI envelopes.
TEST_CASE("Routing mirrors FastAPI 404 and 405", "[api]")
{ ApiHarness harness;
  CHECK(harness.Call("GET", "/nope").status == 404);
  CHECK(harness.Call("POST", "/health").status == 405);
  CHECK(harness.Call("DELETE", "/v1/messages/abc12345").status == 405);
  // Nested ids (slash inside path param) are not routable, as in FastAPI.
  CHECK(harness.Call("GET", "/v1/messages/a/b").status == 404);
}
