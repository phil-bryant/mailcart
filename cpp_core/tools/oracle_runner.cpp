// Oracle parity harness for the mailcart Python -> C++ migration.
//
// Drives the same HTTP-level request scenarios through the C++ API handlers
// against a canned (in-process) Graph upstream, producing deterministic JSON
// results. While the Python reference existed, oracle/compare_oracle.py drove
// the identical scenarios through the FastAPI app and diffed the outputs.
// After retirement, the t17 lane replays the frozen goldens
// (oracle/goldens.json) against this runner.
//
// Modes:
//   run    --scenarios FILE [--out FILE]    print results JSON
//   record --scenarios FILE --record FILE   write goldens
//   replay --scenarios FILE --golden FILE   diff against goldens (exit 1 on drift)
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <sstream>
#include <string>
#include <vector>

#include "mailcartcore/api.hpp"
#include "mailcartcore/api_error.hpp"

namespace
{
  // Non-expiring unsigned JWT shared with the Python oracle harness so both
  // stacks resolve an identical deterministic Graph token (exp 2100-01-01).
  constexpr const char *kOracleJwt =
      "eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJleHAiOjQxMDI0NDQ4MDB9.signature";

  std::string ReadFile(const std::string &path)
  { std::ifstream stream(path);
    if (!stream.is_open())
    { throw std::runtime_error("unable to open file: " + path);
    }
    std::stringstream buffer;
    buffer << stream.rdbuf();
    return buffer.str();
  }

  std::string AsciiLower(std::string value)
  { for (auto &symbol : value)
    { symbol = static_cast<char>(std::tolower(static_cast<unsigned char>(symbol)));
    }
    return value;
  }

  // Canned Graph upstream: entries are consumed in order among matches so
  // pagination sequences replay deterministically.
  class StubGraphTransport
  { public:
    explicit StubGraphTransport(const nlohmann::json &entries)
    { if (entries.is_array())
      { for (const auto &entry : entries)
        { entries_.push_back(entry);
          consumed_.push_back(false);
        }
      }
    }

    mailcartcore::HttpResponse operator()(const mailcartcore::GraphRequestArgs &args,
                                          const std::vector<std::pair<std::string, std::string>> &headers)
    { (void)headers;
      for (size_t index = 0; index < entries_.size(); ++index)
      { if (consumed_[index])
        { continue;
        }
        const auto &entry = entries_[index];
        if (entry.value("method", "") != args.method)
        { continue;
        }
        if (entry.value("path", "") != args.path)
        { continue;
        }
        if (entry.contains("params") && entry["params"].is_object())
        { bool params_match = true;
          for (const auto &[key, expected] : entry["params"].items())
          { bool found = false;
            for (const auto &[actual_key, actual_value] : args.params)
            { if (actual_key == key && actual_value == expected.get<std::string>())
              { found = true;
                break;
              }
            }
            if (!found)
            { params_match = false;
              break;
            }
          }
          if (!params_match)
          { continue;
          }
        }
        if (!entry.value("sticky", false))
        { consumed_[index] = true;
        }
        mailcartcore::HttpResponse response;
        response.transport_ok = true;
        response.status = entry.value("status", 200);
        if (entry.contains("json"))
        { response.body = entry["json"].dump();
        }
        else
        { response.body = entry.value("body", "");
        }
        return response;
      }
      mailcartcore::HttpResponse response;
      response.transport_ok = true;
      response.status = 404;
      response.body = R"({"error":{"code":"ItemNotFound","message":"no fixture matched )" +
                      args.method + " " + args.path + R"("}})";
      return response;
    }

    private:
    std::vector<nlohmann::json> entries_;
    std::vector<bool> consumed_;
  };

  nlohmann::json RunScenario(const nlohmann::json &scenario, const std::filesystem::path &cache_dir)
  { // Deterministic env: fixed Graph token, scenario-selected write token.
    setenv("OUTLOOK_GRAPH_TOKEN", kOracleJwt, 1);
    unsetenv("OUTLOOK_GRAPH_CLIENT_ID");
    unsetenv("MAILCART_API_WRITE_TOKEN_HEADER");
    unsetenv("TELLER_CLASSIFIER_WRITE_TOKEN");
    unsetenv("CLASSY_WRITE_TOKEN");
    const std::string write_token = scenario.value("write_token", "");
    if (write_token.empty())
    { unsetenv("MAILCART_API_WRITE_TOKEN");
    }
    else
    { setenv("MAILCART_API_WRITE_TOKEN", write_token.c_str(), 1);
    }

    const std::filesystem::path cache_path =
        cache_dir / (scenario.value("name", std::string("scenario")) + ".graph_oauth.json");
    std::error_code ec;
    std::filesystem::remove(cache_path, ec);

    mailcartcore::GraphTokenManager token_manager(
        cache_path, nullptr,
        [](const std::string &, const std::string &) -> std::string
        { throw mailcartcore::GraphTokenError("1psa is required to resolve Outlook Graph credentials");
        });
    StubGraphTransport transport(scenario.contains("graph") ? scenario["graph"] : nlohmann::json::array());
    mailcartcore::GraphClient graph(token_manager,
                                    [&transport](const mailcartcore::GraphRequestArgs &args,
                                                 const std::vector<std::pair<std::string, std::string>> &headers)
                                    { return transport(args, headers);
                                    });
    mailcartcore::MailcartApi api(graph);

    const auto &request_spec = scenario["request"];
    mailcartcore::ApiRequest request;
    request.method = request_spec.value("method", "GET");
    request.path = request_spec.value("path", "/");
    if (request_spec.contains("query") && request_spec["query"].is_object())
    { for (const auto &[key, value] : request_spec["query"].items())
      { request.query_params.emplace_back(key, value.is_string() ? value.get<std::string>() : value.dump());
      }
    }
    if (request_spec.contains("headers") && request_spec["headers"].is_object())
    { for (const auto &[key, value] : request_spec["headers"].items())
      { request.headers[AsciiLower(key)] = value.get<std::string>();
      }
    }
    if (request_spec.contains("body"))
    { request.has_body = true;
      request.body = request_spec["body"].is_string() ? request_spec["body"].get<std::string>()
                                                      : request_spec["body"].dump();
    }

    const mailcartcore::ApiResult result = mailcartcore::HandleApiRequest(api, request);
    nlohmann::json output{
        {"name", scenario.value("name", "")},
        {"status", result.status},
        {"body", result.body},
    };
    const auto www_authenticate = result.headers.find("WWW-Authenticate");
    if (www_authenticate != result.headers.end())
    { output["www_authenticate"] = www_authenticate->second;
    }
    return output;
  }

  nlohmann::json RunAll(const std::string &scenarios_path)
  { const nlohmann::json document = nlohmann::json::parse(ReadFile(scenarios_path));
    const auto cache_dir = std::filesystem::temp_directory_path() / "mailcart-oracle";
    std::filesystem::create_directories(cache_dir);
    nlohmann::json results = nlohmann::json::array();
    for (const auto &scenario : document["scenarios"])
    { results.push_back(RunScenario(scenario, cache_dir));
    }
    return results;
  }

  int Usage()
  { std::cerr << "usage: mailcart_oracle_runner run --scenarios FILE [--out FILE]\n"
              << "       mailcart_oracle_runner record --scenarios FILE --record FILE\n"
              << "       mailcart_oracle_runner replay --scenarios FILE --golden FILE\n";
    return 2;
  }
} // namespace

int main(int argc, char **argv)
{ if (argc < 2)
  { return Usage();
  }
  const std::string mode = argv[1];
  std::string scenarios_path;
  std::string out_path;
  std::string record_path;
  std::string golden_path;
  for (int index = 2; index + 1 < argc; index += 2)
  { const std::string flag = argv[index];
    const std::string value = argv[index + 1];
    if (flag == "--scenarios")
    { scenarios_path = value;
    }
    else if (flag == "--out")
    { out_path = value;
    }
    else if (flag == "--record")
    { record_path = value;
    }
    else if (flag == "--golden")
    { golden_path = value;
    }
    else
    { return Usage();
    }
  }
  if (scenarios_path.empty())
  { return Usage();
  }

  try
  { const nlohmann::json results = RunAll(scenarios_path);
    if (mode == "run")
    { if (out_path.empty())
      { std::cout << results.dump(2) << "\n";
      }
      else
      { std::ofstream stream(out_path);
        stream << results.dump(2) << "\n";
      }
      return 0;
    }
    if (mode == "record")
    { if (record_path.empty())
      { return Usage();
      }
      std::ofstream stream(record_path);
      stream << results.dump(2) << "\n";
      std::cout << "recorded " << results.size() << " golden scenario results to " << record_path << "\n";
      return 0;
    }
    if (mode == "replay")
    { if (golden_path.empty())
      { return Usage();
      }
      const nlohmann::json goldens = nlohmann::json::parse(ReadFile(golden_path));
      int mismatches = 0;
      for (size_t index = 0; index < std::max(results.size(), goldens.size()); ++index)
      { const nlohmann::json actual = index < results.size() ? results[index] : nlohmann::json();
        const nlohmann::json expected = index < goldens.size() ? goldens[index] : nlohmann::json();
        if (actual != expected)
        { ++mismatches;
          std::cerr << "scenario mismatch [" << index << "] "
                    << expected.value("name", actual.value("name", "?")) << "\n"
                    << "  expected: " << expected.dump() << "\n"
                    << "  actual:   " << actual.dump() << "\n";
        }
      }
      if (mismatches > 0)
      { std::cerr << mismatches << " scenario(s) diverged from goldens\n";
        return 1;
      }
      std::cout << "replayed " << results.size() << " scenarios; all match goldens\n";
      return 0;
    }
    return Usage();
  }
  catch (const std::exception &exc)
  { std::cerr << "mailcart_oracle_runner: " << exc.what() << "\n";
    return 1;
  }
}
