// libFuzzer target for the scoped-search query parser and text normalizers
// (port of scripts/matchy_mailcart_api.py _parse_scoped_query / _strip_html).
// Replaces the Hypothesis fuzz lane (t10). ApiError(400) is the expected,
// non-crashing rejection path for malformed queries.
#include <cstddef>
#include <cstdint>
#include <string>

#include "mailcartcore/api_error.hpp"
#include "mailcartcore/search.hpp"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{ const std::string input(reinterpret_cast<const char *>(data), size);
  try
  { const mailcartcore::SearchCriteria criteria = mailcartcore::ParseScopedQuery(input);
    const mailcartcore::AhoCorasick matcher = mailcartcore::BuildCriteriaMatcher(criteria);
    (void)matcher.Search(mailcartcore::NormalizeSearchText(input));
  }
  catch (const mailcartcore::ApiError &)
  { // Malformed queries fail closed with HTTP 400; not a crash.
  }
  (void)mailcartcore::StripHtml(input);
  (void)mailcartcore::ParseIsoDate(input);
  (void)mailcartcore::ParseReceivedAtDate(input);
  return 0;
}
