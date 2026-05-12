#include "mailcart.hpp"
#include "outlook_client.hpp"

#include <iostream>
#include <string>
#include <vector>

class TestMetrics
{ public:
  TestMetrics()
    : total_tests_(0),
      failed_tests_(0),
      total_expectations_(0),
      failed_expectations_(0)
  {
  }

  void RecordExpectation(bool passed)
  { total_expectations_ = total_expectations_ + 1;
    if (!passed)
    { failed_expectations_ = failed_expectations_ + 1;
    }
  }

  void RecordTest(bool passed)
  { total_tests_ = total_tests_ + 1;
    if (!passed)
    { failed_tests_ = failed_tests_ + 1;
    }
  }

  [[nodiscard]] int TotalTests() const
  { return total_tests_;
  }

  [[nodiscard]] int FailedTests() const
  { return failed_tests_;
  }

  [[nodiscard]] int PassedTests() const
  { int passed_tests = total_tests_ - failed_tests_;
    return passed_tests;
  }

  [[nodiscard]] int TotalExpectations() const
  { return total_expectations_;
  }

  [[nodiscard]] int FailedExpectations() const
  { return failed_expectations_;
  }

  [[nodiscard]] int PassedExpectations() const
  { int passed_expectations = total_expectations_ - failed_expectations_;
    return passed_expectations;
  }

 private:
  int total_tests_;
  int failed_tests_;
  int total_expectations_;
  int failed_expectations_;
};

TestMetrics g_test_metrics;

class FakeOutlookGateway : public OutlookServiceGateway
{ public:
  FakeOutlookGateway() = default;

  [[nodiscard]] std::string FetchSearchPayload(std::string query, int limit) const override
  { std::string payload = "search:query=" + query + ";limit=" + std::to_string(limit);
    return payload;
  }

  [[nodiscard]] std::string FetchMessagePayload(std::string message_id) const override
  { std::string payload = "message:id=" + message_id;
    return payload;
  }
};

class FakeOutlookParser : public OutlookPayloadParser
{ public:
  FakeOutlookParser() = default;

  [[nodiscard]] std::vector<OutlookJsonObject> ParseSearchPayload(const std::string &raw_payload) const override
  { (void)raw_payload;
    std::vector<OutlookJsonObject> search_results;
    OutlookJsonObject first_result;
    first_result.SetStringField("id", "msg-001");
    first_result.SetStringField("subject", "Project update");
    first_result.SetStringField("preview", "Latest milestone reached");
    search_results.push_back(first_result);

    OutlookJsonObject second_result;
    second_result.SetStringField("id", "msg-002");
    second_result.SetStringField("subject", "Lunch?");
    second_result.SetStringField("preview", "Are you free at noon?");
    second_result.SetStringField("receivedAt", "2026-05-06T22:00:00Z");
    search_results.push_back(second_result);

    return search_results;
  }

  [[nodiscard]] OutlookJsonObject ParseMessagePayload(const std::string &raw_payload) const override
  { OutlookJsonObject message_object;
    message_object.SetStringField("id", "msg-001");
    message_object.SetStringField("sender", "ceo@example.com");
    message_object.SetStringField("recipient", "team@example.com");
    message_object.SetStringField("subject", "Project update");
    message_object.SetStringField("receivedAt", "2026-05-06T21:00:00Z");
    message_object.SetStringField("bodyText", "Delivery is on schedule.");
    message_object.SetStringField("bodyHtml", "<p>Delivery is on schedule.</p>");
    message_object.SetStringField("attachmentCount", "1");
    message_object.SetStringField("attachment0Id", "att-1");
    message_object.SetStringField("attachment0Name", "report.pdf");
    message_object.SetStringField("attachment0Type", "application/pdf");
    message_object.SetStringField("attachment0Size", "1024");
    message_object.SetStringField("rawMarker", raw_payload);
    return message_object;
  }
};

bool Expect(const std::string &expectation_name, bool condition)
{ g_test_metrics.RecordExpectation(condition);
  if (condition)
  { std::cout << "  ✓ " << expectation_name << '\n';
  }
  else
  { std::cerr << "  x " << expectation_name << '\n';
  }
  return condition;
}

bool RunIntegrationTest(const std::string &test_name, bool (*test_function)())
{ std::cout << "Running " << test_name << '\n';
  bool passed = test_function();
  g_test_metrics.RecordTest(passed);
  if (passed)
  { std::cout << "✓ " << test_name << " passed\n";
  }
  else
  { std::cerr << "x " << test_name << " failed\n";
  }
  return passed;
}

bool TestMimeContent()
{ MimeContent html = MimeContent::Html("<p>Hello</p>");
  MimeContent unknown("", "");

  bool passed = true;
  bool expectation_passed = Expect("HTML MIME detection", html.isHtml());
  passed = passed && expectation_passed;
  expectation_passed = Expect("HTML should not be plain text", !html.isPlainText());
  passed = passed && expectation_passed;
  expectation_passed = Expect("empty type should normalize", unknown.contentType() == "application/unknown");
  passed = passed && expectation_passed;
  expectation_passed = Expect("empty MIME content should report empty", unknown.empty());
  passed = passed && expectation_passed;
  return passed;
}

bool TestMailcartRobustness()
{ Mailcart mailcart("", "", "", "hello");
  mailcart.SetSubject("");
  mailcart.SetBody("updated");

  bool passed = true;
  bool expectation_passed = Expect("sender default", mailcart.sender() == "unknown@local");
  passed = passed && expectation_passed;
  expectation_passed = Expect("recipient default", mailcart.recipient() == "unknown@local");
  passed = passed && expectation_passed;
  expectation_passed = Expect("subject normalization", mailcart.subject() == "(no subject)");
  passed = passed && expectation_passed;
  expectation_passed = Expect("body update", mailcart.body() == "updated");
  passed = passed && expectation_passed;
  expectation_passed = Expect("body setter uses plain text MIME", mailcart.mimeContent().contentType() == "text/plain");
  passed = passed && expectation_passed;
  return passed;
}

bool TestOutlookMailcartPopulation()
{ OutlookJsonObject json_object;
  json_object.SetStringField("id", "m-123");
  json_object.SetStringField("sender", "alice@example.com");
  json_object.SetStringField("recipient", "bob@example.com");
  json_object.SetStringField("subject", "Meeting notes");
  json_object.SetStringField("receivedAt", "2026-05-06T20:00:00Z");
  json_object.SetStringField("bodyText", "");
  json_object.SetStringField("bodyHtml", "<p>Notes</p>");
  json_object.SetStringField("attachmentCount", "1");
  json_object.SetStringField("attachment0Id", "att-100");
  json_object.SetStringField("attachment0Name", "notes.txt");
  json_object.SetStringField("attachment0Type", "text/plain");
  json_object.SetStringField("attachment0Size", "44");

  OutlookMailcart outlook_mailcart(json_object);

  bool passed = true;
  bool expectation_passed = Expect("type override", outlook_mailcart.type() == "outlook_mailcart");
  passed = passed && expectation_passed;
  expectation_passed = Expect("message id mapping", outlook_mailcart.messageId() == "m-123");
  passed = passed && expectation_passed;
  expectation_passed = Expect("received timestamp mapping", outlook_mailcart.receivedAt() == "2026-05-06T20:00:00Z");
  passed = passed && expectation_passed;
  expectation_passed = Expect("html fallback when text missing", outlook_mailcart.mimeContent().isHtml());
  passed = passed && expectation_passed;
  expectation_passed = Expect("body from html fallback", outlook_mailcart.body() == "<p>Notes</p>");
  passed = passed && expectation_passed;
  expectation_passed = Expect("body html accessor", outlook_mailcart.bodyHtml() == "<p>Notes</p>");
  passed = passed && expectation_passed;
  expectation_passed = Expect("body text accessor", outlook_mailcart.bodyText() == "");
  passed = passed && expectation_passed;
  expectation_passed = Expect("attachment count", outlook_mailcart.attachments().size() == 1);
  passed = passed && expectation_passed;
  expectation_passed = Expect("attachment name mapping", outlook_mailcart.attachments()[0].fileName() == "notes.txt");
  passed = passed && expectation_passed;
  return passed;
}

bool TestOutlookClientSearchAndRead()
{ FakeOutlookGateway gateway;
  FakeOutlookParser parser;
  OutlookClient client(gateway, parser);

  std::vector<OutlookMailcartSummary> search_results = client.SearchMailcarts("project", 10);
  OutlookMailcart read_mailcart = client.ReadMailcart("msg-001");

  bool passed = true;
  bool expectation_passed = Expect("search result count", search_results.size() == 2);
  passed = passed && expectation_passed;
  expectation_passed = Expect("search first id", search_results[0].messageId() == "msg-001");
  passed = passed && expectation_passed;
  expectation_passed = Expect("search second subject", search_results[1].subject() == "Lunch?");
  passed = passed && expectation_passed;
  expectation_passed = Expect("search includes received date", search_results[1].receivedAt() == "2026-05-06T22:00:00Z");
  passed = passed && expectation_passed;
  expectation_passed = Expect("read mailcart id", read_mailcart.messageId() == "msg-001");
  passed = passed && expectation_passed;
  expectation_passed = Expect("read mailcart body text preference", read_mailcart.body() == "Delivery is on schedule.");
  passed = passed && expectation_passed;
  expectation_passed = Expect("read MIME plain-text preference", read_mailcart.mimeContent().isPlainText());
  passed = passed && expectation_passed;
  expectation_passed = Expect("read attachment mapped", read_mailcart.attachments()[0].attachmentId() == "att-1");
  passed = passed && expectation_passed;
  return passed;
}

int main()
{ bool all_passed = true;
  bool test_passed = RunIntegrationTest("TestMimeContent", TestMimeContent);
  all_passed = all_passed && test_passed;
  test_passed = RunIntegrationTest("TestMailcartRobustness", TestMailcartRobustness);
  all_passed = all_passed && test_passed;
  test_passed = RunIntegrationTest("TestOutlookMailcartPopulation", TestOutlookMailcartPopulation);
  all_passed = all_passed && test_passed;
  test_passed = RunIntegrationTest("TestOutlookClientSearchAndRead", TestOutlookClientSearchAndRead);
  all_passed = all_passed && test_passed;

  int exit_code = 0;
  if (all_passed)
  { std::cout << "All outlook integration checks passed.\n";
  }
  else
  { std::cerr << "One or more outlook integration checks failed.\n";
    exit_code = 1;
  }
  std::cout << "Final count: tests " << g_test_metrics.PassedTests() << "/" << g_test_metrics.TotalTests()
            << " passed, expectations " << g_test_metrics.PassedExpectations() << "/"
            << g_test_metrics.TotalExpectations() << " passed.\n";
  return exit_code;
}
