#include "mime_content.hpp"
#include <utility>

namespace
{
  // #R001: Normalize empty MIME content types to application/unknown.
  std::string NormalizeContentType(std::string content_type)
  { std::string normalized = std::move(content_type);
    if (normalized.empty())
    { normalized = "application/unknown";
    }
    return normalized;
  }
} // namespace

// #R005: Preserve initialized content type and content payload via accessors.
MimeContent::MimeContent(std::string content_type, std::string content)
    : content_type_(NormalizeContentType(std::move(content_type))), content_(std::move(content))
{}

// #R005: Expose normalized content type through a read-only accessor.
const std::string &MimeContent::contentType() const
{ const std::string &value = content_type_;
  return value;
}

// #R005: Expose MIME payload through a read-only accessor.
const std::string &MimeContent::content() const
{ const std::string &value = content_;
  return value;
}

// #R010: Detect plain-text payloads by exact MIME type match.
bool MimeContent::isPlainText() const
{ bool plain_text = false;
  if (content_type_ == "text/plain")
  { plain_text = true;
  }
  return plain_text;
}

// #R015: Detect HTML payloads by exact MIME type match.
bool MimeContent::isHtml() const
{ bool html = false;
  if (content_type_ == "text/html")
  { html = true;
  }
  return html;
}

// #R020: Report empty state based on content payload only.
bool MimeContent::empty() const
{ bool is_empty = content_.empty();
  return is_empty;
}

// #R025: Update content type with normalization semantics.
void MimeContent::SetContentType(std::string content_type)
{ content_type_ = NormalizeContentType(std::move(content_type));
}

// #R030: Replace content payload without changing content type.
void MimeContent::SetContent(std::string content)
{ content_ = std::move(content);
}

// #R035: Provide canonical plain-text MIME factory.
MimeContent MimeContent::PlainText(std::string content)
{ MimeContent plain_text("text/plain", std::move(content));
  return plain_text;
}

// #R040: Provide canonical HTML MIME factory.
MimeContent MimeContent::Html(std::string content)
{ MimeContent html("text/html", std::move(content));
  return html;
}
