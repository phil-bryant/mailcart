// Catch2 migration of the legacy custom-harness outlook_integration_test.cpp.
#include <catch2/catch_test_macros.hpp>

#include "mailcart.hpp"
#include "outlook_client.hpp"

namespace
{
  class FakeOutlookGateway : public OutlookServiceGateway
  { public:
    // #R010: Return canned search payload text for deterministic integration checks.
    [[nodiscard]] std::string FetchSearchPayload(std::string query, int limit) const override
    { return "search:query=" + query + ";limit=" + std::to_string(limit);
    }

    // #R010: Return canned message payload text for deterministic integration checks.
    [[nodiscard]] std::string FetchMessagePayload(std::string message_id) const override
    { return "message:id=" + message_id;
    }
  };

  class FakeOutlookParser : public OutlookPayloadParser
  { public:
    // #R015: Return canned search objects for deterministic parser behavior.
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

    // #R015: Return canned message object for deterministic parser behavior.
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
} // namespace

// #R025: Verify MIME detection and normalization robustness.
TEST_CASE("MimeContent detection and normalization", "[outlook-core]")
{ const MimeContent html = MimeContent::Html("<p>Hello</p>");
  const MimeContent unknown("", "");

  CHECK(html.isHtml());
  CHECK_FALSE(html.isPlainText());
  CHECK(unknown.contentType() == "application/unknown");
  CHECK(unknown.empty());
}

// #R025: Verify Mailcart normalization and mutation robustness.
TEST_CASE("Mailcart normalization and mutation", "[outlook-core]")
{ Mailcart mailcart("", "", "", "hello");
  mailcart.SetSubject("");
  mailcart.SetBody("updated");

  CHECK(mailcart.sender() == "unknown@local");
  CHECK(mailcart.recipient() == "unknown@local");
  CHECK(mailcart.subject() == "(no subject)");
  CHECK(mailcart.body() == "updated");
  CHECK(mailcart.mimeContent().contentType() == "text/plain");
}

// #R030: Verify OutlookMailcart field population and accessor mapping.
TEST_CASE("OutlookMailcart population and accessors", "[outlook-core]")
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

  const OutlookMailcart outlook_mailcart(json_object);

  CHECK(outlook_mailcart.type() == "outlook_mailcart");
  CHECK(outlook_mailcart.messageId() == "m-123");
  CHECK(outlook_mailcart.receivedAt() == "2026-05-06T20:00:00Z");
  CHECK(outlook_mailcart.mimeContent().isHtml());
  CHECK(outlook_mailcart.body() == "<p>Notes</p>");
  CHECK(outlook_mailcart.bodyHtml() == "<p>Notes</p>");
  CHECK(outlook_mailcart.bodyText().empty());
  REQUIRE(outlook_mailcart.attachments().size() == 1);
  CHECK(outlook_mailcart.attachments()[0].fileName() == "notes.txt");
}

// #R030: Verify OutlookClient search/read mapping against fake gateway/parser.
TEST_CASE("OutlookClient search and read mapping", "[outlook-core]")
{ const FakeOutlookGateway gateway;
  const FakeOutlookParser parser;
  const OutlookClient client(gateway, parser);

  const std::vector<OutlookMailcartSummary> search_results = client.SearchMailcarts("project", 10);
  const OutlookMailcart read_mailcart = client.ReadMailcart("msg-001");

  REQUIRE(search_results.size() == 2);
  CHECK(search_results[0].messageId() == "msg-001");
  CHECK(search_results[1].subject() == "Lunch?");
  CHECK(search_results[1].receivedAt() == "2026-05-06T22:00:00Z");
  CHECK(read_mailcart.messageId() == "msg-001");
  CHECK(read_mailcart.body() == "Delivery is on schedule.");
  CHECK(read_mailcart.mimeContent().isPlainText());
  REQUIRE(!read_mailcart.attachments().empty());
  CHECK(read_mailcart.attachments()[0].attachmentId() == "att-1");
}
