// libFuzzer target for Graph payload mapping (port of search/get_message
// response handling in scripts/matchy_mailcart_api.py). The input is parsed as
// a Graph JSON payload and fed through the API handlers via a stub transport so
// the mapping, HTML extraction, and matching paths are exercised on hostile
// input without opening sockets.
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <string>
#include <vector>

#include <nlohmann/json.hpp>

#include "mailcartcore/api.hpp"
#include "mailcartcore/api_error.hpp"
#include "mailcartcore/graph.hpp"
#include "mailcartcore/token.hpp"

namespace
{
  // Non-expiring unsigned JWT (exp 2100-01-01) so GetAccessToken resolves from
  // the environment without contacting 1psa or the refresh endpoint.
  constexpr const char *kFuzzJwt =
      "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJleHAiOjQxMDI0NDQ4MDB9.signature";
} // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{ setenv("OUTLOOK_GRAPH_TOKEN", kFuzzJwt, 1);
  unsetenv("OUTLOOK_GRAPH_CLIENT_ID");

  const std::string input(reinterpret_cast<const char *>(data), size);
  nlohmann::json payload = nlohmann::json::parse(input, nullptr, false);
  if (payload.is_discarded())
  { return 0;
  }

  const std::filesystem::path cache_path =
      std::filesystem::temp_directory_path() / "mailcart-fuzz-graph.json";
  mailcartcore::GraphTokenManager token_manager(
      cache_path, nullptr,
      [](const std::string &, const std::string &) -> std::string
      { throw mailcartcore::GraphTokenError("1psa disabled in fuzzing");
      });

  // Every Graph call returns the fuzzed payload as a 200 so the response-mapping
  // code paths run regardless of which endpoint is exercised.
  auto transport = [&payload](const mailcartcore::GraphRequestArgs &,
                              const std::vector<std::pair<std::string, std::string>> &)
  { mailcartcore::HttpResponse response;
    response.transport_ok = true;
    response.status = 200;
    response.body = payload.dump();
    return response;
  };
  mailcartcore::GraphClient graph(token_manager, transport);
  mailcartcore::MailcartApi api(graph);

  try
  { (void)api.SearchMessages("", 50);
  }
  catch (const mailcartcore::ApiError &)
  {
  }
  try
  { (void)api.SearchMessages("subject:test body:hello", 25);
  }
  catch (const mailcartcore::ApiError &)
  {
  }
  try
  { (void)api.GetMessage("AAAA1234");
  }
  catch (const mailcartcore::ApiError &)
  {
  }
  try
  { (void)api.MoveMessage("AAAA1234", "matchy");
  }
  catch (const mailcartcore::ApiError &)
  {
  }
  return 0;
}
