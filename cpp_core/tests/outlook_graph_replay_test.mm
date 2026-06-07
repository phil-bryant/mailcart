#include "OutlookGraphConversions.h"
#include "OutlookGraphHttpClient.h"

#import <Foundation/Foundation.h>

#include <iostream>
#include <string>
#include <vector>

namespace
{
  struct ReplayResponse
  {
    std::string expected_authorization;
    std::string body;
    NSInteger status_code;
  };

  class ReplayMetrics
  {
   public:
    // #R001: Initialize aggregate counters for replay tests and expectations.
    ReplayMetrics()
      : total_tests_(0),
        failed_tests_(0),
        total_expectations_(0),
        failed_expectations_(0)
    {
    }

    // #R001: Record one expectation and mark failures.
    void RecordExpectation(bool passed)
    {
      total_expectations_ = total_expectations_ + 1;
      if (!passed)
      {
        failed_expectations_ = failed_expectations_ + 1;
      }
    }

    // #R001: Record one test result and mark failures.
    void RecordTest(bool passed)
    {
      total_tests_ = total_tests_ + 1;
      if (!passed)
      {
        failed_tests_ = failed_tests_ + 1;
      }
    }

    // #R001: Expose whether all tests passed.
    [[nodiscard]] bool AllPassed() const
    {
      return failed_tests_ == 0 && failed_expectations_ == 0;
    }

    // #R001: Print aggregate replay metrics summary.
    void PrintSummary() const
    {
      std::cout << "Final count: tests " << (total_tests_ - failed_tests_) << "/" << total_tests_
                << " passed, expectations " << (total_expectations_ - failed_expectations_) << "/"
                << total_expectations_ << " passed.\n";
    }

   private:
    int total_tests_;
    int failed_tests_;
    int total_expectations_;
    int failed_expectations_;
  };

  ReplayMetrics g_metrics;
  std::vector<ReplayResponse> g_replay_responses;
  size_t g_replay_index = 0;
  bool g_refresh_called = false;
  int g_token_resolve_calls = 0;
  std::string g_replay_transport_failure;

  // #R005: Resolve replay fixture paths from the mailcart repository root.
  NSString *FixturePath(const std::string &fixture_name)
  {
    const char *repo_root = std::getenv("MAILCART_REPO_ROOT");
    if (repo_root == nullptr)
    {
      return nil;
    }
    return [NSString stringWithFormat:@"%s/cpp_core/tests/fixtures/graph/%s", repo_root, fixture_name.c_str()];
  }

  // #R005: Load UTF-8 replay fixture text and return empty string on missing content.
  std::string LoadFixture(const std::string &fixture_name)
  {
    NSString *path = FixturePath(fixture_name);
    if (path == nil)
    {
      return "";
    }
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data == nil)
    {
      return "";
    }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text == nil)
    {
      return "";
    }
    return mailcart_bridge::ToStdString(text);
  }

  // #R010: Install queued deterministic responses for Graph transport replay.
  void SetReplayResponses(const std::vector<ReplayResponse> &responses)
  {
    g_replay_responses = responses;
    g_replay_index = 0;
    g_replay_transport_failure.clear();
    g_refresh_called = false;
    g_token_resolve_calls = 0;
  }

  // #R010: Execute the queued deterministic transport callback used by replay tests.
  NSData *ReplayTransport(NSURLRequest *request, NSHTTPURLResponse **http_response, NSError **request_error)
  {
    if (request_error != nullptr)
    {
      *request_error = nil;
    }
    if (g_replay_index >= g_replay_responses.size())
    {
      g_replay_transport_failure = "replay transport exhausted queued responses";
      if (http_response != nullptr)
      {
        *http_response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                      statusCode:599
                                                     HTTPVersion:@"HTTP/1.1"
                                                    headerFields:@{}];
      }
      return [@"{}" dataUsingEncoding:NSUTF8StringEncoding];
    }

    const ReplayResponse response = g_replay_responses[g_replay_index];
    g_replay_index = g_replay_index + 1;
    NSString *authorization = [request valueForHTTPHeaderField:@"Authorization"];
    std::string authorization_text = mailcart_bridge::ToStdString(authorization == nil ? @"" : authorization);
    if (!response.expected_authorization.empty() && authorization_text != response.expected_authorization)
    {
      g_replay_transport_failure = "authorization mismatch expected '" + response.expected_authorization + "' got '" +
                                   authorization_text + "'";
    }

    if (http_response != nullptr)
    {
      *http_response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                    statusCode:response.status_code
                                                   HTTPVersion:@"HTTP/1.1"
                                                  headerFields:@{}];
    }
    NSString *body = mailcart_bridge::ToNSString(response.body);
    return [body dataUsingEncoding:NSUTF8StringEncoding];
  }

  // #R010: Simulate a successful token refresh branch for deterministic replay.
  BOOL ReplayRefresh()
  {
    g_refresh_called = true;
    return YES;
  }

  // #R010: Resolve deterministic replay tokens before and after refresh.
  NSString *ReplayTokenResolver()
  {
    g_token_resolve_calls = g_token_resolve_calls + 1;
    if (g_refresh_called)
    {
      return @"token-refreshed";
    }
    return @"token-initial";
  }

  // #R001: Record and print one expectation result.
  bool Expect(const std::string &name, bool passed)
  {
    g_metrics.RecordExpectation(passed);
    if (passed)
    {
      std::cout << "  ✓ " << name << "\n";
    }
    else
    {
      std::cerr << "  x " << name << "\n";
    }
    return passed;
  }

  // #R001: Run one named replay test function and record pass/fail.
  bool RunReplayTest(const std::string &test_name, bool (*test_function)())
  {
    std::cout << "Running " << test_name << "\n";
    bool passed = test_function();
    g_metrics.RecordTest(passed);
    if (passed)
    {
      std::cout << "✓ " << test_name << " passed\n";
    }
    else
    {
      std::cerr << "x " << test_name << " failed\n";
    }
    return passed;
  }

  // #R015: Replay Graph search with 401->refresh->200 and verify deterministic payload mapping.
  bool TestSearchPayloadRefreshReplay()
  {
    std::string unauthorized_body = LoadFixture("error_401.json");
    std::string search_payload = LoadFixture("search_response.json");
    SetReplayResponses({
        {"Bearer token-initial", unauthorized_body, 401},
        {"Bearer token-refreshed", search_payload, 200},
    });
    mailcart_bridge::InstallGraphTransportHook(ReplayTransport);
    mailcart_bridge::InstallGraphRefreshHook(ReplayRefresh);
    mailcart_bridge::InstallGraphTokenResolverHook(ReplayTokenResolver);

    std::string payload = mailcart_bridge::BuildGraphSearchPayload("cvs", 1);
    id parsed = mailcart_bridge::ParseJsonObject(payload);
    NSDictionary *root = mailcart_bridge::JsonDictionaryOrEmpty(parsed);
    NSArray *values = mailcart_bridge::JsonArrayOrEmpty(root[@"value"]);
    NSString *next_cursor = mailcart_bridge::JsonStringOrEmpty(root[@"nextCursor"]);
    NSString *error_text = mailcart_bridge::JsonStringOrEmpty(root[@"error"]);

    bool passed = true;
    passed = Expect("search replay has no transport assertion failure", g_replay_transport_failure.empty()) && passed;
    passed = Expect("search replay consumed both queued requests", g_replay_index == 2) && passed;
    passed = Expect("search replay called refresh branch", g_refresh_called) && passed;
    passed = Expect("search replay resolved token twice", g_token_resolve_calls >= 2) && passed;
    passed = Expect("search replay returns one filtered row", values.count == 1) && passed;
    passed = Expect("search replay keeps next cursor", [next_cursor isEqualToString:@"https://graph.microsoft.com/v1.0/me/messages?$skiptoken=cursor-abc"]) &&
             passed;
    passed = Expect("search replay has empty error text", error_text.length == 0) && passed;
    return passed;
  }

  // #R020: Replay message and attachment Graph responses and verify merged deterministic message payload.
  bool TestMessagePayloadReplay()
  {
    std::string message_payload = LoadFixture("message_response.json");
    std::string attachments_payload = LoadFixture("attachments_response.json");
    SetReplayResponses({
        {"Bearer token-initial", message_payload, 200},
        {"Bearer token-initial", attachments_payload, 200},
    });
    mailcart_bridge::InstallGraphTransportHook(ReplayTransport);
    mailcart_bridge::InstallGraphRefreshHook(nullptr);
    mailcart_bridge::InstallGraphTokenResolverHook(ReplayTokenResolver);

    std::string payload = mailcart_bridge::BuildGraphMessagePayload("msg-graph-123");
    id parsed = mailcart_bridge::ParseJsonObject(payload);
    NSDictionary *root = mailcart_bridge::JsonDictionaryOrEmpty(parsed);
    NSArray *attachments = mailcart_bridge::JsonArrayOrEmpty(root[@"attachments"]);
    NSString *identifier = mailcart_bridge::JsonStringOrEmpty(root[@"id"]);

    bool passed = true;
    passed = Expect("message replay has no transport assertion failure", g_replay_transport_failure.empty()) && passed;
    passed = Expect("message replay consumed both message and attachment calls", g_replay_index == 2) && passed;
    passed = Expect("message replay keeps message id", [identifier isEqualToString:@"msg-graph-123"]) && passed;
    passed = Expect("message replay merges one attachment", attachments.count == 1) && passed;
    if (attachments.count == 1)
    {
      NSDictionary *first = mailcart_bridge::JsonDictionaryOrEmpty(attachments[0]);
      passed = Expect("message replay keeps attachment name",
                      [mailcart_bridge::JsonStringOrEmpty(first[@"name"]) isEqualToString:@"receipt.pdf"]) &&
               passed;
    }
    return passed;
  }

  // #R025: Replay non-2xx transport responses and verify error text truncation behavior.
  bool TestFetchGraphGetDataErrorTruncation()
  {
    std::string long_body(350, 'x');
    SetReplayResponses({
        {"Bearer token-initial", std::string("{\"error\":\"") + long_body + "\"}", 500},
    });
    mailcart_bridge::InstallGraphTransportHook(ReplayTransport);
    mailcart_bridge::InstallGraphRefreshHook(nullptr);
    mailcart_bridge::InstallGraphTokenResolverHook(nullptr);

    NSString *error_text = @"";
    NSURL *url = [NSURL URLWithString:@"https://graph.microsoft.com/v1.0/me/messages"];
    NSData *payload = mailcart_bridge::FetchGraphGetData(url, @"token-initial", NO, &error_text);
    std::string error_value = mailcart_bridge::ToStdString(error_text);

    bool passed = true;
    passed = Expect("error replay returns nil payload", payload == nil) && passed;
    passed = Expect("error replay includes HTTP status prefix", error_value.find("Graph returned HTTP 500:") != std::string::npos) &&
             passed;
    passed = Expect("error replay body text is truncated", error_value.size() < 340) && passed;
    return passed;
  }
} // namespace

// #R030: Execute all replay tests and return non-zero when any replay check fails.
int main()
{
  bool all_passed = true;
  all_passed = RunReplayTest("TestSearchPayloadRefreshReplay", TestSearchPayloadRefreshReplay) && all_passed;
  all_passed = RunReplayTest("TestMessagePayloadReplay", TestMessagePayloadReplay) && all_passed;
  all_passed = RunReplayTest("TestFetchGraphGetDataErrorTruncation", TestFetchGraphGetDataErrorTruncation) && all_passed;
  mailcart_bridge::ResetGraphTestHooks();

  if (all_passed && g_metrics.AllPassed())
  {
    std::cout << "All outlook graph replay checks passed.\n";
    g_metrics.PrintSummary();
    return 0;
  }
  std::cerr << "One or more outlook graph replay checks failed.\n";
  g_metrics.PrintSummary();
  return 1;
}
